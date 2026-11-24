extends Node
## Shared look & feel (autoload "Look"): the original dark "neon" style.
## Dark navy space, thin glowing outlines, plain text, simple block heroes.
##
## Colour roles (kept under the old names so the other scripts did not need renaming):
##   INK      = text colour (soft white-blue)       CREAM    = panel accent (cyan)
##   LAVENDER = secondary accent (violet)           PINK/MINT/GOLD/CORAL = button accents

const INK := Color(0.88, 0.94, 1.0)
const CREAM := Color(0.3, 0.9, 1.0)
const LAVENDER := Color(0.7, 0.45, 1.0)
const PINK := Color(1.0, 0.45, 0.8)
const MINT := Color(0.3, 1.0, 0.5)
const GOLD := Color(1.0, 0.85, 0.3)
const CORAL := Color(1.0, 0.35, 0.35)
const BG := Color(0.02, 0.02, 0.07)
const PANEL := Color(0.04, 0.05, 0.14)

const P1_BODY := Color(1.0, 0.4, 0.2)      # Iron Flare
const P1_DARK := Color(1.0, 0.55, 0.3)
const P2_BODY := Color(0.35, 0.85, 1.0)    # Cryo Cap
const P2_DARK := Color(0.45, 0.9, 1.0)

## One tint per difficulty tier: 0 easy, 1 medium, 2 hard, 3 boss (alien).
const THEMES := [
	{"wall": Color(0.3, 0.9, 1.0), "fill": Color(0.06, 0.07, 0.18), "bg": Color(0.02, 0.02, 0.07)},
	{"wall": Color(0.35, 0.8, 1.0), "fill": Color(0.05, 0.08, 0.18), "bg": Color(0.02, 0.03, 0.09)},
	{"wall": Color(0.85, 0.5, 1.0), "fill": Color(0.09, 0.05, 0.18), "bg": Color(0.04, 0.02, 0.08)},
	{"wall": Color(0.4, 1.0, 0.5), "fill": Color(0.04, 0.10, 0.09), "bg": Color(0.02, 0.05, 0.05)},
]

var font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font


# ------------------------------------------------------------------ primitives
## A dark panel with a glowing outline in the accent colour `fill`.
## (`fill` is the ACCENT: the inside is always dark so light text stays readable.)
func box(ci: CanvasItem, r: Rect2, fill: Color, _radius: int = 10, _border: Color = Color(0, 0, 0, 0), _bw: int = 0) -> void:
	var a := clampf(fill.a, 0.0, 1.0)
	var neon := Color(fill.r, fill.g, fill.b, 1.0)
	ci.draw_rect(r, Color(neon.r * 0.10, neon.g * 0.10, neon.b * 0.10 + 0.04, maxf(a, 0.55) if a < 1.0 else 0.94))
	ci.draw_rect(r, Color(neon, 0.22 * a), false, 5.0)
	ci.draw_rect(r.grow(-1.0), Color(neon, 0.95 * a), false, 2.0)


func txt(ci: CanvasItem, s: String, pos: Vector2, size: int, col: Color = Color.WHITE,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0, outline: int = 0, _ocol: Color = Color.BLACK) -> void:
	if outline > 0:
		ci.draw_string_outline(font, pos, s, align, w, size, mini(outline, 3), Color(0, 0, 0.04, 0.9))
	ci.draw_string(font, pos, s, align, w, size, col)


func text_w(s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func sparkle(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(p, r * 0.7, col)


func face(_ci: CanvasItem, _p: Vector2, _r: float, _ink: Color = INK) -> void:
	pass


## Infinity stone: glowing diamond (as in the original).
func gem(ci: CanvasItem, p: Vector2, r: float, col: Color, t: float = 0.0, _with_face: bool = true) -> void:
	ci.draw_circle(p, r * 1.45, Color(col, 0.16 + 0.05 * sin(t * 4.0)))
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.8, 0), p + Vector2(0, r), p + Vector2(-r * 0.8, 0)])
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.WHITE, 1.5)


# ------------------------------------------------------------------ the heroes
## Block hero with a glowing outline and a white visor. `feet` is the bottom-centre point.
## (mood / squash / bob are accepted for compatibility; the original hero was a plain block.)
func draw_hero(ci: CanvasItem, id: int, feet: Vector2, face_dir: float, _t: float, mood: String,
		_squash: float, _bob: float, k: float = 1.0, alpha: float = 1.0) -> void:
	var color: Color = P1_BODY if id == 0 else P2_BODY
	var c := Color(color, alpha)
	ci.draw_set_transform(feet + Vector2(0, -15.0 * k), 0.0, Vector2(k, k))
	var body := Rect2(-12.0, -15.0, 24.0, 30.0)
	ci.draw_rect(body.grow(4.0), Color(color, 0.15 * alpha))
	ci.draw_rect(body, Color(color.darkened(0.6), alpha))
	ci.draw_rect(body, c, false, 2.0)
	var vis := Color(1, 1, 1, alpha)
	if mood == "hurt":
		vis = Color(1.0, 0.5, 0.5, alpha)
	ci.draw_rect(Rect2(-7.0 + 3.0 * face_dir, -9.0, 14.0, 6.0), vis)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func bubble(ci: CanvasItem, text: String, anchor: Vector2, alpha: float = 1.0) -> void:
	var size := 15
	var w: float = text_w(text, size) + 18.0
	var r := Rect2(anchor.x - w * 0.5, anchor.y - 32.0, w, 26.0)
	ci.draw_rect(r, Color(0.04, 0.05, 0.14, 0.92 * alpha))
	ci.draw_rect(r, Color(CREAM, alpha), false, 2.0)
	txt(ci, text, Vector2(r.position.x, r.position.y + 18.0), size, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, w)
