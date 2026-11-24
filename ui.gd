extends CanvasLayer
## All menus + the in-game HUD. Everything is drawn on one pane so the look matches the world.
## Menus can be driven by mouse, keyboard (W/S/arrows + Enter/Space) or the ESP32 joystick
## (up/down moves the highlight, JUMP button presses it).

const VIEW := Vector2(1280, 720)

var main                      # set by main.gd before add_child
var pane: Node2D
var sel := 0
var items: Array = []         # [{label, id, rect}]
var _t := 0.0
var mouse_pos := Vector2(-999, -999)

const HUD_BTNS := [
	{"id": "pause", "label": "PAUSE", "rect": Rect2(1060, 12, 100, 38)},
	{"id": "restart", "label": "RESTART", "rect": Rect2(1168, 12, 104, 38)},
]


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	pane = Node2D.new()
	add_child(pane)
	pane.draw.connect(_paint)


func _process(delta: float) -> void:
	_t += delta
	pane.queue_redraw()


# ---------------------------------------------------------------- menus
func on_state(s) -> void:
	sel = 0
	items.clear()
	var S = main.State
	match s:
		S.HOME:
			_set_items([["START GAME", "start"], ["HOW TO PLAY", "howto"], ["MUSIC", "music"],
				["SOUND FX", "sfx"], ["VOICES", "voice"], ["STOP / QUIT", "quit"]])
		S.PAUSED:
			_set_items([["RESUME", "resume"], ["RESTART LEVEL", "restart"], ["MUSIC", "music"],
				["SOUND FX", "sfx"], ["VOICES", "voice"], ["STOP - HOME", "home"]])
		S.ENDING:
			_set_items([["PLAY AGAIN", "start"], ["HOME", "home"]])


func _set_items(list: Array) -> void:
	var y0 := 250.0 if main.state == main.State.HOME else 270.0
	var n := 0
	for it in list:
		var small: bool = it[1] in ["music", "sfx", "voice"]
		items.append({"label": it[0], "id": it[1], "small": small, "rect": Rect2(0, 0, 0, 0)})
		n += 1
	# layout: big buttons stacked, toggles side-by-side in a row
	var y := y0
	var toggles: Array = []
	for it in items:
		if it["small"]:
			toggles.append(it)
			continue
		it["rect"] = Rect2(VIEW.x * 0.5 - 170.0, y, 340.0, 58.0)
		y += 70.0
	if main.state == main.State.ENDING:
		for i in items.size():
			items[i]["rect"] = Rect2(VIEW.x * 0.5 - 250.0 + i * 260.0, 610.0, 240.0, 56.0)
		return
	var tx := VIEW.x * 0.5 - 170.0
	for it in toggles:
		it["rect"] = Rect2(tx, y + 4.0, 106.0, 44.0)
		tx += 117.0
	# keep list order stable for keyboard: big buttons first then toggles, stop last
	var stop_item = null
	for it in items:
		if it["id"] in ["quit", "home"]:
			stop_item = it
	if stop_item != null:
		# move the stop button below the toggles
		stop_item["rect"] = Rect2(VIEW.x * 0.5 - 170.0, y + 62.0, 340.0, 58.0)
		items.erase(stop_item)
		items.append(stop_item)


func nav(dir: int) -> void:
	if items.is_empty():
		return
	sel = posmod(sel + dir, items.size())
	Sfx.play("ui_move", -6.0)


func accept() -> void:
	if items.is_empty():
		return
	_do(String(items[sel]["id"]))


func _do(id: String) -> void:
	Sfx.play("ui_click", -4.0)
	match id:
		"start":
			main.start_game()
		"howto":
			main.show_howto()
		"quit":
			main.quit_game()
		"resume":
			main.resume_game()
		"restart":
			main.restart_level()
		"home":
			main.go_home()
		"pause":
			main.pause_game()
		"music":
			Sfx.set_music(not Sfx.music_on)
		"sfx":
			Sfx.sfx_on = not Sfx.sfx_on
		"voice":
			Sfx.voice_on = not Sfx.voice_on


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = event.position
		for i in items.size():
			if (items[i]["rect"] as Rect2).has_point(mouse_pos) and sel != i:
				sel = i
				Sfx.play("ui_move", -8.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		for it in items:
			if (it["rect"] as Rect2).has_point(p):
				_do(String(it["id"]))
				get_viewport().set_input_as_handled()
				return
		var st = main.state
		if st == main.State.PLAY or st == main.State.COUNTDOWN:
			for b in HUD_BTNS:
				if (b["rect"] as Rect2).has_point(p):
					_do(String(b["id"]))
					return
		elif st == main.State.HOWTO:
			main.back_to_menu()


# ---------------------------------------------------------------- painting
func _paint() -> void:
	var S = main.State
	match main.state:
		S.HOME:
			_home()
		S.HOWTO:
			_howto()
		S.COUNTDOWN, S.PLAY:
			_hud()
			if main.state == S.COUNTDOWN:
				_countdown()
		S.PAUSED:
			_hud()
			_veil(0.6)
			_panel("PAUSED", Rect2(VIEW.x * 0.5 - 230.0, 150.0, 460.0, 490.0))
			_draw_items()
		S.CLEAR:
			_hud()
			_tally()
		S.TIMEUP:
			_hud()
			_timeup()
		S.ENDING:
			_ending()
	_stop_ring()


func _veil(a: float) -> void:
	pane.draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.1, 0.07, 0.2, a))


func _panel(title: String, r: Rect2) -> void:
	Look.box(pane, r, Look.CREAM, 30, Look.LAVENDER, 6)
	Look.txt(pane, title, Vector2(r.position.x, r.position.y + 68.0), 48, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _btn(it: Dictionary, selected: bool) -> void:
	var r: Rect2 = it["rect"]
	var id: String = it["id"]
	var col := Look.PINK
	var label: String = it["label"]
	if it["small"]:
		var on: bool = (id == "music" and Sfx.music_on) or (id == "sfx" and Sfx.sfx_on) or (id == "voice" and Sfx.voice_on)
		col = Look.MINT if on else Color("d4cfe0")
		label = label + (" ON" if on else " OFF")
	elif id in ["quit", "home"]:
		col = Look.CORAL.lightened(0.25)
	elif id in ["start", "resume"]:
		col = Look.MINT
	elif id == "restart":
		col = Look.GOLD
	var lift := -4.0 if selected else 0.0
	var rr := Rect2(r.position + Vector2(0, lift), r.size)
	Look.box(pane, rr, col, 18, Look.INK if selected else col.darkened(0.2), 4 if selected else 3)
	var fs := 15 if it["small"] else 26
	Look.txt(pane, label, Vector2(rr.position.x, rr.position.y + rr.size.y * 0.5 + fs * 0.35), fs, Look.INK,
		HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
	if selected:
		Look.sparkle(pane, rr.position + Vector2(-16, rr.size.y * 0.5), 8.0 + sin(_t * 8.0) * 2.0, Look.GOLD)
		Look.sparkle(pane, rr.position + Vector2(rr.size.x + 16, rr.size.y * 0.5), 8.0 + sin(_t * 8.0) * 2.0, Look.GOLD)


func _draw_items() -> void:
	for i in items.size():
		_btn(items[i], i == sel)


# ---------------------------------------------------------------- home
func _home() -> void:
	var cx := VIEW.x * 0.5
	var bob := sin(_t * 2.0) * 5.0
	Look.txt(pane, "NEON INFINITY", Vector2(0, 112.0 + bob), 78, Look.GOLD, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 10)
	Look.txt(pane, "D U O", Vector2(0, 176.0 + bob), 52, Look.PINK, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 8)
	Look.draw_hero(pane, 0, Vector2(cx - 330.0, 330.0 + bob), 1.0, _t, "happy", 0.0, 0.0, 2.2)
	Look.draw_hero(pane, 1, Vector2(cx + 330.0, 330.0 - bob), -1.0, _t, "happy", 0.0, 0.0, 2.2)
	_draw_items()
	# the four always-visible control chips
	var chips := [["START", "Enter / START btn", Look.MINT], ["PAUSE", "P / Esc / PAUSE btn", Look.LAVENDER],
		["RESTART", "R (in game)", Look.GOLD], ["STOP", "hold Backspace / STOP btn", Look.CORAL.lightened(0.25)]]
	for i in 4:
		var r := Rect2(100.0 + i * 270.0, 650.0, 250.0, 54.0)
		Look.box(pane, r, Color(chips[i][2], 0.9), 16, Look.INK, 3)
		Look.txt(pane, chips[i][0], Vector2(r.position.x, r.position.y + 24.0), 20, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		Look.txt(pane, chips[i][1], Vector2(r.position.x, r.position.y + 44.0), 12, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var es := ""
	if Controllers.esp_connected(0) or Controllers.esp_connected(1):
		es = "Joystick controller connected: P1 %s   P2 %s" % ["OK" if Controllers.esp_connected(0) else "--", "OK" if Controllers.esp_connected(1) else "--"]
	else:
		es = "No joystick detected - keyboard works fine!  (P1: A/D + W   P2: arrows)"
	Look.txt(pane, es, Vector2(0, 636.0), 15, Look.CREAM, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 4)


func _howto() -> void:
	var r := Rect2(140, 50, 1000, 620)
	Look.box(pane, r, Look.CREAM, 30, Look.LAVENDER, 6)
	Look.txt(pane, "HOW TO PLAY", Vector2(r.position.x, 118.0), 46, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var lines := [
		["Work together!  Collect every infinity stone, then BOTH heroes step into the exit portal.", Look.INK],
		["EMBER (P1, orange) is safe in orange plasma, but cryo goo hurts.   FROST (P2, blue) is the opposite.", Look.INK],
		["Green acid hurts both.  Meteors, urchins and the alien hurt too - if one is hit, both restart at the flag.", Look.INK],
		["Beat the clock: every whole second left is worth +10 points for each player.", Look.INK],
		["Out of time? The level simply restarts - you can do it!", Look.INK],
	]
	var y := 170.0
	for l in lines:
		Look.txt(pane, l[0], Vector2(r.position.x + 40.0, y), 19, l[1], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80.0)
		y += 36.0
	var hdr := Look.P1_DARK
	Look.txt(pane, "CONTROLS", Vector2(r.position.x, 372.0), 28, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Look.txt(pane, "PLAYER 1 (EMBER)", Vector2(r.position.x + 40.0, 416.0), 22, hdr)
	Look.txt(pane, "Keyboard:  A / D move,  W or Space jump", Vector2(r.position.x + 40.0, 448.0), 18, Look.INK)
	Look.txt(pane, "Joystick:  stick left/right, buttons JUMP / STOP / PAUSE / START", Vector2(r.position.x + 40.0, 474.0), 18, Look.INK)
	Look.txt(pane, "PLAYER 2 (FROST)", Vector2(r.position.x + 40.0, 520.0), 22, Look.P2_DARK)
	Look.txt(pane, "Keyboard:  Left / Right move,  Up jump", Vector2(r.position.x + 40.0, 552.0), 18, Look.INK)
	Look.txt(pane, "Joystick:  same layout on the second controller", Vector2(r.position.x + 40.0, 578.0), 18, Look.INK)
	Look.txt(pane, "Anytime:  P / Esc = pause,  R = restart level,  hold Backspace or STOP button = go home",
		Vector2(r.position.x, 620.0), 17, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Look.txt(pane, "press any button to go back", Vector2(r.position.x, 652.0), 14, Look.LAVENDER.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


# ---------------------------------------------------------------- HUD
func _fmt(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [s / 60, s % 60]


func _hud() -> void:
	var m = main
	# top bar
	Look.box(pane, Rect2(10, 8, 1040, 46), Color(Look.INK, 0.72), 22)
	var title := "LEVEL %d  %s" % [m.level_idx + 1, m.level["name"]]
	Look.txt(pane, title, Vector2(30, 40), 22, Look.CREAM)
	var tier: String = ["EASY", "EASY", "MEDIUM", "MEDIUM", "HARD", "HARD", "BOSS"][m.level_idx]
	Look.txt(pane, tier, Vector2(30.0 + Look.text_w(title, 22) + 12.0, 40), 14, Look.GOLD)
	# timer
	var low: bool = m.time_left < 10.0
	var tcol := Look.CORAL if low and int(_t * 4.0) % 2 == 0 else Look.CREAM
	var secs: int = int(ceil(m.time_left))
	var tr := Rect2(480, 12, 130, 38)
	Look.box(pane, tr, Look.INK, 18, Look.GOLD if not low else Look.CORAL, 3)
	Look.txt(pane, "%d s" % secs, Vector2(tr.position.x, tr.position.y + 29.0), 28, tcol, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
	# time bar
	var frac: float = clampf(m.time_left / m.time_limit, 0.0, 1.0)
	Look.box(pane, Rect2(620, 22, 180, 18), Color(1, 1, 1, 0.2), 9)
	if frac > 0.02:
		Look.box(pane, Rect2(620, 22, 180.0 * frac, 18), Look.MINT if frac > 0.25 else Look.CORAL, 9)
	# gems
	Look.gem(pane, Vector2(840, 31), 11.0, Look.GOLD, _t, false)
	Look.txt(pane, "%d / %d" % [m.stones_got, m.stones_total], Vector2(858, 40), 22, Look.CREAM)
	Look.txt(pane, "bonus +%d" % (int(m.time_left) * 10), Vector2(930, 40), 17, Look.MINT)
	# per-player score chips (bottom corners so they never hide the action)
	_score_chip(Rect2(12, 668, 230, 42), 0)
	_score_chip(Rect2(1038, 668, 230, 42), 1)
	# clickable pause / restart
	for b in HUD_BTNS:
		var r: Rect2 = b["rect"]
		var hov := r.has_point(mouse_pos)
		Look.box(pane, r, Look.LAVENDER if b["id"] == "pause" else Look.GOLD, 16, Look.INK, 3 if hov else 2)
		Look.txt(pane, b["label"], Vector2(r.position.x, r.position.y + 25.0), 16, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# alien warning: green pulse on the left edge when it is close
	if m.alien_on and m.players.size() == 2:
		var rear: float = minf(m.players[0].position.x, m.players[1].position.x)
		var near: float = clampf((760.0 - (rear - m.alien_x)) / 500.0, 0.0, 1.0)
		if near > 0.0:
			var a: float = near * (0.35 + 0.15 * sin(_t * 9.0))
			for k in 8:
				pane.draw_rect(Rect2(0, 0, 90.0 - k * 10.0, VIEW.y), Color(0.45, 1.0, 0.4, a * 0.18))
			Look.txt(pane, "ALIEN!", Vector2(14, 360), 26, Color(0.6, 1.0, 0.5, clampf(near * 1.6, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 5)
	# banner
	if m.banner_t > 0.0 and m.state == m.State.PLAY:
		var a: float = clampf(m.banner_t * 3.0, 0.0, 1.0)
		var w: float = Look.text_w(m.banner, 24) + 50.0
		var br := Rect2(VIEW.x * 0.5 - w * 0.5, 74, w, 42)
		Look.box(pane, br, Color(Look.CREAM, a * 0.95), 21, Color(Look.INK, a), 3)
		Look.txt(pane, m.banner, Vector2(br.position.x, br.position.y + 29.0), 24, Color(Look.INK, a), HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
	if m.go_t > 0.0:
		Look.txt(pane, "GO!", Vector2(0, 340), 120, Look.MINT, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 12)


func _score_chip(r: Rect2, i: int) -> void:
	var col: Color = Look.P1_BODY if i == 0 else Look.P2_BODY
	Look.box(pane, r, Color(Look.INK, 0.75), 20, col, 3)
	Look.txt(pane, "%s  P%d" % [main.HERO_NAMES[i], i + 1], Vector2(r.position.x + 14.0, r.position.y + 27.0), 15, col)
	var tot: int = int(main.score[i]) + int(main.lvl_pts[i])
	Look.txt(pane, str(tot), Vector2(r.position.x, r.position.y + 29.0), 24, Look.CREAM, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14.0)


func _countdown() -> void:
	var m = main
	var n := int(ceil(m.countdown_t - 0.9))
	Look.box(pane, Rect2(VIEW.x * 0.5 - 330, 180, 660, 180), Color(Look.INK, 0.65), 36)
	Look.txt(pane, "LEVEL %d" % (m.level_idx + 1), Vector2(0, 245), 38, Look.GOLD, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 6)
	Look.txt(pane, m.level["name"], Vector2(0, 295), 44, Look.CREAM, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 6)
	Look.txt(pane, String(m.level["hint"]), Vector2(0, 336), 19, Look.PINK, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 4)
	Look.txt(pane, "Time limit: %d s" % int(m.time_limit), Vector2(0, 392), 22, Look.MINT, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 4)
	if n >= 1 and n <= 3:
		Look.txt(pane, str(n), Vector2(0, 520), 120, Look.GOLD, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 12)


# ---------------------------------------------------------------- level clear tally
func _tally() -> void:
	var m = main
	_veil(0.35)
	var r := Rect2(VIEW.x * 0.5 - 340.0, 130.0, 680.0, 440.0)
	Look.box(pane, r, Look.CREAM, 30, Look.MINT, 6)
	Look.txt(pane, "LEVEL %d CLEAR!" % (m.level_idx + 1), Vector2(r.position.x, r.position.y + 62.0), 46, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Look.txt(pane, "Time used: %d s of %d s" % [int(m.level_time_used), int(m.time_limit)],
		Vector2(r.position.x, r.position.y + 96.0), 20, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Look.txt(pane, "EMBER", Vector2(r.position.x + 390.0, r.position.y + 140.0), 20, Look.P1_DARK, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
	Look.txt(pane, "FROST", Vector2(r.position.x + 530.0, r.position.y + 140.0), 20, Look.P2_DARK, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
	var y := r.position.y + 190.0
	var run_a := 0
	var run_b := 0
	for i in m.tally.size():
		if i >= m.tally_shown:
			break
		var row: Dictionary = m.tally[i]
		Look.txt(pane, String(row["label"]), Vector2(r.position.x + 36.0, y), 20, Look.INK)
		Look.txt(pane, "+%d" % int(row["a"]), Vector2(r.position.x + 390.0, y), 24, Look.INK, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
		Look.txt(pane, "+%d" % int(row["b"]), Vector2(r.position.x + 530.0, y), 24, Look.INK, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
		run_a += int(row["a"])
		run_b += int(row["b"])
		y += 46.0
	pane.draw_line(Vector2(r.position.x + 30.0, r.position.y + 340.0), Vector2(r.end.x - 30.0, r.position.y + 340.0), Look.LAVENDER, 3.0)
	Look.txt(pane, "TOTAL SCORE", Vector2(r.position.x + 36.0, r.position.y + 384.0), 24, Look.INK)
	Look.txt(pane, str(int(m.score[0])), Vector2(r.position.x + 380.0, r.position.y + 384.0), 30, Look.P1_DARK, HORIZONTAL_ALIGNMENT_RIGHT, 110.0)
	Look.txt(pane, str(int(m.score[1])), Vector2(r.position.x + 520.0, r.position.y + 384.0), 30, Look.P2_DARK, HORIZONTAL_ALIGNMENT_RIGHT, 110.0)
	if m.tally_shown >= m.tally.size():
		Look.txt(pane, "press JUMP / Enter to continue", Vector2(r.position.x, r.position.y + 424.0), 14, Look.LAVENDER.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _timeup() -> void:
	_veil(0.5)
	var bob := sin(_t * 10.0) * 4.0
	Look.txt(pane, "TIME'S UP!", Vector2(0, 320.0 + bob), 96, Look.CORAL, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 12)
	Look.txt(pane, "Let's try again - you can do it!", Vector2(0, 385), 30, Look.CREAM, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 6)


# ---------------------------------------------------------------- results screen
func _ending() -> void:
	var m = main
	_veil(0.35)
	for k in 18:
		var x := fposmod(float(k) * 97.0 + _t * 40.0, VIEW.x)
		var y := fposmod(float(k) * 53.0 + _t * 60.0, VIEW.y)
		Look.sparkle(pane, Vector2(x, y), 5.0 + float(k % 3) * 2.0, Color(Look.GOLD, 0.8))
	var r := Rect2(190, 28, 900, 570)
	Look.box(pane, r, Look.CREAM, 30, Look.GOLD, 6)
	Look.txt(pane, "YOU SAVED THE GALAXY!", Vector2(r.position.x, 98.0), 50, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var s0: int = m.score[0]
	var s1: int = m.score[1]
	for i in 2:
		var cx: float = r.position.x + 270.0 + i * 360.0
		Look.draw_hero(pane, i, Vector2(cx, 250.0), 1.0 if i == 0 else -1.0, _t, "happy", 0.0, 0.0, 1.9)
		Look.txt(pane, m.HERO_NAMES[i], Vector2(cx - 120.0, 286.0), 24, Look.P1_DARK if i == 0 else Look.P2_DARK, HORIZONTAL_ALIGNMENT_CENTER, 240.0)
		Look.txt(pane, "%d" % (s0 if i == 0 else s1), Vector2(cx - 120.0, 338.0), 52, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, 240.0)
		Look.txt(pane, "points", Vector2(cx - 120.0, 362.0), 16, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	var winner := "It's a TIE - perfect teamwork!" if s0 == s1 else ("EMBER collected the most points!" if s0 > s1 else "FROST collected the most points!")
	Look.txt(pane, winner, Vector2(r.position.x, 400.0), 22, Look.P1_DARK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Look.box(pane, Rect2(r.position.x + 40.0, 424.0, r.size.x - 80.0, 56.0), Look.INK, 24)
	Look.txt(pane, "TOTAL TIME   %s" % _fmt(m.run_time), Vector2(r.position.x, 462.0), 32, Look.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Look.txt(pane, "Team total: %d points     Restarts: %d" % [s0 + s1, m.deaths], Vector2(r.position.x, 512.0), 20, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var best := 0
	for lr in m.level_results:
		best += int(lr["tries"]) - 1
	Look.txt(pane, "Time-outs / retries: %d     (all %d levels cleared)" % [best, m.level_results.size()], Vector2(r.position.x, 544.0), 17, Look.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_draw_items()


# ---------------------------------------------------------------- hold-to-stop ring
func _stop_ring() -> void:
	if main.stop_hold <= 0.05:
		return
	var c := Vector2(VIEW.x * 0.5, 360)
	var f: float = clampf(main.stop_hold, 0.0, 1.0)
	pane.draw_circle(c, 60.0, Color(Look.INK, 0.7))
	pane.draw_arc(c, 48.0, -PI * 0.5, -PI * 0.5 + TAU * f, 40, Look.CORAL, 10.0)
	Look.txt(pane, "STOP", Vector2(c.x - 40.0, c.y + 8.0), 22, Look.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
