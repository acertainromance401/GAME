extends Node2D
## Phase-2 Godot scaffold for the pixel-boxing prototype. Ports the actual
## GAMEPLAY logic from desktop-pixel-boxing/pixel_boxing_topdown.py:
## movement, duck/backstep/guard evasion, the full 8-punch combat system
## (start_attack/attempt_hit), anti-mash tuning (whiff recovery, stagger,
## move staleness), a basic enemy AI, and the round/match state machine.
##
## Visuals are intentionally still placeholder (see scripts/fighter.gd):
## colored squares + a facing line + an attack-cone indicator + HP bars,
## no skeleton/joints/gloves, no pseudo-3rd-person camera projection, no
## hitstop/camera-shake/particles/crowd/ropes/commentary yet - those are
## later phases once the core feel is confirmed to work in-engine.

const BG_COLOR := Color("#091427")
const ARENA_BG := Color("#182946")
const ARENA_EDGE := Color("#365486")
const PLAYER_COLOR := Color("#65d1ff")
const ENEMY_COLOR := Color("#ff6b8f")
const GOLD := Color("#ffd86f")

const PLAYER_SPEED := 210.0
const DUCK_MAX := 34.0
const DUCK_SMOOTH := 14.0
const BACK_MAX := 38.0
const BACK_SMOOTH := 12.5

const FighterScript := preload("res://scripts/fighter.gd")

var arena_rect: Polygon2D
var hud: Label
var feedback_label: Label
var overlay_label: Label

var player: Node2D
var enemy: Node2D

var player_duck_target := 0.0
var player_duck_offset := 0.0
var player_back_target := 0.0
var player_back_offset := 0.0

var round_i := 1
var max_rounds: int = CombatData.ROUND_LIMIT
var score_player := 0
var score_enemy := 0
var round_time := CombatData.ROUND_SECONDS
var state := "intro"
var overlay_title := ""
var overlay_body := ""
var feedback_text := ""
var feedback_timer := 0.0
var enemy_ai_timer := 0.0

var _prev_keys: Dictionary = {}
const _EDGE_KEYS := [KEY_A, KEY_D, KEY_Q, KEY_E, KEY_W, KEY_S, KEY_SPACE, KEY_R]


func _ready() -> void:
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

	player = FighterScript.new()
	player.fighter_name = "Player"
	player.fighter_color = PLAYER_COLOR
	add_child(player)

	enemy = FighterScript.new()
	enemy.fighter_name = "Enemy"
	enemy.fighter_color = ENEMY_COLOR
	add_child(enemy)

	hud = Label.new()
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.position = Vector2(16.0, 12.0)
	add_child(hud)

	feedback_label = Label.new()
	feedback_label.add_theme_color_override("font_color", GOLD)
	feedback_label.position = Vector2(400.0, 60.0)
	add_child(feedback_label)

	overlay_label = Label.new()
	overlay_label.add_theme_color_override("font_color", Color.WHITE)
	overlay_label.position = Vector2(300.0, 300.0)
	add_child(overlay_label)

	_reset_match()


func _reset_match() -> void:
	round_i = 1
	score_player = 0
	score_enemy = 0
	state = "intro"
	_reset_fighters()
	overlay_title = "TOP-DOWN BOXING"
	overlay_body = "Best of %d rounds. Press Space to start Round 1." % max_rounds


func _reset_fighters() -> void:
	player.position = Vector2(170.0, 295.0)
	player.hp = player.max_hp
	player.stamina = player.max_stamina
	player.action = "idle"
	player.action_t = 0.0
	player.action_dur = 0.0
	player.streak_action = ""
	player.streak_count = 0

	enemy.position = Vector2(420.0, 295.0)
	enemy.hp = enemy.max_hp
	enemy.stamina = enemy.max_stamina
	enemy.action = "idle"
	enemy.action_t = 0.0
	enemy.action_dur = 0.0
	enemy.streak_action = ""
	enemy.streak_count = 0

	player_duck_target = 0.0
	player_duck_offset = 0.0
	player_back_target = 0.0
	player_back_offset = 0.0
	round_time = CombatData.ROUND_SECONDS
	enemy_ai_timer = 0.0


func _start_round() -> void:
	_reset_fighters()
	state = "fight"


func _show_feedback(text: String) -> void:
	feedback_text = text
	feedback_timer = 0.35


func _process(delta: float) -> void:
	match state:
		"fight":
			overlay_label.visible = false
			_update_fight(delta)
		_:
			overlay_label.visible = true
			overlay_label.text = "%s\n%s" % [overlay_title, overlay_body]
			if _just_pressed(KEY_SPACE):
				if state == "match_over":
					_reset_match()
				else:
					_start_round()

	if _just_pressed(KEY_R):
		_reset_match()

	feedback_timer = max(0.0, feedback_timer - delta)
	player.update_visual()
	enemy.update_visual()
	_update_hud()
	_store_prev_keys()


func _just_pressed(keycode: int) -> bool:
	var now := Input.is_physical_key_pressed(keycode)
	var was: bool = _prev_keys.get(keycode, false)
	return now and not was


func _store_prev_keys() -> void:
	for k in _EDGE_KEYS:
		_prev_keys[k] = Input.is_physical_key_pressed(k)


func _update_hud() -> void:
	hud.text = "PLAYER HP %3d  ST %3d\nENEMY  HP %3d  ST %3d\nROUND %d/%d   %ds\nSCORE  P %d - %d E" % [
		player.hp, int(player.stamina), enemy.hp, int(enemy.stamina),
		round_i, max_rounds, int(ceil(round_time)), score_player, score_enemy,
	]
	feedback_label.text = feedback_text if feedback_timer > 0.0 else ""


func _update_fight(delta: float) -> void:
	_update_facing(player, enemy)
	_update_facing(enemy, player)

	if state != "fight":
		return

	if _just_pressed(KEY_A):
		_start_combo_attack("a")
	if _just_pressed(KEY_D):
		_start_combo_attack("d")
	if _just_pressed(KEY_Q):
		_show_feedback("DUCK LEFT")
	if _just_pressed(KEY_E):
		_show_feedback("DUCK RIGHT")
	if _just_pressed(KEY_S) and player_back_target <= 0.0:
		_show_feedback("BACKSTEP")
		player.invuln = max(player.invuln, 0.10)
	if _just_pressed(KEY_W) and _is_guarding():
		_show_feedback("GUARD UP")

	_update_player_movement(delta)
	_update_player_duck(delta)
	_update_player_backstep(delta)
	_update_ai(delta)
	_update_actor_timers(player, delta)
	_update_actor_timers(enemy, delta)

	round_time = max(0.0, round_time - delta)
	if round_time <= 0.0:
		if player.hp > enemy.hp:
			_end_round("player", "Time")
		elif enemy.hp > player.hp:
			_end_round("enemy", "Time")
		else:
			_end_round("draw", "Time")


func _update_facing(actor: Node2D, target: Node2D) -> void:
	var to_target := target.position - actor.position
	if to_target.length() > 0.0001:
		actor.facing = to_target.normalized()


func _is_guarding() -> bool:
	return Input.is_physical_key_pressed(KEY_W) and player.action_t >= player.action_dur and player.stagger <= 0.0


func _update_player_movement(delta: float) -> void:
	if player.action_t < player.action_dur or player.stagger > 0.0:
		return
	var forward := 0.0
	var strafe := 0.0
	if Input.is_physical_key_pressed(KEY_UP):
		forward += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		forward -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		strafe += 1.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		strafe -= 1.0
	if forward == 0.0 and strafe == 0.0:
		return
	var right := Vector2(player.facing.y, -player.facing.x)
	var move: Vector2 = (player.facing * forward + right * strafe).normalized()
	player.position += move * PLAYER_SPEED * delta
	_clamp_to_arena(player)


func _update_player_duck(delta: float) -> void:
	var right := Vector2(player.facing.y, -player.facing.x)
	var target := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		target = -1.0
	elif Input.is_physical_key_pressed(KEY_E):
		target = 1.0
	player_duck_target = target
	var desired := player_duck_target * DUCK_MAX
	var k := 1.0 - exp(-DUCK_SMOOTH * delta)
	var new_offset: float = lerp(player_duck_offset, desired, k)
	var delta_offset := new_offset - player_duck_offset
	player_duck_offset = new_offset
	if absf(delta_offset) > 0.0001:
		player.position += right * delta_offset
		_clamp_to_arena(player)


func _update_player_backstep(delta: float) -> void:
	player_back_target = 1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0
	var desired := player_back_target * BACK_MAX
	var k := 1.0 - exp(-BACK_SMOOTH * delta)
	var new_offset: float = lerp(player_back_offset, desired, k)
	var delta_offset := new_offset - player_back_offset
	player_back_offset = new_offset
	if absf(delta_offset) > 0.0001:
		player.position -= player.facing * delta_offset
		_clamp_to_arena(player)


func _clamp_to_arena(actor: Node2D) -> void:
	actor.position.x = clamp(actor.position.x, CombatData.ARENA_MIN.x + actor.radius, CombatData.ARENA_MAX.x - actor.radius)
	actor.position.y = clamp(actor.position.y, CombatData.ARENA_MIN.y + actor.radius, CombatData.ARENA_MAX.y - actor.radius)


func _start_combo_attack(key: String) -> void:
	var q := Input.is_physical_key_pressed(KEY_Q)
	var e := Input.is_physical_key_pressed(KEY_E)
	var w := Input.is_physical_key_pressed(KEY_W)
	var action_name := ""
	if w:
		action_name = "left_uppercut" if key == "a" else "right_uppercut"
	elif q:
		action_name = "left_body" if key == "a" else "right_hook"
	elif e:
		action_name = "left_hook" if key == "a" else "right_body"
	else:
		action_name = "jab" if key == "a" else "cross"
	_start_attack(player, action_name)


func _start_attack(actor: Node2D, name: String) -> void:
	if actor.action_t < actor.action_dur or actor.stagger > 0.0:
		return
	if not CombatData.PUNCH_SPECS.has(name):
		return
	var spec: Dictionary = CombatData.PUNCH_SPECS[name]
	if actor.stamina < spec["cost"]:
		return

	if actor.streak_action == name:
		actor.streak_count += 1
	else:
		actor.streak_action = name
		actor.streak_count = 1
	var stale_mult: float = max(
		CombatData.STALE_FLOOR,
		pow(CombatData.STALE_DECAY, max(0, actor.streak_count - CombatData.STALE_THRESHOLD))
	)
	var dmg: int = max(1, int(round(spec["damage"] * stale_mult)))

	actor.action = name
	actor.action_t = 0.0
	actor.acted = false
	actor.whiff_penalized = false
	actor.action_dur = spec["action_dur"]
	actor.active_a = spec["active_a"]
	actor.active_b = spec["active_b"]
	actor.punch_damage = dmg
	actor.punch_range = spec["range"]
	actor.half_angle_deg = spec["half_angle_deg"]
	actor.stamina = clamp(actor.stamina - float(spec["cost"]), 0.0, actor.max_stamina)


func _attempt_hit(attacker: Node2D, defender: Node2D) -> void:
	if defender.invuln > 0.0 or (defender.action == "dodge" and defender.dodge_t > 0.0):
		if defender == player:
			_show_feedback("DODGE SUCCESS")
		return

	var to_defender := defender.position - attacker.position
	var dist := to_defender.length()
	if dist > attacker.punch_range + defender.radius:
		return

	var dir := to_defender.normalized()
	var dot: float = attacker.facing.dot(dir)
	var limit := cos(deg_to_rad(attacker.half_angle_deg))
	if dot < limit:
		return

	if defender == player and CombatData.DUCK_EVADE_KEY.has(attacker.action):
		var needed: String = CombatData.DUCK_EVADE_KEY[attacker.action]
		var duck_ratio: float = clamp(absf(player_duck_offset) / max(DUCK_MAX, 0.0001), 0.0, 1.0)
		var duck_dir := ""
		if player_duck_offset > 0.0:
			duck_dir = "duck_right"
		elif player_duck_offset < 0.0:
			duck_dir = "duck_left"
		if duck_ratio >= CombatData.DUCK_EVADE_THRESHOLD and duck_dir == needed:
			_show_feedback("DUCK EVADE")
			return

	var dmg: int = attacker.punch_damage
	var punished_whiff: bool = defender.exposed > 0.0
	if punished_whiff:
		dmg = int(round(dmg * CombatData.EXPOSED_DMG_MULT))

	var guarding := defender == player and _is_guarding()
	if guarding:
		dmg = max(1, int(round(dmg * CombatData.GUARD_DAMAGE_MULT)))

	var interrupted: bool = (
		CombatData.PUNCH_SPECS.has(defender.action)
		and defender.action_t < defender.action_dur
		and not defender.acted
	)
	if interrupted:
		defender.action = "idle"
		defender.action_t = 0.0
		defender.action_dur = 0.0

	defender.hp = clampi(defender.hp - dmg, 0, defender.max_hp)
	defender.hit_flash = 0.18
	defender.invuln = 0.08
	defender.stagger = CombatData.STAGGER_LOCK * (1.5 if interrupted else 1.0)
	defender.streak_count = 0

	if attacker == player and punished_whiff:
		_show_feedback("COUNTER HIT!")
	elif defender == player and interrupted:
		_show_feedback("STAGGERED")
	elif defender == player and guarding:
		_show_feedback("BLOCKED")

	if defender.hp <= 0:
		var winner := "player" if attacker == player else "enemy"
		_show_feedback("KO!")
		_end_round(winner, "KO")


func _update_actor_timers(actor: Node2D, delta: float) -> void:
	actor.stamina = clamp(actor.stamina + delta * 17.0, 0.0, actor.max_stamina)
	actor.invuln = max(0.0, actor.invuln - delta)
	actor.dodge_t = max(0.0, actor.dodge_t - delta)
	actor.hit_flash = max(0.0, actor.hit_flash - delta)
	actor.exposed = max(0.0, actor.exposed - delta)
	actor.stagger = max(0.0, actor.stagger - delta)
	actor.anim_t += delta

	if actor.action_t < actor.action_dur:
		actor.action_t += delta
		if (
			CombatData.PUNCH_SPECS.has(actor.action)
			and not actor.acted
			and actor.active_a <= actor.action_t and actor.action_t <= actor.active_b
		):
			var target := enemy if actor == player else player
			_attempt_hit(actor, target)
			actor.acted = true
		if actor.action_t >= actor.action_dur:
			if CombatData.PUNCH_SPECS.has(actor.action) and not actor.acted and not actor.whiff_penalized:
				actor.action_dur += CombatData.WHIFF_RECOVERY
				actor.whiff_penalized = true
				actor.exposed = CombatData.WHIFF_RECOVERY + 0.05
				if actor == player:
					_show_feedback("OFF BALANCE")
			else:
				actor.action = "idle"


func _update_ai(delta: float) -> void:
	enemy_ai_timer = max(0.0, enemy_ai_timer - delta)
	if enemy.action_t >= enemy.action_dur:
		var to_player := player.position - enemy.position
		var dist := to_player.length()
		if dist > 130.0:
			var dir := to_player.normalized()
			enemy.position += dir * 155.0 * delta
			_clamp_to_arena(enemy)

	if player.exposed > 0.0 and enemy.action_t >= enemy.action_dur and enemy.stagger <= 0.0:
		enemy_ai_timer = 0.0

	if enemy_ai_timer > 0.0:
		return

	var cooldown_scale := 1.0 + 0.15 * float(round_i - 1)
	enemy_ai_timer = randf_range(0.14, 0.30) / cooldown_scale
	var dist2 := (player.position - enemy.position).length()
	if dist2 < 84.0 and randf() < 0.28:
		enemy.action = "dodge"
		enemy.action_t = 0.0
		enemy.action_dur = 0.22
		enemy.punch_range = 0.0
		enemy.acted = true
		enemy.invuln = 0.14
		enemy.dodge_t = 0.14
		var back := (enemy.position - player.position).normalized()
		enemy.position += back * 40.0
		_clamp_to_arena(enemy)
	elif dist2 < 110.0:
		_start_attack(enemy, "cross" if randf() < 0.55 else "jab")


func _end_round(winner: String, _reason: String) -> void:
	state = "round_break"
	if winner == "player":
		score_player += 1
	elif winner == "enemy":
		score_enemy += 1

	var player_won := score_player > max_rounds / 2
	var enemy_won := score_enemy > max_rounds / 2
	var last_round := round_i >= max_rounds

	if player_won or enemy_won or last_round:
		state = "match_over"
		var title := "MATCH DRAW"
		if score_player > score_enemy:
			title = "PLAYER WINS THE MATCH"
		elif score_enemy > score_player:
			title = "ENEMY WINS THE MATCH"
		overlay_title = title
		overlay_body = "Final score P%d-%dE  |  Space or R: restart" % [score_player, score_enemy]
		return

	var result := winner.to_upper() if winner in ["player", "enemy"] else "DRAW"
	overlay_title = "ROUND %d - %s" % [round_i, result]
	overlay_body = "Score P%d-%dE  |  Space: next round" % [score_player, score_enemy]
	round_i += 1

