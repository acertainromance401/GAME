import math
import random
import tkinter as tk
from dataclasses import dataclass, field

WIDTH = 960
HEIGHT = 540
ARENA = (80, 90, 880, 430)
ROUND_LIMIT = 3
ROUND_SECONDS = 45
CHAR_SCALE = 1.18
DEBUG_HITBOX_DEFAULT = False

BG_TOP = "#081325"
BG_BOTTOM = "#03060d"
RING_FILL = "#22314f"
RING_FILL_2 = "#2b4066"
ROPE_1 = "#b87333"
ROPE_2 = "#ffd36b"
POST = "#ffe27f"
PLAYER = "#6ad3ff"
PLAYER_DARK = "#2f91d4"
ENEMY = "#ff6a86"
ENEMY_DARK = "#d74666"
SKIN = "#f0c5a3"
OUTLINE = "#0b0d14"
WHITE = "#eef6ff"
GOLD = "#ffd65a"
GREEN = "#73ff9b"
RED = "#ff5f7a"
BLUE = "#68b8ff"
GRAY = "#9db2d1"

MAC_KEYCODE_MAP = {
    0: "a",
    1: "s",
    2: "d",
    4: "h",
    6: "z",
    7: "x",
    8: "c",
    9: "v",
    12: "q",
    13: "w",
    14: "e",
    15: "r",
    16: "y",
    17: "t",
    49: "space",
    123: "left",
    124: "right",
    125: "down",
    126: "up",
}

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


def clamp(v, a, b):
    return max(a, min(b, v))


def dist(ax, ay, bx, by):
    return math.hypot(ax - bx, ay - by)


@dataclass
class Fighter:
    name: str
    x: float
    y: float
    color: str
    color_dark: str
    facing: int = 1
    hp: int = 100
    stamina: int = 100
    max_hp: int = 100
    max_stamina: int = 100
    action: str = "idle"
    action_t: float = 0.0
    action_dur: float = 0.0
    active_a: float = 0.0
    active_b: float = 0.0
    damage: int = 0
    reach: float = 18.0
    body_w: int = 26
    body_h: int = 20
    hitstun: float = 0.0
    invuln: float = 0.0
    guard: bool = False
    dodge: float = 0.0
    duck_side: str = ""
    combo: int = 0
    ai_timer: float = 0.0
    vx: float = 0.0
    vy: float = 0.0
    flash: float = 0.0
    walk_phase: float = 0.0
    hurt_timer: float = 0.0
    hurt_dir: int = 0
    lean: float = 0.0
    ai_weights: dict = field(default_factory=lambda: {
        "jab": 1.0,
        "cross": 1.0,
        "left_body": 1.0,
        "right_body": 1.0,
        "left_hook": 1.0,
        "right_hook": 1.0,
        "left_uppercut": 1.0,
        "right_uppercut": 1.0,
        "advance": 1.0,
        "guard": 1.0,
        "dodge": 1.0,
    })
    ai_aggression: float = 1.0
    ai_experience: float = 0.0
    ai_last_action: str = ""


class PixelBoxingApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Pixel Boxing")
        self.root.configure(bg="#05080d")
        self.root.minsize(960, 620)

        self.canvas = tk.Canvas(self.root, width=WIDTH, height=HEIGHT, bg="#05080d", highlightthickness=0)
        self.canvas.pack(fill="both", expand=False)
        self.canvas.focus_set()

        self.hud = tk.Frame(self.root, bg="#05080d")
        self.hud.pack(fill="x", padx=10, pady=(0, 10))

        self.status = tk.Label(self.hud, text="Neon Ring ready.", fg=WHITE, bg="#05080d", font=("Helvetica", 11, "bold"), anchor="w")
        self.status.pack(fill="x")

        self.controls = tk.Label(
            self.hud,
            text="Move: Arrow | Backstep: S | Duck: Q/E | Guard: W | Jab: A | Cross: D | Q+A Left Body | Q+D Right Hook | E+A Left Hook | E+D Right Body | W+A Left Uppercut | W+D Right Uppercut | Next Round: Space | Hitbox: H | Restart: R",
            fg=GRAY,
            bg="#05080d",
            font=("Helvetica", 10),
            anchor="w",
        )
        self.controls.pack(fill="x", pady=(2, 0))

        self.bindings()
        self.started = False
        self.overlay_visible = True
        self.overlay_title = "NEON RING"
        self.overlay_text = "Press Space to start. Keep range, punish with hooks, and spend stamina wisely."
        self.screen_flash = 0.0
        self.shake = 0.0
        self.hit_stop = 0.0
        self.char_scale = CHAR_SCALE
        self.show_hitboxes = DEBUG_HITBOX_DEFAULT
        self.round_time = float(ROUND_SECONDS)
        self.score_player = 0
        self.score_enemy = 0
        self.dodge_hud_timer = 0.0
        self.dodge_hud_text = ""
        self.last_tick = None
        self.log = ["Neon Ring ready."]
        self.keys_down = set()
        self.key_debug = ""
        self.player_pattern = {
            "move_left": 0.0,
            "move_right": 0.0,
            "move_up": 0.0,
            "move_down": 0.0,
            "duck_left": 0.0,
            "duck_right": 0.0,
            "guard": 0.0,
            "jab": 0.0,
            "cross": 0.0,
            "left_body": 0.0,
            "right_body": 0.0,
            "left_hook": 0.0,
            "right_hook": 0.0,
            "left_uppercut": 0.0,
            "right_uppercut": 0.0,
        }
        self.reset_match()

        self.root.after(16, self.tick)

    def sc(self, value):
        return int(round(value * self.char_scale))

    def bindings(self):
        self.root.bind_all("<KeyPress>", self.on_key_down)
        self.root.bind_all("<KeyRelease>", self.on_key_up)
        self.root.bind_all("<Button-1>", lambda e: self.root.focus_force())

    def reset_match(self):
        self.round = 1
        self.max_rounds = ROUND_LIMIT
        self.round_time = float(ROUND_SECONDS)
        self.score_player = 0
        self.score_enemy = 0
        self.player = Fighter("Player", 180, 360, PLAYER, PLAYER_DARK)
        self.enemy = Fighter("Enemy", 740, 360, ENEMY, ENEMY_DARK)
        self.player.hp = self.player.max_hp = 100
        self.enemy.hp = self.enemy.max_hp = 100
        self.player.stamina = self.player.max_stamina = 100
        self.enemy.stamina = self.enemy.max_stamina = 100
        self.player.action = "idle"
        self.enemy.action = "idle"
        self.player.action_t = self.enemy.action_t = 0.0
        self.player.hitstun = self.enemy.hitstun = 0.0
        self.player.invuln = self.enemy.invuln = 0.0
        self.player.guard = self.enemy.guard = False
        self.player.dodge = self.enemy.dodge = 0.0
        self.player.duck_side = self.enemy.duck_side = ""
        self.player.combo = self.enemy.combo = 0
        self.player.flash = self.enemy.flash = 0.0
        self.player.walk_phase = self.enemy.walk_phase = 0.0
        self.player.hurt_timer = self.enemy.hurt_timer = 0.0
        self.player.hurt_dir = self.enemy.hurt_dir = 0
        self.player.lean = self.enemy.lean = 0.0
        self.player.ai_timer = 0.0
        self.enemy.ai_timer = 0.4
        self.enemy.ai_aggression = 1.0
        self.enemy.ai_experience = 0.0
        self.enemy.ai_last_action = ""
        self.state = "intro"
        self.winner = None
        self.started = False
        self.overlay_visible = True
        self.overlay_title = "NEON RING"
        self.overlay_text = "Press Space to start. Win rounds by KO or by HP when time expires."
        self.dodge_hud_timer = 0.0
        self.dodge_hud_text = ""
        self.log = ["Match reset."]
        self.keys_down.clear()
        self.key_debug = ""
        for key in self.player_pattern:
            self.player_pattern[key] = 0.0

    def show_dodge_feedback(self, defender, source="DODGE"):
        who = "YOU" if defender.name == "Player" else "ENEMY"
        self.dodge_hud_text = f"{who} {source} SUCCESS"
        self.dodge_hud_timer = 0.36
        self.push_log(f"{defender.name} {source.lower()} success")

    def start_round(self):
        self.state = "fight"
        self.overlay_visible = False
        self.round_time = float(ROUND_SECONDS)
        self.push_log(f"Round {self.round} bell.")

    def push_log(self, text):
        self.log.insert(0, text)
        self.log = self.log[:4]
        self.status.config(text="   ".join(self.log))

    def set_overlay(self, visible, title="", text=""):
        self.overlay_visible = visible
        self.overlay_title = title
        self.overlay_text = text

    def record_player_pattern(self, tag):
        if tag not in self.player_pattern:
            return
        self.player_pattern[tag] = min(20.0, self.player_pattern[tag] + 1.0)

    def decay_player_pattern(self):
        for key in self.player_pattern:
            self.player_pattern[key] *= 0.996

    def dominant_player_pattern(self):
        return max(self.player_pattern.items(), key=lambda item: item[1])[0]

    def normalize_key(self, event):
        key = (getattr(event, "keysym", "") or "").lower()
        if key in {"up", "down", "left", "right", "space", "q", "w", "e", "a", "s", "d", "r", "z", "x", "c", "v", "h"}:
            return key

        keycode = getattr(event, "keycode", None)
        if keycode in MAC_KEYCODE_MAP:
            return MAC_KEYCODE_MAP[keycode]

        char = (getattr(event, "char", "") or "").lower()
        if char in {"q", "w", "e", "a", "s", "d", "r", "z", "x", "c", "v", "h", " "}:
            return "space" if char == " " else char

        return key

    def on_key_down(self, e):
        key = self.normalize_key(e)
        self.key_debug = key
        self.keys_down.add(key)

        if key == "h":
            self.show_hitboxes = False
            self.push_log("Hitbox debug disabled")
            return

        if key == "r":
            self.reset_match()
            self.set_overlay(True, "Restarted", "A new bout is ready. Press Space to begin.")
            return

        if key == "space":
            if self.state == "intro":
                self.started = True
                self.start_round()
            elif self.state == "round_break":
                self._next_round()
            elif self.state == "match_over":
                self.reset_match()
            return

        if not self.started and key in ("up", "down", "left", "right", "a", "d", "q", "w", "e"):
            self.started = True
            if self.state == "intro":
                self.start_round()

        if self.state != "fight":
            return

        if key == "up":
            self.record_player_pattern("move_up")
            self.move_player(0, -1)
        elif key == "down":
            self.record_player_pattern("move_down")
            self.move_player(0, 1)
        elif key == "s":
            self.record_player_pattern("move_down")
            self.backstep_player()
        elif key == "left":
            self.record_player_pattern("move_left")
            self.move_player(-1, 0)
        elif key == "right":
            self.record_player_pattern("move_right")
            self.move_player(1, 0)
        elif key in ("q", "e"):
            self.record_player_pattern("duck_left" if key == "q" else "duck_right")
            self.player.duck_side = "left" if key == "q" else "right"
        elif key == "w":
            self.record_player_pattern("guard")
            self.player.guard = True
            if self.player.action_t <= 0 and self.player.hitstun <= 0:
                self.player.action = "guard"
        elif key in ("a", "d"):
            self.start_combo_action(key)

    def on_key_up(self, e):
        key = self.normalize_key(e)
        self.keys_down.discard(key)
        if key in ("q", "e") and self.player.duck_side == ("left" if key == "q" else "right"):
            self.player.duck_side = ""
        if key == "w":
            self.player.guard = False
            if self.player.action == "guard" and self.player.action_t <= 0:
                self.finish_action(self.player)

    def move_player(self, dx, dy):
        if self.player.hitstun > 0 or self.player.action_t > 0:
            return
        step_x = dx * 11
        step_y = dy * 11
        self.player.x = clamp(self.player.x + step_x, ARENA[0] + 32, ARENA[2] - 32)
        self.player.y = clamp(self.player.y + step_y, ARENA[1] + 26, ARENA[3] - 22)
        self.player.action = "move"
        self.player.vx = step_x * 5
        self.player.vy = step_y * 5
        self.player.facing = 1 if self.player.x < self.enemy.x else -1

    def backstep_player(self):
        if self.player.hitstun > 0 or self.player.action_t > 0:
            return
        # Backstep slides opposite from facing with brief i-frame.
        self.player.facing = 1 if self.player.x < self.enemy.x else -1
        step = -self.player.facing
        self.player.x = clamp(self.player.x + step * 42, ARENA[0] + 32, ARENA[2] - 32)
        self.player.vx = step * 180
        self.player.vy = 0
        self.player.invuln = max(self.player.invuln, 0.16)
        self.player.dodge = 0.16
        self.player.action = "dodge"
        self.player.action_t = 0.0
        self.player.action_dur = 0.20
        self.player.active_a = 0.0
        self.player.active_b = 0.0
        self.player.damage = 0
        self.player.reach = 0
        self.player.action_done = True
        self.player.flash = 0.0

    def start_combo_action(self, key):
        q_down = "q" in self.keys_down
        e_down = "e" in self.keys_down
        w_down = "w" in self.keys_down

        if w_down:
            if key == "a":
                self.record_player_pattern("left_uppercut")
                self.start_action(self.player, "left_uppercut")
            else:
                self.record_player_pattern("right_uppercut")
                self.start_action(self.player, "right_uppercut")
            return

        if q_down:
            if key == "a":
                self.record_player_pattern("left_body")
                self.start_action(self.player, "left_body")
            else:
                self.record_player_pattern("right_hook")
                self.start_action(self.player, "right_hook")
            return

        if e_down:
            if key == "a":
                self.record_player_pattern("left_hook")
                self.start_action(self.player, "left_hook")
            else:
                self.record_player_pattern("right_body")
                self.start_action(self.player, "right_body")
            return

        if key == "a":
            self.record_player_pattern("jab")
            self.start_action(self.player, "jab")
        else:
            self.record_player_pattern("cross")
            self.start_action(self.player, "cross")

    def start_action(self, fighter, action):
        if fighter.hitstun > 0:
            return
        if fighter.action in ATTACK_ACTIONS and fighter.action_t < fighter.action_dur:
            return
        if fighter.action == "dodge" and fighter.action_t < fighter.action_dur:
            return
        costs = {
            "jab": 7,
            "cross": 10,
            "left_body": 10,
            "right_body": 10,
            "left_hook": 12,
            "right_hook": 12,
            "left_uppercut": 14,
            "right_uppercut": 14,
            "guard": 4,
            "dodge": 6,
        }
        if fighter.stamina < costs[action] and action != "guard":
            return
        fighter.stamina = clamp(fighter.stamina - costs[action], 0, fighter.max_stamina)
        fighter.action = action
        fighter.action_t = 0.0
        fighter.action_done = False
        if action == "jab":
            fighter.action_dur, fighter.active_a, fighter.active_b, fighter.damage, fighter.reach = 0.32, 0.08, 0.18, 7, 28
        elif action == "cross":
            fighter.action_dur, fighter.active_a, fighter.active_b, fighter.damage, fighter.reach = 0.48, 0.18, 0.34, 11, 34
        elif action in ("left_body", "right_body"):
            fighter.action_dur, fighter.active_a, fighter.active_b, fighter.damage, fighter.reach = 0.44, 0.16, 0.30, 11, 24
        elif action in ("left_hook", "right_hook"):
            fighter.action_dur, fighter.active_a, fighter.active_b, fighter.damage, fighter.reach = 0.48, 0.18, 0.34, 13, 26
        elif action in ("left_uppercut", "right_uppercut"):
            fighter.action_dur, fighter.active_a, fighter.active_b, fighter.damage, fighter.reach = 0.52, 0.20, 0.38, 15, 24
        elif action == "guard":
            fighter.action_dur, fighter.active_a, fighter.active_b, fighter.damage, fighter.reach = 999, 0.0, 0.0, 0, 0
            fighter.guard = True
        elif action == "dodge":
            fighter.action_dur, fighter.active_a, fighter.active_b, fighter.damage, fighter.reach = 0.20, 0.0, 0.0, 0, 0
            fighter.invuln = 0.16
            fighter.dodge = 0.16
            step = -fighter.facing
            fighter.x = clamp(fighter.x + step * 24, ARENA[0] + 32, ARENA[2] - 32)
            fighter.vx = step * 130
            fighter.vy = 0
        fighter.flash = 0.0

    def finish_action(self, fighter):
        fighter.action = "idle"
        fighter.action_t = 0.0
        fighter.action_dur = 0.0
        fighter.action_done = False
        fighter.active_a = fighter.active_b = 0.0
        fighter.damage = 0
        fighter.reach = 18.0
        fighter.guard = False

    def ai_choose(self):
        e, p = self.enemy, self.player
        if e.hitstun > 0 or e.action_t > 0:
            return
        if e.ai_timer > 0:
            return
        e.ai_timer = random.uniform(0.12, 0.34) / e.ai_aggression
        distance = dist(e.x, e.y, p.x, p.y)
        dominant = self.dominant_player_pattern()

        def choose_action(candidates):
            total = sum(weight for _, weight in candidates)
            pick = random.uniform(0, total)
            current = 0.0
            for action, weight in candidates:
                current += weight
                if pick <= current:
                    return action
            return candidates[-1][0]

        if e.hp < 30 and random.random() < 0.40:
            self.start_action(e, "guard")
            e.ai_last_action = "guard"
            return
        if distance > 112:
            approach = -1 if self.enemy.x > self.player.x else 1
            self.enemy.x = clamp(self.enemy.x + approach * (11 + int(4 * e.ai_aggression)), ARENA[0] + 30, ARENA[2] - 30)
            self.enemy.y = clamp(self.enemy.y + random.uniform(-4, 4), ARENA[1] + 24, ARENA[3] - 20)
            e.action = "move"
            return
        if distance > 76:
            if dominant in ("guard", "duck_left", "duck_right"):
                action = choose_action([
                    ("jab", 1.0),
                    ("cross", 1.2),
                    ("left_body", 2.0),
                    ("right_body", 2.0),
                    ("left_uppercut", 1.8),
                    ("right_uppercut", 1.8),
                ])
            else:
                action = choose_action([
                    ("jab", 2.2),
                    ("cross", 1.8),
                    ("left_hook", 1.2),
                    ("right_hook", 1.2),
                ])
            if random.random() < 0.32:
                approach = -1 if self.enemy.x > self.player.x else 1
                self.enemy.x = clamp(self.enemy.x + approach * (6 + int(2 * e.ai_aggression)), ARENA[0] + 30, ARENA[2] - 30)
                self.enemy.y = clamp(self.enemy.y + random.uniform(-6, 6), ARENA[1] + 24, ARENA[3] - 20)
                e.action = "move"
            else:
                self.start_action(e, action)
                e.ai_last_action = action
            return
        if distance < 54 and random.random() < 0.22:
            self.start_action(e, "dodge")
            e.ai_last_action = "dodge"
            return
        if dominant == "duck_left":
            action = choose_action([("right_uppercut", 3.0), ("right_hook", 1.8), ("cross", 1.0)])
        elif dominant == "duck_right":
            action = choose_action([("left_uppercut", 3.0), ("left_hook", 1.8), ("jab", 1.0)])
        elif dominant == "guard":
            action = choose_action([("left_body", 2.4), ("right_body", 2.4), ("left_hook", 1.4), ("right_hook", 1.4)])
        elif dominant in ("jab", "cross"):
            action = choose_action([("cross", 2.0), ("jab", 2.0), ("dodge", 1.2), ("guard", 1.2)])
        else:
            action = choose_action([
                ("jab", 1.8),
                ("cross", 1.6),
                ("left_hook", 1.3),
                ("right_hook", 1.3),
                ("left_body", 1.0),
                ("right_body", 1.0),
            ])
        self.start_action(e, action)
        e.ai_last_action = action

    def apply_hit(self, attacker, defender, name, zone="body"):
        if defender.invuln > 0:
            if defender.action == "dodge":
                self.show_dodge_feedback(defender, "DODGE")
            return
        if defender.action == "dodge" and defender.dodge > 0:
            self.show_dodge_feedback(defender, "DODGE")
            return
        damage = attacker.damage
        if zone == "head":
            damage = int(round(damage * 1.45))
        note = "hit"
        if defender.guard:
            damage = max(1, int(damage * 0.35))
            note = "blocked"
        defender.hp = clamp(defender.hp - damage, 0, defender.max_hp)
        defender.hitstun = 0.18 if zone == "head" else (0.14 if damage >= 13 else 0.10)
        defender.invuln = 0.08
        defender.flash = 0.20
        defender.hurt_timer = 0.22 if damage < 13 else 0.30
        defender.hurt_dir = 1 if attacker.x < defender.x else -1
        defender.lean = clamp(defender.lean + defender.hurt_dir * (0.24 if damage < 13 else 0.36), -0.45, 0.45)
        attacker.combo += 1
        self.shake = max(self.shake, damage * 0.7)
        self.screen_flash = 0.12
        self.hit_stop = max(self.hit_stop, 0.08 if damage < 12 else 0.12)
        self.push_log(f"{attacker.name} {name.replace('_', ' ')} {zone.upper()} {note} {damage}")
        self.knockback(attacker, defender, 11 if name == "jab" else 14 if "hook" in name else 13 if "body" in name else 15)

        if attacker.name == "Enemy":
            reward = 1.0 if note == "hit" else 0.35
            attacker.ai_experience += reward * damage
            attacker.ai_aggression = clamp(attacker.ai_aggression + 0.04 * reward, 0.85, 2.4)
            attacker.ai_weights[name] = clamp(attacker.ai_weights.get(name, 1.0) + 0.12 * reward, 0.7, 4.0)
        elif defender.name == "Enemy":
            attacker_pattern = self.dominant_player_pattern()
            defender.ai_aggression = clamp(defender.ai_aggression + 0.01, 0.85, 2.4)
            if attacker_pattern in defender.ai_weights:
                defender.ai_weights[attacker_pattern] = clamp(defender.ai_weights[attacker_pattern] + 0.03, 0.7, 4.0)

    def knockback(self, a, d, force):
        dx = 1 if d.x > a.x else -1
        d.x = clamp(d.x + dx * force, ARENA[0] + 28, ARENA[2] - 28)
        d.y = clamp(d.y + (1 if d.y > a.y else -1) * 4, ARENA[1] + 22, ARENA[3] - 18)

    def update_fighter(self, f, other, dt):
        f.stamina = clamp(f.stamina + dt * 9, 0, f.max_stamina)
        f.invuln = max(0.0, f.invuln - dt)
        f.dodge = max(0.0, f.dodge - dt)
        f.hitstun = max(0.0, f.hitstun - dt)
        f.flash = max(0.0, f.flash - dt)
        f.hurt_timer = max(0.0, f.hurt_timer - dt)
        f.lean *= 0.90
        if f.ai_timer > 0:
            f.ai_timer = max(0.0, f.ai_timer - dt)

        if f.action == "guard":
            f.stamina = clamp(f.stamina - dt * 12, 0, f.max_stamina)

        if f.action == "guard":
            f.facing = 1 if f.x < other.x else -1
            if f.stamina <= 0:
                self.finish_action(f)
            return

        if f.action in ATTACK_ACTIONS or f.action == "dodge":
            f.action_t += dt
            if f.action in ATTACK_ACTIONS and not f.action_done and f.active_a <= f.action_t <= f.active_b:
                contact_zone = self.combat_contact(f, other)
                if contact_zone in ("body", "head"):
                    self.apply_hit(f, other, f.action, contact_zone)
                    f.action_done = True
                elif contact_zone == "evade":
                    # Punch is spent when the opponent slips it.
                    f.action_done = True
            if f.action_t >= f.action_dur:
                self.finish_action(f)
            return

        if f.hitstun <= 0 and f.action != "guard":
            f.facing = 1 if f.x < other.x else -1

        # drag and bounds
        if abs(f.vx) > 1 or abs(f.vy) > 1:
            f.x += f.vx * dt
            f.y += f.vy * dt
            f.vx *= 0.82
            f.vy *= 0.82
            f.walk_phase += dt * (10 + abs(f.vx) * 0.1 + abs(f.vy) * 0.1)
        elif f.action == "move":
            f.walk_phase += dt * 8

        f.x = clamp(f.x, ARENA[0] + 28, ARENA[2] - 28)
        f.y = clamp(f.y, ARENA[1] + 22, ARENA[3] - 18)

    def fighter_origin(self, f):
        pose = self.action_pose(f)
        x = f.x + int(pose["x"] * (1 if f.facing == 1 else -1))
        y = f.y + pose["y"]
        if f.hurt_timer > 0:
            x += f.hurt_dir * self.sc(2)
        return x, y, pose

    def fighter_hurtboxes(self, f):
        center_x, center_y, pose = self.fighter_origin(f)
        center_x += int(f.lean * self.sc(3))

        torso_w = self.sc(26)
        torso_top = center_y - self.sc(5) + pose["torso"]
        torso_h = self.sc(18)
        head_w = self.sc(14)
        head_h = self.sc(14)

        if f.duck_side:
            torso_top += self.sc(4)
            torso_h = self.sc(14)
            head_h = self.sc(12)
        elif f.action == "guard":
            torso_top += self.sc(1)
            torso_h = self.sc(16)
            head_h = self.sc(12)
        elif f.action in ("left_uppercut", "right_uppercut"):
            torso_h = self.sc(18)
            head_h = self.sc(14)

        if f.action == "dodge":
            torso_top += self.sc(2)

        torso_left = center_x - torso_w / 2
        torso_right = center_x + torso_w / 2
        torso_bottom = torso_top + torso_h

        head_center_x = center_x
        head_top = torso_top - self.sc(18) + pose["head"]
        if f.duck_side:
            head_top += self.sc(8)
        if f.action == "guard":
            head_top += self.sc(5)
        if f.action == "dodge":
            head_top += self.sc(3)
        head_left = head_center_x - head_w / 2
        head_right = head_center_x + head_w / 2
        head_bottom = head_top + head_h

        return [(torso_left, torso_top, torso_right, torso_bottom), (head_left, head_top, head_right, head_bottom)]

    def fighter_hurtbox_map(self, f):
        torso, head = self.fighter_hurtboxes(f)
        return {"body": torso, "head": head}

    def fighter_attackboxes(self, f):
        if f.action not in ATTACK_ACTIONS:
            return []
        if f.action_dur <= 0:
            return []

        phase = clamp(f.action_t / f.action_dur, 0.0, 1.0)
        action_bonus = {
            "jab": self.sc(2),
            "cross": self.sc(4),
            "left_body": self.sc(-1),
            "right_body": self.sc(-1),
            "left_hook": self.sc(1),
            "right_hook": self.sc(1),
            "left_uppercut": self.sc(0),
            "right_uppercut": self.sc(0),
        }
        # Long-arm character silhouette with controlled extension per move.
        arm_length = self.sc(16) + action_bonus.get(f.action, 0) + (self.sc(4) if phase >= 0.22 else 0) + (self.sc(6) if phase >= 0.48 else 0)
        arm_thickness = self.sc(12) if f.action in ("jab", "cross") else self.sc(14)
        vertical_shift = 0
        if f.action == "left_body":
            vertical_shift = self.sc(12)
        elif f.action == "right_body":
            vertical_shift = self.sc(14)
        elif f.action == "left_hook":
            vertical_shift = self.sc(3)
        elif f.action == "right_hook":
            vertical_shift = self.sc(5)
        elif f.action in ("left_uppercut", "right_uppercut"):
            vertical_shift = self.sc(15)

        center_x, center_y, pose = self.fighter_origin(f)
        forward = 1 if f.facing == 1 else -1
        strike_side = "lead"
        if f.action in ("cross", "right_body", "right_hook", "right_uppercut"):
            strike_side = "rear"
        shoulder_sign = forward if strike_side == "lead" else -forward
        shoulder_x = center_x + shoulder_sign * self.sc(8)
        fist_x = shoulder_x + forward * arm_length
        if f.facing == 1:
            left = shoulder_x
            right = fist_x
        else:
            left = fist_x
            right = shoulder_x
        top = center_y - self.sc(10) + vertical_shift + pose["torso"]
        if strike_side == "rear":
            top += self.sc(1)
        if f.duck_side:
            top += self.sc(2)
        bottom = top + arm_thickness
        if left > right:
            left, right = right, left
        pad = self.sc(3)
        boxes = [(left - pad, top - pad, right + pad, bottom + pad)]

        elbow_mid_x = (shoulder_x + fist_x) / 2
        boxes.append((elbow_mid_x - self.sc(6), top - self.sc(2), elbow_mid_x + self.sc(6), bottom + self.sc(2)))

        if phase >= 0.50:
            fist_top = top - 1 if f.action not in ("left_uppercut", "right_uppercut") else top - 3
            fist_bottom = fist_top + (self.sc(12) if f.action in ("jab", "cross") else self.sc(14))
            boxes.append((fist_x - self.sc(7), fist_top - self.sc(2), fist_x + self.sc(7), fist_bottom + self.sc(2)))

        return boxes

    def rects_overlap(self, a, b):
        if a is None or b is None:
            return False
        ax0, ay0, ax1, ay1 = a
        bx0, by0, bx1, by1 = b
        return ax0 < bx1 and ax1 > bx0 and ay0 < by1 and ay1 > by0

    def is_head_punch(self, action):
        return action in ("jab", "cross", "left_hook", "right_hook")

    def duck_evades_head_punch(self, attacker, defender):
        if not defender.duck_side:
            return False
        if not self.is_head_punch(attacker.action):
            return False
        return True

    def combat_contact(self, attacker, defender):
        attackboxes = self.fighter_attackboxes(attacker)
        if not attackboxes:
            return None
        hurt = self.fighter_hurtbox_map(defender)
        if any(self.rects_overlap(attack, hurt["head"]) for attack in attackboxes):
            if self.duck_evades_head_punch(attacker, defender):
                self.show_dodge_feedback(defender, "DUCK")
                return "evade"
            return "head"
        if any(self.rects_overlap(attack, hurt["body"]) for attack in attackboxes):
            return "body"
        return None

    def action_phase(self, f):
        if f.action_t <= 0 or f.action_dur <= 0:
            return 0.0
        return clamp(f.action_t / f.action_dur, 0.0, 1.0)

    def action_pose(self, f):
        pose = {
            "x": 0,
            "y": 0,
            "torso": 0,
            "head": 0,
            "guard": False,
            "duck": 0,
            "reach": 0,
        }
        phase = self.action_phase(f)

        if f.action == "guard":
            pose["torso"] = -self.sc(3)
            pose["head"] = -self.sc(3)
            pose["guard"] = True
        elif f.duck_side:
            pose["duck"] = 2 if f.duck_side == "right" else -2
            pose["x"] = self.sc(10) if f.duck_side == "right" else -self.sc(10)
            pose["y"] = self.sc(2)
            pose["torso"] = self.sc(12)
            pose["head"] = self.sc(12)

        if f.action in ("jab", "cross", "left_body", "right_body", "left_hook", "right_hook", "left_uppercut", "right_uppercut"):
            if f.action == "jab":
                if phase < 0.18:
                    pose["x"] = -self.sc(3)
                    pose["y"] = -self.sc(2)
                    pose["torso"] = -self.sc(2)
                elif phase < 0.42:
                    pose["x"] = self.sc(3)
                    pose["torso"] = -self.sc(1)
                elif phase < 0.72:
                    pose["x"] = self.sc(7)
                    pose["torso"] = self.sc(1)
                else:
                    pose["x"] = self.sc(3)
            elif f.action == "cross":
                if phase < 0.18:
                    pose["x"] = -self.sc(4)
                    pose["y"] = -self.sc(2)
                    pose["torso"] = -self.sc(2)
                elif phase < 0.42:
                    pose["x"] = self.sc(4)
                    pose["torso"] = -self.sc(1)
                elif phase < 0.72:
                    pose["x"] = self.sc(9)
                    pose["torso"] = self.sc(1)
                else:
                    pose["x"] = self.sc(4)
            elif f.action == "left_hook":
                if phase < 0.20:
                    pose["x"] = -self.sc(2)
                    pose["y"] = -self.sc(1)
                    pose["torso"] = -self.sc(2)
                elif phase < 0.48:
                    pose["x"] = self.sc(5)
                    pose["y"] = -self.sc(1)
                    pose["torso"] = -self.sc(1)
                else:
                    pose["x"] = self.sc(7)
                    pose["y"] = -self.sc(1)
            elif f.action == "right_hook":
                if phase < 0.20:
                    pose["x"] = -self.sc(4)
                    pose["torso"] = -self.sc(1)
                elif phase < 0.48:
                    pose["x"] = self.sc(4)
                    pose["torso"] = self.sc(1)
                else:
                    pose["x"] = self.sc(9)
                    pose["torso"] = self.sc(2)
            elif f.action == "left_body":
                if phase < 0.20:
                    pose["x"] = -self.sc(2)
                    pose["y"] = self.sc(2)
                    pose["torso"] = self.sc(2)
                elif phase < 0.48:
                    pose["x"] = self.sc(2)
                    pose["y"] = self.sc(3)
                    pose["torso"] = self.sc(3)
                else:
                    pose["x"] = self.sc(4)
                    pose["y"] = self.sc(2)
            elif f.action == "right_body":
                if phase < 0.20:
                    pose["x"] = -self.sc(4)
                    pose["y"] = self.sc(2)
                    pose["torso"] = self.sc(2)
                elif phase < 0.48:
                    pose["x"] = self.sc(2)
                    pose["y"] = self.sc(3)
                    pose["torso"] = self.sc(3)
                else:
                    pose["x"] = self.sc(4)
                    pose["y"] = self.sc(2)
            elif f.action in ("left_uppercut", "right_uppercut"):
                if phase < 0.18:
                    pose["x"] = -self.sc(2)
                    pose["y"] = self.sc(2)
                    pose["torso"] = self.sc(1)
                elif phase < 0.48:
                    pose["x"] = self.sc(4)
                    pose["y"] = self.sc(3)
                    pose["torso"] = self.sc(2)
                    pose["head"] = self.sc(1)
                else:
                    pose["x"] = self.sc(5)
                    pose["y"] = self.sc(2)
                    pose["head"] = self.sc(1)
            if f.action in ("cross", "right_body", "right_hook", "right_uppercut"):
                pose["x"] += self.sc(1)
        elif f.action == "dodge":
            pose["x"] = -self.sc(9) if f.facing == 1 else self.sc(9)
            pose["y"] = self.sc(9)
            pose["torso"] = self.sc(3)
            pose["head"] = self.sc(7)
        elif f.action == "hit":
            pose["x"] = -self.sc(2) if f.facing == 1 else self.sc(2)
            pose["y"] = self.sc(1)

        return pose

    def in_range(self, a, d):
        return self.combat_contact(a, d) == "body"

    def update(self, dt):
        if self.state == "intro":
            if self.started:
                self.state = "fight"
                self.overlay_visible = False

        if self.state != "fight":
            return

        if self.hit_stop > 0:
            self.hit_stop = max(0.0, self.hit_stop - dt)
            self.screen_flash = max(0.0, self.screen_flash - dt * 1.2)
            self.shake = max(0.0, self.shake - dt * 6)
            return

        self.decay_player_pattern()

        # movement from held keys
        mx = (1 if 'right' in self.keys_down else 0) - (1 if 'left' in self.keys_down else 0)
        my = (1 if 'down' in self.keys_down else 0) - (1 if 'up' in self.keys_down else 0)
        if self.player.hitstun <= 0 and self.player.action_t <= 0:
            if mx or my:
                mag = max(1.0, math.hypot(mx, my))
                self.player.x = clamp(self.player.x + (mx / mag) * 80 * dt, ARENA[0] + 28, ARENA[2] - 28)
                self.player.y = clamp(self.player.y + (my / mag) * 80 * dt, ARENA[1] + 22, ARENA[3] - 18)
                self.player.action = "move"

        # action input handled on keydown
        self.ai_choose()
        self.update_fighter(self.player, self.enemy, dt)
        self.update_fighter(self.enemy, self.player, dt)

        self.round_time = max(0.0, self.round_time - dt)

        if self.player.guard and self.player.action_t <= 0 and self.player.hitstun <= 0:
            self.player.action = "guard"
        elif not self.player.guard and self.player.action == "guard" and self.player.action_t <= 0:
            self.finish_action(self.player)

        if self.player.hp <= 0:
            self.end_round("enemy", "KO")
            return
        if self.enemy.hp <= 0:
            self.end_round("player", "KO")
            return
        if self.round_time <= 0.0:
            if self.player.hp > self.enemy.hp:
                self.end_round("player", "Time")
            elif self.enemy.hp > self.player.hp:
                self.end_round("enemy", "Time")
            else:
                self.end_round("draw", "Time")
            return

        self.screen_flash = max(0.0, self.screen_flash - dt * 2.0)
        self.shake = max(0.0, self.shake - dt * 20)
        self.dodge_hud_timer = max(0.0, self.dodge_hud_timer - dt)

        if self.player.action_t > 0:
            self.overlay_text = self.action_label(self.player.action)
        elif self.player.duck_side:
            self.overlay_text = f"Duck {self.player.duck_side.title()}"
        elif self.player.guard:
            self.overlay_text = "Guard up"
        else:
            self.overlay_text = "Arrow Keys move. Q/E duck. W guard. A jab. D cross. Hold chords for body shots and uppercuts."

    def end_round(self, winner, reason):
        if self.state != "fight":
            return
        self.state = "round_break"

        if winner == "player":
            self.score_player += 1
            self.push_log(f"Round {self.round}: Player {reason}")
        elif winner == "enemy":
            self.score_enemy += 1
            self.push_log(f"Round {self.round}: Enemy {reason}")
        else:
            self.push_log(f"Round {self.round}: Draw {reason}")

        player_won_match = self.score_player > self.max_rounds // 2
        enemy_won_match = self.score_enemy > self.max_rounds // 2
        last_round = self.round >= self.max_rounds

        if player_won_match or enemy_won_match or last_round:
            self.state = "match_over"
            if self.score_player > self.score_enemy:
                self.set_overlay(True, "Victory", "Match won. Press R to restart or Space for a new match.")
            elif self.score_enemy > self.score_player:
                self.set_overlay(True, "Defeat", "Enemy wins the match. Press R to restart or Space for a new match.")
            else:
                self.set_overlay(True, "Draw", "Match is tied. Press R to restart or Space for a new match.")
            return

        self.set_overlay(True, f"Round {self.round} End", "Press Space to start the next round.")
        self.round += 1

    def _next_round(self):
        if self.state != "round_break":
            return
        self.reset_round_only()
        self.state = "fight"
        self.set_overlay(False, '', '')
        self.push_log(f"Round {self.round} bell.")

    def reset_round_only(self):
        self.player = Fighter("Player", 180, 360, PLAYER, PLAYER_DARK)
        self.enemy = Fighter("Enemy", 740, 360, ENEMY, ENEMY_DARK)
        self.player.hp = self.player.max_hp = 100
        self.enemy.hp = self.enemy.max_hp = 100
        self.player.stamina = self.player.max_stamina = 100
        self.enemy.stamina = self.enemy.max_stamina = 100
        self.player.guard = self.enemy.guard = False
        self.player.duck_side = self.enemy.duck_side = ""
        self.player.action = self.enemy.action = "idle"
        self.player.action_t = self.enemy.action_t = 0.0
        self.player.hitstun = self.enemy.hitstun = 0.0
        self.player.invuln = self.enemy.invuln = 0.0
        self.player.combo = self.enemy.combo = 0
        self.player.ai_timer = 0.0
        self.enemy.ai_timer = 0.25
        self.hit_stop = 0.0
        self.dodge_hud_timer = 0.0
        self.dodge_hud_text = ""
        self.round_time = float(ROUND_SECONDS)

    def action_label(self, action):
        return {
            "jab": "Jab",
            "cross": "Cross",
            "left_body": "Left Body",
            "right_body": "Right Body",
            "left_hook": "Left Hook",
            "right_hook": "Right Hook",
            "left_uppercut": "Left Uppercut",
            "right_uppercut": "Right Uppercut",
            "guard": "Guard",
            "dodge": "Dodge",
            "move": "Footwork",
            "idle": "Ready",
        }.get(action, action.replace("_", " ").title())

    def draw_text(self, x, y, text, color=WHITE, size=11, bold=True):
        self.canvas.create_text(x, y, text=text, fill=color, font=("Helvetica", size, "bold" if bold else "normal"))

    def draw_background(self):
        self.canvas.delete("all")
        # gradient background bands
        for i in range(0, HEIGHT, 6):
            t = i / HEIGHT
            c = self.mix(BG_TOP, BG_BOTTOM, t)
            self.canvas.create_rectangle(0, i, WIDTH, i + 6, outline=c, fill=c)
        # arena glow and crowd
        for i in range(18):
            self.canvas.create_rectangle(20 + i * 50, 34 + (i % 2) * 3, 38 + i * 50, 60 + (i % 3) * 4, fill="#101a30", outline="")
        self.canvas.create_rectangle(ARENA[0] - 18, ARENA[1] - 18, ARENA[2] + 18, ARENA[3] + 18, outline="#0f1730", fill="#17233b", width=2)
        self.canvas.create_rectangle(ARENA[0], ARENA[1], ARENA[2], ARENA[3], outline="#31486d", fill=RING_FILL, width=2)
        self.canvas.create_rectangle(ARENA[0] + 2, ARENA[1] + 2, ARENA[2] - 2, ARENA[3] - 2, outline="#2f4770", fill=RING_FILL_2, width=2)

        # ropes
        rope_y = [ARENA[1] + 14, ARENA[1] + 38, ARENA[1] + 92, ARENA[1] + 116]
        for idx, y in enumerate(rope_y):
            self.canvas.create_rectangle(ARENA[0] - 6, y, ARENA[2] + 6, y + 4, fill=ROPE_2 if idx % 2 else ROPE_1, outline="")

        # corner posts
        corners = [(ARENA[0], ARENA[1]), (ARENA[2] - 8, ARENA[1]), (ARENA[0], ARENA[3] - 8), (ARENA[2] - 8, ARENA[3] - 8)]
        for x, y in corners:
            self.canvas.create_rectangle(x, y, x + 8, y + 8, fill=POST, outline="")

        # center mark
        self.canvas.create_line((ARENA[0] + ARENA[2]) / 2 - 24, (ARENA[1] + ARENA[3]) / 2, (ARENA[0] + ARENA[2]) / 2 + 24, (ARENA[1] + ARENA[3]) / 2, fill="#4a5e81", width=3)
        self.canvas.create_line((ARENA[0] + ARENA[2]) / 2, (ARENA[1] + ARENA[3]) / 2 - 24, (ARENA[0] + ARENA[2]) / 2, (ARENA[1] + ARENA[3]) / 2 + 24, fill="#4a5e81", width=3)

        # mat pixel texture
        for y in range(ARENA[1] + 10, ARENA[3] - 8, 10):
            for x in range(ARENA[0] + 10, ARENA[2] - 8, 12):
                self.canvas.create_rectangle(x, y, x + 2, y + 2, fill="#314361", outline="")

    def draw_fighter(self, f):
        # Shadow
        shadow_w = 20 + min(10, abs(f.vx) * 0.06)
        self.canvas.create_oval(f.x - shadow_w / 2, f.y + 14, f.x + shadow_w / 2, f.y + 20, fill="#000000", outline="", stipple="gray50")

        if f.name == "Enemy":
            facing = -1 if f.x > self.player.x else 1
        else:
            facing = 1 if f.x < self.enemy.x else -1
        f.facing = facing

        duck_shift_x = -self.sc(10) if f.duck_side == 'left' else self.sc(10) if f.duck_side == 'right' else 0
        duck_drop = self.sc(7) if f.duck_side else 0
        bob = math.sin(f.walk_phase * 0.9) * 1.0
        if f.action == 'hit':
            bob += self.sc(2)
        if f.action == 'dodge':
            bob -= self.sc(4)
        y = f.y + duck_drop + bob

        # Palette / flash
        body = f.color if f.flash <= 0 else GOLD
        dark = f.color_dark
        skin = SKIN if f.flash <= 0 else WHITE
        outline = OUTLINE
        pose = self.action_pose(f)
        hurtboxes = self.fighter_hurtboxes(f)
        attackboxes = self.fighter_attackboxes(f)

        # Pixel-art style body blocks
        base_x = int(f.x + duck_shift_x)
        base_y = int(y)
        if f.action == 'hit':
            base_x += -self.sc(2) if f.facing == 1 else self.sc(2)
        if f.hurt_timer > 0:
            base_x += f.hurt_dir * self.sc(2)
        base_x += int(pose["x"] * (1 if f.facing == 1 else -1))
        base_y += pose["y"]

        # legs
        leg_shift = self.sc(5) if f.action == 'guard' else self.sc(7) if f.duck_side else 0
        if f.action in ('jab', 'cross', 'left_body', 'right_body', 'left_hook', 'right_hook', 'left_uppercut', 'right_uppercut'):
            leg_shift += self.sc(2)
        step = math.sin(f.walk_phase) * (self.sc(2) if f.action == 'move' else 0)
        step_offset = 1 if step > 0 else 0
        duck_left = f.duck_side == 'left'
        duck_right = f.duck_side == 'right'
        left_leg_y = base_y + self.sc(2) + leg_shift + step_offset + (self.sc(1) if duck_left else 0)
        right_leg_y = base_y + self.sc(2) + leg_shift + (1 if step < 0 else 0) + (self.sc(1) if duck_right else 0)
        left_leg_x = base_x - self.sc(9) + (1 if step < 0 else 0) + (self.sc(1) if duck_right else -self.sc(1) if duck_left else 0)
        right_leg_x = base_x + self.sc(1) + (1 if step > 0 else 0) + (self.sc(3) if duck_right else 0)
        self.canvas.create_rectangle(left_leg_x, left_leg_y, left_leg_x + self.sc(7), left_leg_y + self.sc(20), fill=dark, outline=outline)
        self.canvas.create_rectangle(right_leg_x, right_leg_y, right_leg_x + self.sc(7), right_leg_y + self.sc(20), fill=dark, outline=outline)
        self.canvas.create_rectangle(left_leg_x + 1, left_leg_y + 1, left_leg_x + self.sc(6), left_leg_y + self.sc(19), fill=body, outline=outline)
        self.canvas.create_rectangle(right_leg_x + 1, right_leg_y + 1, right_leg_x + self.sc(6), right_leg_y + self.sc(19), fill=body, outline=outline)

        # torso
        torso_y = base_y - self.sc(11) + pose["torso"] + (-self.sc(2) if f.action == 'dodge' else 0) + pose["duck"] + (1 if f.hurt_timer > 0 else 0)
        torso_x = base_x - self.sc(11) if f.facing == 1 else base_x - self.sc(7)
        if f.action == 'hit':
            torso_x += -self.sc(2) if f.facing == 1 else self.sc(2)
        torso_x += int(f.lean * self.sc(4))
        if f.action in ('jab', 'cross', 'left_body', 'right_body', 'left_hook', 'right_hook', 'left_uppercut', 'right_uppercut'):
            torso_x += pose["reach"]
        self.canvas.create_rectangle(torso_x - 1, torso_y - 1, torso_x + self.sc(17), torso_y + self.sc(17), fill=outline, outline="")
        self.canvas.create_rectangle(torso_x, torso_y, torso_x + self.sc(15), torso_y + self.sc(15), fill=body, outline="")
        self.canvas.create_rectangle(torso_x + self.sc(3), torso_y + self.sc(3), torso_x + self.sc(11), torso_y + self.sc(6), fill=dark, outline="")
        self.canvas.create_rectangle(torso_x + self.sc(4), torso_y + self.sc(9), torso_x + self.sc(10), torso_y + self.sc(11), fill=dark, outline="")

        # head
        head_x = base_x - self.sc(11) if f.facing == -1 else base_x - self.sc(2)
        head_y = torso_y - self.sc(13) + pose["head"] + (self.sc(2) if f.duck_side else 0) + (1 if f.hurt_timer > 0 else 0)
        self.canvas.create_rectangle(head_x - 1, head_y - 1, head_x + self.sc(13), head_y + self.sc(13), fill=outline, outline="")
        self.canvas.create_rectangle(head_x, head_y, head_x + self.sc(11), head_y + self.sc(11), fill=skin, outline="")
        self.canvas.create_rectangle(head_x + self.sc(2), head_y + self.sc(3), head_x + self.sc(4), head_y + self.sc(5), fill=outline, outline="")
        self.canvas.create_rectangle(head_x + self.sc(7), head_y + self.sc(3), head_x + self.sc(9), head_y + self.sc(5), fill=outline, outline="")
        self.canvas.create_rectangle(head_x + self.sc(3), head_y + self.sc(8), head_x + self.sc(8), head_y + self.sc(9), fill=outline, outline="")

        # gloves / arms
        phase = self.action_phase(f)
        forward_dir = 1 if f.facing == 1 else -1
        if f.duck_side and f.action not in ATTACK_ACTIONS and f.action not in ('guard', 'dodge', 'hit'):
            self.draw_arm(f, base_x, torso_y + self.sc(8), forward_dir, extended=False, color=dark, rear=False, swing=-self.sc(1))
            self.draw_arm(f, base_x, torso_y + self.sc(5), forward_dir, extended=False, color=dark, upper=True, rear=True, swing=-self.sc(2))
        elif f.action == 'jab':
            lead_ext = phase >= 0.28
            lead_up = phase < 0.22
            rear_up = phase < 0.55
            self.draw_arm(f, base_x, torso_y + (self.sc(5) if lead_up else self.sc(6)), forward_dir, extended=lead_ext, color=f.color, rear=False)
            self.draw_arm(f, base_x, torso_y + self.sc(7), forward_dir, extended=False, color=dark, upper=rear_up, rear=True)
        elif f.action == 'cross':
            lead_guard = phase < 0.40
            rear_ext = phase >= 0.30
            self.draw_arm(f, base_x, torso_y + self.sc(6), forward_dir, extended=False, color=dark, upper=lead_guard, rear=False)
            self.draw_arm(f, base_x, torso_y + (self.sc(6) if phase < 0.24 else self.sc(5)), forward_dir, extended=rear_ext, color=f.color, rear=True, swing=self.sc(2))
        elif f.action in ('left_hook', 'right_hook'):
            hook_h = phase < 0.25
            hook_ext = phase >= 0.34
            hook_rear = f.action == 'right_hook'
            hook_base_y = torso_y + (self.sc(2) if f.action == 'left_hook' else self.sc(3))
            self.draw_arm(f, base_x, hook_base_y, forward_dir, extended=hook_ext, color=f.color, upper=hook_h, rear=hook_rear, swing=self.sc(3 if f.action == 'left_hook' else 4))
            self.draw_arm(f, base_x, torso_y + self.sc(7), forward_dir, extended=False, color=dark, upper=False, rear=not hook_rear)
        elif f.action in ('left_body', 'right_body'):
            body_ext = phase >= 0.28
            body_rear = f.action == 'right_body'
            body_base_y = torso_y + (self.sc(7) if f.action == 'left_body' else self.sc(7))
            self.draw_arm(f, base_x, body_base_y, forward_dir, extended=body_ext, color=f.color, rear=body_rear, swing=self.sc(1 if f.action == 'left_body' else 1))
            self.draw_arm(f, base_x, torso_y + self.sc(6), forward_dir, extended=False, color=dark, upper=True, rear=not body_rear)
        elif f.action in ('left_uppercut', 'right_uppercut'):
            upper_ext = phase >= 0.32
            upper_rear = f.action == 'right_uppercut'
            self.draw_arm(f, base_x, torso_y + self.sc(2), forward_dir, extended=upper_ext, color=f.color, upper=True, rear=upper_rear, swing=self.sc(2))
            self.draw_arm(f, base_x, torso_y + self.sc(6), forward_dir, extended=False, color=dark, upper=False, rear=not upper_rear)
        elif f.action == 'guard':
            self.draw_arm(f, base_x, torso_y + self.sc(1), forward_dir, extended=False, color=dark, upper=True, rear=False)
            self.draw_arm(f, base_x, torso_y + self.sc(2), forward_dir, extended=False, color=dark, upper=True, rear=True)
        elif f.action == 'dodge':
            self.draw_arm(f, base_x, torso_y + self.sc(6), forward_dir, extended=False, color=dark, rear=False, swing=-self.sc(2))
            self.draw_arm(f, base_x, torso_y + self.sc(4), forward_dir, extended=False, color=dark, upper=True, rear=True, swing=-self.sc(2))
        else:
            self.draw_arm(f, base_x, torso_y + self.sc(5), forward_dir, extended=False, color=dark, rear=False)
            self.draw_arm(f, base_x, torso_y + self.sc(6), forward_dir, extended=False, color=dark, rear=True)

        if f.flash > 0:
            self.canvas.create_rectangle(base_x - 1, head_y - 1, base_x + 12, head_y + 12, outline="#ffffff", width=1)

        # Hitbox overlays are intentionally hidden during normal play for visual clarity.

        # Attack trails removed to avoid hitbox-like afterimage artifacts.

    def draw_arm(self, f, base_x, base_y, dir_sign, extended=False, color=BLUE, upper=False, rear=False, swing=0):
        outline = OUTLINE
        forward = dir_sign
        anchor_sign = -forward if rear else forward
        start_x = base_x + anchor_sign * self.sc(8) + swing
        start_y = base_y + (-self.sc(2) if upper else 0)
        reach = self.sc(17) if extended else self.sc(10)
        elbow_x = start_x + forward * (self.sc(8) if extended else self.sc(5))
        glove_x = start_x + forward * reach
        glove_y = start_y + (-self.sc(5) if upper else 0)
        if rear and extended:
            glove_x += forward * self.sc(2)

        seg_top = start_y + 1
        seg_bottom = seg_top + self.sc(3)
        seg0_l, seg0_r = sorted((start_x + 1, elbow_x + 1))
        seg1_l, seg1_r = sorted((elbow_x + 1, glove_x + 1))
        self.canvas.create_rectangle(seg0_l - 1, seg_top - 1, seg0_r + 2, seg_bottom + 1, fill=outline, outline="")
        self.canvas.create_rectangle(seg1_l - 1, seg_top - 1, seg1_r + 2, seg_bottom + 1, fill=outline, outline="")
        self.canvas.create_rectangle(seg0_l, seg_top, seg0_r + 1, seg_bottom, fill=color, outline="")
        self.canvas.create_rectangle(seg1_l, seg_top, seg1_r + 1, seg_bottom, fill=color, outline="")

        self.canvas.create_rectangle(start_x - 1, start_y - 1, start_x + 4, start_y + 4, fill=outline, outline="")
        self.canvas.create_rectangle(elbow_x - 1, start_y - 1, elbow_x + 4, start_y + 4, fill=outline, outline="")
        self.canvas.create_rectangle(glove_x - 3, glove_y - 3, glove_x + 6, glove_y + 6, fill=outline, outline="")
        self.canvas.create_rectangle(start_x, start_y, start_x + 3, start_y + 3, fill=color, outline="")
        self.canvas.create_rectangle(elbow_x, start_y, elbow_x + 3, start_y + 3, fill=color, outline="")
        self.canvas.create_rectangle(glove_x - 2, glove_y - 2, glove_x + 5, glove_y + 5, fill=color, outline="")

    def mix(self, c1, c2, t):
        def hex_to_rgb(h):
            h = h.lstrip('#')
            return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
        def rgb_to_hex(rgb):
            return '#%02x%02x%02x' % rgb
        a = hex_to_rgb(c1)
        b = hex_to_rgb(c2)
        rgb = tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))
        return rgb_to_hex(rgb)

    def draw_hud(self):
        self.canvas.delete("hud")
        # screen-space overlays on canvas for a finished look
        if self.overlay_visible:
            x0, y0, x1, y1 = 220, 50, 740, 165
            self.canvas.create_rectangle(x0, y0, x1, y1, fill="#0a1020", outline="#5477a8", width=2, tags="hud")
            self.canvas.create_text(480, 78, text=self.overlay_title, fill=WHITE, font=("Helvetica", 26, "bold"), tags="hud")
            self.canvas.create_text(480, 118, text=self.overlay_text, fill=GRAY, font=("Helvetica", 12), width=470, tags="hud")

        self.canvas.create_rectangle(352, 12, 608, 58, fill="#09111f", outline="#2a3b5c", tags="hud")
        self.canvas.create_text(480, 28, text=f"P {self.score_player}  -  {self.score_enemy} E", fill=WHITE, font=("Helvetica", 15, "bold"), tags="hud")
        self.canvas.create_text(480, 46, text=f"Time {int(self.round_time):02d}s", fill=GOLD, font=("Helvetica", 11, "bold"), tags="hud")

        if self.dodge_hud_timer > 0:
            pulse = 0.35 + 0.65 * (self.dodge_hud_timer / 0.36)
            self.canvas.create_text(480, 72, text=self.dodge_hud_text, fill=self.mix("#6fe8ff", WHITE, pulse * 0.5), font=("Helvetica", 12, "bold"), tags="hud")

        # quick status chip
        status_text = self.action_label(self.player.action)
        if self.player.duck_side:
            status_text = f"Duck {self.player.duck_side.title()}"
        elif self.player.guard:
            status_text = "Guard"
        self.canvas.create_rectangle(14, 12, 332, 58, fill="#09111f", outline="#2a3b5c", tags="hud")
        self.canvas.create_text(26, 24, anchor="w", text=f"Round {self.round}/{self.max_rounds}", fill=WHITE, font=("Helvetica", 12, "bold"), tags="hud")
        self.canvas.create_text(26, 40, anchor="w", text=f"Action: {status_text}   Combo: {self.player.combo}", fill=GRAY, font=("Helvetica", 10), tags="hud")

        # health / stamina bars
        self.draw_bar(14, 66, 300, 11, self.player.hp / self.player.max_hp, GREEN, "HP")
        self.draw_bar(14, 82, 300, 9, self.player.stamina / self.player.max_stamina, BLUE, "ST")
        self.draw_bar(14, 100, 300, 10, self.enemy.hp / self.enemy.max_hp, RED, f"ENEMY HP {self.enemy.hp}/{self.enemy.max_hp}")
        self.draw_bar(14, 114, 300, 7, self.enemy.stamina / self.enemy.max_stamina, GOLD, "EN ST")
        if self.enemy.flash > 0 or self.enemy.hitstun > 0:
            self.canvas.create_text(320, 105, anchor="w", text="HIT", fill=GOLD, font=("Helvetica", 10, "bold"), tags="hud")
        self.canvas.create_text(24, 136, anchor="w", text=f"Enemy AI {self.enemy.ai_aggression:.2f}x  Learn {self.enemy.ai_experience:.1f}", fill=GRAY, font=("Helvetica", 9, "bold"), tags="hud")
        self.canvas.create_text(24, 150, anchor="w", text=f"Reads: {self.dominant_player_pattern().replace('_', ' ').title()}", fill=GRAY, font=("Helvetica", 9), tags="hud")

        # bottom log strip
        self.canvas.create_rectangle(14, 468, 946, 528, fill="#08111d", outline="#253654", tags="hud")
        self.canvas.create_text(26, 488, anchor="w", text=self.log[0], fill=WHITE, font=("Helvetica", 12, "bold"), tags="hud")
        self.canvas.create_text(26, 512, anchor="w", text=" | ".join(self.log[1:]), fill=GRAY, font=("Helvetica", 10), tags="hud")
        self.canvas.create_text(930, 24, anchor="e", text=f"Key {self.key_debug or '-'}", fill=GRAY, font=("Helvetica", 9, "bold"), tags="hud")
        self.canvas.create_text(930, 40, anchor="e", text=f"Hitbox {'ON' if self.show_hitboxes else 'OFF'}", fill=GRAY, font=("Helvetica", 9), tags="hud")

    def draw_bar(self, x, y, width, height, ratio, color, label):
        ratio = clamp(ratio, 0.0, 1.0)
        self.canvas.create_rectangle(x, y, x + width, y + height, fill="#0d1727", outline="#24344f", tags="hud")
        self.canvas.create_rectangle(x + 1, y + 1, x + 1 + int((width - 2) * ratio), y + height - 1, fill=color, outline="", tags="hud")
        self.canvas.create_text(x + width - 6, y + height / 2, text=label, fill=WHITE, font=("Helvetica", 8, "bold"), anchor="e", tags="hud")

    def tick(self):
        dt = 0.016
        if self.state == "fight":
            self.update(dt)
        self.draw_background()
        self.draw_fighter(self.player)
        self.draw_fighter(self.enemy)
        self.draw_hud()
        self.root.after(16, self.tick)

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    PixelBoxingApp().run()
