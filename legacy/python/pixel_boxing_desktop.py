import math
import random
import tkinter as tk
from dataclasses import dataclass

WIDTH = 960
HEIGHT = 540
ARENA = (90, 88, 870, 426)
ROUND_LIMIT = 3
TARGET_FPS = 60

BG_TOP = "#08152a"
BG_BOTTOM = "#03060d"
RING_1 = "#263553"
RING_2 = "#31486d"
ROPE_A = "#b36a2e"
ROPE_B = "#ffd26b"
POST = "#f4d36c"
WHITE = "#eef6ff"
MUTED = "#9db2d1"
GREEN = "#73ff9b"
RED = "#ff5f7a"
BLUE = "#63d2ff"
BLUE_DARK = "#2f8ed6"
RED_DARK = "#d94467"
SKIN = "#f1c6a3"
OUTLINE = "#0a0c13"
YELLOW = "#ffd65a"


def clamp(value, low, high):
    return max(low, min(high, value))


def distance(ax, ay, bx, by):
    return math.hypot(ax - bx, ay - by)


@dataclass
class Fighter:
    name: str
    x: float
    y: float
    body: str
    body_dark: str
    hp: int = 100
    stamina: float = 100.0
    max_hp: int = 100
    max_stamina: int = 100
    facing: int = 1
    action: str = "idle"
    action_time: float = 0.0
    action_duration: float = 0.0
    active_a: float = 0.0
    active_b: float = 0.0
    damage: int = 0
    reach: float = 18.0
    hitstun: float = 0.0
    invuln: float = 0.0
    guard_held: bool = False
    dodge_timer: float = 0.0
    ai_timer: float = 0.0
    flash: float = 0.0
    combo: int = 0
    vx: float = 0.0
    vy: float = 0.0
    action_done: bool = False


class PixelBoxingDesktop:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Pixel Boxing")
        self.root.configure(bg="#05080d")
        self.root.minsize(960, 620)

        self.canvas = tk.Canvas(self.root, width=WIDTH, height=HEIGHT, bg="#05080d", highlightthickness=0)
        self.canvas.pack(fill="x")
        self.canvas.focus_set()
        self.canvas.configure(takefocus=1)

        self.bottom = tk.Frame(self.root, bg="#05080d")
        self.bottom.pack(fill="x", padx=12, pady=(0, 12))

        self.title_label = tk.Label(self.bottom, text="Pixel Boxing", fg=WHITE, bg="#05080d", font=("Helvetica", 15, "bold"))
        self.title_label.pack(anchor="w")
        self.status_label = tk.Label(self.bottom, text="Click the ring and press any movement key.", fg=MUTED, bg="#05080d", font=("Helvetica", 10))
        self.status_label.pack(anchor="w", pady=(2, 0))
        self.controls_label = tk.Label(
            self.bottom,
            text="Move: WASD / Arrow Keys | Jab: J | Cross: K | Hook: L | Guard: Hold V | Dodge: Space | Restart: R",
            fg=MUTED,
            bg="#05080d",
            font=("Helvetica", 10),
        )
        self.controls_label.pack(anchor="w", pady=(2, 0))

        self.pressed = set()
        self.logs = ["Ready."]
        self.round = 1
        self.max_rounds = ROUND_LIMIT
        self.state = "intro"
        self.overlay_visible = True
        self.overlay_title = "Press Start"
        self.overlay_text = "Click the ring and press any movement key to begin. Orbit the opponent, land clean shots, and chase the knockout."
        self.shake = 0.0
        self.flash = 0.0
        self.last_tick = None

        self.player = self.make_fighter("Player", 210, 350, BLUE, BLUE_DARK)
        self.enemy = self.make_fighter("Enemy", 742, 350, RED, RED_DARK)
        self.reset_round(full=True)

        self.bind_events()
        self.root.after(16, self.loop)

    def make_fighter(self, name, x, y, body, body_dark):
        return Fighter(name=name, x=x, y=y, body=body, body_dark=body_dark)

    def bind_events(self):
        self.root.bind("<KeyPress>", self.on_key_down)
        self.root.bind("<KeyRelease>", self.on_key_up)
        self.canvas.bind("<Button-1>", lambda e: self.canvas.focus_set())
        self.root.bind("<Button-1>", lambda e: self.canvas.focus_set())

    def reset_round(self, full=False):
        if full:
            self.round = 1
            self.logs = ["Ready."]
            self.state = "intro"
            self.overlay_visible = True
            self.overlay_title = "Press Start"
            self.overlay_text = "Click the ring and press any movement key to begin. Orbit the opponent, land clean shots, and chase the knockout."
        self.player = self.make_fighter("Player", 210, 350, BLUE, BLUE_DARK)
        self.enemy = self.make_fighter("Enemy", 742, 350, RED, RED_DARK)
        self.player.hp = self.player.max_hp = 100
        self.enemy.hp = self.enemy.max_hp = 100
        self.player.stamina = self.player.max_stamina = 100
        self.enemy.stamina = self.enemy.max_stamina = 100
        self.player.ai_timer = 0.0
        self.enemy.ai_timer = 0.25
        self.player.guard_held = False
        self.enemy.guard_held = False
        self.player.combo = 0
        self.enemy.combo = 0
        self.player.action = "idle"
        self.enemy.action = "idle"
        self.player.action_time = 0.0
        self.enemy.action_time = 0.0
        self.player.hitstun = self.enemy.hitstun = 0.0
        self.player.invuln = self.enemy.invuln = 0.0

    def log(self, text):
        self.logs.insert(0, text)
        self.logs = self.logs[:4]
        self.status_label.config(text="   ".join(self.logs))

    def on_key_down(self, event):
        key = event.keysym.lower()
        self.pressed.add(key)

        if key == "r":
            self.reset_round(full=True)
            self.log("Restarted.")
            return

        if self.state == "intro":
            self.state = "fight"
            self.overlay_visible = False
            self.log("Bell.")

        if self.state != "fight":
            return

        if key == "j":
            self.start_action(self.player, "jab")
        elif key == "k":
            self.start_action(self.player, "cross")
        elif key == "l":
            self.start_action(self.player, "hook")
        elif key == "space":
            self.start_action(self.player, "dodge")

        if key == "v":
            self.player.guard_held = True
            if self.player.action_time <= 0 and self.player.hitstun <= 0:
                self.start_action(self.player, "guard")

    def on_key_up(self, event):
        key = event.keysym.lower()
        self.pressed.discard(key)
        if key == "v":
            self.player.guard_held = False
            if self.player.action == "guard" and self.player.action_time <= 0:
                self.finish_action(self.player)

    def start_action(self, fighter, name):
        if fighter.hitstun > 0 or fighter.action_time > 0:
            return

        costs = {"jab": 7, "cross": 10, "hook": 12, "guard": 4, "dodge": 6}
        if name != "guard" and fighter.stamina < costs[name]:
            return

        fighter.stamina = clamp(fighter.stamina - costs[name], 0, fighter.max_stamina)
        fighter.action = name
        fighter.action_time = 0.0
        fighter.action_done = False
        fighter.flash = 0.0
        if name == "jab":
            fighter.action_duration = 0.28
            fighter.active_a = 0.08
            fighter.active_b = 0.16
            fighter.damage = 8
            fighter.reach = 24
        elif name == "cross":
            fighter.action_duration = 0.36
            fighter.active_a = 0.12
            fighter.active_b = 0.22
            fighter.damage = 11
            fighter.reach = 28
        elif name == "hook":
            fighter.action_duration = 0.42
            fighter.active_a = 0.14
            fighter.active_b = 0.28
            fighter.damage = 14
            fighter.reach = 20
        elif name == "guard":
            fighter.action_duration = 999.0
            fighter.active_a = 0.0
            fighter.active_b = 0.0
            fighter.damage = 0
            fighter.reach = 0
            fighter.guard_held = True
        elif name == "dodge":
            fighter.action_duration = 0.18
            fighter.active_a = 0.0
            fighter.active_b = 0.0
            fighter.damage = 0
            fighter.reach = 0
            fighter.invuln = 0.18
            fighter.dodge_timer = 0.18

    def finish_action(self, fighter):
        fighter.action = "idle"
        fighter.action_time = 0.0
        fighter.action_duration = 0.0
        fighter.active_a = fighter.active_b = 0.0
        fighter.damage = 0
        fighter.reach = 18.0
        fighter.action_done = False
        fighter.guard_held = False

    def orbit_player(self, dir_sign):
        if self.player.hitstun > 0 or self.player.action_time > 0:
            return
        dx = self.player.x - self.enemy.x
        dy = self.player.y - self.enemy.y
        angle = math.atan2(dy, dx) + dir_sign * 0.24
        radius = clamp(distance(self.player.x, self.player.y, self.enemy.x, self.enemy.y), 62, 138)
        self.player.x = clamp(self.enemy.x + math.cos(angle) * radius, ARENA[0] + 30, ARENA[2] - 30)
        self.player.y = clamp(self.enemy.y + math.sin(angle) * radius, ARENA[1] + 24, ARENA[3] - 18)
        self.player.action = "move"

    def move_player(self, dx, dy):
        if self.player.hitstun > 0 or self.player.action_time > 0:
            return
        self.player.x = clamp(self.player.x + dx * 10, ARENA[0] + 30, ARENA[2] - 30)
        self.player.y = clamp(self.player.y + dy * 10, ARENA[1] + 24, ARENA[3] - 18)
        self.player.action = "move"

    def enemy_ai(self, dt):
        e, p = self.enemy, self.player
        if e.hp <= 0 or self.state != "fight":
            return
        if e.ai_timer > 0:
            e.ai_timer -= dt
            return
        e.ai_timer = random.uniform(0.18, 0.42)

        d = distance(e.x, e.y, p.x, p.y)
        if e.hp < 30 and random.random() < 0.35:
            self.start_action(e, "guard")
            return
        if d > 112:
            self.move_enemy(-1, 0.2)
            return
        if d > 70:
            if random.random() < 0.45:
                self.start_action(e, "jab")
            else:
                self.move_enemy(-1, random.uniform(-0.15, 0.15))
            return
        if d < 44 and random.random() < 0.25:
            self.start_action(e, "dodge")
            return
        roll = random.random()
        if roll < 0.48:
            self.start_action(e, "jab")
        elif roll < 0.80:
            self.start_action(e, "cross")
        else:
            self.start_action(e, "hook")

    def move_enemy(self, dir_x, dir_y):
        e, p = self.enemy, self.player
        dx = p.x - e.x
        dy = p.y - e.y
        angle = math.atan2(dy, dx) + (0.14 if self.round % 2 == 0 else -0.12)
        if dir_x < 0:
            angle += 0.18
        elif dir_x > 0:
            angle -= 0.18
        radius = clamp(distance(e.x, e.y, p.x, p.y), 58, 118)
        e.x = clamp(p.x - math.cos(angle) * radius, ARENA[0] + 30, ARENA[2] - 30)
        e.y = clamp(p.y - math.sin(angle) * radius, ARENA[1] + 24, ARENA[3] - 18)
        e.action = "move"

    def apply_hit(self, attacker, defender, action_name):
        if defender.invuln > 0:
            return
        dmg = attacker.damage
        note = "hit"
        if defender.guard_held:
            dmg = max(1, int(dmg * 0.35))
            note = "blocked"
        defender.hp = clamp(defender.hp - dmg, 0, defender.max_hp)
        defender.hitstun = 0.12
        defender.invuln = 0.10
        defender.flash = 0.14
        attacker.combo += 1
        self.shake = max(self.shake, dmg * 0.45)
        self.flash = 0.08
        self.log(f"{attacker.name} {action_name} {note} {dmg}")
        self.knockback(attacker, defender, 9 if action_name == "jab" else 11 if action_name == "cross" else 13)

    def knockback(self, attacker, defender, force):
        direction = 1 if defender.x > attacker.x else -1
        defender.x = clamp(defender.x + direction * force, ARENA[0] + 30, ARENA[2] - 30)
        defender.y = clamp(defender.y + (4 if defender.y > attacker.y else -4), ARENA[1] + 24, ARENA[3] - 18)

    def update_fighter(self, fighter, other, dt):
        fighter.stamina = clamp(fighter.stamina + dt * 8, 0, fighter.max_stamina)
        fighter.invuln = max(0.0, fighter.invuln - dt)
        fighter.hitstun = max(0.0, fighter.hitstun - dt)
        fighter.flash = max(0.0, fighter.flash - dt)
        fighter.dodge_timer = max(0.0, fighter.dodge_timer - dt)

        if fighter.action == "guard":
            fighter.stamina = clamp(fighter.stamina - dt * 14, 0, fighter.max_stamina)
            fighter.facing = 1 if fighter.x < other.x else -1
            return

        if fighter.action_time > 0:
            fighter.action_time += dt
            if not fighter.action_done and fighter.active_a <= fighter.action_time <= fighter.active_b:
                if self.in_range(fighter, other):
                    self.apply_hit(fighter, other, fighter.action)
                    fighter.action_done = True
            if fighter.action_time >= fighter.action_duration:
                self.finish_action(fighter)
            return

        if fighter.hitstun > 0:
            fighter.vx *= 0.90
            fighter.vy *= 0.90
            fighter.facing = 1 if fighter.x < other.x else -1
            return

        # light footwork/drift for an alive ring feel
        if fighter.name == "Enemy" and self.state == "fight":
            dx = other.x - fighter.x
            dy = other.y - fighter.y
            target_radius = 78 if fighter.hp > 40 else 92
            angle = math.atan2(dy, dx) + (0.05 if self.round % 2 == 0 else -0.05)
            fighter.x = clamp(other.x - math.cos(angle) * target_radius, ARENA[0] + 30, ARENA[2] - 30)
            fighter.y = clamp(other.y - math.sin(angle) * target_radius, ARENA[1] + 24, ARENA[3] - 18)

        fighter.facing = 1 if fighter.x < other.x else -1

        if abs(fighter.vx) > 0.5 or abs(fighter.vy) > 0.5:
            fighter.x += fighter.vx * dt
            fighter.y += fighter.vy * dt
            fighter.vx *= 0.84
            fighter.vy *= 0.84

        fighter.x = clamp(fighter.x, ARENA[0] + 30, ARENA[2] - 30)
        fighter.y = clamp(fighter.y, ARENA[1] + 24, ARENA[3] - 18)

    def in_range(self, attacker, defender):
        dx = defender.x - attacker.x
        dy = abs(defender.y - attacker.y)
        forward = dx * attacker.facing
        return forward >= 0 and forward <= attacker.reach and dy <= 18

    def update(self, dt):
        if self.state == "intro":
            return

        # movement
        if self.player.hitstun <= 0 and self.player.action_time <= 0 and self.state == "fight":
            mx = (1 if "d" in self.pressed or "Right" in self.pressed else 0) - (1 if "a" in self.pressed or "Left" in self.pressed else 0)
            my = (1 if "s" in self.pressed or "Down" in self.pressed else 0) - (1 if "w" in self.pressed or "Up" in self.pressed else 0)
            if mx or my:
                mag = max(1.0, math.hypot(mx, my))
                self.player.x = clamp(self.player.x + (mx / mag) * 80 * dt, ARENA[0] + 30, ARENA[2] - 30)
                self.player.y = clamp(self.player.y + (my / mag) * 80 * dt, ARENA[1] + 24, ARENA[3] - 18)
                self.player.action = "move"

        # orbit controls via arrow keys as well
        if self.player.hitstun <= 0 and self.player.action_time <= 0:
            if "left" in self.pressed:
                self.orbit_player(-1)
            elif "right" in self.pressed:
                self.orbit_player(1)
            elif "up" in self.pressed:
                self.move_player(0, -1)
            elif "down" in self.pressed:
                self.move_player(0, 1)

        self.player.guard_held = "v" in self.pressed
        if self.player.guard_held and self.player.action_time <= 0 and self.player.hitstun <= 0:
            if self.player.action != "guard":
                self.start_action(self.player, "guard")
        elif not self.player.guard_held and self.player.action == "guard" and self.player.action_time <= 0:
            self.finish_action(self.player)

        # player attack key repeat handled by keydown
        self.enemy_ai(dt)
        self.update_fighter(self.player, self.enemy, dt)
        self.update_fighter(self.enemy, self.player, dt)

        if self.player.hp <= 0 and self.state != "ko":
            self.state = "ko"
            self.overlay_visible = True
            self.overlay_title = "KO"
            self.overlay_text = "You got knocked out. Press R to restart the match."
            self.log("You were knocked out.")
        elif self.enemy.hp <= 0 and self.state != "ko":
            self.log(f"Round {self.round} KO.")
            if self.round >= self.max_rounds:
                self.state = "ko"
                self.overlay_visible = True
                self.overlay_title = "Victory"
                self.overlay_text = "You won the match. Press R to play again."
            else:
                self.round += 1
                self.overlay_visible = True
                self.overlay_title = "Round KO"
                self.overlay_text = f"Round {self.round} loading..."
                self.state = "between"
                self.root.after(900, self.advance_round)

        self.flash = max(0.0, self.flash - dt * 2.4)
        self.shake = max(0.0, self.shake - dt * 20)

    def advance_round(self):
        if self.state == "ko":
            return
        self.reset_round(full=False)
        self.state = "fight"
        self.overlay_visible = False
        self.log(f"Round {self.round} bell.")

    def draw_background(self):
        self.canvas.delete("all")
        for y in range(0, HEIGHT, 6):
            t = y / HEIGHT
            c = self.mix(BG_TOP, BG_BOTTOM, t)
            self.canvas.create_rectangle(0, y, WIDTH, y + 6, outline=c, fill=c)

        for i in range(18):
            self.canvas.create_rectangle(18 + i * 52, 28 + (i % 2) * 4, 34 + i * 52, 60 + (i % 3) * 2, fill="#101a30", outline="")

        self.canvas.create_rectangle(ARENA[0] - 18, ARENA[1] - 18, ARENA[2] + 18, ARENA[3] + 18, outline="#0f1730", fill="#17233b", width=2)
        self.canvas.create_rectangle(ARENA[0], ARENA[1], ARENA[2], ARENA[3], outline="#31486d", fill=RING_1, width=2)
        self.canvas.create_rectangle(ARENA[0] + 2, ARENA[1] + 2, ARENA[2] - 2, ARENA[3] - 2, outline="#2f4770", fill=RING_2, width=2)

        rope_y = [ARENA[1] + 14, ARENA[1] + 38, ARENA[1] + 90, ARENA[1] + 114]
        for idx, y in enumerate(rope_y):
            self.canvas.create_rectangle(ARENA[0] - 6, y, ARENA[2] + 6, y + 4, fill=ROPE_B if idx % 2 else ROPE_A, outline="")

        for x, y in [(ARENA[0], ARENA[1]), (ARENA[2] - 8, ARENA[1]), (ARENA[0], ARENA[3] - 8), (ARENA[2] - 8, ARENA[3] - 8)]:
            self.canvas.create_rectangle(x, y, x + 8, y + 8, fill=POST, outline="")

        cx = (ARENA[0] + ARENA[2]) / 2
        cy = (ARENA[1] + ARENA[3]) / 2
        self.canvas.create_line(cx - 28, cy, cx + 28, cy, fill="#4a5e81", width=3)
        self.canvas.create_line(cx, cy - 28, cx, cy + 28, fill="#4a5e81", width=3)

        for y in range(ARENA[1] + 10, ARENA[3] - 8, 10):
            for x in range(ARENA[0] + 10, ARENA[2] - 8, 12):
                self.canvas.create_rectangle(x, y, x + 2, y + 2, fill="#314361", outline="")

    def draw_shadow(self, fighter):
        w = 20 + min(10, abs(fighter.vx) * 0.05)
        self.canvas.create_oval(fighter.x - w / 2, fighter.y + 14, fighter.x + w / 2, fighter.y + 20, fill="#000000", outline="", stipple="gray50")

    def draw_arm(self, base_x, base_y, dir_sign, glove_color, arm_color, upper=False, extend=False):
        outline = OUTLINE
        dx = 1 if dir_sign >= 0 else -1
        start_x = base_x + (6 if dx == 1 else -2)
        start_y = base_y + (-2 if upper else 0)
        elbow_x = start_x + dx * 3
        reach = 12 if extend else 6
        glove_x = start_x + dx * reach
        glove_y = start_y + (-4 if upper else 0)
        self.canvas.create_rectangle(start_x - 1, start_y - 1, start_x + 3, start_y + 3, fill=outline, outline="")
        self.canvas.create_rectangle(elbow_x - 1, start_y - 1, elbow_x + 3, start_y + 3, fill=outline, outline="")
        self.canvas.create_rectangle(glove_x - 2, glove_y - 2, glove_x + 4, glove_y + 4, fill=outline, outline="")
        self.canvas.create_rectangle(start_x, start_y, start_x + 2, start_y + 2, fill=arm_color, outline="")
        self.canvas.create_rectangle(elbow_x, start_y, elbow_x + 2, start_y + 2, fill=arm_color, outline="")
        self.canvas.create_rectangle(glove_x - 1, glove_y - 1, glove_x + 3, glove_y + 3, fill=glove_color, outline="")

    def draw_fighter(self, fighter):
        if fighter.name == "Player":
            opp = self.enemy
        else:
            opp = self.player
        fighter.facing = 1 if fighter.x < opp.x else -1

        self.draw_shadow(fighter)
        x = int(fighter.x)
        y = int(fighter.y)
        bob = -3 if fighter.action == "dodge" else 1 if fighter.action == "hit" else int(math.sin((self.round * 0.7) + x * 0.03) * 1.2)
        y += bob

        body = fighter.body if fighter.flash <= 0 else YELLOW
        dark = fighter.body_dark
        skin = SKIN if fighter.flash <= 0 else WHITE
        outline = OUTLINE

        if fighter.action == "hit":
            x += -2 if fighter.facing == 1 else 2

        # legs
        leg_shift = 3 if fighter.action == "guard" else 0
        self.canvas.create_rectangle(x - 8, y + 3 + leg_shift, x - 2, y + 20, fill=dark, outline=outline)
        self.canvas.create_rectangle(x + 2, y + 3 + leg_shift, x + 8, y + 20, fill=dark, outline=outline)
        self.canvas.create_rectangle(x - 7, y + 4 + leg_shift, x - 3, y + 19, fill=body, outline=outline)
        self.canvas.create_rectangle(x + 3, y + 4 + leg_shift, x + 7, y + 19, fill=body, outline=outline)

        # torso
        torso_x = x - 10 if fighter.facing == 1 else x - 6
        torso_y = y - 10 + (2 if fighter.action == "guard" else 0) + (-2 if fighter.action == "dodge" else 0)
        self.canvas.create_rectangle(torso_x - 1, torso_y - 1, torso_x + 16, torso_y + 16, fill=outline, outline="")
        self.canvas.create_rectangle(torso_x, torso_y, torso_x + 14, torso_y + 14, fill=body, outline="")
        self.canvas.create_rectangle(torso_x + 3, torso_y + 3, torso_x + 10, torso_y + 5, fill=dark, outline="")
        self.canvas.create_rectangle(torso_x + 4, torso_y + 8, torso_x + 9, torso_y + 10, fill=dark, outline="")

        # head
        head_x = x - 10 if fighter.facing == -1 else x - 2
        head_y = torso_y - 12 + (-1 if fighter.action == "guard" else 0)
        self.canvas.create_rectangle(head_x - 1, head_y - 1, head_x + 12, head_y + 12, fill=outline, outline="")
        self.canvas.create_rectangle(head_x, head_y, head_x + 10, head_y + 10, fill=skin, outline="")
        self.canvas.create_rectangle(head_x + 2, head_y + 3, head_x + 4, head_y + 5, fill=outline, outline="")
        self.canvas.create_rectangle(head_x + 6, head_y + 3, head_x + 8, head_y + 5, fill=outline, outline="")
        self.canvas.create_rectangle(head_x + 3, head_y + 7, head_x + 7, head_y + 8, fill=outline, outline="")

        # gloves / arms
        if fighter.action == "jab":
            self.draw_arm(torso_x, torso_y + 4, 1 if fighter.facing == 1 else -1, fighter.body, dark, extend=True)
            self.draw_arm(torso_x, torso_y + 6, -1 if fighter.facing == 1 else 1, fighter.body_dark, dark)
        elif fighter.action == "cross":
            self.draw_arm(torso_x, torso_y + 4, 1 if fighter.facing == 1 else -1, fighter.body_dark, dark)
            self.draw_arm(torso_x, torso_y + 6, -1 if fighter.facing == 1 else 1, fighter.body, dark, extend=True)
        elif fighter.action == "hook":
            self.draw_arm(torso_x, torso_y + 2, 1 if fighter.facing == 1 else -1, fighter.body, dark, upper=True, extend=True)
            self.draw_arm(torso_x, torso_y + 6, -1 if fighter.facing == 1 else 1, fighter.body_dark, dark)
        elif fighter.action == "guard":
            self.draw_arm(torso_x, torso_y + 2, 1 if fighter.facing == 1 else -1, fighter.body_dark, dark, upper=True)
            self.draw_arm(torso_x, torso_y + 3, -1 if fighter.facing == 1 else 1, fighter.body_dark, dark, upper=True)
        elif fighter.action == "dodge":
            self.draw_arm(torso_x, torso_y + 4, 1 if fighter.facing == 1 else -1, fighter.body_dark, dark)
            self.draw_arm(torso_x, torso_y + 5, -1 if fighter.facing == 1 else 1, fighter.body_dark, dark)
        elif fighter.action == "hit":
            self.draw_arm(torso_x, torso_y + 2, -1 if fighter.facing == 1 else 1, fighter.body_dark, dark, upper=True)
            self.draw_arm(torso_x, torso_y + 5, 1 if fighter.facing == 1 else -1, fighter.body_dark, dark)
        else:
            self.draw_arm(torso_x, torso_y + 4, 1 if fighter.facing == 1 else -1, fighter.body_dark, dark)
            self.draw_arm(torso_x, torso_y + 5, -1 if fighter.facing == 1 else 1, fighter.body_dark, dark)

        if fighter.flash > 0:
            self.canvas.create_rectangle(head_x - 1, head_y - 1, head_x + 12, head_y + 12, outline="#ffffff", width=1)

    def draw_hud(self):
        self.canvas.create_rectangle(12, 12, 280, 62, fill="#08111d", outline="#2b3e60")
        self.canvas.create_text(24, 24, anchor="w", text=f"Round {self.round}/{self.max_rounds}", fill=WHITE, font=("Helvetica", 12, "bold"))
        self.canvas.create_text(24, 40, anchor="w", text=f"Player {self.player.hp} / {self.player.max_hp}   Stamina {int(self.player.stamina)}", fill=MUTED, font=("Helvetica", 10))
        self.canvas.create_text(24, 54, anchor="w", text=f"Enemy {self.enemy.hp} / {self.enemy.max_hp}", fill=MUTED, font=("Helvetica", 10))

        self.canvas.create_rectangle(12, 464, 948, 528, fill="#08111d", outline="#2b3e60")
        self.canvas.create_text(24, 484, anchor="w", text=self.logs[0], fill=WHITE, font=("Helvetica", 12, "bold"))
        self.canvas.create_text(24, 508, anchor="w", text="   ".join(self.logs[1:]), fill=MUTED, font=("Helvetica", 10))

        if self.overlay_visible:
            self.canvas.create_rectangle(210, 56, 750, 168, fill="#0a1020", outline="#5f82b8", width=2)
            self.canvas.create_text(480, 82, text=self.overlay_title, fill=WHITE, font=("Helvetica", 26, "bold"))
            self.canvas.create_text(480, 126, text=self.overlay_text, fill=MUTED, font=("Helvetica", 12), width=500)

    def draw(self):
        self.canvas.delete("all")
        for y in range(0, HEIGHT, 6):
            t = y / HEIGHT
            self.canvas.create_rectangle(0, y, WIDTH, y + 6, outline=self.mix(BG_TOP, BG_BOTTOM, t), fill=self.mix(BG_TOP, BG_BOTTOM, t))

        for i in range(18):
            self.canvas.create_rectangle(18 + i * 52, 30 + (i % 2) * 4, 34 + i * 52, 58 + (i % 3) * 2, fill="#101a30", outline="")

        self.canvas.create_rectangle(ARENA[0] - 18, ARENA[1] - 18, ARENA[2] + 18, ARENA[3] + 18, outline="#0f1730", fill="#17233b", width=2)
        self.canvas.create_rectangle(ARENA[0], ARENA[1], ARENA[2], ARENA[3], outline="#31486d", fill=RING_1, width=2)
        self.canvas.create_rectangle(ARENA[0] + 2, ARENA[1] + 2, ARENA[2] - 2, ARENA[3] - 2, outline="#2f4770", fill=RING_2, width=2)

        ropes = [ARENA[1] + 14, ARENA[1] + 38, ARENA[1] + 90, ARENA[1] + 114]
        for i, y in enumerate(ropes):
            self.canvas.create_rectangle(ARENA[0] - 6, y, ARENA[2] + 6, y + 4, fill=ROPE_B if i % 2 else ROPE_A, outline="")

        for x, y in [(ARENA[0], ARENA[1]), (ARENA[2] - 8, ARENA[1]), (ARENA[0], ARENA[3] - 8), (ARENA[2] - 8, ARENA[3] - 8)]:
            self.canvas.create_rectangle(x, y, x + 8, y + 8, fill=POST, outline="")

        cx = (ARENA[0] + ARENA[2]) / 2
        cy = (ARENA[1] + ARENA[3]) / 2
        self.canvas.create_line(cx - 28, cy, cx + 28, cy, fill="#4a5e81", width=3)
        self.canvas.create_line(cx, cy - 28, cx, cy + 28, fill="#4a5e81", width=3)

        for y in range(ARENA[1] + 10, ARENA[3] - 8, 10):
            for x in range(ARENA[0] + 10, ARENA[2] - 8, 12):
                self.canvas.create_rectangle(x, y, x + 2, y + 2, fill="#314361", outline="")

        self.draw_shadow(self.player)
        self.draw_shadow(self.enemy)
        # draw farther fighter first based on y for a bit of depth
        if self.player.y < self.enemy.y:
            self.draw_fighter(self.player)
            self.draw_fighter(self.enemy)
        else:
            self.draw_fighter(self.enemy)
            self.draw_fighter(self.player)

        if self.flash > 0:
            alpha = int(90 * self.flash)
            self.canvas.create_rectangle(0, 0, WIDTH, HEIGHT, fill="#ffffff", outline="", stipple="gray75")

        self.draw_hud()

    def loop(self):
        dt = 1 / TARGET_FPS
        if self.state == "fight":
            self.update(dt)
        self.draw()
        self.root.after(int(1000 / TARGET_FPS), self.loop)

    def mix(self, c1, c2, t):
        def hex_to_rgb(h):
            h = h.lstrip("#")
            return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
        a = hex_to_rgb(c1)
        b = hex_to_rgb(c2)
        rgb = tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))
        return "#%02x%02x%02x" % rgb

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    PixelBoxingDesktop().run()
