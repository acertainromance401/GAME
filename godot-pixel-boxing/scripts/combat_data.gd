extends Node
## Ported 1:1 from desktop-pixel-boxing/pixel_boxing_topdown.py's `specs`
## dict in start_attack() and the module-level anti-mash/duck-evade tuning
## constants. This is the actual GAME DESIGN data - the numbers that make
## combat feel the way it does - kept identical between the Tkinter
## prototype and this Godot port so behavior doesn't drift between the two
## as the engine port continues. Registered as an autoload singleton (see
## project.godot's [autoload] section) so any script can read
## `CombatData.PUNCH_SPECS` etc. directly.

const ARENA_MIN := Vector2(70.0, 70.0)
const ARENA_MAX := Vector2(520.0, 520.0)  # square ring, 450x450 world units
const ROUND_LIMIT := 3
const ROUND_SECONDS := 45.0

# Anti-mash tuning (see WHIFF_RECOVERY/EXPOSED_DMG_MULT/etc. in the Python source).
const WHIFF_RECOVERY := 0.22
const EXPOSED_DMG_MULT := 1.4
const STAGGER_LOCK := 0.16
const STALE_THRESHOLD := 2
const STALE_DECAY := 0.85
const STALE_FLOOR := 0.5
const GUARD_DAMAGE_MULT := 0.4

# action_dur, active_a, active_b, damage, range, half_angle_deg, stamina_cost
# Jab deliberately reaches FARTHER than cross (probing/spacing tool vs. a
# tighter, more precise power shot thrown from closer range) - see
# start_attack()'s comment in the Python source for the full per-punch
# design rationale (straight punches = narrow cone, hooks = widest cone but
# shortest reach, uppercuts = short range + narrow-ish cone).
const PUNCH_SPECS := {
	"jab": {"action_dur": 0.24, "active_a": 0.08, "active_b": 0.15, "damage": 6, "range": 78.0, "half_angle_deg": 26.0, "cost": 6},
	"cross": {"action_dur": 0.34, "active_a": 0.14, "active_b": 0.24, "damage": 11, "range": 60.0, "half_angle_deg": 20.0, "cost": 11},
	"left_body": {"action_dur": 0.32, "active_a": 0.12, "active_b": 0.22, "damage": 9, "range": 54.0, "half_angle_deg": 40.0, "cost": 9},
	"right_body": {"action_dur": 0.35, "active_a": 0.14, "active_b": 0.24, "damage": 10, "range": 56.0, "half_angle_deg": 38.0, "cost": 10},
	"left_hook": {"action_dur": 0.36, "active_a": 0.16, "active_b": 0.26, "damage": 11, "range": 50.0, "half_angle_deg": 56.0, "cost": 11},
	"right_hook": {"action_dur": 0.38, "active_a": 0.17, "active_b": 0.28, "damage": 12, "range": 52.0, "half_angle_deg": 50.0, "cost": 12},
	"left_uppercut": {"action_dur": 0.40, "active_a": 0.18, "active_b": 0.30, "damage": 13, "range": 44.0, "half_angle_deg": 26.0, "cost": 13},
	"right_uppercut": {"action_dur": 0.42, "active_a": 0.19, "active_b": 0.31, "damage": 14, "range": 46.0, "half_angle_deg": 24.0, "cost": 14},
}

# Directional duck evasion: duck TOWARD the side a punch is perceived to
# arrive from (not away from it) - see DUCK_EVADE_KEY's comment in the
# Python source for the full explanation of this (intentionally
# counter-intuitive) design rule.
const DUCK_EVADE_KEY := {
	"jab": "duck_right",
	"left_hook": "duck_right",
	"left_uppercut": "duck_right",
	"cross": "duck_left",
	"right_hook": "duck_left",
	"right_uppercut": "duck_left",
}
const DUCK_EVADE_THRESHOLD := 0.5
