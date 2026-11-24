/*
  NEON INFINITY DUO - ESP32 joystick controller
  ------------------------------------------------------------------
  Flash the SAME file to both boards. Only two things change:

      Board 1 (Ember / P1):  PLAYER_ID 1   HAS_DISPLAY true    <- also has the buzzer + LED matrix
      Board 2 (Frost / P2):  PLAYER_ID 2   HAS_DISPLAY false

  What it does
    * reads the joystick (2 axes) and 4 push buttons: JUMP, STOP, PAUSE, START
    * prints one line over USB serial ~50 times a second:   id,x,y,jump,stop,pause,start
          x, y  from -1.00 to 1.00   (right = +, up = +)       buttons: 1 = pressed, 0 = released
    * (HAS_DISPLAY boards only) listens for lines such as  E,stone  coming back from the game
      and answers with buzzer beeps + a little picture on the 8x8 LED matrix.

  Library needed (Arduino IDE -> Library Manager):  "Adafruit NeoPixel"
  Board package:  "esp32 by Espressif Systems"   |   Board: "ESP32 Dev Module"
*/

#include <Arduino.h>
#include <Adafruit_NeoPixel.h>

// ====================== 1. EDIT THESE TWO LINES PER BOARD =====================
#define PLAYER_ID    1        // 1 for the first board, 2 for the second board
#define HAS_DISPLAY  true     // true only on the board that carries buzzer + LED matrix
// ==============================================================================

// ---- pins (see the wiring tables in the guide) ----
const int PIN_VRX   = 34;     // joystick VRx  (input-only ADC pin, perfect for this)
const int PIN_VRY   = 35;     // joystick VRy
const int PIN_JUMP  = 25;     // button: jump
const int PIN_STOP  = 26;     // button: stop (hold 1 s to go to the home screen)
const int PIN_PAUSE = 27;     // button: pause / resume
const int PIN_START = 33;     // button: start / confirm
const int PIN_BUZZ  = 22;     // -> 1k resistor -> NPN transistor base that switches the buzzer (board 1 only)
const int PIN_MATRIX = 23;    // WS2812B matrix DIN via 330 ohm  (board 1 only)

// ---- tweakables ----
#define INVERT_X          false   // if pushing the stick RIGHT makes the hero go LEFT, set true
#define INVERT_Y          false   // if pushing the stick UP is read as DOWN, set true
#define BUZZER_ENABLED    true    // false = completely silent (LED matrix still works)
#define BUZZER_ACTIVE_LOW false   // keep false with the transistor driver (pin HIGH = buzzer ON)
#define SERPENTINE        false   // LED matrix wiring: false = every row runs left->right (most 8x8
                                  // panels), true = zig-zag rows
#define MATRIX_BRIGHTNESS 20      // 0-255. Keep it LOW: the matrix draws a lot of current.
const float DEADZONE = 0.12;      // ignore tiny stick wobble around the middle
const unsigned long SEND_EVERY_MS = 20;

// ---------------------------------------------------------------------------
#if HAS_DISPLAY
Adafruit_NeoPixel matrix(64, PIN_MATRIX, NEO_GRB + NEO_KHZ800);
#endif

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

// ============================ buzzer + matrix =============================
#if HAS_DISPLAY
// ---- buzzer: non-blocking "on/off milliseconds" patterns ----
const int MAXSTEPS = 12;
int  buzzSteps[MAXSTEPS];
int  buzzCount = 0, buzzIdx = 0;
unsigned long buzzNext = 0;
bool buzzOn = false;

void buzzWrite(bool on) {
  if (!BUZZER_ENABLED) on = false;
  digitalWrite(PIN_BUZZ, (BUZZER_ACTIVE_LOW ? !on : on) ? HIGH : LOW);
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

// ---- 8x8 pictures: one byte per row, top row first, bit 7 = left-most pixel ----
const uint8_t IMG_SMILE[8]  = {0x3C,0x42,0xA5,0x81,0xA5,0x99,0x42,0x3C};
const uint8_t IMG_GEM[8]    = {0x18,0x3C,0x7E,0xFF,0x7E,0x3C,0x18,0x00};
const uint8_t IMG_FLAG[8]   = {0x60,0x7C,0x7E,0x7C,0x60,0x60,0x60,0x60};
const uint8_t IMG_OUCH[8]   = {0x81,0x42,0x24,0x18,0x18,0x24,0x42,0x81};
const uint8_t IMG_PAUSE[8]  = {0x00,0x66,0x66,0x66,0x66,0x66,0x66,0x00};
const uint8_t IMG_ALIEN[8]  = {0x3C,0x7E,0xDB,0xFF,0xFF,0x24,0x5A,0xA5};
const uint8_t IMG_HEART[8]  = {0x66,0xFF,0xFF,0xFF,0x7E,0x3C,0x18,0x00};
const uint8_t IMG_TIME[8]   = {0xFF,0x7E,0x3C,0x18,0x18,0x24,0x42,0xFF};
const uint8_t IMG_LEVEL[8]  = {0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00};   // a "1"

int pixelIndex(int row, int col) {
  if (SERPENTINE && (row % 2 == 1)) return row * 8 + (7 - col);
  return row * 8 + col;
}
void showImage(const uint8_t *img, uint32_t color) {
  for (int r = 0; r < 8; r++)
    for (int c = 0; c < 8; c++)
      matrix.setPixelColor(pixelIndex(r, c), (img[r] & (0x80 >> c)) ? color : 0);
  matrix.show();
}

const uint32_t COL_GREEN = 0x00C830, COL_GOLD = 0xFFB400, COL_RED = 0xFF1010,
               COL_BLUE = 0x2060FF, COL_PINK = 0xFF2090, COL_LIME = 0x80FF00;

const uint8_t *baseImg = IMG_SMILE;  uint32_t baseCol = COL_GREEN;
unsigned long revertAt = 0;          // 0 = nothing to revert

void showBase() { showImage(baseImg, baseCol); revertAt = 0; }
void flash(const uint8_t *img, uint32_t col, unsigned long ms) {
  showImage(img, col);
  revertAt = millis() + ms;
}
void updateMatrix() {
  if (revertAt && (long)(millis() - revertAt) >= 0) showBase();
}

// ---- reaction to messages from the game ----
// Short and few on purpose (feedback: too many loud beeps were annoying).
// Only gem, hurt, level clear and time-up beep; everything else is silent (picture only).
const int B_STONE[]  = {40, 0};
const int B_HURT[]   = {150, 0};
const int B_CLEAR[]  = {60, 70, 60, 0};
const int B_TIMEUP[] = {120, 80, 120, 0};

void handleEvent(const String &e) {
  if      (e == "stone")      { beep(B_STONE);  flash(IMG_GEM,   COL_GOLD, 700); }
  else if (e == "checkpoint") {                 flash(IMG_FLAG,  COL_LIME, 900); }
  else if (e == "hurt")       { beep(B_HURT);   flash(IMG_OUCH,  COL_RED, 900); }
  else if (e == "clear")      { beep(B_CLEAR);  flash(IMG_HEART, COL_PINK, 2500); }
  else if (e == "timeup")     { beep(B_TIMEUP); flash(IMG_TIME,  COL_RED, 2000); }
  else if (e == "alien")      {                 flash(IMG_ALIEN, COL_LIME, 1200); }
  else if (e == "level")      {                 flash(IMG_LEVEL, COL_BLUE, 900); }
  else if (e == "pause")      { baseImg = IMG_PAUSE; baseCol = COL_BLUE; showBase(); }
  else if (e == "resume" || e == "home") { baseImg = IMG_SMILE; baseCol = COL_GREEN; showBase(); }
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
#endif   // HAS_DISPLAY

// ================================ setup / loop =============================
void setup() {
  Serial.begin(115200);
  analogReadResolution(12);                       // 0..4095
  for (int i = 0; i < 4; i++) pinMode(btns[i].pin, INPUT_PULLUP);
  delay(300);                                     // let the stick spring settle
  centerX = readAvg(PIN_VRX);                     // keep your hands OFF the stick at power-up
  centerY = readAvg(PIN_VRY);

#if HAS_DISPLAY
  pinMode(PIN_BUZZ, OUTPUT);
  buzzWrite(false);
  matrix.begin();
  matrix.setBrightness(MATRIX_BRIGHTNESS);
  showBase();
  static const int hello[] = {40, 0};
  beep(hello);                                    // one tiny "I'm alive" tick
#endif
}

void loop() {
  updateButtons();
#if HAS_DISPLAY
  readGameMessages();
  updateBuzzer();
  updateMatrix();
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
