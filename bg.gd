extends Node2D
## Dark space background (the original look): navy sky, twinkling stars, two outlined planets.
## Lives on its own CanvasLayer behind the world.

const VIEW := Vector2(1280, 720)

var theme_i := 0
var scroll := 0.0
var _t := 0.0
var _stars: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 140:
		_stars.append({
			"p": Vector2(rng.randf() * VIEW.x, rng.randf() * VIEW.y),
			"s": rng.randf_range(0.5, 2.0), "ph": rng.randf() * TAU,
			"par": rng.randf_range(0.01, 0.06),
		})


func set_theme(i: int) -> void:
	theme_i = i


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var th: Dictionary = Look.THEMES[theme_i]
	draw_rect(Rect2(Vector2.ZERO, VIEW), th["bg"])
	var px := fposmod(1000.0 - scroll * 0.05, VIEW.x + 300.0) - 150.0
	draw_circle(Vector2(px, 190), 90, Color(0.15, 0.05, 0.3, 0.6))
	draw_arc(Vector2(px, 190), 90, 0, TAU, 64, Color(0.6, 0.3, 1.0, 0.5), 3.0)
	var qx := fposmod(220.0 - scroll * 0.08, VIEW.x + 300.0) - 150.0
	draw_circle(Vector2(qx, 540), 46, Color(0.05, 0.15, 0.3, 0.6))
	if theme_i == 3:
		draw_rect(Rect2(0, VIEW.y - 140, VIEW.x, 140), Color(0.3, 1.0, 0.3, 0.05))
	for s in _stars:
		var p: Vector2 = s["p"]
		var x := fposmod(p.x - scroll * float(s["par"]), VIEW.x)
		var a := 0.35 + 0.65 * absf(sin(_t * float(s["s"]) + float(s["ph"])))
		draw_circle(Vector2(x, p.y), float(s["s"]), Color(1, 1, 1, a))
