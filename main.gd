extends Node2D
## NEON INFINITY DUO - game manager: state machine, level building, rules, scoring, banter,
## the alien chase, and drawing of the world. Menus/HUD live in ui.gd, background in bg.gd.

const Levels := preload("res://scripts/levels.gd")
const PlayerScript := preload("res://scripts/player.gd")
const UIScript := preload("res://scripts/ui.gd")
const BGScript := preload("res://scripts/bg.gd")

const TILE := 32
const ROWS := 22
const VIEW := Vector2(1280, 720)
const HERO_NAMES := ["EMBER", "FROST"]
const STONE_NAMES := ["SPACE", "MIND", "REALITY", "POWER", "TIME", "SOUL"]
const STONE_COLORS := [Color("5b8cff"), Color("ffd84d"), Color("ff5d73"), Color("b46bff"), Color("4dff9a"), Color("ff9b4d")]
const HAZ := {"f": Color("ff8a4c"), "i": Color("62d0ff"), "a": Color("9be34f")}
const METEOR_WARN := 0.9
const METEOR_SPEED := 430.0
const MAX_SEP := 1000.0          # the heroes are "tethered" this far apart on wide levels

# --- scoring ---
const PTS_STONE := 100
const PTS_CLEAR := 50
const PTS_PER_SEC := 10          # +10 for every whole second left on the clock

enum State { HOME, HOWTO, COUNTDOWN, PLAY, PAUSED, CLEAR, TIMEUP, ENDING }

var state: State = State.HOME
var level_idx := 0
var level: Dictionary = {}
var level_w := 1280.0
var cols := 40
var level_root: Node2D
var cam: Camera2D
var ui: CanvasLayer
var bg: Node2D

var players: Array = []
var respawn_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var wall_rects: Array[Rect2] = []
var hazards: Array = []
var stones: Array = []
var checkpoints: Array = []
var shields: Array = []
var meteors: Array = []
var patrols: Array = []
var particles: Array = []
var exit_rect := Rect2()
var meteor_every := 0.0

var stones_total := 0
var stones_got := 0
var time_limit := 30.0
var time_left := 30.0
var run_time := 0.0               # all active play time, retries included
var level_time_used := 0.0
var attempts_this_level := 0
var deaths := 0
var score: Array = [0, 0]         # banked points
var lvl_pts: Array = [0, 0]       # gem points in the current attempt (banked on clear)
var level_results: Array = []
var tally: Array = []
var tally_t := 0.0
var tally_shown := 0

var countdown_t := 0.0
var go_t := 0.0
var timeup_t := 0.0
var respawn_t := 0.0
var banner := ""
var banner_t := 0.0
var shake := 0.0
var stop_hold := 0.0
var exit_hint_cd := 0.0

var voice_cd: Array = [0.0, 0.0]
var danger_t := 0.0
var apart_t := 0.0
var relief_cd := 0.0

var alien_on := false
var alien_x := -1000.0
var alien_roar_t := 0.0
var min_alien_gap := 99999.0      # telemetry for the automated tests

var cheat_invincible := false     # used only by the automated tests
var t_anim := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	bg = BGScript.new()
	bg_layer.add_child(bg)
	cam = Camera2D.new()
	cam.position = VIEW * 0.5
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = 1280
	cam.limit_bottom = 720
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	add_child(cam)
	ui = UIScript.new()
	ui.main = self
	add_child(ui)
	Controllers.hw_button.connect(_on_hw_button)
	Controllers.hw_nav.connect(_on_hw_nav)
	set_state(State.HOME)
	Sfx.start_music()


func set_state(s: State) -> void:
	state = s
	ui.on_state(s)


# =====================================================================
#  PUBLIC ACTIONS (called by the menus, hardware buttons and keyboard)
# =====================================================================
func start_game() -> void:
	get_tree().paused = false
	score = [0, 0]
	run_time = 0.0
	deaths = 0
	level_results.clear()
	load_level(0)


func quit_game() -> void:
	get_tree().quit()


func show_howto() -> void:
	set_state(State.HOWTO)


func back_to_menu() -> void:
	set_state(State.HOME)


func pause_game() -> void:
	if state != State.PLAY and state != State.COUNTDOWN:
		return
	get_tree().paused = true
	Sfx.play("pause")
	Sfx.duck(true)
	Controllers.send_event("pause")
	set_state(State.PAUSED)


func resume_game() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	Sfx.play("pause")
	Sfx.duck(false)
	Controllers.send_event("resume")
	set_state(State.PLAY if countdown_t <= 0.0 else State.COUNTDOWN)


func restart_level() -> void:
	if state == State.HOME or state == State.HOWTO or state == State.ENDING:
		return
	get_tree().paused = false
	Sfx.duck(false)
	attempts_this_level += 1
	load_level(level_idx, true)


func go_home() -> void:
	get_tree().paused = false
	Sfx.duck(false)
	if level_root:
		level_root.queue_free()
		level_root = null
	players.clear()
	wall_rects.clear()
	hazards.clear()
	stones.clear()
	checkpoints.clear()
	shields.clear()
	meteors.clear()
	patrols.clear()
	particles.clear()
	alien_on = false
	bg.set_theme(0)
	bg.scroll = 0.0
	cam.limit_right = 1280
	cam.position = VIEW * 0.5
	cam.reset_smoothing()
	Controllers.send_event("home")
	set_state(State.HOME)


# =====================================================================
#  LEVEL LOADING
# =====================================================================
func load_level(idx: int, retry: bool = false) -> void:
	level_idx = idx
	if not retry:
		attempts_this_level = 0
	if level_root:
		level_root.queue_free()
	level_root = Node2D.new()
	level_root.visible = true
	level_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level_root)

	players.clear()
	wall_rects.clear()
	hazards.clear()
	stones.clear()
	checkpoints.clear()
	shields.clear()
	meteors.clear()
	patrols.clear()
	particles.clear()

	level = Levels.DATA[idx]
	var map: Array = level["map"]
	cols = (map[0] as String).length()
	level_w = float(cols * TILE)
	time_limit = float(level["time"])
	time_left = time_limit
	meteor_every = float(level["meteor_every"])
	level_time_used = 0.0
	lvl_pts = [0, 0]
	stones_got = 0
	respawn_t = 0.0
	timeup_t = 0.0
	go_t = 0.0

	var solid: Array = []
	var stone_n := 0
	for r in ROWS:
		var line: String = map[r]
		var row: Array = []
		row.resize(cols)
		row.fill(false)
		var c := 0
		while c < cols:
			var ch: String = line[c]
			var cx := c * TILE + TILE * 0.5
			var bottom := float((r + 1) * TILE)
			match ch:
				"#":
					row[c] = true
				"1":
					respawn_pos[0] = Vector2(cx, bottom - PlayerScript.SIZE.y * 0.5 - 0.5)
				"2":
					respawn_pos[1] = Vector2(cx, bottom - PlayerScript.SIZE.y * 0.5 - 0.5)
				"*":
					stones.append({"pos": Vector2(cx, r * TILE + TILE * 0.5), "got": false,
						"kind": (idx * 2 + stone_n) % 6})
					stone_n += 1
				"f", "i", "a":
					var c0 := c
					while c + 1 < cols and line[c + 1] == ch:
						c += 1
					hazards.append({"rect": Rect2(c0 * TILE, r * TILE + 10, (c - c0 + 1) * TILE, TILE - 10),
						"kind": ch, "seed": c0})
				"c":
					checkpoints.append({"rect": Rect2(c * TILE - 6, r * TILE - 32, TILE + 12, TILE * 2),
						"base": Vector2(cx, bottom - 15.5), "active": false})
				"S":
					shields.append({"pos": Vector2(cx, r * TILE + TILE * 0.5), "taken": false})
				"M":
					if meteor_every > 0.0:
						meteors.append({"x": cx, "y": 0.0, "stop": VIEW.y, "state": 0,
							"t": 1.5 + float(meteors.size()) * 0.8})
				"E":
					exit_rect = Rect2(c * TILE - 8, bottom - 64, TILE + 16, 64)
			c += 1
		solid.append(row)

	for pt in level["patrols"]:
		patrols.append({"cx": float(pt["x"]), "y": float((int(pt["row"]) + 1) * TILE) - 12.0,
			"range": float(pt["range"]), "speed": float(pt["speed"]), "ph": 0.0, "rect": Rect2()})

	wall_rects = _merge_walls(solid)
	for w in wall_rects:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = w.size
		cs.shape = rs
		body.position = w.position + w.size * 0.5
		body.add_child(cs)
		level_root.add_child(body)

	for i in 2:
		var p = PlayerScript.new()
		p.setup(i)
		p.position = respawn_pos[i]
		p.frozen = true
		p.jumped.connect(_on_jumped)
		p.landed.connect(_on_landed)
		level_root.add_child(p)
		players.append(p)

	stones_total = stones.size()
	alien_on = bool(level["alien"])
	alien_x = respawn_pos[0].x - 560.0
	alien_roar_t = 0.0
	min_alien_gap = 99999.0
	voice_cd = [2.0, 3.0]
	danger_t = 0.0
	apart_t = 0.0
	relief_cd = 0.0

	bg.set_theme(int(level["theme"]))
	cam.limit_right = int(level_w)
	cam.position = Vector2(clampf((respawn_pos[0].x + respawn_pos[1].x) * 0.5, 640.0, maxf(640.0, level_w - 640.0)), 360.0)
	cam.reset_smoothing()

	countdown_t = 2.4 if attempts_this_level == 0 else 1.3
	Sfx.duck(false)
	Controllers.send_event("level")
	set_state(State.COUNTDOWN)


## Merge solid tiles into as few rectangles as possible (fewer collision shapes).
func _merge_walls(solid: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var open := {}
	for r in range(ROWS + 1):
		var cur := {}
		if r < ROWS:
			var c := 0
			while c < cols:
				if solid[r][c]:
					var c0 := c
					while c < cols and solid[r][c]:
						c += 1
					cur[Vector2i(c0, c - 1)] = true
				else:
					c += 1
		for key in open.keys():
			if not cur.has(key):
				var r0: int = open[key]
				out.append(Rect2(key.x * TILE, r0 * TILE, (key.y - key.x + 1) * TILE, (r - r0) * TILE))
				open.erase(key)
		for key in cur.keys():
			if not open.has(key):
				open[key] = r
	return out


# =====================================================================
#  INPUT
# =====================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	var in_menu: bool = state == State.HOME or state == State.PAUSED or state == State.ENDING
	if in_menu:
		if k == KEY_UP or k == KEY_W:
			ui.nav(-1)
		elif k == KEY_DOWN or k == KEY_S:
			ui.nav(1)
		elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			ui.accept()
	match k:
		KEY_ESCAPE, KEY_P:
			if state == State.PLAY or state == State.COUNTDOWN:
				pause_game()
			elif state == State.PAUSED:
				resume_game()
			elif state == State.HOWTO:
				back_to_menu()
		KEY_R:
			if state == State.PLAY or state == State.PAUSED or state == State.COUNTDOWN:
				restart_level()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if state == State.CLEAR:
				_skip_tally()
			elif state == State.HOWTO:
				back_to_menu()


func _on_hw_button(btn: String, _player: int) -> void:
	match state:
		State.HOME:
			if btn == "start":
				start_game()
			elif btn == "jump":
				ui.accept()
		State.HOWTO:
			back_to_menu()
		State.PAUSED:
			if btn == "pause" or btn == "start":
				resume_game()
			elif btn == "jump":
				ui.accept()
		State.PLAY, State.COUNTDOWN:
			if btn == "pause":
				pause_game()
		State.CLEAR:
			if btn == "start" or btn == "jump":
				_skip_tally()
		State.ENDING:
			if btn == "start":
				start_game()
			elif btn == "jump":
				ui.accept()


func _on_hw_nav(dir: int) -> void:
	if state == State.HOME or state == State.PAUSED or state == State.ENDING:
		ui.nav(dir)


# =====================================================================
#  FRAME LOOPS
# =====================================================================
func _process(delta: float) -> void:
	t_anim += delta
	banner_t = maxf(0.0, banner_t - delta)
	exit_hint_cd = maxf(0.0, exit_hint_cd - delta)
	# hold STOP (hardware button or Backspace) for one second to quit to the home screen
	if (state == State.PLAY or state == State.COUNTDOWN or state == State.PAUSED) and Controllers.stop_held():
		stop_hold += delta
		if stop_hold >= 1.0:
			stop_hold = 0.0
			go_home()
	else:
		stop_hold = maxf(0.0, stop_hold - delta * 3.0)
	if state != State.PAUSED:
		_update_camera(delta)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if state == State.PAUSED:
		return
	_update_particles(delta)
	match state:
		State.COUNTDOWN:
			countdown_t -= delta
			if countdown_t <= 0.0:
				countdown_t = 0.0
				_begin_play()
		State.PLAY:
			go_t = maxf(0.0, go_t - delta)
			_tick_play(delta)
		State.CLEAR:
			_tick_clear(delta)
		State.TIMEUP:
			timeup_t -= delta
			if timeup_t <= 0.0:
				attempts_this_level += 1
				load_level(level_idx, true)


func _begin_play() -> void:
	for p in players:
		p.frozen = false
	go_t = 0.8
	Sfx.play("go")
	set_state(State.PLAY)


func _update_camera(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 2.5)
	cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 9.0
	if players.size() == 2:
		var mid: float = (players[0].position.x + players[1].position.x) * 0.5
		cam.position = Vector2(clampf(mid, 640.0, maxf(640.0, level_w - 640.0)), 360.0)
	bg.scroll = cam.get_screen_center_position().x


func _tick_play(delta: float) -> void:
	run_time += delta
	level_time_used += delta
	time_left -= delta
	if time_left <= 0.0:
		_time_up()
		return
	_update_meteors(delta)
	_update_patrols(delta)
	_apply_tether()
	if respawn_t > 0.0:
		respawn_t -= delta
		if respawn_t <= 0.0:
			_respawn_players()
		return
	_update_alien(delta)
	if respawn_t > 0.0:
		return

	for p in players:
		var hb: Rect2 = p.hurtbox()
		if p.position.y > VIEW.y + 80.0:
			if _try_hurt(p, "Whoops! Both back to the flag"):
				return
		for h in hazards:
			var hr: Rect2 = h["rect"]
			if hr.intersects(hb) and _hazard_hurts(String(h["kind"]), p.id):
				if _try_hurt(p, "Oopsie! Both back to the flag"):
					return
		for pt in patrols:
			var pr: Rect2 = pt["rect"]
			if pr.intersects(hb):
				if _try_hurt(p, "Ouch! Spiky urchin!"):
					return
		for m in meteors:
			if int(m["state"]) == 2 and Rect2(float(m["x"]) - 9.0, float(m["y"]) - 9.0, 18.0, 18.0).intersects(hb):
				if _try_hurt(p, "Bonk! A meteor!"):
					return
		for s in stones:
			if not s["got"] and (s["pos"] as Vector2).distance_to(p.position) < 26.0:
				s["got"] = true
				stones_got += 1
				lvl_pts[p.id] += PTS_STONE
				Sfx.play("ka_ching")
				Controllers.send_event("stone")
				_burst(s["pos"], STONE_COLORS[int(s["kind"])], 14, 150.0)
				p.set_mood("happy", 0.9)
				_banner("%s STONE found!  (%d/%d)" % [STONE_NAMES[int(s["kind"])], stones_got, stones_total], 1.6)
		for sh in shields:
			if not sh["taken"] and not p.shield and (sh["pos"] as Vector2).distance_to(p.position) < 26.0:
				sh["taken"] = true
				p.shield = true
				Sfx.play("shield")
				_burst(sh["pos"], Color("8ff0ff"), 10, 120.0)
		for cp in checkpoints:
			var cr: Rect2 = cp["rect"]
			if not cp["active"] and cr.has_point(p.position):
				for o in checkpoints:
					o["active"] = false
				cp["active"] = true
				var base: Vector2 = cp["base"]
				respawn_pos[0] = base + Vector2(-9, 0)
				respawn_pos[1] = base + Vector2(9, 0)
				Sfx.play("checkpoint")
				Controllers.send_event("checkpoint")
				_burst(base + Vector2(0, -20), Color("ffe27a"), 12, 130.0)
				_banner("Checkpoint saved!", 1.3)
				_relief(0)
				_relief(1)

	_check_exit()
	_banter(delta)


func _hazard_hurts(kind: String, pid: int) -> bool:
	match kind:
		"a":
			return true
		"f":
			return pid == 1      # orange plasma goo only hurts Frost
		"i":
			return pid == 0      # blue cryo goo only hurts Ember
	return false


## Returns true if this caused a shared respawn.
func _try_hurt(p, msg: String) -> bool:
	if cheat_invincible or p.invuln > 0.0:
		return false
	if p.shield:
		p.shield = false
		p.invuln = 1.5
		Sfx.play("shield", -4.0, 0.7)
		_banner("Shield saved you!", 1.0)
		return false
	_hurt_everyone(msg)
	return true


func _hurt_everyone(msg: String) -> void:
	deaths += 1
	respawn_t = 0.9
	shake = 1.0
	Sfx.play("hurt")
	Controllers.send_event("hurt")
	_banner(msg, 1.0)
	for q in players:
		q.frozen = true
		q.velocity = Vector2.ZERO
		q.set_mood("hurt", 0.9)
		_burst(q.position, Color("ffffff"), 8, 140.0)
	if alien_on:
		alien_x = minf(alien_x, respawn_pos[0].x - 560.0)


func _respawn_players() -> void:
	for p in players:
		p.position = respawn_pos[p.id]
		p.velocity = Vector2.ZERO
		p.frozen = false
		p.invuln = 1.2
		p.set_mood("normal", 0.0)


func _check_exit() -> void:
	var both := true
	for p in players:
		if not exit_rect.has_point(p.position):
			both = false
	if not both:
		return
	if stones_got >= stones_total and stones_total > 0:
		_level_clear()
	elif exit_hint_cd <= 0.0:
		exit_hint_cd = 3.0
		_banner("Collect all the gems first!", 1.6)


# =====================================================================
#  HAZARDS THAT MOVE
# =====================================================================
func _update_meteors(delta: float) -> void:
	for m in meteors:
		match int(m["state"]):
			0:
				m["t"] = float(m["t"]) - delta
				if float(m["t"]) <= 0.0:
					m["state"] = 1
					m["t"] = METEOR_WARN
					m["stop"] = _meteor_stop_y(float(m["x"]))
			1:
				m["t"] = float(m["t"]) - delta
				if float(m["t"]) <= 0.0:
					m["state"] = 2
					m["y"] = TILE * 1.5
			2:
				m["y"] = float(m["y"]) + METEOR_SPEED * delta
				if float(m["y"]) >= float(m["stop"]) - 8.0:
					var impact := Vector2(float(m["x"]), float(m["stop"]))
					m["state"] = 0
					m["t"] = meteor_every + randf() * 1.2
					_burst(impact, Color("ffb066"), 10, 160.0)
					for p in players:     # a near miss earns a sigh of relief
						if absf(p.position.x - impact.x) < 70.0 and absf(p.position.y - impact.y) < 90.0 and relief_cd <= 0.0:
							_relief(p.id)
							relief_cd = 5.0


func _meteor_stop_y(x: float) -> float:
	var best := VIEW.y
	for w in wall_rects:
		if x >= w.position.x and x <= w.end.x and w.position.y > 40.0 and w.position.y < best:
			best = w.position.y
	return best


func _update_patrols(delta: float) -> void:
	for pt in patrols:
		var rng: float = maxf(float(pt["range"]), 1.0)
		pt["ph"] = float(pt["ph"]) + delta * float(pt["speed"]) / rng
		var pos := Vector2(float(pt["cx"]) + sin(float(pt["ph"])) * rng, float(pt["y"]))
		pt["rect"] = Rect2(pos - Vector2(11, 11), Vector2(22, 22))


func _alien_speed() -> float:
	var lead: float = maxf(players[0].position.x, players[1].position.x)
	return lerpf(110.0, 175.0, clampf(lead / level_w, 0.0, 1.0))


func _update_alien(delta: float) -> void:
	if not alien_on:
		return
	alien_x += _alien_speed() * delta
	var rear: float = minf(players[0].position.x, players[1].position.x)
	var gap := rear - alien_x
	min_alien_gap = minf(min_alien_gap, gap)
	alien_roar_t -= delta
	if gap < 420.0:
		shake = maxf(shake, 0.25 + (420.0 - gap) / 900.0)
		if alien_roar_t <= 0.0:
			alien_roar_t = 3.2
			Sfx.play("alien_roar", -2.0)
			Controllers.send_event("alien")
	if gap < 18.0 and not cheat_invincible:
		_hurt_everyone("The alien got you!")


func _apply_tether() -> void:
	if level_w < 1300.0 or players.size() < 2:
		return
	var a: float = players[0].position.x
	var b: float = players[1].position.x
	if absf(a - b) > MAX_SEP:
		var lead: int = 0 if a > b else 1
		var follow: int = 1 - lead
		players[lead].position.x = players[follow].position.x + MAX_SEP
		players[lead].velocity.x = minf(players[lead].velocity.x, 0.0)


# =====================================================================
#  TEAMWORK BANTER  ("Watch out!", "You can do it!", sighs of relief)
# =====================================================================
func _banter(delta: float) -> void:
	for i in 2:
		voice_cd[i] = maxf(0.0, float(voice_cd[i]) - delta)
	relief_cd = maxf(0.0, relief_cd - delta)
	danger_t -= delta
	if danger_t <= 0.0:
		danger_t = 0.2
		for target in 2:
			var speaker := 1 - target
			if float(voice_cd[speaker]) > 0.0 or players[speaker].frozen:
				continue
			if _danger_near(players[target]):
				_say(speaker, "watch_out", "Watch out!", 4.0)
				break
	var d: Vector2 = players[0].position - players[1].position
	if absf(d.x) > 520.0 or absf(d.y) > 300.0:
		apart_t += delta
	else:
		apart_t = minf(apart_t, 0.0)
	if apart_t > 1.5:
		var lead := 0 if players[0].position.x > players[1].position.x else 1
		if float(voice_cd[lead]) <= 0.0:
			_say(lead, "you_can_do_it", "You can do it!", 9.0)
			apart_t = -6.0


func _danger_near(p) -> bool:
	var hb: Rect2 = p.hurtbox()
	var ahead := 120.0
	var zone := hb.grow_individual(ahead if p.facing < 0.0 else 20.0, 22.0, ahead if p.facing > 0.0 else 20.0, 8.0)
	for h in hazards:
		var hr: Rect2 = h["rect"]
		if _hazard_hurts(String(h["kind"]), p.id) and zone.intersects(hr) and not hb.intersects(hr):
			return true
	for pt in patrols:
		var pr: Rect2 = pt["rect"]
		if zone.intersects(pr.grow(14.0)):
			return true
	for m in meteors:
		var mx: float = m["x"]
		if int(m["state"]) == 1 and absf(mx - p.position.x) < 90.0:
			return true
		if int(m["state"]) == 2 and absf(mx - p.position.x) < 70.0 and float(m["y"]) < p.position.y:
			return true
	if alien_on and p.position.x - alien_x < 520.0 and p.position.x - alien_x > 0.0:
		return true
	return false


func _say(i: int, key: String, text: String, cooldown: float) -> void:
	players[i].say(text, 1.5)
	Sfx.voice(i, key)
	voice_cd[i] = cooldown


func _relief(i: int) -> void:
	Sfx.play("sigh_p%d" % (i + 1), -3.0)
	players[i].say("Phew~", 1.3)
	players[i].set_mood("happy", 1.3)


func _banner(text: String, seconds: float) -> void:
	banner = text
	banner_t = seconds


# =====================================================================
#  LEVEL CLEAR / TIME UP / ENDING
# =====================================================================
func _level_clear() -> void:
	var secs := int(time_left)
	var bonus := secs * PTS_PER_SEC
	tally = [
		{"label": "Gems collected", "a": lvl_pts[0], "b": lvl_pts[1]},
		{"label": "Level complete", "a": PTS_CLEAR, "b": PTS_CLEAR},
		{"label": "Speed bonus  (%d s left x %d)" % [secs, PTS_PER_SEC], "a": bonus, "b": bonus},
	]
	for i in 2:
		score[i] += int(lvl_pts[i]) + PTS_CLEAR + bonus
	level_results.append({"time": level_time_used, "bonus": bonus, "tries": attempts_this_level + 1})
	tally_t = 0.0
	tally_shown = 0
	for p in players:
		p.frozen = true
		p.shield = false
		p.set_mood("happy", 6.0)
	Sfx.play("clear")
	Controllers.send_event("clear")
	_relief(0)
	_burst(exit_rect.get_center(), Color("fff2a0"), 30, 220.0)
	set_state(State.CLEAR)


func _tick_clear(delta: float) -> void:
	tally_t += delta
	var marks := [0.9, 1.7, 2.5]
	while tally_shown < tally.size() and tally_t >= float(marks[tally_shown]):
		tally_shown += 1
		Sfx.play("ka_ching")
	if tally_shown >= tally.size() and tally_t >= 4.2:
		_next_level()


func _skip_tally() -> void:
	if tally_shown >= tally.size() and tally_t >= 3.0:
		_next_level()


func _next_level() -> void:
	if level_idx + 1 < Levels.DATA.size():
		load_level(level_idx + 1)
	else:
		Sfx.play("win")
		Controllers.send_event("clear")
		if level_root:
			level_root.visible = false
		set_state(State.ENDING)


func _time_up() -> void:
	Sfx.play("timeup")
	Controllers.send_event("timeup")
	timeup_t = 2.0
	time_left = 0.0
	for p in players:
		p.frozen = true
		p.set_mood("hurt", 2.0)
	set_state(State.TIMEUP)


# =====================================================================
#  PARTICLES + CALLBACKS
# =====================================================================
func _burst(pos: Vector2, col: Color, n: int, speed: float) -> void:
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(speed * 0.3, speed)
		particles.append({"p": pos, "v": v, "life": randf_range(0.5, 0.9), "max": 0.9, "c": col, "s": randf_range(3.0, 6.0)})


func _update_particles(delta: float) -> void:
	for pa in particles:
		pa["life"] = float(pa["life"]) - delta
		pa["p"] = (pa["p"] as Vector2) + (pa["v"] as Vector2) * delta
		pa["v"] = (pa["v"] as Vector2) * (1.0 - 2.0 * delta) + Vector2(0, 160.0) * delta
	particles = particles.filter(func(pa) -> bool: return float(pa["life"]) > 0.0)


func _on_jumped(pos: Vector2) -> void:
	_burst(pos + Vector2(0, 14), Color(1, 1, 1, 0.8), 3, 60.0)


func _on_landed(pos: Vector2) -> void:
	_burst(pos, Color(1, 1, 1, 0.8), 5, 80.0)


# =====================================================================
#  DRAWING THE WORLD
# =====================================================================
func _draw() -> void:
	if level.is_empty() or players.is_empty() or state == State.HOME or state == State.HOWTO or state == State.ENDING:
		return
	var t := t_anim
	var th: Dictionary = Look.THEMES[int(level["theme"])]
	var wall_c: Color = th["wall"]

	for w in wall_rects:
		Look.box(self, w, wall_c)

	for h in hazards:
		var r: Rect2 = h["rect"]
		var col: Color = HAZ[h["kind"]]
		draw_rect(r, Color(col, 0.45))
		var y0 := r.position.y + sin(t * 4.0 + r.position.x * 0.1) * 2.0
		var y1 := r.position.y + sin(t * 4.0 + r.end.x * 0.1) * 2.0
		draw_line(Vector2(r.position.x, y0), Vector2(r.end.x, y1), col.lightened(0.4), 3.0)

	for pt in patrols:
		_draw_urchin(pt["rect"].get_center(), t)

	for cp in checkpoints:
		var b: Vector2 = cp["base"]
		var fc := Color(0.3, 1.0, 0.5) if cp["active"] else Color(0.6, 0.6, 0.7)
		draw_line(Vector2(b.x, b.y + 15.5), Vector2(b.x, b.y - 25.0), fc, 3.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(b.x, b.y - 25.0), Vector2(b.x + 16.0, b.y - 18.0), Vector2(b.x, b.y - 11.0)]), fc)

	for sh in shields:
		if not sh["taken"]:
			var p: Vector2 = (sh["pos"] as Vector2) + Vector2(0, sin(t * 3.0) * 3.0)
			draw_arc(p, 12.0, 0, TAU, 24, Color(0.5, 0.95, 1.0), 2.5)
			draw_circle(p, 5.0, Color(0.5, 0.95, 1.0, 0.6))

	for s in stones:
		if s["got"]:
			continue
		var gp: Vector2 = (s["pos"] as Vector2) + Vector2(0, sin(t * 3.0 + (s["pos"] as Vector2).x) * 3.0)
		Look.gem(self, gp, 11.0, STONE_COLORS[int(s["kind"])], t)

	# exit portal
	var open := stones_got >= stones_total
	var pc := Color(0.3, 1.0, 0.5) if open else Color(1.0, 0.3, 0.3)
	draw_rect(exit_rect, Color(pc, 0.15 + 0.1 * sin(t * 4.0)))
	draw_rect(exit_rect, pc, false, 3.0)
	draw_arc(exit_rect.get_center(), 14.0, t * 3.0, t * 3.0 + 4.0, 16, pc, 2.5)
	Look.txt(self, "EXIT" if open else "LOCKED", Vector2(exit_rect.position.x - 20.0, exit_rect.position.y - 6.0), 12, pc,
		HORIZONTAL_ALIGNMENT_CENTER, exit_rect.size.x + 40.0)

	for m in meteors:
		if int(m["state"]) == 1:
			var f := 0.4 + 0.6 * absf(sin(t * 16.0))
			var mx: float = m["x"]
			draw_colored_polygon(PackedVector2Array([
				Vector2(mx - 10, 72), Vector2(mx + 10, 72), Vector2(mx, 94)]), Color(1, 0.2, 0.2, f))
			draw_line(Vector2(mx, 98), Vector2(mx, float(m["stop"])), Color(1, 0.2, 0.2, 0.10), 2.0)
		elif int(m["state"]) == 2:
			var mp := Vector2(float(m["x"]), float(m["y"]))
			draw_line(mp - Vector2(0, 46), mp, Color(1, 0.5, 0.1, 0.5), 5.0)
			draw_circle(mp, 12.0, Color(1, 0.5, 0.1, 0.35))
			draw_circle(mp, 7.0, Color(1, 0.85, 0.4))

	if alien_on:
		_draw_alien(t)

	for pa in particles:
		var a: float = clampf(float(pa["life"]) / float(pa["max"]), 0.0, 1.0)
		var pc2: Color = pa["c"]
		draw_circle(pa["p"], float(pa["s"]) * 0.5 * (0.5 + a), Color(pc2, a))


## Spiky patrol enemy: a dark core with a glowing red-violet spike ring (no face).
func _draw_urchin(c: Vector2, t: float) -> void:
	var col := Color(1.0, 0.3, 0.6)
	var pts := PackedVector2Array()
	for k in 16:
		var a := t * 1.2 + float(k) * TAU / 16.0
		var rr := 19.0 if k % 2 == 0 else 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_circle(c, 22.0, Color(col, 0.14))
	draw_colored_polygon(pts, Color(col, 0.35))
	pts.append(pts[0])
	draw_polyline(pts, col, 2.0)
	draw_circle(c, 4.0, Color(1, 0.8, 0.9))


## The boss: a huge dark creature with a glowing green outline and one red eye.
func _draw_alien(t: float) -> void:
	var cx := alien_x - 120.0
	var cy := 400.0 + sin(t * 2.0) * 10.0
	var neon := Color(0.4, 1.0, 0.5)
	draw_circle(Vector2(cx - 30.0, cy), 190.0, Color(neon, 0.07))
	var body := PackedVector2Array()
	for k in 36:
		var a := float(k) * TAU / 36.0
		var rr := 125.0 + (14.0 if k % 2 == 0 else -6.0) + sin(t * 3.0 + float(k)) * 4.0
		body.append(Vector2(cx, cy) + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(body, Color(0.03, 0.10, 0.07))
	body.append(body[0])
	draw_polyline(body, neon, 3.0)
	for k in 4:
		var y0 := cy - 60.0 + float(k) * 40.0
		var pts := PackedVector2Array()
		for s in 8:
			pts.append(Vector2(cx - 110.0 - float(s) * 24.0, y0 + sin(t * 4.0 + float(s) * 0.7 + float(k)) * 10.0))
		draw_polyline(pts, Color(neon, 0.6), 3.0)
	var eye := Vector2(cx + 40.0, cy - 25.0)
	draw_circle(eye, 40.0, Color(1.0, 0.15, 0.15, 0.25))
	draw_circle(eye, 30.0, Color(0.15, 0.0, 0.0))
	draw_arc(eye, 30.0, 0.0, TAU, 32, Color(1.0, 0.3, 0.3), 3.0)
	var look := Vector2(1, 0)
	if players.size() == 2:
		var tgt: Vector2 = players[0].position if players[0].position.x < players[1].position.x else players[1].position
		look = (tgt - eye).normalized()
	draw_circle(eye + look * 10.0, 11.0, Color(1.0, 0.35, 0.35))
	var mouth := PackedVector2Array()
	for k in 9:
		mouth.append(Vector2(cx - 5.0 + float(k) * 12.0, cy + 62.0 + (14.0 if k % 2 == 0 else 0.0)))
	draw_polyline(mouth, neon, 3.0)
