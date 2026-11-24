extends Node
## Unified input (autoload "Controllers"). The game can be played with the keyboard alone,
## with the two ESP32 joysticks alone, or with a mix of both.
##
## Keyboard   P1: A / D + W or Space      P2: Left / Right + Up
## ESP32      each board sends a line over UDP port 4210:  id,x,y,jump,stop,pause,start
##            id = 1 or 2 | x,y in [-1..1] (right = +, up = +) | buttons are 0 or 1
##            (tools/serial_bridge.py forwards the USB-serial lines from the boards to this port)
## Game -> hardware: events like "E,stone" are sent to UDP port 4211 (the bridge hands them to
##            the board that has the buzzer and the LED matrix).

signal hw_button(btn: String, player: int)   # rising edge of jump / stop / pause / start
signal hw_nav(dir: int)                      # joystick pushed up (-1) or down (+1), for menus

const UDP_PORT := 4210
const OUT_PORT := 4211
const DEADZONE := 0.35
const ESP_TIMEOUT := 1.0
const BUTTONS := ["jump", "stop", "pause", "start"]

var _in := PacketPeerUDP.new()
var _out := PacketPeerUDP.new()
var _esp: Array = []
var _nav_lock: Array = [false, false]

# Test hooks: the automated bot drives the heroes through these.
var bot_on := false
var bot_axis: Array = [0.0, 0.0]
var bot_jump: Array = [false, false]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		_esp.append({"x": 0.0, "y": 0.0, "seen": -99.0,
			"jump": false, "stop": false, "pause": false, "start": false})
	var err := _in.bind(UDP_PORT)
	if err != OK:
		push_warning("Could not listen on UDP port %d (error %d) - joystick input disabled." % [UDP_PORT, err])
	_out.set_dest_address("127.0.0.1", OUT_PORT)


func _process(_delta: float) -> void:
	while _in.get_available_packet_count() > 0:
		_parse(_in.get_packet().get_string_from_utf8().strip_edges())
	for i in 2:
		var y: float = _esp[i]["y"] if esp_connected(i) else 0.0
		if absf(y) < 0.4:
			_nav_lock[i] = false
		elif absf(y) > 0.7 and not _nav_lock[i]:
			_nav_lock[i] = true
			hw_nav.emit(-1 if y > 0.0 else 1)


func _parse(msg: String) -> void:
	var p := msg.split(",")
	if p.size() < 4:
		return
	var idx := int(p[0]) - 1
	if idx < 0 or idx > 1:
		return
	var e: Dictionary = _esp[idx]
	e["x"] = clampf(float(p[1]), -1.0, 1.0)
	e["y"] = clampf(float(p[2]), -1.0, 1.0)
	e["seen"] = Time.get_ticks_msec() / 1000.0
	var now: Array = [false, false, false, false]
	if p.size() >= 7:
		for b in 4:
			now[b] = int(p[3 + b]) != 0
	else:
		now[0] = int(p[3]) != 0        # old 4-field format: x,y,jump only
	for b in 4:
		var key: String = BUTTONS[b]
		if now[b] and not e[key]:
			hw_button.emit(key, idx)
		e[key] = now[b]


func esp_connected(i: int) -> bool:
	return Time.get_ticks_msec() / 1000.0 - float(_esp[i]["seen"]) < ESP_TIMEOUT


func get_axis(i: int) -> float:
	if bot_on:
		return float(bot_axis[i])
	var v := 0.0
	if esp_connected(i):
		v = _esp[i]["x"]
		if absf(v) < DEADZONE:
			v = 0.0
	var kb := 0.0
	if i == 0:
		kb = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	else:
		kb = float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
	return clampf(v + kb, -1.0, 1.0)


func jump_held(i: int) -> bool:
	if bot_on:
		return bool(bot_jump[i])
	var j := false
	if esp_connected(i):
		j = bool(_esp[i]["jump"]) or float(_esp[i]["y"]) > 0.7
	if i == 0:
		j = j or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_SPACE)
	else:
		j = j or Input.is_key_pressed(KEY_UP)
	return j


## True while a STOP button (either joystick) or Backspace is held.
func stop_held() -> bool:
	if bot_on:
		return false
	for i in 2:
		if esp_connected(i) and bool(_esp[i]["stop"]):
			return true
	return Input.is_key_pressed(KEY_BACKSPACE)


func send_event(name: String) -> void:
	_out.put_packet(("E,%s\n" % name).to_utf8_buffer())
