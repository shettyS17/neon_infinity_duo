extends CharacterBody2D
## One hero: movement (coyote time + jump buffer), block-hero drawing, soft jump/landing sounds.

signal jumped(pos: Vector2)
signal landed(pos: Vector2)

const SIZE := Vector2(24, 30)
const SPEED := 230.0
const ACCEL := 1900.0
const GRAVITY := 1500.0
const JUMP_V := -570.0
const COYOTE := 0.09
const BUFFER := 0.10

var id := 0
var shield := false
var frozen := false
var invuln := 0.0
var facing := 1.0
var squash := 0.0
var bubble_text := ""
var bubble_t := 0.0
var mood_name := ""
var mood_t := 0.0

var _coyote_t := 0.0
var _buffer_t := 0.0
var _prev_jump := false
var _was_on_floor := true
var _fall_speed := 0.0
var _run_t := 0.0
var _pant_t := 0.0
var _bob_t := 0.0


func setup(p_id: int) -> void:
	id = p_id
	collision_layer = 2
	collision_mask = 1          # heroes only collide with the world, never with each other
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = SIZE
	cs.shape = rs
	add_child(cs)


func hurtbox() -> Rect2:
	return Rect2(position - SIZE * 0.5 + Vector2(3, 3), SIZE - Vector2(6, 6))


func say(text: String, seconds: float = 1.5) -> void:
	bubble_text = text
	bubble_t = seconds


func set_mood(m: String, seconds: float) -> void:
	mood_name = m
	mood_t = seconds


func _physics_process(delta: float) -> void:
	var dir := 0.0
	var jump := false
	if not frozen:
		dir = Controllers.get_axis(id)
		jump = Controllers.jump_held(id)
	velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * delta)
	if dir != 0.0:
		facing = signf(dir)

	if is_on_floor():
		_coyote_t = COYOTE
	else:
		_coyote_t -= delta
	if jump and not _prev_jump:
		_buffer_t = BUFFER
	else:
		_buffer_t -= delta

	velocity.y += GRAVITY * delta
	if _buffer_t > 0.0 and _coyote_t > 0.0:
		velocity.y = JUMP_V
		_buffer_t = 0.0
		_coyote_t = 0.0
		squash = -0.2
		Sfx.play("jump_p%d" % (id + 1))
		jumped.emit(position)
	if not jump and velocity.y < -220.0:      # let go early = shorter hop
		velocity.y = -220.0
	_prev_jump = jump
	_fall_speed = maxf(_fall_speed, velocity.y)

	move_and_slide()

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		if _fall_speed > 260.0:
			squash = 0.22
			Sfx.play("land")
			landed.emit(position + Vector2(0, SIZE.y * 0.5))
		_fall_speed = 0.0
	if on_floor:
		_fall_speed = 0.0
	_was_on_floor = on_floor

	_bob_t += delta * absf(velocity.x) / 26.0 if on_floor else 0.0

	squash = move_toward(squash, 0.0, delta * 1.5)
	invuln = maxf(0.0, invuln - delta)
	bubble_t = maxf(0.0, bubble_t - delta)
	mood_t = maxf(0.0, mood_t - delta)
	self_modulate.a = 0.45 if (invuln > 0.0 and int(Time.get_ticks_msec() / 80) % 2 == 0) else 1.0
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var mood := "normal"
	if mood_t > 0.0:
		mood = mood_name
	elif velocity.y < -80.0:
		mood = "jump"
	var bob: float = sin(_bob_t) * 2.5 if is_on_floor() else 0.0
	Look.draw_hero(self, id, Vector2(0, SIZE.y * 0.5), facing, t, mood, squash, bob)
	if shield:
		draw_arc(Vector2(0, -2), 25.0, 0.0, TAU, 32, Color(0.55, 0.95, 1.0, 0.95), 3.0)
		draw_circle(Vector2(0, -2), 25.0, Color(0.55, 0.95, 1.0, 0.16))
	Look.txt(self, "P%d" % (id + 1), Vector2(-20, -44), 14, Color(Look.P1_BODY if id == 0 else Look.P2_BODY),
		HORIZONTAL_ALIGNMENT_CENTER, 40.0, 5)
	if bubble_t > 0.0:
		Look.bubble(self, bubble_text, Vector2(0, -52), clampf(bubble_t * 3.0, 0.0, 1.0))
