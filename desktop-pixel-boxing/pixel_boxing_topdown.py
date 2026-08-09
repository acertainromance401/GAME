import math
import random
import tkinter as tk
from dataclasses import dataclass

WIDTH = 960
HEIGHT = 700
ARENA = (70, 70, 520, 520)
ROUND_LIMIT = 3
ROUND_SECONDS = 45

BG = "#091427"
ARENA_BG = "#182946"
ARENA_EDGE = "#365486"
PLAYER_COLOR = "#65d1ff"
ENEMY_COLOR = "#ff6b8f"
WHITE = "#eef6ff"
GRAY = "#9cb0cf"
GREEN = "#77ff9f"
RED = "#ff6b8f"
GOLD = "#ffd86f"

ATTACK_ACTIONS = (
    "jab",
    "cross",
    "left_body",
    "right_body",
    "left_hook",
    "right_hook",
    "left_uppercut",
    "right_uppercut",
)

# Anti-mash tuning: punishes throwing hands with no regard for spacing or
# timing instead of just rewarding whoever presses the attack key fastest.
WHIFF_RECOVERY = 0.22       # extra recovery lock added after a missed swing
EXPOSED_DMG_MULT = 1.4      # bonus damage for punishing an off-balance opponent
STAGGER_LOCK = 0.16         # brief flinch lockout applied to anyone who gets hit
STALE_THRESHOLD = 2         # repeats of the same move allowed before it weakens
STALE_DECAY = 0.85          # damage multiplier applied per repeat past the threshold
STALE_FLOOR = 0.5           # minimum multiplier a stale move can be decayed to
GUARD_DAMAGE_MULT = 0.4     # incoming damage multiplier while actively holding guard (W)

# Directional duck evasion for head attacks: you duck TOWARD the side the
# punch is arriving from (not away from it) - e.g. an enemy jab (lead hand)
# arrives from the defender's right, so ducking right (E) is what slips it.
# Only exact opposite-of-thrown-hand pairing evades; the wrong direction (or
# no duck at all) leaves the punch free to land.
DUCK_EVADE_KEY = {
    "jab": "e",
    "left_hook": "e",
    "left_uppercut": "e",
    "cross": "q",
    "right_hook": "q",
    "right_uppercut": "q",
}
DUCK_EVADE_THRESHOLD = 0.5   # fraction of duck_max the player must commit to for the duck to count

# Sports-commentary style narration lines, keyed by event. Several variants
# per key so it doesn't repeat itself every single exchange; {atk}/{def_} are
# filled in with the attacker/defender's display name (named def_, not def -
# def is a reserved keyword so it can't be used as a str.format() keyword
# argument; the placeholder in these strings must match that exactly or
# format() raises KeyError at runtime instead of substituting anything).
# This is purely a HUD caption (see show_commentary/draw_hud) - it never
# touches gameplay state.
COMMENTARY_LINES = {
    "jab": ["{atk}의 빠른 잽! 거리를 재는군요.", "잽으로 시야를 여는 {atk}!", "가볍지만 정확한 잽이 꽂힙니다."],
    "cross": ["묵직한 크로스, {atk}의 정확한 한 방!", "크로스 카운터, 제대로 들어갔습니다!", "{atk}의 크로스가 깔끔하게 적중!"],
    "hook": ["훅이 옆에서 감아 들어갑니다!", "{atk}의 훅, 각도가 좋았어요!", "사이드에서 훅이 명중합니다!"],
    "body": ["보디샷이 제대로 박힙니다!", "{atk}가 몸통을 노렸어요!", "복부를 강타하는 좋은 선택!"],
    "uppercut": ["어퍼컷이 턱을 강타합니다!", "밑에서 올려치는 {atk}의 어퍼컷!", "짧지만 강력한 어퍼컷!"],
    "counter": ["카운터!! {atk}가 빈틈을 놓치지 않습니다!", "완벽한 타이밍의 카운터!"],
    "guard": ["가드로 잘 막아낸 {def_}!", "단단한 블록, 데미지를 줄였습니다."],
    "stagger": ["{def_}가 휘청거립니다!", "균형을 잃었어요, 큰 기회입니다!"],
    "duck_evade": ["기가 막힌 더킹으로 피해냅니다!", "완벽한 슬립, 종이 한 장 차이!"],
    "dodge": ["몸을 날려 회피하는 {def_}!", "간발의 차로 피해냅니다!"],
    "ko": ["끝났습니다!! K.O.!!", "쓰러졌습니다! 경기 종료!"],
}


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def length(x, y):
    return math.hypot(x, y)


def normalize(x, y):
    mag = math.hypot(x, y)
    if mag < 1e-6:
        return 1.0, 0.0
    return x / mag, y / mag


def lerp(a, b, t):
    return a + (b - a) * t


def hex_to_rgb(color):
    color = color.lstrip("#")
    return int(color[0:2], 16), int(color[2:4], 16), int(color[4:6], 16)


def rgb_to_hex(rgb):
    return "#%02x%02x%02x" % rgb


def mix_color(c1, c2, t):
    t = clamp(t, 0.0, 1.0)
    a = hex_to_rgb(c1)
    b = hex_to_rgb(c2)
    rgb = (
        int(a[0] * (1 - t) + b[0] * t),
        int(a[1] * (1 - t) + b[1] * t),
        int(a[2] * (1 - t) + b[2] * t),
    )
    return rgb_to_hex(rgb)


@dataclass
class Fighter:
    name: str
    x: float
    y: float
    color: str
    radius: float = 17.0
    hp: int = 100
    max_hp: int = 100
    stamina: float = 100.0
    max_stamina: float = 100.0
    facing_x: float = 1.0
    facing_y: float = 0.0
    action: str = "idle"
    action_t: float = 0.0
    action_dur: float = 0.0
    active_a: float = 0.0
    active_b: float = 0.0
    damage: int = 0
    range: float = 0.0
    half_angle_deg: float = 0.0
    acted: bool = False
    invuln: float = 0.0
    dodge: float = 0.0
    hit_flash: float = 0.0
    ai_timer: float = 0.0
    anim_t: float = 0.0
    exposed: float = 0.0
    stagger: float = 0.0
    whiff_penalized: bool = False
    streak_action: str = ""
    streak_count: int = 0


class TopDownPrototype:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Pixel Boxing Top-Down Prototype")
        self.root.configure(bg="#05080d")
        self.canvas = tk.Canvas(self.root, width=WIDTH, height=HEIGHT, bg=BG, highlightthickness=0)
        self.canvas.pack(fill="both", expand=False)

        self.status = tk.Label(
            self.root,
            text="Arrows move, hold S backstep, hold W guard. A jab / D cross / Q+A left body / Q+D right hook / E+A left hook / E+D right body / W+A left uppercut / W+D right uppercut. Space: start/next round. R: restart match.",
            fg=WHITE,
            bg="#05080d",
            anchor="w",
            font=("Helvetica", 11, "bold"),
        )
        self.status.pack(fill="x", padx=8, pady=(6, 8))

        self.log = ""

        # Pseudo third-person camera parameters.
        self.cam_dist = 260.0
        # side_scale and forward_scale are kept close to each other so the
        # square world-space ARENA (450x450 units) actually reads as a
        # square ring on screen instead of a stretched-wide rectangle -
        # side_scale=1.45 vs forward_scale=0.90 used to blow the near edge
        # of the ring out to ~950px (off both sides of the canvas) while the
        # far edge shrank to ~270px, an extreme un-square trapezoid.
        self.cam_side_scale = 0.8
        self.cam_forward_scale = 1.15
        self.cam_ground_y = HEIGHT * 0.76
        self.cam_screen_bias_x = -84.0
        self.cam_screen_bias_y = 24.0
        self.cam_smooth = 8.8
        self.cam_shoulder_side = 28.0
        self.cam_shoulder_back = 18.0
        # Fighters need a bit of extra depth-to-screen-Y sensitivity beyond
        # the floor's own forward_scale: at real punching range the two
        # boxers are only a few dozen world units apart, which the floor's
        # scale (tuned for the whole 450-unit-deep arena) barely separates
        # on screen - they'd stack almost on top of each other. BUT applying
        # a flat steeper multiplier everywhere (the old cam_actor_forward_scale
        # approach) made a fighter far from the camera anchor (e.g. the enemy
        # at the start of a round, or either fighter near the arena's far/near
        # walls) render at a screen Y that no longer matches where the floor
        # itself places that same depth - visually "floating" outside the
        # ring's own rendered boundary even though they were legally inside
        # ARENA's world-space bounds. Fix: the extra sensitivity now fades
        # out (Gaussian falloff on cam_z) the further a point is from the
        # camera anchor, so it stays strong at close combat range but
        # converges back to the floor's own forward_scale at long range,
        # keeping fighters visually anchored to the floor everywhere.
        self.cam_actor_extra_scale = 1.2
        self.cam_actor_boost_sigma = 80.0

        self.duck_max = 34.0
        self.duck_smooth = 14.0
        self.back_max = 38.0
        self.back_smooth = 12.5
        self.guard_smooth = 18.0

        # Impact feedback: a hit briefly (a) freezes most of the game's
        # motion ("hitstop") and (b) rattles the camera, both classic
        # fighting-game techniques for making punches feel like they
        # actually connect instead of just ticking a health bar down.
        self.hitstop_timer = 0.0
        self.shake_timer = 0.0
        self.shake_mag = 0.0
        self.shake_x = 0.0
        self.shake_y = 0.0

        # Static background crowd - generated once with a fixed seed so it
        # doesn't reshuffle every restart, then just re-projected each frame
        # like any other world-space geometry (see draw_crowd).
        self.crowd_seats = self._generate_crowd()

        # Hit-impact juice: short-lived spark particles (world-space, so they
        # project/pan with the camera like anything else), purely cosmetic
        # and triggered from attempt_hit.
        self.particles = []
        # Ghost after-images of the most recently drawn glove positions, used
        # to fake a quick motion trail on punches (see draw_fighter).
        self.prev_hand_pos = {}

        self.max_rounds = ROUND_LIMIT
        self.reset_match()

        self.root.bind_all("<KeyPress>", self.on_key_down)
        self.root.bind_all("<KeyRelease>", self.on_key_up)

        self.tick()

    def reset_match(self):
        # Full match reset: fresh fighters, round count, and score, but the
        # Tk window/canvas/camera tuning constants are left untouched.
        self.player = Fighter("Player", 170, 295, PLAYER_COLOR)
        self.enemy = Fighter("Enemy", 420, 295, ENEMY_COLOR)
        self.cam_anchor_x = self.player.x
        self.cam_anchor_y = self.player.y
        self.player_stance_x = self.player.x
        self.player_stance_y = self.player.y
        self.cam_facing_x, self.cam_facing_y = normalize(self.enemy.x - self.player.x, self.enemy.y - self.player.y)
        self.player_duck_target = 0.0
        self.player_duck_offset = 0.0
        self.player_back_target = 0.0
        self.player_back_offset = 0.0
        self.player_guard_offset = 0.0
        self.hitstop_timer = 0.0
        self.shake_timer = 0.0
        self.shake_mag = 0.0
        self.shake_x = 0.0
        self.shake_y = 0.0
        self.keys = set()
        self.feedback_text = ""
        self.feedback_timer = 0.0
        self.commentary_text = ""
        self.commentary_timer = 0.0
        self.particles = []
        self.prev_hand_pos = {}
        self.round = 1
        self.score_player = 0
        self.score_enemy = 0
        self.round_time = float(ROUND_SECONDS)
        self.enemy_ai_cd = 0.0
        self.state = "intro"
        self.set_overlay("TOP-DOWN BOXING", f"Best of {self.max_rounds} rounds. Press Space to start Round 1.")
        self.push_log("Press Space to start Round 1.")

    def reset_round_only(self):
        # Between-round reset: HP/stamina/position/action state reset, but
        # round number and match score carry over.
        self.player = Fighter("Player", 170, 295, PLAYER_COLOR)
        self.enemy = Fighter("Enemy", 420, 295, ENEMY_COLOR)
        self.cam_anchor_x = self.player.x
        self.cam_anchor_y = self.player.y
        self.player_stance_x = self.player.x
        self.player_stance_y = self.player.y
        self.cam_facing_x, self.cam_facing_y = normalize(self.enemy.x - self.player.x, self.enemy.y - self.player.y)
        self.player_duck_target = 0.0
        self.player_duck_offset = 0.0
        self.player_back_target = 0.0
        self.player_back_offset = 0.0
        self.player_guard_offset = 0.0
        self.hitstop_timer = 0.0
        self.shake_timer = 0.0
        self.shake_mag = 0.0
        self.shake_x = 0.0
        self.shake_y = 0.0
        self.commentary_text = ""
        self.commentary_timer = 0.0
        self.particles = []
        self.prev_hand_pos = {}
        self.keys = set()
        self.round_time = float(ROUND_SECONDS)

    def set_overlay(self, title, body):
        self.overlay_title = title
        self.overlay_body = body

    def _start_round(self):
        self.reset_round_only()
        self.state = "fight"
        self.push_log(f"Round {self.round} bell.")

    def end_round(self, winner, reason):
        self.state = "round_break"
        if winner == "player":
            self.score_player += 1
            self.push_log(f"Round {self.round}: Player {reason}")
        elif winner == "enemy":
            self.score_enemy += 1
            self.push_log(f"Round {self.round}: Enemy {reason}")
        else:
            self.push_log(f"Round {self.round}: Draw ({reason})")

        player_won_match = self.score_player > self.max_rounds // 2
        enemy_won_match = self.score_enemy > self.max_rounds // 2
        last_round = self.round >= self.max_rounds

        if player_won_match or enemy_won_match or last_round:
            self.state = "match_over"
            if self.score_player > self.score_enemy:
                title = "PLAYER WINS THE MATCH"
            elif self.score_enemy > self.score_player:
                title = "ENEMY WINS THE MATCH"
            else:
                title = "MATCH DRAW"
            self.set_overlay(title, f"Final score P{self.score_player}-{self.score_enemy}E  |  Space or R: restart")
            return

        result = winner.upper() if winner in ("player", "enemy") else "DRAW"
        self.set_overlay(
            f"ROUND {self.round} - {result} ({reason})",
            f"Score P{self.score_player}-{self.score_enemy}E  |  Space: next round",
        )
        self.round += 1

    def push_log(self, text):
        self.log = text
        self.status.config(text=text)

    def show_feedback(self, text):
        self.feedback_text = text
        self.feedback_timer = 0.35
        self.push_log(text)

    def show_commentary(self, key, attacker=None, defender=None):
        # Sports-commentary style caption (see COMMENTARY_LINES/draw_hud) -
        # purely cosmetic, picked at random from that event's variants and
        # formatted with the attacker/defender's display name if given.
        lines = COMMENTARY_LINES.get(key)
        if not lines:
            return
        text = random.choice(lines).format(
            atk=attacker.name if attacker else "",
            def_=defender.name if defender else "",
        )
        self.commentary_text = text
        self.commentary_timer = 1.7

    def punch_category(self, action):
        if action in ("left_hook", "right_hook"):
            return "hook"
        if action in ("left_body", "right_body"):
            return "body"
        if action in ("left_uppercut", "right_uppercut"):
            return "uppercut"
        if action == "cross":
            return "cross"
        return "jab"

    def spawn_hit_particles(self, x, y, color, count):
        # World-space spark burst: stored as plain world (x, y) so it gets
        # projected/panned/scaled by the camera exactly like anything else
        # next frame, instead of being pinned to a fixed screen position.
        for _ in range(count):
            angle = random.uniform(0.0, 2.0 * math.pi)
            speed = random.uniform(70.0, 170.0)
            life = random.uniform(0.16, 0.30)
            self.particles.append({
                "x": x, "y": y,
                "vx": math.cos(angle) * speed, "vy": math.sin(angle) * speed,
                "life": life, "max_life": life, "color": color,
            })

    def update_particles(self, dt):
        alive = []
        for p in self.particles:
            p["x"] += p["vx"] * dt
            p["y"] += p["vy"] * dt
            p["vx"] *= 0.90
            p["vy"] *= 0.90
            p["life"] -= dt
            if p["life"] > 0:
                alive.append(p)
        self.particles = alive

    def draw_particles(self):
        for p in self.particles:
            t = clamp(p["life"] / p["max_life"], 0.0, 1.0)
            sx, sy, persp, cam_z = self.project_world(p["x"], p["y"])
            scale = self.sprite_scale(persp)
            r = max(0.6, 2.6 * scale * t)
            col = mix_color(p["color"], BG, (1.0 - t) * 0.75)
            # Offset up to roughly chest/head height on the sprite instead
            # of at the character's feet-level world anchor.
            py = sy - 16.0 * scale
            self.canvas.create_oval(sx - r, py - r, sx + r, py + r, fill=col, outline="")

    def on_key_down(self, event):
        key = (event.keysym or "").lower()
        self.keys.add(key)

        if key == "r":
            self.reset_match()
            return

        if self.state != "fight":
            if key == "space":
                if self.state in ("intro", "round_break"):
                    self._start_round()
                elif self.state == "match_over":
                    self.reset_match()
            return

        if key in ("a", "d"):
            self.start_combo_attack(key)
        elif key == "q":
            self.player_duck_target = -1.0
            self.show_feedback("DUCK LEFT")
        elif key == "e":
            self.player_duck_target = 1.0
            self.show_feedback("DUCK RIGHT")
        elif key == "s":
            if self.player_back_target <= 0:
                self.show_feedback("BACKSTEP")
            self.player_back_target = 1.0
            self.player.invuln = max(self.player.invuln, 0.10)
        elif key == "w" and self.is_guarding(self.player):
            self.show_feedback("GUARD UP")

    def on_key_up(self, event):
        key = (event.keysym or "").lower()
        if key in self.keys:
            self.keys.remove(key)
        if key == "q" and self.player_duck_target < 0:
            self.player_duck_target = 0.0
        elif key == "e" and self.player_duck_target > 0:
            self.player_duck_target = 0.0
        elif key == "s" and self.player_back_target > 0:
            self.player_back_target = 0.0

    def start_combo_attack(self, key):
        q_down = "q" in self.keys
        e_down = "e" in self.keys
        w_down = "w" in self.keys

        if w_down:
            action = "left_uppercut" if key == "a" else "right_uppercut"
        elif q_down:
            action = "left_body" if key == "a" else "right_hook"
        elif e_down:
            action = "left_hook" if key == "a" else "right_body"
        else:
            action = "jab" if key == "a" else "cross"

        self.start_attack(self.player, action)

    def start_attack(self, actor, name):
        if actor.action_t < actor.action_dur or actor.stagger > 0:
            return
        # (action_dur, active_a, active_b, damage, range, half_angle_deg, cost)
        # Range/half_angle are tuned per punch identity, not just copy-pasted
        # from one "straight/hook/upper" template: jab is the probing/
        # spacing tool so it reaches the FARTHEST of any punch (even farther
        # than cross) with a moderate cone; cross trades that reach for a
        # tighter, more precise cone and is thrown from closer range; hooks
        # get the widest cones (a sweeping arc can land at an angle a
        # straight punch can't) but the shortest reach (arms stay bent, not
        # extended); uppercuts are similarly short-range/close-quarters with
        # a narrow-ish cone since they're aimed straight up under the chin.
        specs = {
            "jab": (0.24, 0.08, 0.15, 6, 78, 26, 6),
            "cross": (0.34, 0.14, 0.24, 11, 60, 20, 11),
            "left_body": (0.32, 0.12, 0.22, 9, 54, 40, 9),
            "right_body": (0.35, 0.14, 0.24, 10, 56, 38, 10),
            "left_hook": (0.36, 0.16, 0.26, 11, 50, 56, 11),
            "right_hook": (0.38, 0.17, 0.28, 12, 52, 50, 12),
            "left_uppercut": (0.40, 0.18, 0.30, 13, 44, 26, 13),
            "right_uppercut": (0.42, 0.19, 0.31, 14, 46, 24, 14),
        }
        if name not in specs:
            return
        action_dur, active_a, active_b, damage, atk_range, half_angle_deg, cost = specs[name]
        if actor.stamina < cost:
            return

        # Repeating the exact same punch back-to-back stales its damage so
        # single-button mashing loses to mixing attacks with footwork.
        if actor.streak_action == name:
            actor.streak_count += 1
        else:
            actor.streak_action = name
            actor.streak_count = 1
        stale_mult = max(STALE_FLOOR, STALE_DECAY ** max(0, actor.streak_count - STALE_THRESHOLD))
        damage = max(1, int(round(damage * stale_mult)))

        actor.action = name
        actor.action_t = 0.0
        actor.acted = False
        actor.whiff_penalized = False
        actor.action_dur = action_dur
        actor.active_a = active_a
        actor.active_b = active_b
        actor.damage = damage
        actor.range = atk_range
        actor.half_angle_deg = half_angle_deg
        actor.stamina = clamp(actor.stamina - cost, 0, actor.max_stamina)

    def start_dodge(self, actor, side):
        if actor.action_t < actor.action_dur or actor.stagger > 0:
            return
        if actor.stamina < 8:
            return

        fx, fy = actor.facing_x, actor.facing_y
        if side == "left":
            dx, dy = -fy, fx
            label = "LEFT DODGE"
        elif side == "right":
            dx, dy = fy, -fx
            label = "RIGHT DODGE"
        else:
            dx, dy = -fx, -fy
            label = "BACKSTEP"

        dist = 54 if side != "back" else 48
        actor.x = clamp(actor.x + dx * dist, ARENA[0] + actor.radius, ARENA[2] - actor.radius)
        actor.y = clamp(actor.y + dy * dist, ARENA[1] + actor.radius, ARENA[3] - actor.radius)
        actor.action = "dodge"
        actor.action_t = 0.0
        actor.action_dur = 0.22
        actor.active_a = 0.0
        actor.active_b = 0.0
        actor.damage = 0
        actor.range = 0.0
        actor.half_angle_deg = 0.0
        actor.acted = True
        actor.invuln = 0.14
        actor.dodge = 0.14
        actor.stamina = clamp(actor.stamina - 8, 0, actor.max_stamina)
        if actor.name == "Player":
            self.show_feedback(label)

    def is_guarding(self, actor):
        # Only the player actively holds guard (mirrors duck/backstep being
        # player-only special cases elsewhere in this file). Guarding only
        # counts while the actor is free to act - mid-punch or flinching
        # overrides it, same as duck/backstep would.
        if actor.name != "Player":
            return False
        return "w" in self.keys and actor.action_t >= actor.action_dur and actor.stagger <= 0

    def attempt_hit(self, attacker, defender):
        if defender.invuln > 0 or (defender.action == "dodge" and defender.dodge > 0):
            if defender.name == "Player":
                self.show_feedback("DODGE SUCCESS")
            self.show_commentary("dodge", attacker, defender)
            return

        vx = defender.x - attacker.x
        vy = defender.y - attacker.y
        d = length(vx, vy)
        if d > attacker.range + defender.radius:
            return

        tx, ty = normalize(vx, vy)
        dot = attacker.facing_x * tx + attacker.facing_y * ty
        limit = math.cos(math.radians(attacker.half_angle_deg))
        if dot < limit:
            return

        if defender.name == "Player" and attacker.action in DUCK_EVADE_KEY:
            needed_key = DUCK_EVADE_KEY[attacker.action]
            duck_ratio = clamp(abs(self.player_duck_offset) / max(self.duck_max, 1e-6), 0.0, 1.0)
            duck_dir = "e" if self.player_duck_offset > 0 else "q" if self.player_duck_offset < 0 else None
            if duck_ratio >= DUCK_EVADE_THRESHOLD and duck_dir == needed_key:
                self.show_feedback("DUCK EVADE")
                self.show_commentary("duck_evade", attacker, defender)
                return

        damage = attacker.damage
        punished_whiff = defender.exposed > 0
        if punished_whiff:
            damage = int(round(damage * EXPOSED_DMG_MULT))

        guarding = self.is_guarding(defender)
        if guarding:
            damage = max(1, int(round(damage * GUARD_DAMAGE_MULT)))

        # Getting hit mid-swing cancels the punch outright instead of letting
        # both fighters trade for free, so reckless mashing gets cut short.
        interrupted = defender.action in ATTACK_ACTIONS and defender.action_t < defender.action_dur and not defender.acted
        if interrupted:
            defender.action = "idle"
            defender.action_t = 0.0
            defender.action_dur = 0.0

        defender.hp = clamp(defender.hp - damage, 0, defender.max_hp)
        defender.hit_flash = 0.18
        defender.invuln = 0.08
        defender.stagger = STAGGER_LOCK * (1.5 if interrupted else 1.0)
        defender.streak_count = 0

        # Impact feedback: brief hitstop (near-freeze) plus a camera rattle,
        # scaled a little by damage so a jab barely nudges the view but a
        # clean power shot actually feels like it landed.
        self.hitstop_timer = max(self.hitstop_timer, 0.05 + min(damage, 20) * 0.0035)
        self.shake_timer = max(self.shake_timer, 0.16)
        self.shake_mag = max(self.shake_mag, 3.0 + min(damage, 20) * 0.55)
        spark_color = "#9fd8ff" if guarding else "#fff2c9"
        self.spawn_hit_particles(defender.x, defender.y, spark_color, 7 + min(damage, 20) // 2)

        if attacker.name == "Player" and punished_whiff:
            self.show_feedback("COUNTER HIT!")
        elif defender.name == "Player" and interrupted:
            self.show_feedback("STAGGERED")
        elif defender.name == "Player" and guarding:
            self.show_feedback("BLOCKED")

        # Commentary priority: a landed counter/guard/stagger call is more
        # interesting than the generic per-punch-type line, so those take
        # precedence over it; KO overrides everything below since it's
        # about to end the round anyway.
        if punished_whiff:
            self.show_commentary("counter", attacker, defender)
        elif guarding:
            self.show_commentary("guard", attacker, defender)
        elif interrupted:
            self.show_commentary("stagger", attacker, defender)
        else:
            self.show_commentary(self.punch_category(attacker.action), attacker, defender)

        if defender.hp <= 0:
            winner = "player" if attacker.name == "Player" else "enemy"
            self.show_feedback("KO!")
            self.show_commentary("ko", attacker, defender)
            self.end_round(winner, "KO")

    def update_facing(self, actor, target):
        fx, fy = normalize(target.x - actor.x, target.y - actor.y)
        actor.facing_x = fx
        actor.facing_y = fy

    def update_player_movement(self, dt):
        if self.player.action_t < self.player.action_dur or self.player.stagger > 0:
            return
        strafe = (1 if "right" in self.keys else 0) - (1 if "left" in self.keys else 0)
        forward = (1 if "up" in self.keys else 0) - (1 if "down" in self.keys else 0)
        if strafe == 0 and forward == 0:
            return
        right_x, right_y = self.player.facing_y, -self.player.facing_x
        move_x = forward * self.player.facing_x + strafe * right_x
        move_y = forward * self.player.facing_y + strafe * right_y
        nx, ny = normalize(move_x, move_y)
        speed = 210
        dx = nx * speed * dt
        dy = ny * speed * dt
        self.player.x = clamp(self.player.x + dx, ARENA[0] + self.player.radius, ARENA[2] - self.player.radius)
        self.player.y = clamp(self.player.y + dy, ARENA[1] + self.player.radius, ARENA[3] - self.player.radius)
        # Track the "stance" position (intentional movement only) separately
        # from player.x/y so the camera can follow it without being dragged
        # around by the duck/backstep hold-and-return offsets.
        self.player_stance_x = clamp(self.player_stance_x + dx, ARENA[0] + self.player.radius, ARENA[2] - self.player.radius)
        self.player_stance_y = clamp(self.player_stance_y + dy, ARENA[1] + self.player.radius, ARENA[3] - self.player.radius)

    def update_ai(self, dt):
        e = self.enemy
        p = self.player

        e.ai_timer = max(0.0, e.ai_timer - dt)
        if e.action_t >= e.action_dur:
            dx = p.x - e.x
            dy = p.y - e.y
            dist = length(dx, dy)
            if dist > 130:
                nx, ny = normalize(dx, dy)
                e.x = clamp(e.x + nx * 155 * dt, ARENA[0] + e.radius, ARENA[2] - e.radius)
                e.y = clamp(e.y + ny * 155 * dt, ARENA[1] + e.radius, ARENA[3] - e.radius)

        # Capitalize immediately on the player's off-balance whiff window
        # instead of waiting out a random cooldown, so spamming attacks
        # blind gets punished rather than rewarded.
        if p.exposed > 0 and e.action_t >= e.action_dur and e.stagger <= 0:
            e.ai_timer = 0.0

        if e.ai_timer > 0 or self.state != "fight":
            return

        # Rounds ramp up the pressure a little, mirroring the escalating
        # difficulty the rest of the project uses for later rounds.
        cooldown_scale = 1.0 + 0.15 * (self.round - 1)
        e.ai_timer = random.uniform(0.14, 0.30) / cooldown_scale
        dist = length(p.x - e.x, p.y - e.y)
        if dist < 84 and random.random() < 0.28:
            self.start_dodge(e, random.choice(["left", "right", "back"]))
        elif dist < 110:
            self.start_attack(e, "cross" if random.random() < 0.55 else "jab")

    def update_actor_timers(self, actor, dt):
        actor.stamina = clamp(actor.stamina + dt * 17, 0, actor.max_stamina)
        actor.invuln = max(0.0, actor.invuln - dt)
        actor.dodge = max(0.0, actor.dodge - dt)
        actor.hit_flash = max(0.0, actor.hit_flash - dt)
        actor.exposed = max(0.0, actor.exposed - dt)
        actor.stagger = max(0.0, actor.stagger - dt)
        actor.anim_t += dt

        if actor.action_t < actor.action_dur:
            actor.action_t += dt
            if actor.action in ATTACK_ACTIONS and not actor.acted and actor.active_a <= actor.action_t <= actor.active_b:
                target = self.enemy if actor.name == "Player" else self.player
                self.attempt_hit(actor, target)
                actor.acted = True
            if actor.action_t >= actor.action_dur:
                if actor.action in ATTACK_ACTIONS and not actor.acted and not actor.whiff_penalized:
                    # A clean miss leaves you off balance a little longer,
                    # and vulnerable to a harder punish hit during that window.
                    actor.action_dur += WHIFF_RECOVERY
                    actor.whiff_penalized = True
                    actor.exposed = WHIFF_RECOVERY + 0.05
                    if actor.name == "Player":
                        self.show_feedback("OFF BALANCE")
                else:
                    actor.action = "idle"

    def attack_arc_color(self, action):
        if action in ("left_body", "right_body"):
            return "#ff9c5e"
        if action in ("left_hook", "right_hook"):
            return "#ff7a5a"
        if action in ("left_uppercut", "right_uppercut"):
            return "#ff4f6f"
        return GOLD

    def update_player_duck(self, dt):
        right_x, right_y = self.player.facing_y, -self.player.facing_x
        desired = self.player_duck_target * self.duck_max
        k = 1.0 - math.exp(-self.duck_smooth * dt)
        new_offset = lerp(self.player_duck_offset, desired, k)
        delta = new_offset - self.player_duck_offset
        self.player_duck_offset = new_offset
        if abs(delta) < 1e-4:
            return
        nx = self.player.x + right_x * delta
        ny = self.player.y + right_y * delta
        self.player.x = clamp(nx, ARENA[0] + self.player.radius, ARENA[2] - self.player.radius)
        self.player.y = clamp(ny, ARENA[1] + self.player.radius, ARENA[3] - self.player.radius)

    def update_player_backstep(self, dt):
        desired = self.player_back_target * self.back_max
        k = 1.0 - math.exp(-self.back_smooth * dt)
        new_offset = lerp(self.player_back_offset, desired, k)
        delta = new_offset - self.player_back_offset
        self.player_back_offset = new_offset
        if abs(delta) < 1e-4:
            return
        nx = self.player.x - self.player.facing_x * delta
        ny = self.player.y - self.player.facing_y * delta
        self.player.x = clamp(nx, ARENA[0] + self.player.radius, ARENA[2] - self.player.radius)
        self.player.y = clamp(ny, ARENA[1] + self.player.radius, ARENA[3] - self.player.radius)

    def update_player_guard(self, dt):
        # Purely a pose/timing smoother: is_guarding() (checked live against
        # self.keys) is what actually gates the damage reduction, so the
        # block stays responsive even while this offset eases in/out for the
        # visual raise/lower motion.
        desired = 1.0 if self.is_guarding(self.player) else 0.0
        k = 1.0 - math.exp(-self.guard_smooth * dt)
        self.player_guard_offset = clamp(lerp(self.player_guard_offset, desired, k), 0.0, 1.0)

    def update(self, dt):
        if self.state != "fight":
            return

        self.update_facing(self.player, self.enemy)
        self.update_facing(self.enemy, self.player)
        self.update_player_movement(dt)
        self.update_player_duck(dt)
        self.update_player_backstep(dt)
        self.update_player_guard(dt)
        self.update_ai(dt)
        self.update_actor_timers(self.player, dt)
        self.update_actor_timers(self.enemy, dt)
        self.feedback_timer = max(0.0, self.feedback_timer - dt)
        self.commentary_timer = max(0.0, self.commentary_timer - dt)
        self.update_particles(dt)

        if self.state == "fight":
            self.round_time = max(0.0, self.round_time - dt)
            if self.round_time <= 0.0:
                if self.player.hp > self.enemy.hp:
                    self.end_round("player", "Time")
                elif self.enemy.hp > self.player.hp:
                    self.end_round("enemy", "Time")
                else:
                    self.end_round("draw", "Time")

        # The camera's own facing/rotation is tracked separately from the
        # player's live facing_x/y: live facing is recomputed every frame
        # from the player's ACTUAL (duck-shifted) position toward the
        # opponent, so it flutters slightly whenever the player ducks -
        # that flutter used to leak into camera_basis() and made the whole
        # view rotate/shake a little on every duck even though the camera
        # position term already used the duck-immune player_stance_x/y.
        # Deriving cam_facing from the stance position instead keeps the
        # camera's rotation stable while ducking; only intentional arrow-key
        # movement (which updates player_stance_x/y) turns the camera.
        self.cam_facing_x, self.cam_facing_y = normalize(
            self.enemy.x - self.player_stance_x, self.enemy.y - self.player_stance_y
        )

        right_x, right_y, fwd_x, fwd_y = self.camera_basis()

        # The camera tracks the player's tracked "stance" position (updated
        # only by intentional arrow-key movement), not the raw player.x/y,
        # so duck/backstep hold-and-return offsets never drag the screen.
        target_cam_x = self.player_stance_x + right_x * self.cam_shoulder_side - fwd_x * self.cam_shoulder_back
        target_cam_y = self.player_stance_y + right_y * self.cam_shoulder_side - fwd_y * self.cam_shoulder_back
        k = 1.0 - math.exp(-self.cam_smooth * dt)
        self.cam_anchor_x = lerp(self.cam_anchor_x, target_cam_x, k)
        self.cam_anchor_y = lerp(self.cam_anchor_y, target_cam_y, k)

        if self.shake_timer > 0:
            self.shake_timer = max(0.0, self.shake_timer - dt)
            falloff = self.shake_timer / 0.16
            mag = self.shake_mag * falloff
            self.shake_x = random.uniform(-1.0, 1.0) * mag
            self.shake_y = random.uniform(-1.0, 1.0) * mag * 0.6
        else:
            self.shake_x = 0.0
            self.shake_y = 0.0

    def camera_basis(self):
        fx, fy = self.cam_facing_x, self.cam_facing_y
        rx, ry = fy, -fx
        return rx, ry, fx, fy

    def project_world(self, wx, wy, forward_scale=None, actor_depth_boost=False):
        rx, ry = wx - self.cam_anchor_x, wy - self.cam_anchor_y
        right_x, right_y, fwd_x, fwd_y = self.camera_basis()
        cam_x = rx * right_x + ry * right_y
        cam_z = rx * fwd_x + ry * fwd_y

        if forward_scale is None:
            forward_scale = self.cam_forward_scale
        if actor_depth_boost:
            # See the cam_actor_extra_scale comment in __init__: the boost
            # is strongest right at the camera anchor (close combat range,
            # where the two fighters need extra vertical separation) and
            # fades to ~0 with distance, so far-from-anchor points (e.g. a
            # fighter near the arena's back wall, or the enemy's spawn
            # position at the start of a round) converge back to the exact
            # same forward_scale the floor itself uses - no more mismatch
            # between "where the fighter renders" and "where the floor is".
            boost = self.cam_actor_extra_scale * math.exp(-(cam_z * cam_z) / (2.0 * self.cam_actor_boost_sigma ** 2))
            forward_scale = self.cam_forward_scale + boost

        depth = clamp(self.cam_dist + cam_z, 120.0, 900.0)
        persp = self.cam_dist / depth
        # self.shake_x/y is a decaying random offset applied on hit impact
        # (see attempt_hit/update) - added here so every projected point
        # (arena, crowd, both fighters) shakes together as one camera, not
        # just the fighter sprites.
        sx = WIDTH * 0.5 + self.cam_screen_bias_x + self.shake_x + cam_x * self.cam_side_scale * persp
        sy = self.cam_ground_y + self.cam_screen_bias_y + self.shake_y - cam_z * forward_scale * persp
        return sx, sy, persp, cam_z

    def sprite_scale(self, persp):
        return clamp(0.72 + 0.62 * persp, 0.55, 1.45)

    def screen_facing(self, fx, fy):
        right_x, right_y, fwd_x, fwd_y = self.camera_basis()
        sx = fx * right_x + fy * right_y
        sy = -(fx * fwd_x + fy * fwd_y)
        return sx, sy

    def _generate_crowd(self):
        # Fixed-seed background crowd: a fistful of world-space "seats"
        # outside the ARENA bounds, projected/drawn every frame exactly like
        # the floor/grid so they pan and scale with the camera instead of
        # looking pasted onto the screen. Fixed seed keeps the crowd stable
        # across restarts instead of reshuffling every reset_match().
        rng = random.Random(20260809)
        palette = ["#5a6b8c", "#8a7a6b", "#6b5a4a", "#4a5a6b", "#7a6b8a", "#3a4a5a", "#8a5a5a", "#5a8a6b"]
        seats = []
        # Far stands, behind/around the opponent's baseline - the most
        # prominent bank of seats since the camera looks toward them. More
        # rows (packed closer right behind the ropes, spreading out further
        # back) and more seats per row than the first pass, which left the
        # far background looking sparse/empty.
        for row_wx in (535, 565, 600, 640, 685, 735, 795, 860, 935):
            count = 22
            for i in range(count):
                wy = -60 + i * (680.0 / (count - 1)) + rng.uniform(-10, 10)
                seats.append((row_wx + rng.uniform(-9, 9), wy, rng.choice(palette)))
        # Side stands running along both long edges of the ring - more rows,
        # packed a bit tighter, so the sides read as full stands rather than
        # a single thin line of spectators.
        for row_wy in (0, -30, -62, 590, 622, 655):
            count = 12
            for i in range(count):
                wx = 75 + i * (440.0 / (count - 1)) + rng.uniform(-10, 10)
                seats.append((wx, row_wy + rng.uniform(-8, 8), rng.choice(palette)))
        return seats

    def draw_crowd(self):
        for wx, wy, color in self.crowd_seats:
            sx, sy, persp, cam_z = self.project_world(wx, wy)
            scale = self.sprite_scale(persp) * 0.85
            fog_t = clamp((cam_z + 60.0) / 760.0, 0.1, 0.78)
            tint = mix_color(color, BG, fog_t)
            body_r = 3.2 * scale
            head_r = 2.2 * scale
            self.canvas.create_oval(sx - body_r, sy - 1.0 * scale, sx + body_r, sy + 4.4 * scale, fill=tint, outline="")
            self.canvas.create_oval(sx - head_r, sy - 5.4 * scale, sx + head_r, sy - 5.4 * scale + 2 * head_r, fill=tint, outline="")

    def draw_ring_ropes(self):
        # Fake "height" for corner posts/ropes: there's no true vertical (Z)
        # axis in this projection, so a post's on-screen rise is just the
        # corner's own screen point pushed straight up, scaled by persp so
        # near posts read taller than far ones - the same trick used for
        # sprite_scale/fog elsewhere in this file.
        corners_world = [(ARENA[0], ARENA[1]), (ARENA[2], ARENA[1]), (ARENA[2], ARENA[3]), (ARENA[0], ARENA[3])]
        projected = [self.project_world(wx, wy) for wx, wy in corners_world]
        post_color = mix_color("#d3453f", BG, 0.1)
        rope_color = mix_color("#f2c94c", BG, 0.18)
        tops = []
        for sx, sy, persp, cam_z in projected:
            top_y = sy - 130.0 * persp * 0.55
            tops.append(top_y)
            self.canvas.create_line(sx, sy, sx, top_y, fill=post_color, width=4)
            self.canvas.create_oval(sx - 4, top_y - 4, sx + 4, top_y + 4, fill=post_color, outline="")
        for frac in (0.32, 0.6, 0.88):
            pts = []
            for i in range(4):
                sx, sy, persp, cam_z = projected[i]
                rope_y = sy + (tops[i] - sy) * frac
                pts.append((sx, rope_y))
            for i in range(4):
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % 4]
                self.canvas.create_line(x0, y0, x1, y1, fill=rope_color, width=2)

    def draw_arena(self):
        self.canvas.delete("all")
        self.canvas.create_rectangle(0, 0, WIDTH, HEIGHT, fill=BG, outline=BG)
        self.draw_crowd()
        c0 = self.project_world(ARENA[0], ARENA[1])
        c1 = self.project_world(ARENA[2], ARENA[1])
        c2 = self.project_world(ARENA[2], ARENA[3])
        c3 = self.project_world(ARENA[0], ARENA[3])
        floor_poly = [c0[0], c0[1], c1[0], c1[1], c2[0], c2[1], c3[0], c3[1]]
        self.canvas.create_polygon(floor_poly, fill=ARENA_BG, outline=ARENA_EDGE, width=3)

        # Perspective grid to reinforce over-shoulder depth.
        for gy in range(ARENA[1] + 40, ARENA[3], 44):
            l = self.project_world(ARENA[0], gy)
            r = self.project_world(ARENA[2], gy)
            fog_t = clamp(((l[3] + r[3]) * 0.5 + 80.0) / 820.0, 0.0, 0.62)
            self.canvas.create_line(l[0], l[1], r[0], r[1], fill=mix_color("#2a3f68", BG, fog_t), width=1)
        for gx in range(ARENA[0] + 40, ARENA[2], 44):
            t = self.project_world(gx, ARENA[1])
            b = self.project_world(gx, ARENA[3])
            fog_t = clamp(((t[3] + b[3]) * 0.5 + 80.0) / 820.0, 0.0, 0.62)
            self.canvas.create_line(t[0], t[1], b[0], b[1], fill=mix_color("#274066", BG, fog_t), width=1)

        self.draw_ring_ropes()

    def action_phase(self, fighter):
        if fighter.action_dur <= 1e-6:
            return 0.0
        return clamp(fighter.action_t / fighter.action_dur, 0.0, 1.0)

    def draw_bone(self, x0, y0, x1, y1, width, color, outline):
        self.canvas.create_line(x0, y0, x1, y1, fill=outline, width=width + 3, capstyle="round")
        self.canvas.create_line(x0, y0, x1, y1, fill=color, width=width, capstyle="round")

    def draw_joint(self, x, y, r, color, outline):
        self.canvas.create_oval(x - r - 1, y - r - 1, x + r + 1, y + r + 1, fill=outline, outline="")
        self.canvas.create_oval(x - r, y - r, x + r, y + r, fill=color, outline="")

    def draw_fist(self, x, y, kx, ky, scale, color, outline):
        # Oriented glove capsule instead of a plain circle: (kx, ky) points
        # the way the knuckles are facing, so a straight jab/cross reads as
        # pointing forward at the target, a hook visibly rotates through its
        # arc as it sweeps around, and an uppercut rotates to point straight
        # up as it drives through the chin - the fist's own facing becomes
        # another readable signal of which attack is coming.
        kmag = length(kx, ky)
        if kmag < 1e-6:
            kx, ky = 1.0, 0.0
        else:
            kx, ky = kx / kmag, ky / kmag
        px, py = -ky, kx
        back_x, back_y = x - kx * 1.6 * scale, y - ky * 1.6 * scale
        front_x, front_y = x + kx * 3.0 * scale, y + ky * 3.0 * scale
        w = 2.6 * scale
        poly = [
            back_x + px * w, back_y + py * w,
            front_x + px * w * 0.7, front_y + py * w * 0.7,
            front_x - px * w * 0.7, front_y - py * w * 0.7,
            back_x - px * w, back_y - py * w,
        ]
        self.canvas.create_polygon(poly, fill=outline, outline="")
        inset = 0.74
        poly_inner = [
            back_x + px * w * inset, back_y + py * w * inset,
            front_x + px * w * 0.7 * inset, front_y + py * w * 0.7 * inset,
            front_x - px * w * 0.7 * inset, front_y - py * w * 0.7 * inset,
            back_x - px * w * inset, back_y - py * w * inset,
        ]
        self.canvas.create_polygon(poly_inner, fill=color, outline="")

    def draw_foot(self, x, y, dir_x, dir_y, scale, color, outline):
        # Small elongated shoe shape oriented along the facing direction so
        # feet read as feet rather than as another joint circle.
        side_x, side_y = -dir_y, dir_x
        heel_x, heel_y = x - dir_x * 2.0 * scale, y - dir_y * 2.0 * scale
        toe_x, toe_y = x + dir_x * 4.5 * scale, y + dir_y * 4.5 * scale
        w = 2.6 * scale
        poly = [
            heel_x + side_x * w, heel_y + side_y * w,
            toe_x + side_x * w * 0.6, toe_y + side_y * w * 0.6,
            toe_x - side_x * w * 0.6, toe_y - side_y * w * 0.6,
            heel_x - side_x * w, heel_y - side_y * w,
        ]
        self.canvas.create_polygon(poly, fill=outline, outline="")
        inset = 0.75
        poly_inner = [
            heel_x + side_x * w * inset, heel_y + side_y * w * inset,
            toe_x + side_x * w * 0.6 * inset, toe_y + side_y * w * 0.6 * inset,
            toe_x - side_x * w * 0.6 * inset, toe_y - side_y * w * 0.6 * inset,
            heel_x - side_x * w * inset, heel_y - side_y * w * inset,
        ]
        self.canvas.create_polygon(poly_inner, fill=color, outline="")

    def strike_side(self, action):
        if action in ("jab", "left_body", "left_hook", "left_uppercut"):
            return "lead"
        if action in ("cross", "right_body", "right_hook", "right_uppercut"):
            return "rear"
        return "lead"

    def compute_strike_pose(self, action, phase, scale):
        # Per-punch biomechanical profiles derived from docs/motion.md: each
        # of the 8 punches gets its own kinetic-chain shape (hip drive, torso
        # rotation, foot pivot, level change) instead of sharing one generic
        # "straight/hook/upper" template, so a jab visibly reads as short and
        # rotation-free while a cross reads as a full hip-to-shoulder drive.
        #
        # NOTE on magnitudes: "fwd"/"side"/"up" are added directly to the
        # already-projected on-screen shoulder position along the screen-
        # space facing/side axes (see draw_fighter) - there is no further
        # perspective divide at this step, so these numbers translate to
        # screen pixels close to 1:1 (scaled by the character's own sprite
        # scale). Earlier values were tuned assuming heavy camera
        # foreshortening that turned out not to apply here, which made every
        # punch's reach barely register on screen (a few percent of body
        # height) - it looked like a twitch near the chin instead of a
        # committed strike. These values are deliberately large (a strike
        # should visibly travel a large fraction of the fighter's own body
        # height from windup to peak extension) so the motion reads clearly.
        # extend rises slowly toward the peak (phase 0.20->0.54) then snaps
        # back noticeably FASTER (phase 0.54->0.70) than it extended -
        # standard "slow anticipation, fast action" animation timing, which
        # reads as a sharp, snappy strike instead of a limp symmetric swing
        # that takes as long to retract as it did to throw.
        if phase <= 0.54:
            extend = clamp((phase - 0.20) / 0.34, 0.0, 1.0)
        else:
            extend = clamp(1.0 - (phase - 0.54) / 0.16, 0.0, 1.0)
        windup = clamp((0.28 - phase) / 0.28, 0.0, 1.0)

        if action == "jab":
            # Lead hand only: the LONGEST-reaching punch in the kit (a
            # probing/spacing tool, not a power shot) - straight and
            # rotation-free, the lead shoulder rolls forward just enough to
            # shield the chin, and recovery is immediate.
            return {
                "fwd": 10 * scale + 55 * scale * extend,
                "side": -3.0 * scale * windup,
                "up": -1.5 * scale,
                "torso_forward": 4.5 * scale * extend,
                "torso_side": -1.2 * scale * windup,
                "hip_turn": (-1.2 * scale * windup) + (3.2 * scale * extend),
                "pivot": 0.25 * extend,
                "crouch_bonus": 0.0,
                "knuckle_fwd": 1.0,
                "knuckle_side": 0.0,
                "knuckle_up": 0.0,
            }

        if action == "cross":
            # Full kinetic chain: rear foot/heel pivots first, hips and torso
            # rotate hard, the rear shoulder drives through last, weight
            # transfers onto the lead leg - but the net reach is deliberately
            # SHORTER than the jab (a tighter, more precise strike thrown
            # from closer range, not a longer one).
            return {
                "fwd": 9 * scale + 38 * scale * extend,
                "side": -8.0 * scale * windup,
                "up": -2.5 * scale,
                "torso_forward": 7.5 * scale * extend,
                "torso_side": -4.6 * scale * windup,
                "hip_turn": (-5.0 * scale * windup) + (11.0 * scale * extend),
                "pivot": extend,
                "crouch_bonus": 0.0,
                "knuckle_fwd": 1.0,
                "knuckle_side": 0.0,
                "knuckle_up": 0.0,
            }

        if action in ("left_body", "right_body"):
            # The whole stance dips first (level change), the punch stays
            # short and slightly bent rather than fully straight, and the
            # body rises back up during recovery.
            dip = clamp((0.34 - phase) / 0.34, 0.0, 1.0)
            return {
                "fwd": 7 * scale + 32 * scale * extend,
                "side": -8.0 * scale * windup,
                "up": 7.0 * scale,
                "torso_forward": 4.0 * scale * extend,
                "torso_side": -3.8 * scale * windup,
                "hip_turn": (-5.0 * scale * windup) + (9.5 * scale * extend),
                "pivot": extend,
                "crouch_bonus": 3.4 * scale * dip,
                "knuckle_fwd": 0.85,
                "knuckle_side": 0.25,
                "knuckle_up": 0.15,
            }

        if action in ("left_hook", "right_hook"):
            # Semicircular arc that swings OUTSIDE-IN at the opponent's head:
            # the fist chambers out wide to the striking side first (elbow
            # cocked out away from the body), then sweeps across the front
            # toward the centerline/target as it connects - not the reverse
            # (a hook is not a punch that starts tucked near the body and
            # reaches straight outward). "side" is deliberately positive at
            # the start of the swing (outward) and swings toward/past zero
            # (inward, toward the opponent's head) as sweep completes.
            sweep = clamp((phase - 0.20) / 0.52, 0.0, 1.0)
            return {
                "fwd": 6 * scale + 16 * scale * extend,
                "side": (19.0 * scale) - (27.0 * scale) * sweep,
                "up": -1.5 * scale,
                "torso_forward": 2.0 * scale,
                "torso_side": (-6.2 * scale) + (9.4 * scale) * sweep,
                "hip_turn": (-6.2 * scale) + (11.5 * scale) * sweep,
                "pivot": sweep,
                "crouch_bonus": 0.0,
                # Fist starts turned mostly sideways (still winding up on the
                # arc) and rotates to face more forward as it sweeps through
                # to connect, visibly reading as a rotating hook rather than
                # a straight punch.
                "knuckle_fwd": 0.25 + 0.65 * sweep,
                "knuckle_side": 1.0 - 0.55 * sweep,
                "knuckle_up": 0.0,
            }

        # left_uppercut / right_uppercut: knees/hips dip first, then the
        # striking-side leg drives the ground away, sending the hip, torso,
        # shoulder and fist upward together in a short vertical path.
        rise = clamp((phase - 0.26) / 0.50, 0.0, 1.0)
        dip = clamp((0.30 - phase) / 0.30, 0.0, 1.0)
        return {
            "fwd": 6 * scale + 16 * scale * extend,
            "side": -5.5 * scale * windup,
            "up": (11.0 * scale) + (-26.0 * scale) * rise,
            "torso_forward": 3.2 * scale,
            "torso_side": -2.2 * scale * windup,
            "hip_turn": (-3.2 * scale * windup) + (7.5 * scale * rise),
            "pivot": rise,
            "crouch_bonus": 3.0 * scale * dip * (1.0 - rise),
            # Fist rotates from a slightly forward/down chamber into pointing
            # straight up as it drives through the chin.
            "knuckle_fwd": 0.5 + 0.2 * rise,
            "knuckle_side": 0.15,
            "knuckle_up": 0.35 - 1.15 * rise,
        }


    def draw_fighter(self, f):
        sx, sy, persp, cam_z = self.project_world(f.x, f.y, actor_depth_boost=True)
        scale = self.sprite_scale(persp)
        fog_t = clamp((cam_z + 60.0) / 760.0, 0.0, 0.58)

        skin = mix_color("#f1c39d", BG, fog_t)
        body = mix_color(WHITE if f.hit_flash > 0 else f.color, BG, fog_t)
        body_dark = mix_color("#24324d", BG, fog_t * 0.8)
        # Gloves/shoes are tinted from each fighter's own color (brightened
        # for the gloves, darkened for the shoes) instead of a single shared
        # skin-tone glove for both fighters - real boxers wear corner-colored
        # gear, and it makes player vs. enemy silhouettes read apart faster.
        glove = mix_color(mix_color(f.color, WHITE, 0.4), BG, fog_t)
        shoe = mix_color(mix_color(f.color, "#161d2c", 0.65), BG, fog_t * 0.7)
        trunks = mix_color("#eef2f8", BG, fog_t * 0.4)
        trunks_trim = mix_color(f.color, BG, fog_t)
        outline = mix_color("#0a1020", BG, fog_t * 0.7)

        # A grounded contact shadow, anchored at the fighter's actual world
        # position (not the crouch/duck-shifted torso), so the sprite always
        # reads as standing ON the floor instead of floating over it -
        # without this there's no visual link at all between the character
        # and the ground plane beneath them.
        shadow_color = mix_color("#000000", ARENA_BG, 0.55 + fog_t * 0.3)
        shadow_y = sy + 25.0 * scale
        self.canvas.create_oval(
            sx - 10.0 * scale, shadow_y - 3.2 * scale,
            sx + 10.0 * scale, shadow_y + 3.2 * scale,
            fill=shadow_color, outline="",
        )

        dir_x, dir_y = self.screen_facing(f.facing_x, f.facing_y)
        dmag = length(dir_x, dir_y)
        if dmag < 1e-6:
            dir_x, dir_y = 1.0, 0.0
        else:
            dir_x, dir_y = dir_x / dmag, dir_y / dmag
        side_x, side_y = -dir_y, dir_x

        phase = self.action_phase(f)
        duck_ratio = 0.0
        back_ratio = 0.0
        guard_ratio = 0.0
        if f.name == "Player":
            duck_ratio = clamp(abs(self.player_duck_offset) / max(self.duck_max, 1e-6), 0.0, 1.0)
            back_ratio = clamp(self.player_back_offset / max(self.back_max, 1e-6), 0.0, 1.0)
            guard_ratio = clamp(self.player_guard_offset, 0.0, 1.0)
        elif f.action == "dodge":
            back_ratio = clamp(1.0 - phase, 0.0, 1.0)

        idle_active = f.action_t >= f.action_dur and duck_ratio < 0.05 and back_ratio < 0.05 and guard_ratio < 0.05
        idle_bob = math.sin(f.anim_t * 3.2) * (1.0 * scale) if idle_active else 0.0
        idle_sway = math.sin(f.anim_t * 1.6) * (0.7 * scale) if idle_active else 0.0
        # Subtle breathing: the chest/shoulder width pulses a little on its
        # own slower cycle, on top of the bob/sway footwork motion, so an
        # idle fighter never looks like a perfectly frozen mannequin.
        breath = math.sin(f.anim_t * 2.1) * (0.35 * scale) if idle_active else 0.0

        shoulder_half = 7.2 * scale + breath
        hip_half = 5.4 * scale
        lead_sign = -1.0
        rear_sign = 1.0

        # Resolve the punch profile once up front so body shots/uppercuts can
        # feed their extra stance-dip ("crouch_bonus") into the same level
        # change used by duck/backstep, instead of the torso floating at a
        # fixed height while only the arm/hip move.
        strike_arm = None
        strike_sign = 0.0
        profile = None
        if f.action in ATTACK_ACTIONS:
            strike_arm = self.strike_side(f.action)
            strike_sign = lead_sign if strike_arm == "lead" else rear_sign
            profile = self.compute_strike_pose(f.action, phase, scale)

        crouch = (5.0 * duck_ratio + 3.2 * back_ratio + 1.8 * guard_ratio) * scale + (profile["crouch_bonus"] if profile else 0.0)
        torso_center_x = sx - dir_x * (2.5 * back_ratio * scale) + side_x * idle_sway
        torso_center_y = sy - 3.0 * scale + crouch - idle_bob
        hip_center_x = sx + side_x * idle_sway * 0.5
        hip_center_y = sy + 8.0 * scale + crouch - idle_bob * 0.4
        neck_x = torso_center_x + dir_x * (1.4 * scale)
        # Neck kept short and given real width below (neck_w) so the head
        # reads as seated into the shoulders instead of perched on a long
        # thin stick ("floating head" - a longer/thinner neck plus the idle
        # bob motion made the head look like it was bobbing on its own,
        # disconnected from the body).
        neck_y = torso_center_y - 6.5 * scale + 3.0 * crouch
        head_center_x = neck_x + dir_x * (1.6 * scale)
        head_center_y = neck_y - 4.5 * scale + 1.5 * crouch

        # Guard-up idle hand pose (boxing stance) instead of hanging arms.
        guard_lift = 1.0 - clamp(duck_ratio * 0.5, 0.0, 0.5)
        lead_hand = (
            torso_center_x + side_x * (shoulder_half * lead_sign * 0.8) + dir_x * (7.0 * scale),
            torso_center_y - (10.0 * scale * guard_lift) + side_y * (shoulder_half * lead_sign * 0.8),
        )
        rear_hand = (
            torso_center_x + side_x * (shoulder_half * rear_sign * 0.8) + dir_x * (4.0 * scale),
            torso_center_y - (9.0 * scale * guard_lift) + side_y * (shoulder_half * rear_sign * 0.8),
        )
        if f.action == "dodge" or duck_ratio > 0.05:
            # Hands stay high and tight to the face while slipping/backing off.
            lead_hand = (
                torso_center_x + side_x * (shoulder_half * lead_sign * 0.55) + dir_x * (3.5 * scale),
                head_center_y + 1.0 * scale,
            )
            rear_hand = (
                torso_center_x + side_x * (shoulder_half * rear_sign * 0.55) + dir_x * (3.0 * scale),
                head_center_y + 2.0 * scale,
            )
        elif guard_ratio > 0.05:
            # Full double guard: both gloves pulled tight against the
            # temples/chin with elbows tucked to the ribs, clearly distinct
            # from the loose ready-stance guard and from the duck/slip pose.
            lift = 3.0 * scale * guard_ratio
            lead_hand = (
                torso_center_x + side_x * (shoulder_half * lead_sign * 0.32) + dir_x * (1.6 * scale),
                head_center_y + 2.4 * scale - lift * 0.2,
            )
            rear_hand = (
                torso_center_x + side_x * (shoulder_half * rear_sign * 0.32) + dir_x * (1.6 * scale),
                head_center_y + 3.0 * scale - lift * 0.2,
            )

        torso_lean_side = 0.0
        torso_lean_fwd = 0.0
        hip_turn = 0.0
        rear_pivot = 0.0
        lead_pivot = 0.0
        if profile is not None:
            torso_lean_side = profile["torso_side"] * strike_sign
            torso_lean_fwd = profile["torso_forward"]
            hip_turn = profile["hip_turn"] * strike_sign
            if strike_arm == "rear":
                rear_pivot = profile["pivot"]
            else:
                lead_pivot = profile["pivot"]

        torso_center_x += side_x * torso_lean_side + dir_x * torso_lean_fwd
        torso_center_y += side_y * torso_lean_side + dir_y * torso_lean_fwd
        hip_center_x += side_x * hip_turn * 0.6
        hip_center_y += side_y * hip_turn * 0.6
        neck_x += side_x * torso_lean_side * 0.5
        neck_y += side_y * torso_lean_side * 0.5
        head_center_x += side_x * torso_lean_side * 0.4
        head_center_y += side_y * torso_lean_side * 0.4

        lead_shoulder = (
            torso_center_x + side_x * shoulder_half * lead_sign,
            torso_center_y + side_y * shoulder_half * lead_sign,
        )
        rear_shoulder = (
            torso_center_x + side_x * shoulder_half * rear_sign,
            torso_center_y + side_y * shoulder_half * rear_sign,
        )

        if strike_arm is not None:
            strike_shoulder = lead_shoulder if strike_arm == "lead" else rear_shoulder
            strike_hand = (
                strike_shoulder[0]
                + dir_x * profile["fwd"]
                + side_x * profile["side"] * strike_sign,
                strike_shoulder[1]
                + dir_y * profile["fwd"]
                + side_y * profile["side"] * strike_sign
                + profile["up"],
            )
            if strike_arm == "lead":
                lead_hand = strike_hand
                rear_hand = (rear_hand[0] + dir_x * (1.0 * scale), rear_hand[1] - 1.0 * scale)
            else:
                rear_hand = strike_hand
                lead_hand = (lead_hand[0] + dir_x * (1.2 * scale), lead_hand[1] - 0.8 * scale)

        # Fist/knuckle facing: defaults to "forward" (a natural guard-fist
        # orientation) and only the currently-striking hand rotates to the
        # punch-specific direction from its profile, so straight punches
        # visibly point at the target, hooks rotate through their arc, and
        # uppercuts rotate upward as they rise.
        lead_knuckle = (dir_x, dir_y)
        rear_knuckle = (dir_x, dir_y)
        if strike_arm is not None:
            k_fwd = profile["knuckle_fwd"]
            k_side = profile["knuckle_side"] * strike_sign
            k_up = profile["knuckle_up"]
            strike_knuckle = (dir_x * k_fwd + side_x * k_side, dir_y * k_fwd + side_y * k_side + k_up)
            if strike_arm == "lead":
                lead_knuckle = strike_knuckle
            else:
                rear_knuckle = strike_knuckle

        # Arm elbows bend out from torso for readable silhouettes.
        def elbow_of(shoulder, hand, sign):
            mx = (shoulder[0] + hand[0]) * 0.5
            my = (shoulder[1] + hand[1]) * 0.5
            return (
                mx + side_x * sign * (4.4 * scale),
                my + side_y * sign * (4.4 * scale) + 1.6 * scale,
            )

        lead_elbow = elbow_of(lead_shoulder, lead_hand, lead_sign)
        rear_elbow = elbow_of(rear_shoulder, rear_hand, rear_sign)

        left_hip = (
            hip_center_x + side_x * hip_half * lead_sign,
            hip_center_y + side_y * hip_half * lead_sign,
        )
        right_hip = (
            hip_center_x + side_x * hip_half * rear_sign,
            hip_center_y + side_y * hip_half * rear_sign,
        )

        knee_bend = 1.0 + duck_ratio * 0.6 + back_ratio * 0.3 + guard_ratio * 0.2

        # Lead foot pivots and lifts its heel on lead-hand strikes (jab is
        # barely affected since its pivot amount is tiny, but hooks/uppercuts
        # thrown with the lead hand visibly turn on the front foot).
        lead_knee = (
            left_hip[0] + dir_x * (3.0 * scale + 2.0 * scale * lead_pivot) + side_x * (-1.0 * scale - 2.0 * scale * lead_pivot),
            left_hip[1] + dir_y * (3.0 * scale + 2.0 * scale * lead_pivot) + (10.0 * scale * knee_bend),
        )
        lead_foot = (
            left_hip[0] + dir_x * (6.0 * scale + 3.0 * scale * lead_pivot) + side_x * (-2.0 * scale - 3.5 * scale * lead_pivot),
            left_hip[1] + dir_y * (6.0 * scale + 3.0 * scale * lead_pivot) + (19.0 * scale * knee_bend) - (3.0 * scale * lead_pivot),
        )

        # Rear foot pivots and lifts its heel on rear-hand strikes for a
        # believable weight-transfer / hip-drive read.
        rear_knee = (
            right_hip[0] + dir_x * (1.0 * scale + 2.0 * scale * rear_pivot) + side_x * (1.0 * scale + 2.0 * scale * rear_pivot),
            right_hip[1] + dir_y * (1.0 * scale + 2.0 * scale * rear_pivot) + (10.0 * scale * knee_bend),
        )
        rear_foot = (
            right_hip[0] + dir_x * (2.5 * scale + 3.0 * scale * rear_pivot) + side_x * (2.2 * scale + 3.5 * scale * rear_pivot),
            right_hip[1] + dir_y * (2.5 * scale + 3.0 * scale * rear_pivot) + (19.0 * scale * knee_bend) - (3.0 * scale * rear_pivot),
        )

        limb_w = max(3, int(4.0 * scale))
        # Upper limbs (bicep/thigh) render thicker than lower limbs
        # (forearm/shin), tapering at the elbow/knee - a plain constant
        # width read as a soft, boneless noodle-arm; this bulge is the
        # cheapest way to suggest actual muscle mass on a stick-figure rig.
        upper_w = max(4, int(limb_w * 1.3))
        lower_w = max(2, int(limb_w * 0.75))
        neck_w = max(3, int(3.6 * scale))

        # Legs and feet render first (behind torso).
        self.draw_bone(left_hip[0], left_hip[1], lead_knee[0], lead_knee[1], upper_w, body_dark, outline)
        self.draw_bone(lead_knee[0], lead_knee[1], lead_foot[0], lead_foot[1], lower_w, body, outline)
        self.draw_joint(lead_knee[0], lead_knee[1], 2.6 * scale, body_dark, outline)
        self.draw_foot(lead_foot[0], lead_foot[1], dir_x, dir_y, scale, shoe, outline)

        self.draw_bone(right_hip[0], right_hip[1], rear_knee[0], rear_knee[1], upper_w, body_dark, outline)
        self.draw_bone(rear_knee[0], rear_knee[1], rear_foot[0], rear_foot[1], lower_w, body, outline)
        self.draw_joint(rear_knee[0], rear_knee[1], 2.6 * scale, body_dark, outline)
        self.draw_foot(rear_foot[0], rear_foot[1], dir_x, dir_y, scale, shoe, outline)

        # Tapered torso (broad shoulders, narrower waist) reads more human
        # than a plain circle and shows the hip/shoulder counter-rotation.
        waist_half = 5.0 * scale
        torso_poly = [
            lead_shoulder[0] + side_x * 1.4 * scale, lead_shoulder[1] + side_y * 1.4 * scale,
            rear_shoulder[0] + side_x * 1.4 * scale, rear_shoulder[1] + side_y * 1.4 * scale,
            hip_center_x + side_x * waist_half * rear_sign, hip_center_y + side_y * waist_half * rear_sign + 6.0 * scale,
            hip_center_x + side_x * waist_half * lead_sign, hip_center_y + side_y * waist_half * lead_sign + 6.0 * scale,
        ]
        self.canvas.create_polygon(torso_poly, fill=outline, outline="", width=0)
        inset = 1.1
        torso_poly_inner = [
            lead_shoulder[0] + side_x * 1.4 * scale * inset, lead_shoulder[1] + side_y * 1.4 * scale * inset,
            rear_shoulder[0] + side_x * 1.4 * scale * inset, rear_shoulder[1] + side_y * 1.4 * scale * inset,
            hip_center_x + side_x * waist_half * rear_sign * inset, hip_center_y + side_y * waist_half * rear_sign * inset + 5.6 * scale,
            hip_center_x + side_x * waist_half * lead_sign * inset, hip_center_y + side_y * waist_half * lead_sign * inset + 5.6 * scale,
        ]
        self.canvas.create_polygon(torso_poly_inner, fill=body, outline="")

        # Ab/pec shading: a couple of subtle crease lines across the belly
        # plus a sternum centerline, all in a tone between the outline and
        # body colors so it reads as muscle definition, not a hard stripe.
        shade = mix_color(outline, body, 0.4)
        ab_half = waist_half * 0.62
        for ab_off in (2.4 * scale, 5.6 * scale):
            self.canvas.create_line(
                hip_center_x + side_x * ab_half * rear_sign, hip_center_y + side_y * ab_half * rear_sign - 8.0 * scale + ab_off,
                hip_center_x + side_x * ab_half * lead_sign, hip_center_y + side_y * ab_half * lead_sign - 8.0 * scale + ab_off,
                fill=shade, width=max(1, int(1.1 * scale)),
            )
        self.canvas.create_line(
            torso_center_x + dir_x * 0.6 * scale, torso_center_y - 6.5 * scale,
            torso_center_x + dir_x * 0.6 * scale, torso_center_y + 1.5 * scale,
            fill=shade, width=max(1, int(1.0 * scale)),
        )

        # Boxing trunks: a bright, contrasting band across the hips/upper
        # thighs (classic white boxing shorts) so the silhouette breaks up
        # into jersey + shorts + legs instead of reading as one flat
        # head-to-toe bodysuit. It starts exactly where the torso fill ends
        # so it reads as a garment boundary, not an overlapping smear, and a
        # team-color side stripe + waistband ties it back to each fighter's
        # own color.
        trunk_half = waist_half * 1.3
        trunk_top = 1.5 * scale
        trunk_hem = 13.0 * scale
        trunks_poly = [
            hip_center_x + side_x * trunk_half * lead_sign, hip_center_y + side_y * trunk_half * lead_sign + trunk_top,
            hip_center_x + side_x * trunk_half * rear_sign, hip_center_y + side_y * trunk_half * rear_sign + trunk_top,
            hip_center_x + side_x * trunk_half * 0.72 * rear_sign, hip_center_y + side_y * trunk_half * 0.72 * rear_sign + trunk_top + trunk_hem,
            hip_center_x + side_x * trunk_half * 0.72 * lead_sign, hip_center_y + side_y * trunk_half * 0.72 * lead_sign + trunk_top + trunk_hem,
        ]
        self.canvas.create_polygon(trunks_poly, fill=trunks, outline=outline, width=1)
        # Waistband + matching side stripes down each hip in the team color.
        self.canvas.create_line(
            hip_center_x + side_x * trunk_half * lead_sign, hip_center_y + side_y * trunk_half * lead_sign + trunk_top,
            hip_center_x + side_x * trunk_half * rear_sign, hip_center_y + side_y * trunk_half * rear_sign + trunk_top,
            fill=trunks_trim, width=max(1, int(2.2 * scale)),
        )
        self.canvas.create_line(
            hip_center_x + side_x * trunk_half * lead_sign, hip_center_y + side_y * trunk_half * lead_sign + trunk_top,
            hip_center_x + side_x * trunk_half * 0.72 * lead_sign, hip_center_y + side_y * trunk_half * 0.72 * lead_sign + trunk_top + trunk_hem,
            fill=trunks_trim, width=max(1, int(1.6 * scale)),
        )
        self.canvas.create_line(
            hip_center_x + side_x * trunk_half * rear_sign, hip_center_y + side_y * trunk_half * rear_sign + trunk_top,
            hip_center_x + side_x * trunk_half * 0.72 * rear_sign, hip_center_y + side_y * trunk_half * 0.72 * rear_sign + trunk_top + trunk_hem,
            fill=trunks_trim, width=max(1, int(1.6 * scale)),
        )
        self.draw_joint(hip_center_x, hip_center_y + 3.0 * scale, 2.6 * scale, trunks_trim, outline)

        # Neck bridges the head to the torso so it never looks detached.
        self.draw_bone(neck_x, neck_y, head_center_x, head_center_y - 3.0 * scale, neck_w, skin, outline)

        # Wrist joints sit just short of the glove, splitting what used to be
        # a single forearm-to-glove bone into forearm + a short hand segment.
        # This gives each arm one more readable link in the chain and lets
        # the glove itself rotate independently at the wrist.
        hand_w = max(2, int(limb_w * 0.85))
        lead_wrist = (
            lead_elbow[0] + (lead_hand[0] - lead_elbow[0]) * 0.78,
            lead_elbow[1] + (lead_hand[1] - lead_elbow[1]) * 0.78,
        )
        rear_wrist = (
            rear_elbow[0] + (rear_hand[0] - rear_elbow[0]) * 0.78,
            rear_elbow[1] + (rear_hand[1] - rear_elbow[1]) * 0.78,
        )

        # Arms rendered over the torso for clear attack reads.
        self.draw_joint(lead_shoulder[0], lead_shoulder[1], 3.6 * scale, body_dark, outline)
        self.draw_bone(lead_shoulder[0], lead_shoulder[1], lead_elbow[0], lead_elbow[1], upper_w, body_dark, outline)
        self.draw_joint(lead_elbow[0], lead_elbow[1], 2.4 * scale, body_dark, outline)
        self.draw_bone(lead_elbow[0], lead_elbow[1], lead_wrist[0], lead_wrist[1], lower_w, body, outline)
        self.draw_joint(lead_wrist[0], lead_wrist[1], 1.8 * scale, body, outline)
        self.draw_bone(lead_wrist[0], lead_wrist[1], lead_hand[0], lead_hand[1], hand_w, skin, outline)

        self.draw_joint(rear_shoulder[0], rear_shoulder[1], 3.6 * scale, body_dark, outline)
        self.draw_bone(rear_shoulder[0], rear_shoulder[1], rear_elbow[0], rear_elbow[1], upper_w, body_dark, outline)
        self.draw_joint(rear_elbow[0], rear_elbow[1], 2.4 * scale, body_dark, outline)
        self.draw_bone(rear_elbow[0], rear_elbow[1], rear_wrist[0], rear_wrist[1], lower_w, body, outline)
        self.draw_joint(rear_wrist[0], rear_wrist[1], 1.8 * scale, body, outline)
        self.draw_bone(rear_wrist[0], rear_wrist[1], rear_hand[0], rear_hand[1], hand_w, skin, outline)

        # Oriented glove capsules replace the old plain circles: they point
        # the way each fist is facing, so the punch type/trajectory reads
        # directly off the glove, not just off the arm's overall pose.
        # A faint ghost of last frame's glove position is drawn first (only
        # while mid-punch) as a cheap motion-trail/streak effect, so a fast
        # jab/cross reads as a snappy blur instead of a single static frame.
        prev = self.prev_hand_pos.get(f.name)
        if prev is not None and f.action in ATTACK_ACTIONS and f.action_t < f.action_dur:
            ghost = mix_color(glove, BG, 0.6)
            self.draw_fist(prev[0][0], prev[0][1], lead_knuckle[0], lead_knuckle[1], scale * 0.92, ghost, outline)
            self.draw_fist(prev[1][0], prev[1][1], rear_knuckle[0], rear_knuckle[1], scale * 0.92, ghost, outline)
        self.prev_hand_pos[f.name] = (lead_hand, rear_hand)

        self.draw_fist(lead_hand[0], lead_hand[1], lead_knuckle[0], lead_knuckle[1], scale, glove, outline)
        self.draw_fist(rear_hand[0], rear_hand[1], rear_knuckle[0], rear_knuckle[1], scale, glove, outline)

        # Head and a simple visor line to show facing.
        head_r = 6.0 * scale
        self.draw_joint(head_center_x, head_center_y, head_r, skin, outline)

        # Hair: a dark cap over the top/back of the head only (offset
        # backward from center so the front/face stays exposed skin) - a
        # plain bald sphere on a stick was a big part of the "robotic, not
        # human" read; even this simple shape makes a huge difference.
        hair_color = mix_color("#171310", BG, fog_t * 0.9)
        hair_cx = head_center_x - dir_x * (head_r * 0.32)
        hair_cy = head_center_y - dir_y * (head_r * 0.32) - head_r * 0.18
        self.canvas.create_oval(
            hair_cx - head_r * 1.02, hair_cy - head_r * 0.98,
            hair_cx + head_r * 1.02, hair_cy + head_r * 0.62,
            fill=hair_color, outline=outline,
        )

        eye_x = head_center_x + dir_x * (head_r * 0.45)
        eye_y = head_center_y + dir_y * (head_r * 0.45)
        self.canvas.create_line(
            eye_x - side_x * 2.2 * scale,
            eye_y - side_y * 2.2 * scale,
            eye_x + side_x * 2.2 * scale,
            eye_y + side_y * 2.2 * scale,
            fill=outline,
            width=max(1, int(1.8 * scale)),
        )
        # Team-color headband across the brow, just behind the eye-line, for
        # a bit of readable per-fighter identity on an otherwise plain head.
        band_x = head_center_x - dir_x * (head_r * 0.15)
        band_y = head_center_y - dir_y * (head_r * 0.15)
        self.canvas.create_line(
            band_x - side_x * head_r * 0.95,
            band_y - side_y * head_r * 0.95,
            band_x + side_x * head_r * 0.95,
            band_y + side_y * head_r * 0.95,
            fill=trunks_trim,
            width=max(1, int(2.2 * scale)),
        )

        if f.action in ATTACK_ACTIONS and f.action_t < f.action_dur:
            r = f.range * scale
            a = math.degrees(math.atan2(-dir_y, dir_x))
            start = a - f.half_angle_deg
            extent = f.half_angle_deg * 2
            self.canvas.create_arc(
                sx - r,
                sy - r,
                sx + r,
                sy + r,
                start=start,
                extent=extent,
                style="arc",
                outline=mix_color(self.attack_arc_color(f.action), BG, fog_t * 0.55),
                width=2,
            )

        hp_ratio = f.hp / f.max_hp
        bar_w = 68
        bx0 = sx - bar_w / 2
        by0 = head_center_y - head_r - 14
        self.canvas.create_rectangle(bx0, by0, bx0 + bar_w, by0 + 7, fill="#0f1727", outline="#2b3e63")
        bar_color = GREEN if f.name == "Player" else RED
        self.canvas.create_rectangle(bx0 + 1, by0 + 1, bx0 + 1 + (bar_w - 2) * hp_ratio, by0 + 6, fill=bar_color, outline="")
        # Thin lighter line along the top of the fill for a subtle glossy/
        # beveled look instead of a flat single-tone bar.
        if hp_ratio > 0:
            self.canvas.create_line(
                bx0 + 1, by0 + 2, bx0 + 1 + (bar_w - 2) * hp_ratio, by0 + 2,
                fill=mix_color(bar_color, WHITE, 0.55), width=1,
            )

    def draw_hud(self):
        self.canvas.create_text(16, 18, anchor="w", fill=WHITE, font=("Helvetica", 12, "bold"), text=f"PLAYER HP {self.player.hp:3d}   ST {int(self.player.stamina):3d}")
        self.canvas.create_text(16, 38, anchor="w", fill=GRAY, font=("Helvetica", 10), text=f"ENEMY  HP {self.enemy.hp:3d}   ST {int(self.enemy.stamina):3d}")
        self.canvas.create_text(WIDTH - 16, 18, anchor="e", fill=GOLD, font=("Helvetica", 12, "bold"), text=f"ROUND {self.round}/{self.max_rounds}   {int(math.ceil(self.round_time)):02d}s")
        self.canvas.create_text(WIDTH - 16, 38, anchor="e", fill=GRAY, font=("Helvetica", 10), text=f"SCORE  P {self.score_player} - {self.score_enemy} E")

        if self.feedback_timer > 0:
            self.canvas.create_text(WIDTH / 2, 34, fill=GOLD, font=("Helvetica", 14, "bold"), text=self.feedback_text)

        if self.commentary_timer > 0:
            # A sports-commentary style caption bar along the bottom of the
            # screen, distinct from the short feedback popup near the top -
            # meant to read like a broadcast play-by-play line rather than a
            # terse status flag.
            bar_top = HEIGHT - 46
            self.canvas.create_rectangle(0, bar_top, WIDTH, HEIGHT, fill="#050a16", outline="")
            self.canvas.create_line(0, bar_top, WIDTH, bar_top, fill="#2b3e63", width=1)
            self.canvas.create_text(
                WIDTH / 2, HEIGHT - 23,
                fill=GOLD, font=("Helvetica", 14, "italic bold"),
                text=self.commentary_text,
            )

        if self.state != "fight":
            self.canvas.create_rectangle(230, 236, 730, 352, fill="#0a1223", outline="#5578ab", width=2)
            self.canvas.create_text(480, 276, fill=WHITE, font=("Helvetica", 20, "bold"), text=self.overlay_title)
            self.canvas.create_text(480, 314, fill=GRAY, font=("Helvetica", 12), text=self.overlay_body)

    def tick(self):
        dt = 0.016
        if self.hitstop_timer > 0:
            # Real-time countdown for how long the freeze lasts, but the
            # game itself runs at a crawl while it's active - a brief,
            # near-total pause reads as "the punch actually landed" instead
            # of the hp bar just silently ticking down mid-swing.
            self.hitstop_timer = max(0.0, self.hitstop_timer - dt)
            dt *= 0.12
        self.update(dt)
        self.draw_arena()
        actors = [self.player, self.enemy]
        actors.sort(key=lambda actor: self.project_world(actor.x, actor.y)[3], reverse=True)
        for actor in actors:
            self.draw_fighter(actor)
        self.draw_particles()
        self.draw_hud()
        self.root.after(16, self.tick)

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    TopDownPrototype().run()