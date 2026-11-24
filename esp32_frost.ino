/*
  NEON INFINITY DUO - ESP32 joystick controller
  ------------------------------------------------------------------
  Flash the SAME file to both boards. Only two things change:

      Board 1 (Ember / P1):  PLAYER_ID 1   HAS_BUZZER true    <- also has the buzzer
      Board 2 (Frost / P2):  PLAYER_ID 2   HAS_BUZZER false

  What it does
    * reads the joystick (2 axes) and 4 push buttons: JUMP, STOP, PAUSE, START
    * prints one line over USB serial ~50 times a second:   id,x,y,jump,stop,pause,start
          x, y  from -1.00 to 1.00   (right = +, up = +)       buttons: 1 = pressed, 0 = released
    * (HAS_BUZZER board only) listens for lines such as  E,stone  coming back from the game
      and answers with a short beep.

  No extra libraries are needed.
  Board package:  "esp32 by Espressif Systems"   |   Board: "ESP32 Dev Module"
*/

#include <Arduino.h>

// ====================== 1. EDIT THESE TWO LINES PER BOARD =====================
#define PLAYER_ID    2        // FROST = player 2 (do not change in this file)
#define HAS_BUZZER   false     // Frost has no buzzer
// ==============================================================================

// ---- pins (see the wiring diagrams in the guide) ----
// Every pin is on the RIGHT-hand side of the board (USB socket at the bottom), because on a
// standard breadboard the right side leaves open holes next to the pins and the left side may not.
// The joystick uses D4 and D15 (ADC2 pins). ADC2 only stops working while Wi-Fi is on, and this
// sketch never turns Wi-Fi on, so they read perfectly well.
const int PIN_VRX   = 4;      // joystick VRx  (D4)
const int PIN_VRY   = 15;     // joystick VRy  (D15)
const int PIN_START = 21;     // button: start / confirm   (D21)
const int PIN_JUMP  = 19;     // button: jump              (D19)
const int PIN_STOP  = 18;     // button: stop (hold 1 s to go to the home screen)   (D18)
const int PIN_PAUSE = 5;      // button: pause / resume    (D5)
const int PIN_BUZZ  = 22;     // -> 1k resistor -> NPN transistor base that switches the buzzer (board 1 only)

// ---- tweakables ----
#define INVERT_X          false   // if pushing the stick RIGHT makes the hero go LEFT, set true
#define INVERT_Y          false   // if pushing the stick UP is read as DOWN, set true
#define BUZZER_ENABLED    true    // false = completely silent
const float DEADZONE = 0.12;      // ignore tiny stick wobble around the middle
const unsigned long SEND_EVERY_MS = 20;

// ---------------------------------------------------------------------------
int centerX = 2048, centerY = 2048;

struct Btn {
  int pin;
  bool stable;           // debounced state (true = pressed)
  bool lastRaw;
  unsigned long changedAt;
};
Btn btns[4] = {
  {PIN_JUMP, false, false, 0}, {PIN_STOP, false, false, 0},
  {PIN_PAUSE, false, false, 0}, {PIN_START, false, false, 0}
};

unsigned long lastSend = 0;

// ============================ joystick helpers =============================
int readAvg(int pin) {
  long sum = 0;
  for (int i = 0; i < 8; i++) sum += analogRead(pin);
  return (int)(sum / 8);
}

float norm(int raw, int center, bool invert) {
  float v;
  if (raw >= center) v = (raw - center) / (float)(4095 - center);
  else               v = (raw - center) / (float)center;
  if (invert) v = -v;
  if (fabs(v) < DEADZONE) return 0.0;
  // stretch what is left so the stick still reaches +-1.0
  v = (v > 0) ? (v - DEADZONE) / (1.0 - DEADZONE) : (v + DEADZONE) / (1.0 - DEADZONE);
  if (v > 1.0) v = 1.0;
  if (v < -1.0) v = -1.0;
  return v;
}

void updateButtons() {
  unsigned long now = millis();
  for (int i = 0; i < 4; i++) {
    bool raw = (digitalRead(btns[i].pin) == LOW);       // INPUT_PULLUP: pressed = LOW
    if (raw != btns[i].lastRaw) { btns[i].lastRaw = raw; btns[i].changedAt = now; }
    if (now - btns[i].changedAt > 15 && btns[i].stable != raw) btns[i].stable = raw;
  }
}

// ================================== buzzer =================================
#if HAS_BUZZER
// non-blocking "on/off milliseconds" patterns
const int MAXSTEPS = 12;
int  buzzSteps[MAXSTEPS];
int  buzzCount = 0, buzzIdx = 0;
unsigned long buzzNext = 0;
bool buzzOn = false;

void buzzWrite(bool on) {
  if (!BUZZER_ENABLED) on = false;
  digitalWrite(PIN_BUZZ, on ? HIGH : LOW);               // HIGH switches the transistor on
}
// pattern: alternating ON, OFF, ON, OFF ... durations in ms (0-terminated)
void beep(const int *p) {
  buzzCount = 0;
  while (p[buzzCount] != 0 && buzzCount < MAXSTEPS) { buzzSteps[buzzCount] = p[buzzCount]; buzzCount++; }
  buzzIdx = 0;
  buzzOn = true;
  buzzWrite(true);
  buzzNext = millis() + buzzSteps[0];
}
void updateBuzzer() {
  if (buzzCount == 0) return;
  if ((long)(millis() - buzzNext) < 0) return;
  buzzIdx++;
  if (buzzIdx >= buzzCount) { buzzCount = 0; buzzOn = false; buzzWrite(false); return; }
  buzzOn = !buzzOn;
  buzzWrite(buzzOn);
  buzzNext = millis() + buzzSteps[buzzIdx];
}

// Short and few on purpose (too many loud beeps were annoying).
// Only gem, hurt, level clear and time-up beep; every other event is silent.
const int B_STONE[]  = {40, 0};
const int B_HURT[]   = {150, 0};
const int B_CLEAR[]  = {60, 70, 60, 0};
const int B_TIMEUP[] = {120, 80, 120, 0};

void handleEvent(const String &e) {
  if      (e == "stone")  beep(B_STONE);
  else if (e == "hurt")   beep(B_HURT);
  else if (e == "clear")  beep(B_CLEAR);
  else if (e == "timeup") beep(B_TIMEUP);
}

String rx;
void readGameMessages() {
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n') {
      rx.trim();
      if (rx.startsWith("E,")) handleEvent(rx.substring(2));
      rx = "";
    } else if (rx.length() < 40) {
      rx += c;
    }
  }
}
#endif   // HAS_BUZZER

// ================================ setup / loop =============================
void setup() {
  Serial.begin(115200);
  analogReadResolution(12);                       // 0..4095
  for (int i = 0; i < 4; i++) pinMode(btns[i].pin, INPUT_PULLUP);
  delay(300);                                     // let the stick spring settle
  centerX = readAvg(PIN_VRX);                     // keep your hands OFF the stick at power-up
  centerY = readAvg(PIN_VRY);

#if HAS_BUZZER
  pinMode(PIN_BUZZ, OUTPUT);
  buzzWrite(false);
  static const int hello[] = {40, 0};
  beep(hello);                                    // one tiny "I'm alive" tick
#endif
}

void loop() {
  updateButtons();
#if HAS_BUZZER
  readGameMessages();
  updateBuzzer();
#endif
  unsigned long now = millis();
  if (now - lastSend >= SEND_EVERY_MS) {
    lastSend = now;
    // screen "up" = + : the KY-023 reads LOW values when pushed up on most wirings, so we flip Y
    float x = norm(analogRead(PIN_VRX), centerX, INVERT_X);
    float y = norm(analogRead(PIN_VRY), centerY, !INVERT_Y);
    Serial.printf("%d,%.2f,%.2f,%d,%d,%d,%d\n", PLAYER_ID, x, y,
                  btns[0].stable, btns[1].stable, btns[2].stable, btns[3].stable);
  }
}
