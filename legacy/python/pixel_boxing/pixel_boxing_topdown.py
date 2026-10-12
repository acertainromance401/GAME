import math
import random
import tkinter as tk
import time
from dataclasses import dataclass
from functools import lru_cache

from .audio_feedback import SoundManager
from .boxing_core import (
    ATTACK_ACTIONS,
    ATTACK_SPECS,
    BACKSTEP_STAMINA_COST,
    counter_damage,
    DUCK_EVADE_KEY,
    DUCK_EVADE_THRESHOLD,
    DODGE_STAMINA_COST,
    GUARD_DAMAGE_MULT,
    PlayerHabitMemory,
    ROUND_SECONDS,
    STAGGER_LOCK,
    STAMINA_RECOVERY_PER_SEC,
    WHIFF_RECOVERY,
    adaptation_level,
    adaptive_enemy_weights,
    frame_delta,
    note_player_attack,
    sample_player_tendency,
    spend_stamina,
    snapshot_player_habits,
    try_start_attack,
)
from .game_settings import GameSettings

WIDTH = 960
HEIGHT = 700
ARENA = (70, 70, 520, 520)
FIGHTER_RING_MARGIN = 34.0
KNOCKDOWN_DURATION = 0.9

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


@lru_cache(maxsize=128)
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
    exhausted: float = 0.0
    hit_flash: float = 0.0
    ai_timer: float = 0.0
    anim_t: float = 0.0
    exposed: float = 0.0
    stagger: float = 0.0
    whiff_penalized: bool = False
    streak_action: str = ""
    streak_count: int = 0
    move_input_x: float = 0.0
    move_input_y: float = 0.0
    move_visual_x: float = 0.0
    move_visual_y: float = 0.0
    move_cycle: float = 0.0
    move_inertia_x: float = 0.0
    move_inertia_y: float = 0.0
    duck_pose: float = 0.0
    hit_reaction: float = 0.0
    hit_reaction_dur: float = 0.0
    hit_reaction_strength: float = 0.0
    hit_reaction_kind: str = ""
    hit_reaction_side: float = 0.0
    knocked_out: bool = False
    knockdown: float = 0.0


class TopDownPrototype:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Pixel Boxing Top-Down")
        self.root.configure(bg="#05080d")
        self.canvas = tk.Canvas(self.root, width=WIDTH, height=HEIGHT, bg=BG, highlightthickness=0)
        self.canvas.pack(fill="both", expand=False)

        self.status = tk.Label(
            self.root,
            text="H Controls   O Settings   P/Esc Pause   R Restart",
            fg=WHITE,
            bg="#05080d",
            anchor="w",
            font=("Helvetica", 11, "bold"),
        )
        self.status.pack(fill="x", padx=8, pady=(6, 8))

        self.log = ""
        self.settings = GameSettings.load()
        self.sound = SoundManager(enabled=self.settings.sound_enabled)
        self.modal_view = None
        self.modal_keys = set()
        self.round_transition_timer = 0.0

        # Pseudo third-person camera parameters.
        self.cam_base_dist = 260.0
        self.cam_dist = self.cam_base_dist
        # side_scale and forward_scale are kept close to each other so the
        # square world-space ARENA (450x450 units) actually reads as a
        # square ring on screen instead of a stretched-wide rectangle -
        # side_scale=1.45 vs forward_scale=0.90 used to blow the near edge
        # of the ring out to ~950px (off both sides of the canvas) while the
        # far edge shrank to ~270px, an extreme un-square trapezoid.
        self.cam_side_scale = 0.8
        self.cam_forward_scale = 1.15
        self.cam_ground_y = HEIGHT * 0.71
        self.cam_screen_bias_x = 0.0
        self.cam_screen_bias_y = 10.0
        self.cam_smooth = 8.8
        self.cam_shoulder_side = 28.0
        self.cam_shoulder_back = 18.0
        self.cam_focus_mid_pull = 0.26
        self.cam_focus_mid_pull_far = 0.52
        self.cam_min_dist = 248.0
        self.cam_max_dist = 324.0
        self.cam_zoom_smooth = 5.2
        self.cam_brawl_zoom_in = 14.0
        self.cam_bottom_frame_lift = 0.0
        self.cam_bottom_frame_lift_max = 28.0
        self.cam_bottom_frame_smooth = 5.0
        self.cam_player_punch_lead = 16.0
        self.cam_enemy_punch_lead = 7.5
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

        self.reset_match()

        self.root.bind_all("<KeyPress>", self.on_key_down)
        self.root.bind_all("<KeyRelease>", self.on_key_up)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        self._last_tick_time = time.perf_counter()
        self._running = True
        self._tick_after_id = None
        self.tick()

    def reset_match(self):
        # Full match reset: fresh fighters, round count, and score, but the
        # Tk window/canvas/camera tuning constants are left untouched.
        self.player = Fighter("Player", 170, 295, PLAYER_COLOR)
        self.enemy = Fighter("Enemy", 420, 295, ENEMY_COLOR)
        self.cam_dist = self.cam_base_dist
        self.cam_bottom_frame_lift = 0.0
        self.cam_anchor_x = self.player.x
        self.cam_anchor_y = self.player.y
        self.player_stance_x = self.player.x
        self.player_stance_y = self.player.y
        self.cam_facing_x, self.cam_facing_y = normalize(self.enemy.x - self.player.x, self.enemy.y - self.player.y)
        self.player_duck_target = 0.0
        self.player_duck_offset = 0.0
        self.player_duck_world_x = 0.0
        self.player_duck_world_y = 0.0
        self.player_back_target = 0.0
        self.player_back_offset = 0.0
        self.player_back_risk_applied = False
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
        self.player_habits = PlayerHabitMemory()
        self.enemy_habit_snapshot = snapshot_player_habits(self.player_habits)
        self.enemy_adaptation = adaptation_level(self.enemy_habit_snapshot, self.round)
        self.modal_view = None
        self.modal_keys = set()
        self.round_transition_timer = 0.0
        self.round_result_delay = 0.0
        self.state = "intro"
        self.set_overlay("PIXEL BOXING", "Endless rounds  |  Space Start  |  H Controls  |  O Settings")
        self.push_log("Press Space to start Round 1.")

    def reset_round_only(self):
        # Between-round reset: HP/stamina/position/action state reset, but
        # round number and match score carry over.
        self.player = Fighter("Player", 170, 295, PLAYER_COLOR)
        self.enemy = Fighter("Enemy", 420, 295, ENEMY_COLOR)
        self.cam_dist = self.cam_base_dist
        self.cam_bottom_frame_lift = 0.0
        self.cam_anchor_x = self.player.x
        self.cam_anchor_y = self.player.y
        self.player_stance_x = self.player.x
        self.player_stance_y = self.player.y
        self.cam_facing_x, self.cam_facing_y = normalize(self.enemy.x - self.player.x, self.enemy.y - self.player.y)
        self.player_duck_target = 0.0
        self.player_duck_offset = 0.0
        self.player_duck_world_x = 0.0
        self.player_duck_world_y = 0.0
        self.player_back_target = 0.0
        self.player_back_offset = 0.0
        self.player_back_risk_applied = False
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
        self.modal_view = None
        self.modal_keys = set()
        self.round_transition_timer = 0.0
        self.round_result_delay = 0.0
        self.round_time = float(ROUND_SECONDS)

    def set_overlay(self, title, body):
        self.overlay_title = title
        self.overlay_body = body

    def _start_round(self):
        self.reset_round_only()
        self.state = "round_intro"
        self.round_transition_timer = 1.65
        self.push_log(f"Round {self.round} ready.")

    def ai_learning_percent(self):
        self.ensure_adaptation_state()
        return int(round(self.enemy_adaptation * 100))

    def update_round_transition(self, dt):
        if self.state != "round_intro":
            return
        self.round_transition_timer = max(0.0, self.round_transition_timer - dt)
        if self.round_transition_timer <= 0.0:
            self.state = "fight"
            self.play_sound("round_bell", min_interval=0.5)
            self.push_log(f"Round {self.round} fight.")

    def end_round(self, winner, reason):
        self.state = "round_break"
        self.round_result_delay = 1.25 if reason == "KO" else 0.0
        if reason != "KO":
            self.play_sound("round_end", min_interval=0.5)
        if winner == "player":
            self.score_player += 1
            self.push_log(f"Round {self.round}: Player {reason}")
        elif winner == "enemy":
            self.score_enemy += 1
            self.push_log(f"Round {self.round}: Enemy {reason}")
        else:
            self.push_log(f"Round {self.round}: Draw ({reason})")

        result = winner.upper() if winner in ("player", "enemy") else "DRAW"
        self.set_overlay(
            f"ROUND {self.round} - {result} ({reason})",
            f"AI READ {self.ai_learning_percent():03d}%  |  Session P{self.score_player}-{self.score_enemy}E  |  Space: next round",
        )
        self.round += 1

    def push_log(self, text):
        self.log = text
        self.status.config(text=text)

    def show_feedback(self, text):
        self.feedback_text = text
        self.feedback_timer = 0.35
        self.push_log(text)

    def play_sound(self, name, min_interval=0.035):
        sound = getattr(self, "sound", None)
        return sound.play(name, min_interval=min_interval) if sound else False

    def show_commentary(self, key, attacker=None, defender=None):
        # Sports-commentary style caption (see COMMENTARY_LINES/draw_hud) -
        # purely cosmetic, picked at random from that event's variants and
        # formatted with the attacker/defender's display name if given.
        if not self.settings.commentary_enabled:
            return
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

    def start_hit_reaction(self, defender, action, damage, guarding=False):
        duration = 0.15 + 0.08 * clamp(damage / 20.0, 0.0, 1.0)
        strength = clamp(damage / 13.0, 0.38, 1.35)
        if guarding:
            strength *= 0.42
        defender.hit_reaction = duration
        defender.hit_reaction_dur = duration
        defender.hit_reaction_strength = strength
        defender.hit_reaction_kind = self.punch_category(action)
        defender.hit_reaction_side = -1.0 if action == "jab" or action.startswith("left_") else 1.0

    def hit_reaction_pose(self, fighter, scale=1.0):
        if fighter.hit_reaction <= 0.0 or fighter.hit_reaction_dur <= 0.0:
            return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

        recoil = clamp(fighter.hit_reaction / fighter.hit_reaction_dur, 0.0, 1.0) ** 2
        power = fighter.hit_reaction_strength * recoil * scale
        side = fighter.hit_reaction_side
        kind = fighter.hit_reaction_kind
        if kind == "body":
            return (2.8 * power, 0.5 * side * power, 3.6 * power,
                    1.2 * power, 0.8 * side * power, 2.4 * power)
        if kind == "hook":
            return (-2.0 * power, 2.7 * side * power, 1.0 * power,
                    -4.4 * power, 6.2 * side * power, 0.7 * power)
        if kind == "uppercut":
            return (-2.6 * power, 1.0 * side * power, -0.8 * power,
                    -4.8 * power, 1.8 * side * power, -5.8 * power)
        return (-2.3 * power, 0.8 * side * power, 0.7 * power,
                -5.2 * power, 1.6 * side * power, 0.3 * power)

    def update_knockdown_motions(self, dt):
        for actor in (self.player, self.enemy):
            if not actor.knocked_out:
                continue
            actor.knockdown = clamp(actor.knockdown + dt / KNOCKDOWN_DURATION, 0.0, 1.0)
            actor.hit_reaction = max(0.0, actor.hit_reaction - dt)
            actor.hit_flash = max(0.0, actor.hit_flash - dt)

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
            sx, sy, persp, _ = self.project_world(p["x"], p["y"])
            scale = self.sprite_scale(persp)
            r = max(0.6, 2.6 * scale * t)
            col = mix_color(p["color"], BG, (1.0 - t) * 0.75)
            # Offset up to roughly chest/head height on the sprite instead
            # of at the character's feet-level world anchor.
            py = sy - 16.0 * scale
            self.canvas.create_oval(sx - r, py - r, sx + r, py + r, fill=col, outline="")

    def open_modal(self, name):
        if name not in ("pause", "controls", "settings"):
            raise ValueError(name)
        self.modal_view = name
        self.keys.clear()
        self.player_duck_target = 0.0
        self.player_back_target = 0.0

    def close_modal(self):
        self.modal_view = None
        self.keys.clear()
        self._last_tick_time = time.perf_counter()

    def toggle_setting(self, key):
        setting_names = {
            "1": "sound_enabled",
            "2": "commentary_enabled",
            "3": "camera_shake_enabled",
        }
        name = setting_names.get(key)
        if name is None:
            return False
        enabled = self.settings.toggle(name)
        self.settings.save()
        self.sound.enabled = self.settings.sound_enabled
        if name == "commentary_enabled" and not enabled:
            self.commentary_timer = 0.0
            self.commentary_text = ""
        if name == "camera_shake_enabled" and not enabled:
            self.shake_timer = 0.0
            self.shake_x = 0.0
            self.shake_y = 0.0
        if name == "sound_enabled" and enabled:
            self.sound.play("evade", min_interval=0.0)
        return True

    def on_key_down(self, event):
        key = (event.keysym or "").lower()

        if self.modal_view is not None:
            if key in self.modal_keys:
                return
            self.modal_keys.add(key)
            if key == "r":
                self.reset_match()
                return
            if self.modal_view == "settings" and self.toggle_setting(key):
                return
            if key in ("escape", "p"):
                self.close_modal()
            elif key == "h":
                if self.modal_view == "controls":
                    self.close_modal()
                else:
                    self.open_modal("controls")
            elif key == "o":
                if self.modal_view == "settings":
                    self.close_modal()
                else:
                    self.open_modal("settings")
            return

        if key in ("p", "escape", "h", "o"):
            if key in self.modal_keys:
                return
            self.modal_keys.add(key)
        if key in ("p", "escape"):
            if self.state in ("fight", "round_intro"):
                self.open_modal("pause")
            return
        if key == "h":
            self.open_modal("controls")
            return
        if key == "o":
            self.open_modal("settings")
            return

        if key in self.keys and key in ("q", "e", "s"):
            return

        self.keys.add(key)

        if key == "r":
            self.reset_match()
            return

        if self.state != "fight":
            if key == "space":
                if self.state in ("intro", "round_break"):
                    self._start_round()
            return

        if self.player.exhausted > 0 and key in ("a", "d", "q", "e", "s", "w"):
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
            if self.player.action_t < self.player.action_dur or self.player.stagger > 0 or self.player.stamina < BACKSTEP_STAMINA_COST:
                return
            if self.player_back_target <= 0:
                self.show_feedback("BACKSTEP")
                if spend_stamina(self.player, BACKSTEP_STAMINA_COST):
                    self.show_feedback("GASSED OUT")
                self.player_back_risk_applied = False
            self.player_back_target = 1.0
            self.player.invuln = max(self.player.invuln, 0.10)
        elif key == "w" and self.is_guarding(self.player):
            self.show_feedback("GUARD UP")

    def on_key_up(self, event):
        key = (event.keysym or "").lower()
        self.modal_keys.discard(key)
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
        started = try_start_attack(actor, name).started
        if started and actor.name == "Player":
            self.ensure_adaptation_state()
            note_player_attack(self.player_habits, name)
            if actor.exhausted > 0 and actor.stamina <= 0:
                self.show_feedback("GASSED OUT")
        return started

    def ensure_adaptation_state(self):
        if not hasattr(self, "player_habits") or self.player_habits is None:
            self.player_habits = PlayerHabitMemory()
        if not hasattr(self, "enemy_habit_snapshot"):
            self.enemy_habit_snapshot = snapshot_player_habits(self.player_habits)
        if not hasattr(self, "enemy_adaptation"):
            self.enemy_adaptation = adaptation_level(self.enemy_habit_snapshot, getattr(self, "round", 1))

    def sample_player_habits(self, dt):
        self.ensure_adaptation_state()
        forward_axis = (1 if "up" in self.keys else 0) - (1 if "down" in self.keys else 0)
        duck_dir = "q" if self.player_duck_target < 0 else "e" if self.player_duck_target > 0 else None
        sample_player_tendency(
            self.player_habits,
            dt,
            guarding=self.is_guarding(self.player),
            duck_dir=duck_dir,
            backstep=self.player_back_target > 0.05 or self.player_back_offset > 6.0,
            forward_axis=forward_axis,
        )

    def choose_enemy_option(self, weights):
        total = sum(max(0.0, weight) for weight in weights.values())
        if total <= 1e-9:
            return "wait"
        pick = random.uniform(0.0, total)
        running = 0.0
        for action, weight in weights.items():
            value = max(0.0, weight)
            running += value
            if pick <= running:
                return action
        return next(reversed(weights))

    def enemy_action_weights(self, distance):
        self.ensure_adaptation_state()
        snapshot = snapshot_player_habits(self.player_habits)
        self.enemy_habit_snapshot = snapshot
        self.enemy_adaptation = adaptation_level(snapshot, self.round)
        weights = adaptive_enemy_weights(
            snapshot,
            distance,
            self.round,
            player_exposed=self.player.exposed > 0,
        )

        if self.player.action in ATTACK_ACTIONS and self.player.action_t < self.player.action_dur:
            live_adapt = 0.18 + 0.55 * self.enemy_adaptation
            weights["dodge_left"] += live_adapt
            weights["dodge_right"] += live_adapt
            if distance < 90.0:
                weights["dodge_back"] += 0.22 + 0.65 * self.enemy_adaptation

        if distance > 138.0:
            weights["wait"] += 0.45

        available = {}
        range_limit = self.player.radius
        for action, weight in weights.items():
            if weight <= 0.0:
                continue
            if action in ATTACK_SPECS:
                spec = ATTACK_SPECS[action]
                if self.enemy.stamina < spec.stamina_cost:
                    continue
                extra_reach = 8.0 if action in ("jab", "cross") else 3.0
                if distance > spec.attack_range + range_limit + extra_reach:
                    continue
            elif action.startswith("dodge"):
                dodge_cost = BACKSTEP_STAMINA_COST if action == "dodge_back" else DODGE_STAMINA_COST
                if self.enemy.stamina < dodge_cost:
                    continue
            available[action] = weight

        if not available:
            return {"wait": 1.0}
        return available

    def start_dodge(self, actor, side):
        if actor.action_t < actor.action_dur or actor.stagger > 0 or actor.exhausted > 0:
            return
        stamina_cost = BACKSTEP_STAMINA_COST if side == "back" else DODGE_STAMINA_COST
        if actor.stamina < stamina_cost:
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
        actor.x, actor.y = self.clamp_fighter_to_ring(actor, actor.x + dx * dist, actor.y + dy * dist)
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
        exhausted = spend_stamina(actor, stamina_cost)
        if actor.name == "Player":
            self.show_feedback("GASSED OUT" if exhausted else label)

    def is_guarding(self, actor):
        # Only the player actively holds guard (mirrors duck/backstep being
        # player-only special cases elsewhere in this file). Guarding only
        # counts while the actor is free to act - mid-punch or flinching
        # overrides it, same as duck/backstep would.
        if actor.name != "Player":
            return False
        return "w" in self.keys and actor.action_t >= actor.action_dur and actor.stagger <= 0 and actor.exhausted <= 0

    def attempt_hit(self, attacker, defender):
        if defender.invuln > 0 or (defender.action == "dodge" and defender.dodge > 0):
            if defender.name == "Player":
                self.show_feedback("DODGE SUCCESS")
            self.show_commentary("dodge", attacker, defender)
            self.play_sound("evade")
            return False

        target_x, target_y = defender.x, defender.y
        if defender.name == "Player":
            # Directional ducking is a strict design rule: the correct key
            # evades and the wrong key does not. Remove the duck-only world
            # displacement before distance/cone checks so a wrong-direction
            # duck cannot accidentally escape the cone geometrically. Other
            # movement (including backstep) remains part of the target point.
            target_x -= self.player_duck_world_x
            target_y -= self.player_duck_world_y
        vx = target_x - attacker.x
        vy = target_y - attacker.y
        d = length(vx, vy)
        if d > attacker.range + defender.radius:
            return False

        tx, ty = normalize(vx, vy)
        dot = attacker.facing_x * tx + attacker.facing_y * ty
        limit = math.cos(math.radians(attacker.half_angle_deg))
        if dot < limit:
            return False

        if defender.name == "Player" and attacker.action in DUCK_EVADE_KEY:
            needed_key = DUCK_EVADE_KEY[attacker.action]
            duck_ratio = clamp(abs(self.player_duck_offset) / max(self.duck_max, 1e-6), 0.0, 1.0)
            duck_dir = "e" if self.player_duck_offset > 0 else "q" if self.player_duck_offset < 0 else None
            if duck_ratio >= DUCK_EVADE_THRESHOLD and duck_dir == needed_key:
                self.show_feedback("DUCK EVADE")
                self.show_commentary("duck_evade", attacker, defender)
                self.play_sound("evade")
                return False

        punished_whiff = defender.exposed > 0
        damage = counter_damage(attacker.action, attacker.damage, punished_whiff)

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
        self.start_hit_reaction(defender, attacker.action, damage, guarding)

        # Impact feedback: brief hitstop (near-freeze) plus a camera rattle,
        # scaled a little by damage so a jab barely nudges the view but a
        # clean power shot actually feels like it landed.
        self.hitstop_timer = max(self.hitstop_timer, 0.05 + min(damage, 20) * 0.0035)
        settings = getattr(self, "settings", None)
        if settings is None or settings.camera_shake_enabled:
            self.shake_timer = max(self.shake_timer, 0.16)
            self.shake_mag = max(self.shake_mag, 3.0 + min(damage, 20) * 0.55)
        spark_color = "#9fd8ff" if guarding else "#fff2c9"
        self.spawn_hit_particles(defender.x, defender.y, spark_color, 7 + min(damage, 20) // 2)
        if punished_whiff:
            self.play_sound("counter")
        else:
            self.play_sound("block" if guarding else "hit_heavy" if damage >= 11 else "hit_light")

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
            defender.knocked_out = True
            defender.knockdown = 0.0
            defender.action = "idle"
            defender.action_t = 0.0
            defender.action_dur = 0.0
            self.show_feedback("KO!")
            self.show_commentary("ko", attacker, defender)
            self.play_sound("ko", min_interval=0.5)
            self.end_round(winner, "KO")
        return True

    def update_facing(self, actor, target):
        fx, fy = normalize(target.x - actor.x, target.y - actor.y)
        actor.facing_x = fx
        actor.facing_y = fy

    def clamp_fighter_to_ring(self, actor, x, y):
        margin = max(actor.radius, FIGHTER_RING_MARGIN)
        return (
            clamp(x, ARENA[0] + margin, ARENA[2] - margin),
            clamp(y, ARENA[1] + margin, ARENA[3] - margin),
        )

    def update_player_movement(self, dt):
        if self.player.action_t < self.player.action_dur or self.player.stagger > 0 or self.player.exhausted > 0:
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
        old_x, old_y = self.player.x, self.player.y
        self.player.x, self.player.y = self.clamp_fighter_to_ring(
            self.player,
            self.player.x + dx,
            self.player.y + dy,
        )
        actual_dx = self.player.x - old_x
        actual_dy = self.player.y - old_y
        self.player.move_input_x = actual_dx / max(dt, 1e-6)
        self.player.move_input_y = actual_dy / max(dt, 1e-6)
        # Track the "stance" position (intentional movement only) separately
        # from player.x/y so the camera can follow it without being dragged
        # around by the duck/backstep hold-and-return offsets.
        self.player_stance_x, self.player_stance_y = self.clamp_fighter_to_ring(
            self.player,
            self.player_stance_x + actual_dx,
            self.player_stance_y + actual_dy,
        )

    def update_ai(self, dt):
        e = self.enemy
        p = self.player

        e.ai_timer = max(0.0, e.ai_timer - dt)
        if e.exhausted > 0:
            return
        if e.action_t >= e.action_dur:
            dx = p.x - e.x
            dy = p.y - e.y
            dist = length(dx, dy)
            if dist > 130:
                nx, ny = normalize(dx, dy)
                old_x, old_y = e.x, e.y
                e.x, e.y = self.clamp_fighter_to_ring(e, e.x + nx * 155 * dt, e.y + ny * 155 * dt)
                e.move_input_x = (e.x - old_x) / max(dt, 1e-6)
                e.move_input_y = (e.y - old_y) / max(dt, 1e-6)

        # Capitalize immediately on the player's off-balance whiff window
        # instead of waiting out a random cooldown, so spamming attacks
        # blind gets punished rather than rewarded.
        if p.exposed > 0 and e.action_t >= e.action_dur and e.stagger <= 0:
            e.ai_timer = 0.0

        if e.ai_timer > 0 or self.state != "fight":
            return

        dist = length(p.x - e.x, p.y - e.y)
        adapt = getattr(self, "enemy_adaptation", 0.18)
        cooldown_scale = 1.0 + 0.16 * (self.round - 1) + 0.32 * adapt
        if p.exposed > 0:
            e.ai_timer = random.uniform(0.08, 0.16) / cooldown_scale
        else:
            e.ai_timer = random.uniform(0.12, 0.28) / cooldown_scale

        if dist > 148.0 and p.exposed <= 0:
            return

        option = self.choose_enemy_option(self.enemy_action_weights(dist))
        if option == "wait":
            return
        if option.startswith("dodge_"):
            self.start_dodge(e, option.split("_", 1)[1])
            return
        self.start_attack(e, option)

    def update_actor_timers(self, actor, dt):
        actor.stamina = clamp(actor.stamina + dt * STAMINA_RECOVERY_PER_SEC, 0, actor.max_stamina)
        actor.invuln = max(0.0, actor.invuln - dt)
        actor.dodge = max(0.0, actor.dodge - dt)
        actor.exhausted = max(0.0, actor.exhausted - dt)
        actor.hit_flash = max(0.0, actor.hit_flash - dt)
        actor.hit_reaction = max(0.0, actor.hit_reaction - dt)
        actor.exposed = max(0.0, actor.exposed - dt)
        actor.stagger = max(0.0, actor.stagger - dt)
        actor.anim_t += dt

        move_k = 1.0 - math.exp(-11.0 * dt)
        actor.move_visual_x = lerp(actor.move_visual_x, actor.move_input_x, move_k)
        actor.move_visual_y = lerp(actor.move_visual_y, actor.move_input_y, move_k)
        accel_x = actor.move_input_x - actor.move_visual_x
        accel_y = actor.move_input_y - actor.move_visual_y
        inertia_decay = 1.0 - math.exp(-7.5 * dt)
        actor.move_inertia_x = lerp(actor.move_inertia_x, accel_x * 0.05, inertia_decay)
        actor.move_inertia_y = lerp(actor.move_inertia_y, accel_y * 0.05, inertia_decay)
        move_speed = length(actor.move_visual_x, actor.move_visual_y)
        if move_speed > 6.0:
            actor.move_cycle += dt * lerp(4.8, 8.7, clamp(move_speed / 210.0, 0.0, 1.0))

        if actor.action_t < actor.action_dur:
            actor.action_t += dt
            if actor.action in ATTACK_ACTIONS and not actor.acted and actor.active_a <= actor.action_t <= actor.active_b:
                target = self.enemy if actor.name == "Player" else self.player
                actor.acted = self.attempt_hit(actor, target)
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
        old_x, old_y = self.player.x, self.player.y
        nx = self.player.x + right_x * delta
        ny = self.player.y + right_y * delta
        self.player.x, self.player.y = self.clamp_fighter_to_ring(self.player, nx, ny)
        self.player_duck_world_x += self.player.x - old_x
        self.player_duck_world_y += self.player.y - old_y

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
        self.player.x, self.player.y = self.clamp_fighter_to_ring(self.player, nx, ny)

        recovering = self.player_back_target <= 0.05 and self.player_back_offset > self.back_max * 0.22
        if recovering and self.player.invuln <= 0.0 and not self.player_back_risk_applied:
            self.player.exposed = max(self.player.exposed, 0.16)
            self.player_back_risk_applied = True
        elif self.player_back_offset < 1.0:
            self.player_back_risk_applied = False

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
            if self.state == "round_break":
                self.update_knockdown_motions(dt)
                self.round_result_delay = max(0.0, self.round_result_delay - dt)
                self.feedback_timer = max(0.0, self.feedback_timer - dt)
                self.commentary_timer = max(0.0, self.commentary_timer - dt)
                self.update_particles(dt)
            return

        self.player.move_input_x = 0.0
        self.player.move_input_y = 0.0
        self.enemy.move_input_x = 0.0
        self.enemy.move_input_y = 0.0

        self.update_facing(self.player, self.enemy)
        self.update_facing(self.enemy, self.player)
        self.update_player_movement(dt)
        self.update_player_duck(dt)
        self.update_player_backstep(dt)
        self.update_player_guard(dt)
        duck_pose_k = 1.0 - math.exp(-13.5 * dt)
        player_duck_target = clamp(abs(self.player_duck_offset) / max(self.duck_max, 1e-6), 0.0, 1.0)
        self.player.duck_pose = lerp(self.player.duck_pose, player_duck_target, duck_pose_k)
        self.enemy.duck_pose = lerp(self.enemy.duck_pose, 0.0, duck_pose_k)
        self.sample_player_habits(dt)
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

        spread = length(self.enemy.x - self.player_stance_x, self.enemy.y - self.player_stance_y)
        spread_t = clamp((spread - 86.0) / 190.0, 0.0, 1.0)
        mid_x = (self.player_stance_x + self.enemy.x) * 0.5
        mid_y = (self.player_stance_y + self.enemy.y) * 0.5
        focus_pull = lerp(self.cam_focus_mid_pull, self.cam_focus_mid_pull_far, spread_t)
        focus_x = lerp(self.player_stance_x, mid_x, focus_pull)
        focus_y = lerp(self.player_stance_y, mid_y, focus_pull)
        shoulder_side = lerp(self.cam_shoulder_side, 12.0, spread_t)
        shoulder_back = lerp(self.cam_shoulder_back, 32.0, spread_t)
        zoom_k = 1.0 - math.exp(-self.cam_zoom_smooth * dt)
        brawl_zoom = self.camera_brawl_zoom(spread)
        desired_cam_dist = clamp(self.cam_base_dist + 44.0 * spread_t - brawl_zoom, self.cam_min_dist, self.cam_max_dist)
        self.cam_dist = lerp(self.cam_dist, desired_cam_dist, zoom_k)
        punch_lead_x, punch_lead_y = self.camera_punch_lead()

        # The camera tracks the player's tracked "stance" position (updated
        # only by intentional arrow-key movement), not the raw player.x/y,
        # so duck/backstep hold-and-return offsets never drag the screen.
        # But framing only the player made the whole ring sit too far left
        # and low. Blend toward the fighter midpoint as spacing grows so the
        # bout stays centered while still preserving an over-shoulder feel.
        target_cam_x = focus_x + punch_lead_x + right_x * shoulder_side - fwd_x * shoulder_back
        target_cam_y = focus_y + punch_lead_y + right_y * shoulder_side - fwd_y * shoulder_back
        k = 1.0 - math.exp(-self.cam_smooth * dt)
        self.cam_anchor_x = lerp(self.cam_anchor_x, target_cam_x, k)
        self.cam_anchor_y = lerp(self.cam_anchor_y, target_cam_y, k)

        lower_body_y = max(
            self.project_world(self.player.x, self.player.y)[1],
            self.project_world(self.enemy.x, self.enemy.y)[1],
        )
        bottom_pressure = clamp((lower_body_y - HEIGHT * 0.73) / (HEIGHT * 0.16), 0.0, 1.0)
        desired_bottom_lift = self.cam_bottom_frame_lift_max * bottom_pressure
        lift_k = 1.0 - math.exp(-self.cam_bottom_frame_smooth * dt)
        self.cam_bottom_frame_lift = lerp(self.cam_bottom_frame_lift, desired_bottom_lift, lift_k)

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

    def camera_punch_lead(self):
        lead_x = 0.0
        lead_y = 0.0
        for actor, max_lead in ((self.player, self.cam_player_punch_lead), (self.enemy, self.cam_enemy_punch_lead)):
            if actor.action not in ATTACK_ACTIONS or actor.action_t >= actor.action_dur:
                continue
            spec = ATTACK_SPECS[actor.action]
            duration = max(actor.action_dur, 1e-6)
            phase = clamp(actor.action_t / duration, 0.0, 1.0)
            active_mid = (spec.active_a + spec.active_b) * 0.5 / duration
            active_half = max((spec.active_b - spec.active_a) * 0.5 / duration, 0.06)
            # Peak the camera nudge around the real contact window instead of
            # the whole animation so the look-ahead reads like a punch snap,
            # not a constant drifting camera.
            snap = max(0.0, 1.0 - abs(phase - active_mid) / (active_half + 0.16))
            lead = max_lead * snap
            lead_x += actor.facing_x * lead
            lead_y += actor.facing_y * lead
        return lead_x, lead_y

    def camera_brawl_zoom(self, spread):
        close_t = clamp((126.0 - spread) / 58.0, 0.0, 1.0)
        if close_t <= 0.0:
            return 0.0

        pressure = 0.0
        for actor, weight in ((self.player, 1.0), (self.enemy, 0.82)):
            if actor.action not in ATTACK_ACTIONS or actor.action_t >= actor.action_dur:
                continue
            duration = max(actor.action_dur, 1e-6)
            phase = clamp(actor.action_t / duration, 0.0, 1.0)
            pressure += weight * max(0.0, 1.0 - abs(phase - 0.5) / 0.7)

        return self.cam_brawl_zoom_in * close_t * clamp(pressure, 0.0, 1.0)

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
        sy = self.cam_ground_y + self.cam_screen_bias_y + self.shake_y - self.cam_bottom_frame_lift - cam_z * forward_scale * persp
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
        palette = ["#5f7394", "#927765", "#6f594c", "#4f6578", "#80688d", "#40566c", "#925e62", "#59806d"]
        seats = []
        x0, y0, x1, y1 = ARENA
        for tier, offset in enumerate((28.0, 54.0, 84.0, 118.0)):
            count = 17
            for index in range(count):
                along = index / (count - 1)
                wx = lerp(x0 - 12.0, x1 + 12.0, along) + rng.uniform(-5.0, 5.0)
                wy = lerp(y0 - 12.0, y1 + 12.0, along) + rng.uniform(-5.0, 5.0)
                seats.append((wx, y0 - offset + rng.uniform(-4.0, 4.0), rng.choice(palette), tier))
                seats.append((wx, y1 + offset + rng.uniform(-4.0, 4.0), rng.choice(palette), tier))
                seats.append((x0 - offset + rng.uniform(-4.0, 4.0), wy, rng.choice(palette), tier))
                seats.append((x1 + offset + rng.uniform(-4.0, 4.0), wy, rng.choice(palette), tier))
        return seats

    def draw_stage_lighting(self):
        for band in range(9):
            y0 = 82 + band * 48
            y1 = y0 + 49
            shade = mix_color("#10213a", BG, band / 12.0)
            self.canvas.create_rectangle(0, y0, WIDTH, y1, fill=shade, outline="")

        beam_specs = (
            (260, 146, 390, 620, "#10243d"),
            (480, 124, 480, 650, "#142b45"),
            (700, 146, 570, 620, "#10243d"),
        )
        for light_x, light_y, target_x, target_y, color in beam_specs:
            self.canvas.create_polygon(
                light_x - 8, light_y + 8,
                light_x + 8, light_y + 8,
                target_x + 170, target_y,
                target_x - 170, target_y,
                fill=color,
                outline="",
            )

        self.canvas.create_line(120, 112, WIDTH - 120, 112, fill="#40536f", width=5)
        self.canvas.create_line(120, 128, WIDTH - 120, 128, fill="#263850", width=3)
        for x in range(130, WIDTH - 120, 48):
            self.canvas.create_line(x, 112, x + 20, 128, fill="#30435e", width=2)
            self.canvas.create_line(x + 20, 112, x, 128, fill="#30435e", width=2)
        for light_x in (260, 480, 700):
            self.canvas.create_rectangle(light_x - 12, 128, light_x + 12, 143, fill="#182334", outline="#6f8db7")
            self.canvas.create_line(light_x - 7, 143, light_x + 7, 143, fill="#f4e6b7", width=3)

    def draw_stands(self):
        x0, y0, x1, y1 = ARENA
        tiers = []
        for tier, (inner, outer) in enumerate(((18, 42), (46, 70), (74, 101), (105, 137))):
            quads = (
                ((x0 - outer, y0 - outer), (x0 - inner, y0 - inner), (x0 - inner, y1 + inner), (x0 - outer, y1 + outer)),
                ((x1 + inner, y0 - inner), (x1 + outer, y0 - outer), (x1 + outer, y1 + outer), (x1 + inner, y1 + inner)),
                ((x0 - outer, y0 - outer), (x1 + outer, y0 - outer), (x1 + inner, y0 - inner), (x0 - inner, y0 - inner)),
                ((x0 - inner, y1 + inner), (x1 + inner, y1 + inner), (x1 + outer, y1 + outer), (x0 - outer, y1 + outer)),
            )
            for quad in quads:
                projected = [self.project_world(wx, wy) for wx, wy in quad]
                avg_depth = sum(point[3] for point in projected) / len(projected)
                tiers.append((avg_depth, tier, projected))

        for _, tier, projected in sorted(tiers, key=lambda item: item[0], reverse=True):
            points = [coordinate for point in projected for coordinate in point[:2]]
            fill = mix_color("#17263b", BG, tier * 0.12)
            edge = mix_color("#4a607e", BG, tier * 0.13)
            self.canvas.create_polygon(points, fill=fill, outline=edge, width=1)

    def draw_crowd(self):
        projected_seats = []
        for wx, wy, color, tier in self.crowd_seats:
            sx, sy, persp, cam_z = self.project_world(wx, wy)
            projected_seats.append((cam_z, sx, sy, persp, color, tier))
        for cam_z, sx, sy, persp, color, tier in sorted(projected_seats, reverse=True):
            scale = self.sprite_scale(persp) * lerp(0.82, 0.72, tier / 3.0)
            fog_t = clamp((cam_z + 60.0) / 760.0 + tier * 0.045, 0.08, 0.82)
            tint = mix_color(color, BG, fog_t)
            self.canvas.create_line(
                sx,
                sy + 3.8 * scale,
                sx,
                sy - 5.0 * scale,
                fill=tint,
                width=max(1, int(4.8 * scale)),
                capstyle="round",
            )

    def draw_ring_ropes(self, foreground=False):
        # Fake "height" for corner posts/ropes: there's no true vertical (Z)
        # axis in this projection, so a post's on-screen rise is just the
        # corner's own screen point pushed straight up, scaled by persp so
        # near posts read taller than far ones - the same trick used for
        # sprite_scale/fog elsewhere in this file.
        corners_world = [(ARENA[0], ARENA[1]), (ARENA[2], ARENA[1]), (ARENA[2], ARENA[3]), (ARENA[0], ARENA[3])]
        projected = [self.project_world(wx, wy) for wx, wy in corners_world]
        corner_colors = (PLAYER_COLOR, ENEMY_COLOR, ENEMY_COLOR, PLAYER_COLOR)
        rope_colors = ("#d9e4f5", "#e15a5a", "#d9e4f5")
        corner_depth_cutoff = sorted(point[3] for point in projected)[1]
        edge_depths = [
            (projected[index][3] + projected[(index + 1) % 4][3]) * 0.5
            for index in range(4)
        ]
        edge_depth_cutoff = sorted(edge_depths)[1]
        tops = []
        for index, (sx, sy, persp, cam_z) in enumerate(projected):
            top_y = sy - 130.0 * persp * 0.55
            tops.append(top_y)
            is_foreground = cam_z <= corner_depth_cutoff
            if is_foreground != foreground:
                continue
            post_color = mix_color(corner_colors[index], BG, 0.16)
            self.canvas.create_line(sx + 2, sy, sx + 2, top_y, fill="#050912", width=max(5, int(6 * persp)))
            self.canvas.create_line(sx, sy, sx, top_y, fill=post_color, width=max(3, int(4 * persp)))
            self.canvas.create_oval(sx - 4, top_y - 4, sx + 4, top_y + 4, fill=post_color, outline="#d9e4f5")
            pad_top = lerp(sy, top_y, 0.78)
            pad_bottom = lerp(sy, top_y, 0.35)
            pad_half = max(4.0, 5.5 * persp)
            self.canvas.create_rectangle(
                sx - pad_half,
                pad_top,
                sx + pad_half,
                pad_bottom,
                fill=post_color,
                outline=mix_color(corner_colors[index], WHITE, 0.45),
                width=1,
            )
        for rope_index, frac in enumerate((0.32, 0.6, 0.88)):
            pts = []
            for i in range(4):
                sx, sy, persp, cam_z = projected[i]
                rope_y = sy + (tops[i] - sy) * frac
                pts.append((sx, rope_y))
            for i in range(4):
                is_foreground = edge_depths[i] <= edge_depth_cutoff
                if is_foreground != foreground:
                    continue
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % 4]
                self.canvas.create_line(x0 + 1, y0 + 2, x1 + 1, y1 + 2, fill="#050912", width=4)
                self.canvas.create_line(x0, y0, x1, y1, fill=rope_colors[rope_index], width=2)

    def draw_arena(self):
        self.canvas.delete("all")
        self.canvas.create_rectangle(0, 0, WIDTH, HEIGHT, fill=BG, outline=BG)
        self.draw_stage_lighting()
        self.draw_stands()
        self.draw_crowd()
        c0 = self.project_world(ARENA[0], ARENA[1])
        c1 = self.project_world(ARENA[2], ARENA[1])
        c2 = self.project_world(ARENA[2], ARENA[3])
        c3 = self.project_world(ARENA[0], ARENA[3])
        floor_poly = [c0[0], c0[1], c1[0], c1[1], c2[0], c2[1], c3[0], c3[1]]
        center_x = sum(point[0] for point in (c0, c1, c2, c3)) / 4.0
        center_y = sum(point[1] for point in (c0, c1, c2, c3)) / 4.0
        apron_poly = []
        for point in (c0, c1, c2, c3):
            dx = point[0] - center_x
            dy = point[1] - center_y
            mag = max(length(dx, dy), 1e-6)
            apron_poly.extend((point[0] + dx / mag * 17.0, point[1] + dy / mag * 12.0))
        self.canvas.create_polygon(apron_poly, fill="#0b1322", outline="#49658c", width=3)
        self.canvas.create_polygon(floor_poly, fill=ARENA_BG, outline="#6f8db7", width=3)
        inner_world = (
            (ARENA[0] + 38, ARENA[1] + 38),
            (ARENA[2] - 38, ARENA[1] + 38),
            (ARENA[2] - 38, ARENA[3] - 38),
            (ARENA[0] + 38, ARENA[3] - 38),
        )
        inner_projected = [self.project_world(wx, wy) for wx, wy in inner_world]
        inner_poly = [coordinate for point in inner_projected for coordinate in point[:2]]
        self.canvas.create_polygon(inner_poly, fill="#1b3152", outline="#304c75", width=1)

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

        logo_center = self.project_world((ARENA[0] + ARENA[2]) * 0.5, (ARENA[1] + ARENA[3]) * 0.5)
        logo_side = self.project_world((ARENA[0] + ARENA[2]) * 0.5, (ARENA[1] + ARENA[3]) * 0.5 + 44)
        logo_radius_x = max(22.0, abs(logo_side[0] - logo_center[0]) + 42.0 * logo_center[2])
        logo_radius_y = max(10.0, 18.0 * logo_center[2])
        self.canvas.create_oval(
            logo_center[0] - logo_radius_x,
            logo_center[1] - logo_radius_y,
            logo_center[0] + logo_radius_x,
            logo_center[1] + logo_radius_y,
            fill="#14223a",
            outline="#6f8db7",
            width=2,
        )
        self.canvas.create_text(
            logo_center[0],
            logo_center[1],
            text="PIXEL BOXING",
            fill="#dbe7f7",
            font=("Helvetica", max(8, int(10 * logo_center[2])), "bold"),
        )

        self.draw_ring_ropes(foreground=False)

    def action_phase(self, fighter):
        if fighter.action_dur <= 1e-6:
            return 0.0
        return clamp(fighter.action_t / fighter.action_dur, 0.0, 1.0)

    def draw_bone(self, x0, y0, x1, y1, width, color, outline):
        self.canvas.create_line(x0, y0, x1, y1, fill=outline, width=width + 3, capstyle="round")
        self.canvas.create_line(x0, y0, x1, y1, fill=color, width=width, capstyle="round")

    def draw_tapered_limb(self, x0, y0, x1, y1, start_w, end_w, color, outline):
        dx = x1 - x0
        dy = y1 - y0
        mag = length(dx, dy)
        if mag < 1e-6:
            self.draw_joint(x0, y0, max(start_w, end_w) * 0.5, color, outline)
            return
        nx = -dy / mag
        ny = dx / mag
        outer = [
            x0 + nx * start_w, y0 + ny * start_w,
            x1 + nx * end_w, y1 + ny * end_w,
            x1 - nx * end_w, y1 - ny * end_w,
            x0 - nx * start_w, y0 - ny * start_w,
        ]
        self.canvas.create_polygon(outer, fill=outline, outline="")

        inset = 0.76
        inner = [
            x0 + nx * start_w * inset, y0 + ny * start_w * inset,
            x1 + nx * end_w * inset, y1 + ny * end_w * inset,
            x1 - nx * end_w * inset, y1 - ny * end_w * inset,
            x0 - nx * start_w * inset, y0 - ny * start_w * inset,
        ]
        self.canvas.create_polygon(inner, fill=color, outline="")

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
        cuff_col = mix_color(color, WHITE, 0.28)
        cuff_back_x = back_x - kx * 0.55 * scale
        cuff_back_y = back_y - ky * 0.55 * scale
        self.canvas.create_line(
            cuff_back_x - px * w * 0.78,
            cuff_back_y - py * w * 0.78,
            cuff_back_x + px * w * 0.78,
            cuff_back_y + py * w * 0.78,
            fill=cuff_col,
            width=max(1, int(1.45 * scale)),
        )

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
        sole = mix_color(color, WHITE, 0.24)
        ankle = mix_color(color, WHITE, 0.38)
        self.canvas.create_line(
            heel_x - side_x * w * 0.55,
            heel_y - side_y * w * 0.55,
            toe_x - side_x * w * 0.3,
            toe_y - side_y * w * 0.3,
            fill=sole,
            width=max(1, int(1.1 * scale)),
        )
        cuff_x = heel_x - dir_x * 0.6 * scale
        cuff_y = heel_y - dir_y * 0.6 * scale - 1.6 * scale
        self.canvas.create_line(
            cuff_x - side_x * w * 0.72,
            cuff_y - side_y * w * 0.72,
            cuff_x + side_x * w * 0.72,
            cuff_y + side_y * w * 0.72,
            fill=ankle,
            width=max(1, int(1.2 * scale)),
        )

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
        recover = clamp((phase - 0.56) / 0.18, 0.0, 1.0)
        settle = clamp((phase - 0.78) / 0.16, 0.0, 1.0)
        recoil = max(0.0, recover - settle)

        if action == "jab":
            # Lead hand only: the LONGEST-reaching punch in the kit (a
            # probing/spacing tool, not a power shot) - straight and
            # rotation-free, the lead shoulder rolls forward just enough to
            # shield the chin, and recovery is immediate.
            return {
                "fwd": 10 * scale + 55 * scale * extend - 8.0 * scale * recoil,
                "side": -3.0 * scale * windup - 1.1 * scale * recoil,
                "up": -1.5 * scale + 1.2 * scale * recoil,
                "torso_forward": 4.5 * scale * extend - 3.0 * scale * recoil,
                "torso_side": -1.2 * scale * windup - 0.8 * scale * recoil,
                "hip_turn": (-1.2 * scale * windup) + (3.2 * scale * extend) - 1.5 * scale * recoil,
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
                "fwd": 9 * scale + 38 * scale * extend - 11.0 * scale * recoil,
                "side": -8.0 * scale * windup - 2.6 * scale * recoil,
                "up": -2.5 * scale + 1.9 * scale * recoil,
                "torso_forward": 7.5 * scale * extend - 5.0 * scale * recoil,
                "torso_side": -4.6 * scale * windup - 2.2 * scale * recoil,
                "hip_turn": (-5.0 * scale * windup) + (11.0 * scale * extend) - 4.0 * scale * recoil,
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
                "fwd": 7 * scale + 32 * scale * extend - 8.0 * scale * recoil,
                "side": -8.0 * scale * windup - 2.0 * scale * recoil,
                "up": 7.0 * scale - 1.5 * scale * recoil,
                "torso_forward": 4.0 * scale * extend - 3.2 * scale * recoil,
                "torso_side": -3.8 * scale * windup - 1.8 * scale * recoil,
                "hip_turn": (-5.0 * scale * windup) + (9.5 * scale * extend) - 3.0 * scale * recoil,
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
                "fwd": 6 * scale + 16 * scale * extend - 6.5 * scale * recoil,
                "side": (19.0 * scale) - (27.0 * scale) * sweep - 5.5 * scale * recoil,
                "up": -1.5 * scale + 1.3 * scale * recoil,
                "torso_forward": 2.0 * scale - 2.0 * scale * recoil,
                "torso_side": (-6.2 * scale) + (9.4 * scale) * sweep - 3.5 * scale * recoil,
                "hip_turn": (-6.2 * scale) + (11.5 * scale) * sweep - 4.5 * scale * recoil,
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
            "fwd": 6 * scale + 16 * scale * extend - 6.0 * scale * recoil,
            "side": -5.5 * scale * windup - 1.4 * scale * recoil,
            "up": (11.0 * scale) + (-26.0 * scale) * rise + 4.0 * scale * recoil,
            "torso_forward": 3.2 * scale - 2.0 * scale * recoil,
            "torso_side": -2.2 * scale * windup - 1.1 * scale * recoil,
            "hip_turn": (-3.2 * scale * windup) + (7.5 * scale * rise) - 2.3 * scale * recoil,
            "pivot": rise,
            "crouch_bonus": 3.0 * scale * dip * (1.0 - rise),
            # Fist rotates from a slightly forward/down chamber into pointing
            # straight up as it drives through the chin.
            "knuckle_fwd": 0.5 + 0.2 * rise,
            "knuckle_side": 0.15,
            "knuckle_up": 0.35 - 1.15 * rise,
        }


    def draw_knockdown_fighter(
        self, f, sx, floor_sy, scale, fog_t, body, body_dark, skin,
        glove, shoe, trunks, trunks_trim, outline,
    ):
        progress = clamp(f.knockdown, 0.0, 1.0)
        fall = progress * progress * (3.0 - 2.0 * progress)
        fall_sign = -1.0 if sx > WIDTH * 0.5 else 1.0
        axis_x, axis_y = normalize(
            lerp(0.0, fall_sign, fall),
            lerp(-1.0, -0.12, fall),
        )
        across_x, across_y = -axis_y, axis_x
        hip = (
            sx + fall_sign * 4.0 * scale * fall,
            floor_sy + lerp(8.8, 16.0, fall) * scale,
        )
        chest = (hip[0] + axis_x * 15.0 * scale, hip[1] + axis_y * 15.0 * scale)
        neck = (hip[0] + axis_x * 24.0 * scale, hip[1] + axis_y * 24.0 * scale)
        head = (hip[0] + axis_x * 30.0 * scale, hip[1] + axis_y * 30.0 * scale)
        lead_shoulder = (
            chest[0] - across_x * 7.0 * scale,
            chest[1] - across_y * 7.0 * scale,
        )
        rear_shoulder = (
            chest[0] + across_x * 7.0 * scale,
            chest[1] + across_y * 7.0 * scale,
        )
        lead_hip = (hip[0] - across_x * 4.8 * scale, hip[1] - across_y * 4.8 * scale)
        rear_hip = (hip[0] + across_x * 4.8 * scale, hip[1] + across_y * 4.8 * scale)

        lead_knee = (
            lead_hip[0] - axis_x * 8.0 * scale - across_x * 2.6 * scale,
            lead_hip[1] - axis_y * 8.0 * scale - across_y * 2.6 * scale,
        )
        rear_knee = (
            rear_hip[0] - axis_x * 7.0 * scale + across_x * 3.2 * scale,
            rear_hip[1] - axis_y * 7.0 * scale + across_y * 3.2 * scale,
        )
        lead_foot = (
            lead_knee[0] - axis_x * 9.0 * scale - across_x * 2.2 * scale,
            lead_knee[1] - axis_y * 9.0 * scale - across_y * 2.2 * scale,
        )
        rear_foot = (
            rear_knee[0] - axis_x * 10.0 * scale + across_x * 1.5 * scale,
            rear_knee[1] - axis_y * 10.0 * scale + across_y * 1.5 * scale,
        )
        lead_elbow = (
            lead_shoulder[0]
            + axis_x * 4.0 * scale
            - across_x * lerp(3.0, 10.0, fall) * scale,
            lead_shoulder[1]
            + axis_y * 4.0 * scale
            - across_y * lerp(3.0, 10.0, fall) * scale,
        )
        rear_elbow = (
            rear_shoulder[0]
            + axis_x * 2.0 * scale
            + across_x * lerp(3.0, 11.0, fall) * scale,
            rear_shoulder[1]
            + axis_y * 2.0 * scale
            + across_y * lerp(3.0, 11.0, fall) * scale,
        )
        lead_hand = (
            lerp(
                head[0] - across_x * 5.0 * scale,
                lead_elbow[0] - axis_x * 6.0 * scale,
                fall,
            ),
            lerp(
                head[1] - across_y * 5.0 * scale,
                lead_elbow[1] - axis_y * 6.0 * scale,
                fall,
            ),
        )
        rear_hand = (
            lerp(
                head[0] + across_x * 5.0 * scale,
                rear_elbow[0] + across_x * 5.0 * scale,
                fall,
            ),
            lerp(
                head[1] + across_y * 5.0 * scale,
                rear_elbow[1] + across_y * 5.0 * scale,
                fall,
            ),
        )

        shadow_half = lerp(11.0, 38.0, fall) * scale
        self.canvas.create_oval(
            hip[0] - shadow_half,
            floor_sy + 12.0 * scale,
            hip[0] + shadow_half,
            floor_sy + 20.0 * scale,
            fill=mix_color("#000000", ARENA_BG, 0.58),
            outline="",
        )

        leg_upper_w = max(5, int(7.0 * scale))
        leg_lower_w = max(4, int(5.0 * scale))
        arm_upper_w = max(4, int(5.8 * scale))
        arm_lower_w = max(3, int(4.4 * scale))
        self.draw_tapered_limb(
            lead_hip[0], lead_hip[1], lead_knee[0], lead_knee[1],
            leg_upper_w, leg_upper_w * 0.64, body_dark, outline,
        )
        self.draw_tapered_limb(
            lead_knee[0], lead_knee[1], lead_foot[0], lead_foot[1],
            leg_lower_w, leg_lower_w * 0.58, body, outline,
        )
        self.draw_tapered_limb(
            rear_hip[0], rear_hip[1], rear_knee[0], rear_knee[1],
            leg_upper_w, leg_upper_w * 0.64, body_dark, outline,
        )
        self.draw_tapered_limb(
            rear_knee[0], rear_knee[1], rear_foot[0], rear_foot[1],
            leg_lower_w, leg_lower_w * 0.58, body, outline,
        )
        self.draw_foot(lead_foot[0], lead_foot[1], -axis_x, -axis_y, scale, shoe, outline)
        self.draw_foot(rear_foot[0], rear_foot[1], -axis_x, -axis_y, scale, shoe, outline)

        torso_poly = [
            lead_shoulder[0], lead_shoulder[1],
            rear_shoulder[0], rear_shoulder[1],
            rear_hip[0], rear_hip[1],
            lead_hip[0], lead_hip[1],
        ]
        self.canvas.create_polygon(torso_poly, fill=body, outline=outline, width=2)
        self.draw_tapered_limb(
            lead_hip[0], lead_hip[1], lead_knee[0], lead_knee[1],
            leg_upper_w * 0.9, leg_upper_w * 0.68, trunks, outline,
        )
        self.draw_tapered_limb(
            rear_hip[0], rear_hip[1], rear_knee[0], rear_knee[1],
            leg_upper_w * 0.9, leg_upper_w * 0.68, trunks, outline,
        )
        self.canvas.create_line(
            lead_hip[0], lead_hip[1], rear_hip[0], rear_hip[1],
            fill=trunks_trim, width=max(2, int(2.0 * scale)),
        )
        self.draw_bone(
            chest[0], chest[1], neck[0], neck[1],
            max(3, int(4.2 * scale)), skin, outline,
        )
        self.draw_tapered_limb(
            lead_shoulder[0], lead_shoulder[1], lead_elbow[0], lead_elbow[1],
            arm_upper_w, arm_upper_w * 0.62, body_dark, outline,
        )
        self.draw_tapered_limb(
            lead_elbow[0], lead_elbow[1], lead_hand[0], lead_hand[1],
            arm_lower_w, arm_lower_w * 0.58, skin, outline,
        )
        self.draw_tapered_limb(
            rear_shoulder[0], rear_shoulder[1], rear_elbow[0], rear_elbow[1],
            arm_upper_w, arm_upper_w * 0.62, body_dark, outline,
        )
        self.draw_tapered_limb(
            rear_elbow[0], rear_elbow[1], rear_hand[0], rear_hand[1],
            arm_lower_w, arm_lower_w * 0.58, skin, outline,
        )
        self.draw_fist(lead_hand[0], lead_hand[1], axis_x, axis_y, scale, glove, outline)
        self.draw_fist(rear_hand[0], rear_hand[1], axis_x, axis_y, scale, glove, outline)

        head_r = 6.5 * scale
        self.draw_joint(head[0], head[1], head_r, skin, outline)
        hair = mix_color("#171310", BG, fog_t * 0.9)
        self.canvas.create_arc(
            head[0] - head_r,
            head[1] - head_r,
            head[0] + head_r,
            head[1] + head_r,
            start=0,
            extent=180,
            style="pieslice",
            fill=hair,
            outline=outline,
        )
        self.prev_hand_pos.pop(f.name, None)

    def draw_fighter(self, f):
        sx, floor_sy, persp, cam_z = self.project_world(f.x, f.y, actor_depth_boost=False)
        _, boosted_sy, _, _ = self.project_world(f.x, f.y, actor_depth_boost=True)
        sy = lerp(floor_sy, boosted_sy, 0.38)
        scale = self.sprite_scale(persp) * 1.12
        fog_t = clamp((cam_z + 60.0) / 760.0, 0.0, 0.58)

        skin_base = WHITE if f.hit_flash > 0 else "#f1c39d"
        skin_shadow_base = "#f5ddd0" if f.hit_flash > 0 else "#c78d69"
        skin = mix_color(skin_base, BG, fog_t)
        skin_shadow = mix_color(skin_shadow_base, BG, fog_t * 0.92)
        body = skin
        body_dark = skin_shadow
        # Gloves/shoes are tinted from each fighter's own color (brightened
        # for the gloves, darkened for the shoes) instead of a single shared
        # skin-tone glove for both fighters - real boxers wear corner-colored
        # gear, and it makes player vs. enemy silhouettes read apart faster.
        glove = mix_color(mix_color(f.color, WHITE, 0.4), BG, fog_t)
        shoe = mix_color(mix_color(f.color, "#161d2c", 0.65), BG, fog_t * 0.7)
        trunks = mix_color("#eef2f8", BG, fog_t * 0.4)
        trunks_trim = mix_color(f.color, BG, fog_t)
        outline = mix_color("#0a1020", BG, fog_t * 0.7)
        cloth_shadow = mix_color(trunks_trim, outline, 0.45)

        shadow_color = mix_color("#000000", ARENA_BG, 0.55 + fog_t * 0.3)
        shadow_y = floor_sy + 25.0 * scale
        shadow_dx = clamp((sx - WIDTH * 0.5) * 0.055, -8.0 * scale, 8.0 * scale)
        shadow_length = 9.0 * scale
        self.canvas.create_polygon(
            sx - 6.5 * scale, shadow_y - 1.8 * scale,
            sx + 6.5 * scale, shadow_y - 1.8 * scale,
            sx + shadow_dx + 8.5 * scale, shadow_y + shadow_length,
            sx + shadow_dx - 8.5 * scale, shadow_y + shadow_length,
            fill=mix_color(shadow_color, ARENA_BG, 0.18),
            outline="",
        )
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

        if f.knocked_out:
            self.draw_knockdown_fighter(
                f, sx, floor_sy, scale, fog_t, body, body_dark, skin,
                glove, shoe, trunks, trunks_trim, outline,
            )
            return

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
        duck_tuck = clamp((f.duck_pose - 0.04) / 0.96, 0.0, 1.0)
        duck_round = duck_tuck * duck_tuck
        move_speed = length(f.move_visual_x, f.move_visual_y)
        move_weight = clamp(move_speed / 150.0, 0.0, 1.0)
        facing_right_x, facing_right_y = f.facing_y, -f.facing_x
        move_forward = 0.0
        move_side = 0.0
        if move_speed > 1e-6:
            move_forward = (f.move_visual_x * f.facing_x + f.move_visual_y * f.facing_y) / move_speed
            move_side = (f.move_visual_x * facing_right_x + f.move_visual_y * facing_right_y) / move_speed
        gait = math.sin(f.move_cycle)
        gait_cos = math.cos(f.move_cycle)
        move_drive = clamp(move_speed / 210.0, 0.0, 1.0)
        move_forward_bias = move_forward * move_drive
        move_side_bias = move_side * move_drive
        inertia_speed = length(f.move_inertia_x, f.move_inertia_y)
        inertia_forward = 0.0
        inertia_side = 0.0
        if inertia_speed > 1e-6:
            inertia_forward = (f.move_inertia_x * f.facing_x + f.move_inertia_y * f.facing_y) / max(210.0, inertia_speed)
            inertia_side = (f.move_inertia_x * facing_right_x + f.move_inertia_y * facing_right_y) / max(210.0, inertia_speed)
        inertia_weight = clamp(inertia_speed / 140.0, 0.0, 1.0)

        shoulder_half = (8.9 - 1.25 * duck_round) * scale + breath
        hip_half = 6.1 * scale
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

        crouch = (5.0 * f.duck_pose + 3.2 * back_ratio + 1.8 * guard_ratio) * scale + (profile["crouch_bonus"] if profile else 0.0)
        torso_center_x = sx - dir_x * (2.5 * back_ratio * scale) + side_x * idle_sway
        torso_center_y = sy - 4.0 * scale + crouch - idle_bob
        hip_center_x = sx + side_x * idle_sway * 0.5
        hip_center_y = sy + 8.8 * scale + crouch - idle_bob * 0.4
        torso_center_x += dir_x * (0.95 * scale * move_forward_bias) + side_x * (0.85 * scale * move_side_bias)
        hip_center_x += dir_x * (0.55 * scale * move_forward_bias) + side_x * (1.25 * scale * move_side_bias)
        torso_center_y += 0.22 * scale * abs(move_side_bias)
        hip_center_y += 0.4 * scale * abs(move_forward_bias)
        torso_center_x += dir_x * (2.1 * scale * inertia_forward * inertia_weight) + side_x * (1.55 * scale * inertia_side * inertia_weight)
        hip_center_x += dir_x * (1.15 * scale * inertia_forward * inertia_weight) + side_x * (2.0 * scale * inertia_side * inertia_weight)
        torso_center_y += 0.25 * scale * inertia_weight
        hip_center_y += 0.55 * scale * inertia_weight
        torso_center_x -= dir_x * 3.4 * scale * duck_tuck
        torso_center_y += 1.2 * scale * duck_tuck
        hip_center_x -= dir_x * 1.5 * scale * duck_tuck
        hip_center_y += 0.7 * scale * duck_tuck
        neck_x = torso_center_x + dir_x * (1.7 * scale)
        # Neck kept short and given real width below (neck_w) so the head
        # reads as seated into the shoulders instead of perched on a long
        # thin stick ("floating head" - a longer/thinner neck plus the idle
        # bob motion made the head look like it was bobbing on its own,
        # disconnected from the body).
        # The torso/hips already move down with crouch. Adding the full
        # crouch again here made the head drop much faster than the rest of
        # the body, which read like the head detaching during duck. Keep
        # only a tiny extra compression so the neck still looks slightly
        # tucked instead of rigid.
        neck_y = torso_center_y - (7.0 - 2.1 * duck_tuck) * scale + 0.28 * crouch
        head_center_x = neck_x + dir_x * ((1.8 - 0.42 * duck_tuck) * scale)
        head_center_y = neck_y - (4.8 - 0.9 * duck_tuck) * scale + 0.08 * crouch
        neck_x -= dir_x * 1.25 * scale * duck_tuck
        neck_y += 1.65 * scale * duck_tuck
        head_center_x -= dir_x * 1.8 * scale * duck_tuck
        head_center_y += 1.95 * scale * duck_tuck

        torso_fwd, torso_side, torso_drop, head_fwd, head_side, head_drop = (
            self.hit_reaction_pose(f, scale)
        )
        torso_center_x += dir_x * torso_fwd + side_x * torso_side
        torso_center_y += dir_y * torso_fwd + side_y * torso_side + torso_drop
        hip_center_x += dir_x * torso_fwd * 0.38 + side_x * torso_side * 0.3
        hip_center_y += (
            dir_y * torso_fwd * 0.38
            + side_y * torso_side * 0.3
            + torso_drop * 0.45
        )
        neck_x += dir_x * head_fwd * 0.55 + side_x * head_side * 0.55
        neck_y += (
            dir_y * head_fwd * 0.55
            + side_y * head_side * 0.55
            + head_drop * 0.55
        )
        head_center_x += dir_x * head_fwd + side_x * head_side
        head_center_y += dir_y * head_fwd + side_y * head_side + head_drop

        # Guard-up idle hand pose (boxing stance) instead of hanging arms.
        guard_lift = 1.0 - clamp(f.duck_pose * 0.5, 0.0, 0.5)
        lead_hand = (
            torso_center_x + side_x * (shoulder_half * lead_sign * 0.8) + dir_x * (7.0 * scale),
            torso_center_y - (10.0 * scale * guard_lift) + side_y * (shoulder_half * lead_sign * 0.8),
        )
        rear_hand = (
            torso_center_x + side_x * (shoulder_half * rear_sign * 0.8) + dir_x * (4.0 * scale),
            torso_center_y - (9.0 * scale * guard_lift) + side_y * (shoulder_half * rear_sign * 0.8),
        )
        if f.action == "dodge" or f.duck_pose > 0.05:
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

        # Split the rib cage and pelvis into slightly different centers so
        # the torso doesn't read as one rigid plank. The rib cage follows the
        # shoulder-side lean more, while the pelvis keeps more of the hip
        # drive, producing a small counter-twist through the waist.
        rib_center_x = torso_center_x + side_x * torso_lean_side * 0.12 + dir_x * 0.7 * scale
        rib_center_y = torso_center_y - 0.45 * scale
        pelvis_shift = hip_turn * 0.18 - torso_lean_side * 0.08
        pelvis_center_x = hip_center_x - side_x * pelvis_shift + dir_x * 0.45 * scale
        pelvis_center_y = hip_center_y + 0.9 * scale
        rib_center_x -= dir_x * 1.15 * scale * duck_tuck
        rib_center_y += 1.35 * scale * duck_tuck
        pelvis_center_x -= dir_x * 0.85 * scale * duck_tuck
        pelvis_center_y += 0.95 * scale * duck_tuck
        guard_brace = clamp(guard_ratio, 0.0, 1.0)
        stagger_brace = clamp(f.stagger / max(STAGGER_LOCK, 1e-6), 0.0, 1.0)
        impact_brace = max(stagger_brace, clamp(f.hit_flash * 5.0, 0.0, 1.0))
        brace = max(guard_brace * 0.72, impact_brace)
        if brace > 0.0:
            rib_center_x -= dir_x * (0.85 * scale * guard_brace + 1.8 * scale * impact_brace)
            rib_center_y += 0.35 * scale * guard_brace + 0.95 * scale * impact_brace
            pelvis_center_x -= dir_x * (0.45 * scale * guard_brace + 1.1 * scale * impact_brace)
            pelvis_center_y += 0.25 * scale * guard_brace + 0.65 * scale * impact_brace
            head_center_x -= dir_x * (0.5 * scale * guard_brace + 1.2 * scale * impact_brace)
            head_center_y += 0.2 * scale * guard_brace + 0.6 * scale * impact_brace

        lead_shoulder = (
            rib_center_x + side_x * shoulder_half * lead_sign + dir_x * 0.95 * scale * duck_tuck,
            rib_center_y + side_y * shoulder_half * lead_sign,
        )
        rear_shoulder = (
            rib_center_x + side_x * shoulder_half * rear_sign + dir_x * 0.95 * scale * duck_tuck,
            rib_center_y + side_y * shoulder_half * rear_sign,
        )

        if strike_arm is not None and profile is not None:
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
        elif duck_tuck > 0.0:
            # Ducking should read as curling the whole frame inward, not just
            # translating downward. Pull both gloves slightly across the face
            # and in toward the sternum so the posture looks compact.
            lead_hand = (
                lead_hand[0] - dir_x * (1.5 * scale * duck_tuck) - side_x * (0.8 * scale * duck_tuck),
                lead_hand[1] + 0.55 * scale * duck_tuck,
            )
            rear_hand = (
                rear_hand[0] - dir_x * (1.2 * scale * duck_tuck) + side_x * (0.8 * scale * duck_tuck),
                rear_hand[1] + 0.85 * scale * duck_tuck,
            )

        # Fist/knuckle facing: defaults to "forward" (a natural guard-fist
        # orientation) and only the currently-striking hand rotates to the
        # punch-specific direction from its profile, so straight punches
        # visibly point at the target, hooks rotate through their arc, and
        # uppercuts rotate upward as they rise.
        lead_knuckle = (dir_x, dir_y)
        rear_knuckle = (dir_x, dir_y)
        if strike_arm is not None and profile is not None:
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
        if duck_tuck > 0.0 and strike_arm is None:
            lead_elbow = (
                lerp(lead_elbow[0], rib_center_x + side_x * shoulder_half * lead_sign * 0.36 + dir_x * 2.3 * scale, duck_tuck),
                lerp(lead_elbow[1], rib_center_y + 4.6 * scale, duck_tuck),
            )
            rear_elbow = (
                lerp(rear_elbow[0], rib_center_x + side_x * shoulder_half * rear_sign * 0.36 + dir_x * 2.0 * scale, duck_tuck),
                lerp(rear_elbow[1], rib_center_y + 5.0 * scale, duck_tuck),
            )

        left_hip = (
            pelvis_center_x + side_x * (hip_half + 0.7 * scale * brace) * lead_sign + dir_x * (0.5 * scale - 0.35 * scale * brace),
            pelvis_center_y + side_y * hip_half * lead_sign,
        )
        right_hip = (
            pelvis_center_x + side_x * (hip_half + 0.7 * scale * brace) * rear_sign + dir_x * (0.5 * scale - 0.35 * scale * brace),
            pelvis_center_y + side_y * hip_half * rear_sign,
        )

        if duck_tuck > 0.0:
            # A readable duck needs the lower body to collapse with the torso:
            # hips sink a bit, stance widens, knees travel forward, and the
            # feet stay planted wider under the body instead of remaining in
            # the taller idle stance.
            left_hip = (
                left_hip[0] + side_x * (-1.0 * scale * duck_tuck) - dir_x * 0.45 * scale * duck_tuck,
                left_hip[1] + 0.9 * scale * duck_tuck,
            )
            right_hip = (
                right_hip[0] + side_x * (1.0 * scale * duck_tuck) - dir_x * 0.45 * scale * duck_tuck,
                right_hip[1] + 0.9 * scale * duck_tuck,
            )

        stance_drop = 1.0 + back_ratio * 0.3 + guard_ratio * 0.45 + impact_brace * 0.55
        duck_fold = duck_tuck

        # Lead foot pivots and lifts its heel on lead-hand strikes (jab is
        # barely affected since its pivot amount is tiny, but hooks/uppercuts
        # thrown with the lead hand visibly turn on the front foot).
        lead_knee = (
            left_hip[0] + dir_x * (2.2 * scale + 2.0 * scale * lead_pivot - 0.8 * scale * duck_tuck) + side_x * (-1.8 * scale - 2.0 * scale * lead_pivot - 0.9 * scale * duck_tuck),
            left_hip[1] + dir_y * (2.2 * scale + 2.0 * scale * lead_pivot) + (10.4 * scale * stance_drop),
        )
        lead_foot = (
            left_hip[0] + dir_x * (5.2 * scale + 3.0 * scale * lead_pivot - 1.3 * scale * duck_tuck) + side_x * (-2.8 * scale - 3.5 * scale * lead_pivot - 0.8 * scale * duck_tuck),
            left_hip[1] + dir_y * (5.2 * scale + 3.0 * scale * lead_pivot) + (18.2 * scale * stance_drop) - (3.0 * scale * lead_pivot),
        )

        # Rear foot pivots and lifts its heel on rear-hand strikes for a
        # believable weight-transfer / hip-drive read.
        rear_knee = (
            right_hip[0] + dir_x * (0.2 * scale + 2.0 * scale * rear_pivot - 0.7 * scale * duck_tuck) + side_x * (1.8 * scale + 2.0 * scale * rear_pivot + 0.9 * scale * duck_tuck),
            right_hip[1] + dir_y * (0.2 * scale + 2.0 * scale * rear_pivot) + (10.4 * scale * stance_drop),
        )
        rear_foot = (
            right_hip[0] + dir_x * (1.8 * scale + 3.0 * scale * rear_pivot - 1.1 * scale * duck_tuck) + side_x * (2.9 * scale + 3.5 * scale * rear_pivot + 0.8 * scale * duck_tuck),
            right_hip[1] + dir_y * (1.8 * scale + 3.0 * scale * rear_pivot) + (18.2 * scale * stance_drop) - (3.0 * scale * rear_pivot),
        )

        if duck_fold > 0.0:
            duck_asym = 0.75 * scale * duck_fold
            crouched_lead_knee = (
                left_hip[0] + dir_x * (4.45 * scale + 1.3 * scale * lead_pivot) + side_x * (-3.55 * scale - 1.7 * scale * lead_pivot - duck_asym * 0.55),
                left_hip[1] + 8.0 * scale + 0.35 * scale * brace + duck_asym * 0.22,
            )
            crouched_rear_knee = (
                right_hip[0] + dir_x * (3.9 * scale + 1.3 * scale * rear_pivot) + side_x * (3.05 * scale + 1.7 * scale * rear_pivot + duck_asym * 0.35),
                right_hip[1] + 8.45 * scale + 0.45 * scale * brace - duck_asym * 0.1,
            )
            crouched_lead_foot = (
                left_hip[0] + dir_x * (4.25 * scale + 2.0 * scale * lead_pivot) + side_x * (-5.15 * scale - 2.1 * scale * lead_pivot - duck_asym * 0.5),
                left_hip[1] + 13.45 * scale + 0.2 * scale * guard_brace + duck_asym * 0.1,
            )
            crouched_rear_foot = (
                right_hip[0] + dir_x * (3.85 * scale + 2.0 * scale * rear_pivot) + side_x * (4.8 * scale + 2.1 * scale * rear_pivot + duck_asym * 0.3),
                right_hip[1] + 13.9 * scale + 0.35 * scale * brace - duck_asym * 0.08,
            )
            lead_knee = (
                lerp(lead_knee[0], crouched_lead_knee[0], duck_fold),
                lerp(lead_knee[1], crouched_lead_knee[1], duck_fold),
            )
            rear_knee = (
                lerp(rear_knee[0], crouched_rear_knee[0], duck_fold),
                lerp(rear_knee[1], crouched_rear_knee[1], duck_fold),
            )
            lead_foot = (
                lerp(lead_foot[0], crouched_lead_foot[0], duck_fold),
                lerp(lead_foot[1], crouched_lead_foot[1], duck_fold),
            )
            rear_foot = (
                lerp(rear_foot[0], crouched_rear_foot[0], duck_fold),
                lerp(rear_foot[1], crouched_rear_foot[1], duck_fold),
            )

        if brace > 0.0:
            lead_knee = (
                lead_knee[0] - dir_x * (0.7 * scale * guard_brace + 0.6 * scale * impact_brace) + side_x * (-0.55 * scale * brace),
                lead_knee[1] + 0.45 * scale * brace,
            )
            rear_knee = (
                rear_knee[0] - dir_x * (0.7 * scale * guard_brace + 1.15 * scale * impact_brace) + side_x * (0.55 * scale * brace),
                rear_knee[1] + 0.6 * scale * brace,
            )
            lead_foot = (
                lead_foot[0] - dir_x * (0.8 * scale * guard_brace + 0.6 * scale * impact_brace) + side_x * (-1.0 * scale * brace),
                lead_foot[1] + 0.25 * scale * guard_brace,
            )
            rear_foot = (
                rear_foot[0] - dir_x * (1.2 * scale * guard_brace + 1.8 * scale * impact_brace) + side_x * (1.2 * scale * brace),
                rear_foot[1] + 0.45 * scale * brace,
            )

        if move_weight > 0.03 and f.action_t >= f.action_dur and f.stagger <= 0.0:
            lead_step = gait
            rear_step = -gait
            stride_dir = 1.0 if move_forward >= 0.0 else -1.0
            forward_amp = (3.0 + 4.6 * abs(move_forward)) * scale * move_weight
            side_amp = (1.5 + 3.2 * abs(move_side)) * scale * move_weight
            bounce = abs(gait_cos) * 0.9 * scale * move_weight

            rib_center_y += bounce * 0.4
            pelvis_center_y += bounce * 0.7
            head_center_y += bounce * 0.28

            lead_knee = (
                lead_knee[0] + dir_x * (lead_step * forward_amp * 0.55 * stride_dir) + side_x * (lead_step * side_amp * 0.45 * move_side),
                lead_knee[1] + 0.55 * scale * abs(lead_step) * move_weight,
            )
            rear_knee = (
                rear_knee[0] + dir_x * (rear_step * forward_amp * 0.55 * stride_dir) + side_x * (rear_step * side_amp * 0.45 * move_side),
                rear_knee[1] + 0.55 * scale * abs(rear_step) * move_weight,
            )
            lead_foot = (
                lead_foot[0] + dir_x * (lead_step * forward_amp * stride_dir) + side_x * (lead_step * side_amp * move_side),
                lead_foot[1] - 1.3 * scale * max(0.0, lead_step) * move_weight,
            )
            rear_foot = (
                rear_foot[0] + dir_x * (rear_step * forward_amp * stride_dir) + side_x * (rear_step * side_amp * move_side),
                rear_foot[1] - 1.3 * scale * max(0.0, rear_step) * move_weight,
            )

            if strike_arm is None and duck_tuck < 0.12:
                lead_hand = (
                    lead_hand[0] + dir_x * (rear_step * forward_amp * 0.28 * stride_dir) - side_x * (rear_step * side_amp * 0.18 * move_side),
                    lead_hand[1] + 0.35 * scale * abs(rear_step) * move_weight,
                )
                rear_hand = (
                    rear_hand[0] + dir_x * (lead_step * forward_amp * 0.28 * stride_dir) - side_x * (lead_step * side_amp * 0.18 * move_side),
                    rear_hand[1] + 0.35 * scale * abs(lead_step) * move_weight,
                )

        limb_w = max(3, int(4.8 * scale))
        # Upper limbs (bicep/thigh) render thicker than lower limbs
        # (forearm/shin), tapering at the elbow/knee - a plain constant
        # width read as a soft, boneless noodle-arm; this bulge is the
        # cheapest way to suggest actual muscle mass on a stick-figure rig.
        leg_upper_w = max(5, int(limb_w * 1.48))
        leg_lower_w = max(3, int(limb_w * 0.98))
        arm_upper_w = max(4, int(limb_w * 1.22))
        arm_lower_w = max(3, int(limb_w * 0.88))
        neck_w = max(3, int(4.4 * scale))

        # Legs and feet render first (behind torso).
        self.draw_tapered_limb(left_hip[0], left_hip[1], lead_knee[0], lead_knee[1], leg_upper_w * 0.98, leg_upper_w * 0.64, body_dark, outline)
        self.draw_tapered_limb(lead_knee[0], lead_knee[1], lead_foot[0], lead_foot[1], leg_lower_w * 0.98, leg_lower_w * 0.56, body, outline)
        self.draw_joint(lead_knee[0], lead_knee[1], 2.6 * scale, body_dark, outline)
        self.draw_foot(lead_foot[0], lead_foot[1], dir_x, dir_y, scale, shoe, outline)

        self.draw_tapered_limb(right_hip[0], right_hip[1], rear_knee[0], rear_knee[1], leg_upper_w * 0.98, leg_upper_w * 0.64, body_dark, outline)
        self.draw_tapered_limb(rear_knee[0], rear_knee[1], rear_foot[0], rear_foot[1], leg_lower_w * 0.98, leg_lower_w * 0.56, body, outline)
        self.draw_joint(rear_knee[0], rear_knee[1], 2.6 * scale, body_dark, outline)
        self.draw_foot(rear_foot[0], rear_foot[1], dir_x, dir_y, scale, shoe, outline)

        # Tapered torso (broad shoulders, narrower waist) reads more human
        # than a plain circle and shows the hip/shoulder counter-rotation.
        rib_half = 7.45 * scale
        waist_half = 5.35 * scale
        pelvis_half = hip_half * 1.08
        torso_top_y = rib_center_y - 1.0 * scale
        torso_rib_y = rib_center_y + 3.1 * scale
        torso_waist_y = pelvis_center_y + 0.8 * scale
        torso_poly = [
            lead_shoulder[0] + side_x * 1.6 * scale, lead_shoulder[1] + side_y * 1.6 * scale,
            rib_center_x + side_x * rib_half * lead_sign + dir_x * 1.4 * scale, torso_rib_y + side_y * rib_half * lead_sign,
            pelvis_center_x + side_x * waist_half * lead_sign, torso_waist_y + side_y * waist_half * lead_sign,
            pelvis_center_x + side_x * waist_half * rear_sign, torso_waist_y + side_y * waist_half * rear_sign,
            rib_center_x + side_x * rib_half * rear_sign + dir_x * 1.4 * scale, torso_rib_y + side_y * rib_half * rear_sign,
            rear_shoulder[0] + side_x * 1.6 * scale, rear_shoulder[1] + side_y * 1.6 * scale,
        ]
        self.canvas.create_polygon(torso_poly, fill=outline, outline="", width=0)
        inset = 1.08
        torso_poly_inner = [
            lead_shoulder[0] + side_x * 1.25 * scale * inset, lead_shoulder[1] + side_y * 1.25 * scale * inset,
            rib_center_x + side_x * rib_half * lead_sign * 0.9, torso_rib_y + side_y * rib_half * lead_sign * 0.9,
            pelvis_center_x + side_x * waist_half * lead_sign * 0.92, torso_waist_y + side_y * waist_half * lead_sign * 0.92,
            pelvis_center_x + side_x * waist_half * rear_sign * 0.92, torso_waist_y + side_y * waist_half * rear_sign * 0.92,
            rib_center_x + side_x * rib_half * rear_sign * 0.9, torso_rib_y + side_y * rib_half * rear_sign * 0.9,
            rear_shoulder[0] + side_x * 1.25 * scale * inset, rear_shoulder[1] + side_y * 1.25 * scale * inset,
        ]
        self.canvas.create_polygon(torso_poly_inner, fill=body, outline="")

        pelvis_poly = [
            pelvis_center_x + side_x * pelvis_half * lead_sign, pelvis_center_y - 1.8 * scale + side_y * pelvis_half * lead_sign,
            pelvis_center_x + side_x * pelvis_half * rear_sign, pelvis_center_y - 1.8 * scale + side_y * pelvis_half * rear_sign,
            pelvis_center_x + side_x * hip_half * 0.86 * rear_sign, pelvis_center_y + 4.0 * scale + side_y * hip_half * 0.86 * rear_sign,
            pelvis_center_x + side_x * hip_half * 0.86 * lead_sign, pelvis_center_y + 4.0 * scale + side_y * hip_half * 0.86 * lead_sign,
        ]
        self.canvas.create_polygon(pelvis_poly, fill=skin_shadow, outline=outline, width=1)

        lat_shade = mix_color(body_dark, body, 0.42)
        self.canvas.create_line(
            rib_center_x + side_x * rib_half * 0.78 * lead_sign,
            torso_top_y,
            pelvis_center_x + side_x * waist_half * 0.72 * lead_sign,
            torso_waist_y - 1.0 * scale,
            fill=lat_shade,
            width=max(1, int(1.15 * scale)),
        )
        self.canvas.create_line(
            rib_center_x + side_x * rib_half * 0.78 * rear_sign,
            torso_top_y,
            pelvis_center_x + side_x * waist_half * 0.72 * rear_sign,
            torso_waist_y - 1.0 * scale,
            fill=lat_shade,
            width=max(1, int(1.15 * scale)),
        )

        # Ab/pec shading: a couple of subtle crease lines across the belly
        # plus a sternum centerline, all in a tone between the outline and
        # body colors so it reads as muscle definition, not a hard stripe.
        shade = mix_color(outline, body, 0.4)
        ab_half = waist_half * 0.62
        for ab_off in (2.4 * scale, 5.6 * scale):
            self.canvas.create_line(
                pelvis_center_x + side_x * ab_half * rear_sign, pelvis_center_y + side_y * ab_half * rear_sign - 8.0 * scale + ab_off,
                pelvis_center_x + side_x * ab_half * lead_sign, pelvis_center_y + side_y * ab_half * lead_sign - 8.0 * scale + ab_off,
                fill=shade, width=max(1, int(1.1 * scale)),
            )
        self.canvas.create_line(
            rib_center_x + dir_x * 0.6 * scale, rib_center_y - 6.1 * scale,
            rib_center_x + dir_x * 0.6 * scale, rib_center_y + 1.8 * scale,
            fill=shade, width=max(1, int(1.0 * scale)),
        )
        self.canvas.create_line(
            lead_shoulder[0] + dir_x * 0.8 * scale,
            lead_shoulder[1] + dir_y * 0.8 * scale,
            neck_x,
            neck_y + 0.2 * scale,
            fill=shade,
            width=max(1, int(1.0 * scale)),
        )
        self.canvas.create_line(
            rear_shoulder[0] + dir_x * 0.8 * scale,
            rear_shoulder[1] + dir_y * 0.8 * scale,
            neck_x,
            neck_y + 0.2 * scale,
            fill=shade,
            width=max(1, int(1.0 * scale)),
        )
        trap_col = mix_color(body_dark, body, 0.34)
        trap_left = (
            lead_shoulder[0] + dir_x * 0.55 * scale,
            lead_shoulder[1] + dir_y * 0.55 * scale,
        )
        trap_right = (
            rear_shoulder[0] + dir_x * 0.55 * scale,
            rear_shoulder[1] + dir_y * 0.55 * scale,
        )
        trap_top = (
            neck_x - dir_x * 0.2 * scale,
            neck_y + 0.45 * scale,
        )
        trap_poly = [
            trap_left[0], trap_left[1],
            trap_top[0], trap_top[1],
            trap_right[0], trap_right[1],
            rib_center_x + dir_x * 0.65 * scale,
            rib_center_y - 1.2 * scale,
        ]
        self.canvas.create_polygon(trap_poly, fill=trap_col, outline="")

        # Shorts are merged into the upper legs instead of being a hanging
        # rectangle over the whole pelvis, so the thighs stay readable.
        short_drop = 0.44
        lead_short_end = (
            left_hip[0] + (lead_knee[0] - left_hip[0]) * short_drop,
            left_hip[1] + (lead_knee[1] - left_hip[1]) * short_drop,
        )
        rear_short_end = (
            right_hip[0] + (rear_knee[0] - right_hip[0]) * short_drop,
            right_hip[1] + (rear_knee[1] - right_hip[1]) * short_drop,
        )
        self.draw_tapered_limb(left_hip[0], left_hip[1], lead_short_end[0], lead_short_end[1], leg_upper_w * 0.92, leg_upper_w * 0.68, trunks, outline)
        self.draw_tapered_limb(right_hip[0], right_hip[1], rear_short_end[0], rear_short_end[1], leg_upper_w * 0.92, leg_upper_w * 0.68, trunks, outline)
        self.canvas.create_line(
            left_hip[0] + side_x * 0.8 * scale,
            left_hip[1] + side_y * 0.8 * scale,
            right_hip[0] + side_x * -0.8 * scale,
            right_hip[1] + side_y * -0.8 * scale,
            fill=trunks_trim,
            width=max(1, int(2.2 * scale)),
        )
        self.canvas.create_line(
            left_hip[0] + side_x * 0.7 * scale,
            left_hip[1] + side_y * 0.7 * scale,
            lead_short_end[0] + side_x * 0.18 * scale,
            lead_short_end[1] + side_y * 0.18 * scale,
            fill=trunks_trim,
            width=max(1, int(1.45 * scale)),
        )
        self.canvas.create_line(
            right_hip[0] - side_x * 0.7 * scale,
            right_hip[1] - side_y * 0.7 * scale,
            rear_short_end[0] - side_x * 0.18 * scale,
            rear_short_end[1] - side_y * 0.18 * scale,
            fill=trunks_trim,
            width=max(1, int(1.45 * scale)),
        )
        short_center = [
            left_hip[0] + dir_x * 0.9 * scale,
            left_hip[1] + 0.6 * scale,
            right_hip[0] + dir_x * 0.9 * scale,
            right_hip[1] + 0.6 * scale,
            rear_short_end[0] + dir_x * 0.45 * scale,
            rear_short_end[1] + 1.0 * scale,
            lead_short_end[0] + dir_x * 0.45 * scale,
            lead_short_end[1] + 1.0 * scale,
        ]
        self.canvas.create_polygon(short_center, fill=cloth_shadow, outline="")
        self.draw_joint(pelvis_center_x, pelvis_center_y + 1.9 * scale, 2.2 * scale, trunks_trim, outline)

        # Neck bridges the head to the torso so it never looks detached.
        self.draw_bone(neck_x, neck_y, head_center_x, head_center_y - 3.0 * scale, neck_w, skin, outline)

        # Wrist joints sit just short of the glove, splitting what used to be
        # a single forearm-to-glove bone into forearm + a short hand segment.
        # This gives each arm one more readable link in the chain and lets
        # the glove itself rotate independently at the wrist.
        hand_w = max(2, int(limb_w * 0.9))
        lead_wrist = (
            lead_elbow[0] + (lead_hand[0] - lead_elbow[0]) * 0.78,
            lead_elbow[1] + (lead_hand[1] - lead_elbow[1]) * 0.78,
        )
        rear_wrist = (
            rear_elbow[0] + (rear_hand[0] - rear_elbow[0]) * 0.78,
            rear_elbow[1] + (rear_hand[1] - rear_elbow[1]) * 0.78,
        )

        # Arms rendered over the torso for clear attack reads.
        self.draw_joint(lead_shoulder[0], lead_shoulder[1], 4.25 * scale, body_dark, outline)
        self.draw_tapered_limb(lead_shoulder[0], lead_shoulder[1], lead_elbow[0], lead_elbow[1], arm_upper_w * 0.92, arm_upper_w * 0.6, body_dark, outline)
        self.draw_joint(lead_elbow[0], lead_elbow[1], 2.4 * scale, body_dark, outline)
        self.draw_tapered_limb(lead_elbow[0], lead_elbow[1], lead_wrist[0], lead_wrist[1], arm_lower_w * 0.98, arm_lower_w * 0.56, body, outline)
        self.draw_joint(lead_wrist[0], lead_wrist[1], 1.8 * scale, body, outline)
        self.draw_bone(lead_wrist[0], lead_wrist[1], lead_hand[0], lead_hand[1], hand_w, skin, outline)

        self.draw_joint(rear_shoulder[0], rear_shoulder[1], 4.25 * scale, body_dark, outline)
        self.draw_tapered_limb(rear_shoulder[0], rear_shoulder[1], rear_elbow[0], rear_elbow[1], arm_upper_w * 0.92, arm_upper_w * 0.6, body_dark, outline)
        self.draw_joint(rear_elbow[0], rear_elbow[1], 2.4 * scale, body_dark, outline)
        self.draw_tapered_limb(rear_elbow[0], rear_elbow[1], rear_wrist[0], rear_wrist[1], arm_lower_w * 0.98, arm_lower_w * 0.56, body, outline)
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
        head_r = 6.5 * scale
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
        self.canvas.create_line(
            head_center_x - side_x * head_r * 0.82 - dir_x * head_r * 0.18,
            head_center_y - head_r * 0.08,
            head_center_x + side_x * head_r * 0.82 - dir_x * head_r * 0.18,
            head_center_y - head_r * 0.08,
            smooth=True,
            fill=hair_color,
            width=max(1, int(1.35 * scale)),
        )
        self.canvas.create_line(
            head_center_x - side_x * head_r * 0.9 - dir_x * head_r * 0.34,
            head_center_y - head_r * 0.18,
            head_center_x - side_x * head_r * 0.95 - dir_x * head_r * 0.1,
            head_center_y + head_r * 0.26,
            fill=hair_color,
            width=max(1, int(1.45 * scale)),
        )
        self.canvas.create_line(
            head_center_x + side_x * head_r * 0.9 - dir_x * head_r * 0.34,
            head_center_y - head_r * 0.18,
            head_center_x + side_x * head_r * 0.95 - dir_x * head_r * 0.1,
            head_center_y + head_r * 0.26,
            fill=hair_color,
            width=max(1, int(1.45 * scale)),
        )
        ear_x = head_center_x - side_x * head_r * 0.98 - dir_x * head_r * 0.18
        ear_y = head_center_y - dir_y * head_r * 0.08
        self.canvas.create_oval(
            ear_x - 1.1 * scale,
            ear_y - 1.8 * scale,
            ear_x + 1.1 * scale,
            ear_y + 1.8 * scale,
            fill=skin_shadow,
            outline=outline,
        )
        jaw_x0 = head_center_x - side_x * head_r * 0.78
        jaw_y0 = head_center_y + head_r * 0.35
        jaw_x1 = head_center_x + dir_x * head_r * 0.45
        jaw_y1 = head_center_y + head_r * 0.78
        jaw_x2 = head_center_x + side_x * head_r * 0.4
        jaw_y2 = head_center_y + head_r * 0.48
        self.canvas.create_line(
            [(jaw_x0, jaw_y0), (jaw_x1, jaw_y1), (jaw_x2, jaw_y2)],
            smooth=True,
            fill=skin_shadow,
            width=max(1, int(1.55 * scale)),
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
        nose_x = head_center_x + dir_x * (head_r * 0.56)
        nose_y = head_center_y + dir_y * (head_r * 0.24)
        self.canvas.create_line(
            nose_x,
            nose_y - 1.2 * scale,
            nose_x + side_x * 0.9 * scale,
            nose_y + 0.9 * scale,
            fill=skin_shadow,
            width=max(1, int(1.0 * scale)),
        )
        mouth_x = head_center_x + dir_x * (head_r * 0.22)
        mouth_y = head_center_y + head_r * 0.72
        self.canvas.create_line(
            mouth_x - side_x * 1.35 * scale,
            mouth_y - side_y * 0.25 * scale,
            mouth_x + side_x * 1.35 * scale,
            mouth_y + side_y * 0.25 * scale,
            fill=skin_shadow,
            width=max(1, int(0.95 * scale)),
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

    def draw_meter(self, x, y, width, height, ratio, color, align="left"):
        ratio = clamp(ratio, 0.0, 1.0)
        self.canvas.create_rectangle(
            x, y, x + width, y + height,
            fill="#0a1020", outline="#31476d", width=1,
        )
        fill_width = max(0.0, (width - 4) * ratio)
        if align == "right":
            x0, x1 = x + width - 2 - fill_width, x + width - 2
        else:
            x0, x1 = x + 2, x + 2 + fill_width
        if fill_width > 0:
            self.canvas.create_rectangle(
                x0, y + 2, x1, y + height - 2,
                fill=color, outline="",
            )
            self.canvas.create_line(
                x0, y + 3, x1, y + 3,
                fill=mix_color(color, WHITE, 0.48), width=1,
            )

    def draw_center_panel(self, title, lines, width=600):
        lines = list(lines)
        line_height = 24
        panel_height = 82 + line_height * len(lines)
        x0 = (WIDTH - width) / 2
        y0 = (HEIGHT - panel_height) / 2
        self.canvas.create_rectangle(
            x0, y0, x0 + width, y0 + panel_height,
            fill="#080f1f", outline="#5578ab", width=2,
        )
        self.canvas.create_rectangle(
            x0 + 2, y0 + 2, x0 + width - 2, y0 + 48,
            fill="#13233d", outline="",
        )
        self.canvas.create_text(
            WIDTH / 2, y0 + 25,
            fill=GOLD, font=("Helvetica", 21, "bold"), text=title,
        )
        for index, line in enumerate(lines):
            self.canvas.create_text(
                WIDTH / 2, y0 + 67 + index * line_height,
                fill=WHITE if index == 0 else GRAY,
                font=("Helvetica", 12, "bold" if index == 0 else "normal"),
                text=line,
            )

    def draw_modal(self):
        if self.modal_view == "pause":
            self.draw_center_panel(
                "PAUSED",
                (
                    "P / ESC   Resume",
                    "H   Controls",
                    "O   Settings",
                    "R   Restart Match",
                ),
                width=500,
            )
        elif self.modal_view == "controls":
            self.draw_center_panel(
                "CONTROLS",
                (
                    "ARROWS   Move / circle",
                    "A   Jab        D   Cross",
                    "Q / E   Duck left / right",
                    "S   Backstep        W   Guard",
                    "Q+A Left body     Q+D Right hook",
                    "E+A Left hook     E+D Right body",
                    "W+A Left upper    W+D Right upper",
                    "H / ESC   Back",
                ),
                width=660,
            )
        elif self.modal_view == "settings":
            on_off = lambda enabled: "ON" if enabled else "OFF"
            self.draw_center_panel(
                "SETTINGS",
                (
                    f"1   Sound             {on_off(self.settings.sound_enabled)}",
                    f"2   Commentary        {on_off(self.settings.commentary_enabled)}",
                    f"3   Camera shake      {on_off(self.settings.camera_shake_enabled)}",
                    "O / ESC   Back",
                ),
                width=540,
            )

    def draw_hud(self):
        # Broadcast-style top strip: both corners mirror each other while the
        # round clock stays centered and readable during movement.
        self.canvas.create_rectangle(0, 0, WIDTH, 82, fill="#060c18", outline="")
        self.canvas.create_line(0, 82, WIDTH, 82, fill="#263a5d", width=2)

        self.canvas.create_text(20, 15, anchor="w", fill=PLAYER_COLOR, font=("Helvetica", 11, "bold"), text="BLUE CORNER  PLAYER")
        self.canvas.create_text(WIDTH - 20, 15, anchor="e", fill=ENEMY_COLOR, font=("Helvetica", 11, "bold"), text="ENEMY  RED CORNER")
        self.draw_meter(20, 27, 330, 17, self.player.hp / self.player.max_hp, GREEN)
        self.draw_meter(WIDTH - 350, 27, 330, 17, self.enemy.hp / self.enemy.max_hp, RED, align="right")
        self.draw_meter(20, 50, 250, 9, self.player.stamina / self.player.max_stamina, GOLD)
        self.draw_meter(WIDTH - 270, 50, 250, 9, self.enemy.stamina / self.enemy.max_stamina, GOLD, align="right")
        self.canvas.create_text(356, 35, anchor="w", fill=WHITE, font=("Helvetica", 10, "bold"), text=f"{self.player.hp:03d}")
        self.canvas.create_text(WIDTH - 356, 35, anchor="e", fill=WHITE, font=("Helvetica", 10, "bold"), text=f"{self.enemy.hp:03d}")
        self.canvas.create_text(276, 55, anchor="w", fill=GRAY, font=("Helvetica", 9), text=f"ST {int(self.player.stamina):03d}")
        self.canvas.create_text(WIDTH - 276, 55, anchor="e", fill=GRAY, font=("Helvetica", 9), text=f"ST {int(self.enemy.stamina):03d}")

        self.canvas.create_oval(WIDTH / 2 - 45, 7, WIDTH / 2 + 45, 73, fill="#101d33", outline="#5578ab", width=2)
        self.canvas.create_text(WIDTH / 2, 29, fill=GOLD, font=("Helvetica", 20, "bold"), text=f"{int(math.ceil(self.round_time)):02d}")
        self.canvas.create_text(WIDTH / 2, 51, fill=WHITE, font=("Helvetica", 9, "bold"), text=f"ROUND {self.round}")
        self.canvas.create_text(WIDTH / 2, 65, fill=GRAY, font=("Helvetica", 8), text=f"AI READ {self.ai_learning_percent():03d}%")

        if self.feedback_timer > 0:
            self.canvas.create_text(WIDTH / 2, 100, fill=GOLD, font=("Helvetica", 14, "bold"), text=self.feedback_text)

        if self.commentary_timer > 0:
            bar_top = HEIGHT - 46
            self.canvas.create_rectangle(0, bar_top, WIDTH, HEIGHT, fill="#050a16", outline="")
            self.canvas.create_line(0, bar_top, WIDTH, bar_top, fill="#2b3e63", width=1)
            self.canvas.create_text(
                WIDTH / 2, HEIGHT - 23,
                fill=GOLD, font=("Helvetica", 14, "italic bold"),
                text=self.commentary_text,
            )
        elif self.modal_view is None:
            self.canvas.create_text(
                WIDTH - 12, HEIGHT - 10, anchor="e",
                fill="#63799d", font=("Helvetica", 8),
                text="P PAUSE   H CONTROLS   O SETTINGS",
            )

        if self.modal_view is None and self.state == "round_intro":
            if self.round_transition_timer > 0.42:
                title, body = f"ROUND {self.round}", "READY"
            else:
                title, body = "FIGHT!", ""
            self.draw_center_panel(title, (body,), width=420)
        elif (
            self.modal_view is None
            and self.state != "fight"
            and self.round_result_delay <= 0.0
        ):
            self.draw_center_panel(self.overlay_title, (self.overlay_body,), width=620)

        self.draw_modal()

    def tick(self):
        if not self._running:
            return
        now = time.perf_counter()
        real_dt = frame_delta(self._last_tick_time, now)
        self._last_tick_time = now
        dt = real_dt
        if self.modal_view is None:
            if self.hitstop_timer > 0:
                # Real-time countdown for how long the freeze lasts, but the
                # game itself runs at a crawl while it's active - a brief,
                # near-total pause reads as "the punch actually landed" instead
                # of the hp bar just silently ticking down mid-swing.
                self.hitstop_timer = max(0.0, self.hitstop_timer - real_dt)
                dt *= 0.12
            self.update_round_transition(real_dt)
            self.update(dt)
        self.draw_arena()
        actors = [self.player, self.enemy]
        actors.sort(key=lambda actor: self.project_world(actor.x, actor.y)[3], reverse=True)
        for actor in actors:
            self.draw_fighter(actor)
        self.draw_ring_ropes(foreground=True)
        self.draw_particles()
        self.draw_hud()
        if self._running:
            self._tick_after_id = self.root.after(16, self.tick)

    def close(self):
        if not getattr(self, "_running", False):
            return
        self._running = False
        after_id = getattr(self, "_tick_after_id", None)
        if after_id is not None:
            try:
                self.root.after_cancel(after_id)
            except tk.TclError:
                pass
            self._tick_after_id = None
        try:
            self.root.destroy()
        except tk.TclError:
            pass

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    TopDownPrototype().run()