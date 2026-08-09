extends Node2D
## Phase-1 Godot scaffold for the pixel-boxing prototype. Mirrors the core
## round/match loop and basic arrow-key movement from
## desktop-pixel-boxing/pixel_boxing_topdown.py as a starting point for the
## full engine port.
##
## NOT ported yet (future phases): the 8-punch combat system and hit
## detection, the pseudo-3rd-person camera projection, skeletal
## limb/joint animation, hitstop/camera shake/particles, the ring
## ropes/crowd, and the Korean commentary captions. This scaffold only
## proves the project opens and runs in Godot with the right window size,
## a flat top-down arena, and both fighters moving - everything else still
## needs to be built out.

const BG_COLOR := Color("#091427")
const ARENA_BG := Color("#182946")
const ARENA_EDGE := Color("#365486")
const PLAYER_COLOR := Color("#65d1ff")
const ENEMY_COLOR := Color("#ff6b8f")

const PLAYER_SPEED := 210.0
const FIGHTER_SIZE := Vector2(30.0, 30.0)

var player_pos := Vector2(170.0, 295.0)
var enemy_pos := Vector2(420.0, 295.0)
var round_time := 45.0
var state := "intro"

var arena_rect: Polygon2D
var player_node: ColorRect
var enemy_node: ColorRect
var hud: Label


func _ready() -> void:
	round_time = CombatData.ROUND_SECONDS
	RenderingServer.set_default_clear_color(BG_COLOR)

	arena_rect = Polygon2D.new()
	arena_rect.color = ARENA_BG
	arena_rect.polygon = PackedVector2Array([
		CombatData.ARENA_MIN,
		Vector2(CombatData.ARENA_MAX.x, CombatData.ARENA_MIN.y),
		CombatData.ARENA_MAX,
		Vector2(CombatData.ARENA_MIN.x, CombatData.ARENA_MAX.y),
	])
	add_child(arena_rect)

	var arena_outline := Line2D.new()
	arena_outline.width = 3.0
	arena_outline.default_color = ARENA_EDGE
	arena_outline.closed = true
	arena_outline.points = arena_rect.polygon
	add_child(arena_outline)

	player_node = ColorRect.new()
	player_node.color = PLAYER_COLOR
	player_node.size = FIGHTER_SIZE
	add_child(player_node)

	enemy_node = ColorRect.new()
	enemy_node.color = ENEMY_COLOR
	enemy_node.size = FIGHTER_SIZE
	add_child(enemy_node)

	hud = Label.new()
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.position = Vector2(16.0, 12.0)
	add_child(hud)


func _process(delta: float) -> void:
	match state:
		"intro":
			hud.text = "TOP-DOWN BOXING - Godot port scaffold\nPress Space to start Round 1."
			if Input.is_physical_key_pressed(KEY_SPACE):
				state = "fight"
		"fight":
			_update_player_movement(delta)
			round_time = max(0.0, round_time - delta)
			if round_time <= 0.0:
				state = "round_over"
			hud.text = "ROUND 1/%d   %ds\n(arrow keys move - punches/combat not ported yet)" % [
				CombatData.ROUND_LIMIT, int(ceil(round_time))
			]
		"round_over":
			hud.text = "ROUND OVER - press R to restart"
			if Input.is_physical_key_pressed(KEY_R):
				player_pos = Vector2(170.0, 295.0)
				enemy_pos = Vector2(420.0, 295.0)
				round_time = CombatData.ROUND_SECONDS
				state = "fight"

	player_node.position = player_pos - FIGHTER_SIZE * 0.5
	enemy_node.position = enemy_pos - FIGHTER_SIZE * 0.5


func _update_player_movement(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if move.length() > 0.0:
		move = move.normalized()
		player_pos += move * PLAYER_SPEED * delta
		player_pos.x = clamp(player_pos.x, CombatData.ARENA_MIN.x + 17.0, CombatData.ARENA_MAX.x - 17.0)
		player_pos.y = clamp(player_pos.y, CombatData.ARENA_MIN.y + 17.0, CombatData.ARENA_MAX.y - 17.0)
