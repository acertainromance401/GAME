extends Node2D
class_name Fighter
## Ported from the Python `Fighter` @dataclass in
## desktop-pixel-boxing/pixel_boxing_topdown.py - field-for-field, same
## names where GDScript allows it. `range`/`damage` are renamed to
## `punch_range`/`punch_damage` because `range` is a GDScript builtin
## function and `damage` reads oddly duplicated - everything else matches.
##
## Visual: a colored square body, a facing-direction line, an HP bar, and a
## translucent "attack cone" polygon shown only while actively swinging.
## This is intentionally simple placeholder art (no skeleton/joints/gloves
## yet) - see the migration notes in scripts/main.gd for what's deferred.

var fighter_name: String = "Fighter"
var fighter_color: Color = Color.WHITE

var radius: float = 17.0
var hp: int = 100
var max_hp: int = 100
var stamina: float = 100.0
var max_stamina: float = 100.0
var facing := Vector2.RIGHT
var action: String = "idle"
var action_t: float = 0.0
var action_dur: float = 0.0
var active_a: float = 0.0
var active_b: float = 0.0
var punch_damage: int = 0
var punch_range: float = 0.0
var half_angle_deg: float = 0.0
var acted: bool = false
var invuln: float = 0.0
var dodge_t: float = 0.0
var hit_flash: float = 0.0
var anim_t: float = 0.0
var exposed: float = 0.0
var stagger: float = 0.0
var whiff_penalized: bool = false
var streak_action: String = ""
var streak_count: int = 0

const BODY_SIZE := Vector2(30.0, 30.0)
const HP_BAR_WIDTH := 60.0

var _body: ColorRect
var _facing_line: Line2D
var _range_cone: Polygon2D
var _hp_bg: ColorRect
var _hp_fill: ColorRect


func _ready() -> void:
	_body = ColorRect.new()
	_body.size = BODY_SIZE
	_body.position = -BODY_SIZE * 0.5
	_body.color = fighter_color
	add_child(_body)

	_facing_line = Line2D.new()
	_facing_line.width = 3.0
	_facing_line.default_color = Color(0.0, 0.0, 0.0, 0.6)
	add_child(_facing_line)

	_range_cone = Polygon2D.new()
	_range_cone.color = Color(1.0, 0.85, 0.4, 0.25)
	_range_cone.visible = false
	add_child(_range_cone)

	_hp_bg = ColorRect.new()
	_hp_bg.size = Vector2(HP_BAR_WIDTH, 6.0)
	_hp_bg.color = Color("#0f1727")
	_hp_bg.position = Vector2(-HP_BAR_WIDTH * 0.5, -BODY_SIZE.y * 0.5 - 14.0)
	add_child(_hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.size = Vector2(HP_BAR_WIDTH - 2.0, 4.0)
	_hp_fill.color = Color("#77ff9f")
	_hp_fill.position = _hp_bg.position + Vector2(1.0, 1.0)
	add_child(_hp_fill)


## Called once per frame from main.gd after all state updates, so the
## visuals always reflect this frame's final position/action/hp.
func update_visual() -> void:
	_body.color = fighter_color.lerp(Color.WHITE, clamp(hit_flash / 0.18, 0.0, 1.0))
	_facing_line.points = PackedVector2Array([Vector2.ZERO, facing * (radius + 10.0)])
	_hp_fill.size.x = max(0.0, (HP_BAR_WIDTH - 2.0) * float(hp) / float(max(1, max_hp)))

	if action != "idle" and action_t < action_dur and punch_range > 0.0:
		_range_cone.polygon = _build_cone(punch_range, half_angle_deg)
		_range_cone.visible = true
	else:
		_range_cone.visible = false


func _build_cone(range_len: float, half_angle: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	var base_angle := facing.angle()
	var steps := 10
	for i in range(steps + 1):
		var t: float = lerp(-half_angle, half_angle, float(i) / float(steps))
		var a := base_angle + deg_to_rad(t)
		pts.append(Vector2(cos(a), sin(a)) * range_len)
	return pts
