"""Pure combat data and headless simulation for Pixel Boxing Top-Down.

This module deliberately has no tkinter dependency. The live game imports the
same attack table and attack-start function used by the simulator, so tests,
reinforcement-learning experiments, and the UI cannot silently drift apart.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from typing import Callable, Iterable

ROUND_LIMIT = 3
ROUND_SECONDS = 45.0

WHIFF_RECOVERY = 0.22
EXPOSED_DMG_MULT = 1.4
STAGGER_LOCK = 0.16
STALE_THRESHOLD = 2
STALE_DECAY = 0.85
STALE_FLOOR = 0.5
GUARD_DAMAGE_MULT = 0.4
DUCK_EVADE_THRESHOLD = 0.5
MAX_FRAME_DT = 0.05

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

DUCK_EVADE_KEY = {
    "jab": "e",
    "left_hook": "e",
    "left_uppercut": "e",
    "cross": "q",
    "right_hook": "q",
    "right_uppercut": "q",
}


@dataclass(frozen=True)
class AttackSpec:
    action_dur: float
    active_a: float
    active_b: float
    damage: int
    attack_range: float
    half_angle_deg: float
    stamina_cost: int
    target_zone: str
    fist_radius: float


ATTACK_SPECS = {
    "jab": AttackSpec(0.24, 0.08, 0.15, 6, 78.0, 26.0, 6, "head", 5.0),
    "cross": AttackSpec(0.34, 0.14, 0.24, 11, 60.0, 20.0, 11, "head", 5.4),
    "left_body": AttackSpec(0.32, 0.12, 0.22, 9, 54.0, 40.0, 9, "body", 5.2),
    "right_body": AttackSpec(0.35, 0.14, 0.24, 10, 56.0, 38.0, 10, "body", 5.4),
    "left_hook": AttackSpec(0.36, 0.16, 0.26, 11, 50.0, 56.0, 11, "head", 5.6),
    "right_hook": AttackSpec(0.38, 0.17, 0.28, 12, 52.0, 50.0, 12, "head", 5.8),
    "left_uppercut": AttackSpec(0.40, 0.18, 0.30, 13, 44.0, 26.0, 13, "head", 5.4),
    "right_uppercut": AttackSpec(0.42, 0.19, 0.31, 14, 46.0, 24.0, 14, "head", 5.8),
}

RL_ACTIONS = (
    "wait",
    "approach",
    "retreat",
    "circle_left",
    "circle_right",
    "guard",
    "duck_left",
    "duck_right",
    "backstep",
    *ATTACK_ACTIONS,
)

REWARD_VALUES = {
    "damage_dealt": 1.0,
    "damage_taken": -1.2,
    "ko_win": 100.0,
    "ko_loss": -100.0,
    "round_win": 40.0,
    "round_loss": -40.0,
    "duck_evade": 4.0,
    "backstep_evade": 3.0,
    "guard": 1.5,
    "counter": 6.0,
    "whiff": -3.0,
    "staggered": -4.0,
    "stale_repeat": -1.0,
    "invalid_action": -1.0,
    "cornered": -0.1,
    "idle": -0.05,
}


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def frame_delta(previous: float, current: float) -> float:
    """Return real elapsed time without allowing one stalled frame to jump."""

    return clamp(current - previous, 0.0, MAX_FRAME_DT)


def diagnose_fighter(actor: object) -> tuple[str, ...]:
    """Return human-readable invariant violations for tests/debug logging."""

    errors: list[str] = []
    if not (0 <= actor.hp <= actor.max_hp):
        errors.append(f"hp_out_of_bounds:{actor.hp}/{actor.max_hp}")
    if not (0.0 <= actor.stamina <= actor.max_stamina):
        errors.append(f"stamina_out_of_bounds:{actor.stamina}/{actor.max_stamina}")
    if not all(math.isfinite(value) for value in (actor.x, actor.y, actor.facing_x, actor.facing_y)):
        errors.append("non_finite_position_or_facing")
    if actor.action != "idle" and actor.action not in ATTACK_SPECS and actor.action != "dodge":
        errors.append(f"unknown_action:{actor.action}")
    if actor.action_t < 0 or actor.action_dur < 0:
        errors.append("negative_action_time")
    return tuple(errors)


@dataclass(frozen=True)
class AttackStartResult:
    started: bool
    stale_stage: int = 0
    reason: str = ""


def try_start_attack(actor: object, name: str) -> AttackStartResult:
    """Configure an actor for an attack using the canonical attack table.

    The actor is intentionally duck-typed. Both the Tk Fighter dataclass and
    HeadlessFighter expose these fields, which keeps this function reusable
    without making the UI inherit from simulation classes.
    """

    if name not in ATTACK_SPECS:
        return AttackStartResult(False, reason="unknown_attack")
    if actor.action_t < actor.action_dur:
        return AttackStartResult(False, reason="busy")
    if actor.stagger > 0:
        return AttackStartResult(False, reason="staggered")

    spec = ATTACK_SPECS[name]
    if actor.stamina < spec.stamina_cost:
        return AttackStartResult(False, reason="low_stamina")

    if actor.streak_action == name:
        actor.streak_count += 1
    else:
        actor.streak_action = name
        actor.streak_count = 1

    stale_stage = max(0, actor.streak_count - STALE_THRESHOLD)
    stale_mult = max(STALE_FLOOR, STALE_DECAY**stale_stage)

    actor.action = name
    actor.action_t = 0.0
    actor.acted = False
    actor.whiff_penalized = False
    actor.action_dur = spec.action_dur
    actor.active_a = spec.active_a
    actor.active_b = spec.active_b
    actor.damage = max(1, int(round(spec.damage * stale_mult)))
    actor.range = spec.attack_range
    actor.half_angle_deg = spec.half_angle_deg
    actor.stamina = clamp(actor.stamina - spec.stamina_cost, 0.0, actor.max_stamina)
    return AttackStartResult(True, stale_stage=stale_stage)


@dataclass(frozen=True)
class StrikeGeometry:
    """A swept circular fist hitbox shared by future gameplay and rendering."""

    start: tuple[float, float]
    end: tuple[float, float]
    radius: float
    target_zone: str
    action: str
    phase: float


@dataclass(frozen=True)
class Hurtbox:
    center: tuple[float, float]
    radius: float
    zone: str


@dataclass(frozen=True)
class ContactPoint:
    point: tuple[float, float]
    zone: str
    distance: float


def _closest_point_on_segment(
    point: tuple[float, float],
    start: tuple[float, float],
    end: tuple[float, float],
) -> tuple[tuple[float, float], float]:
    sx, sy = start
    ex, ey = end
    px, py = point
    dx, dy = ex - sx, ey - sy
    length_sq = dx * dx + dy * dy
    if length_sq <= 1e-12:
        return start, math.hypot(px - sx, py - sy)
    t = clamp(((px - sx) * dx + (py - sy) * dy) / length_sq, 0.0, 1.0)
    closest = (sx + dx * t, sy + dy * t)
    return closest, math.hypot(px - closest[0], py - closest[1])


def strike_contact(strike: StrikeGeometry, hurtbox: Hurtbox) -> ContactPoint | None:
    """Return the physical contact point for a swept fist/hurtbox overlap."""

    if strike.target_zone != hurtbox.zone:
        return None
    point, distance = _closest_point_on_segment(hurtbox.center, strike.start, strike.end)
    if distance > strike.radius + hurtbox.radius:
        return None
    return ContactPoint(point=point, zone=hurtbox.zone, distance=distance)


def first_strike_contact(
    strike: StrikeGeometry, hurtboxes: Iterable[Hurtbox]
) -> ContactPoint | None:
    contacts = [contact for box in hurtboxes if (contact := strike_contact(strike, box))]
    return min(contacts, key=lambda item: item.distance, default=None)


@dataclass
class HeadlessFighter:
    name: str
    x: float
    y: float
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
    exposed: float = 0.0
    stagger: float = 0.0
    whiff_penalized: bool = False
    streak_action: str = ""
    streak_count: int = 0
    defense: str = "wait"


@dataclass(frozen=True)
class RewardEvent:
    actor: str
    kind: str
    amount: float
    value: float = 1.0


@dataclass(frozen=True)
class CombatObservation:
    distance_bucket: str
    angle_bucket: str
    own_hp_bucket: int
    opponent_hp_bucket: int
    own_stamina_bucket: int
    opponent_stamina_bucket: int
    own_action: str
    opponent_action: str
    own_exposed: bool
    opponent_exposed: bool
    own_staggered: bool
    opponent_staggered: bool
    wall_bucket: str
    time_bucket: int

    def as_key(self) -> tuple[object, ...]:
        return tuple(self.__dict__.values())


@dataclass(frozen=True)
class StepResult:
    player_observation: CombatObservation
    enemy_observation: CombatObservation
    player_reward: float
    enemy_reward: float
    done: bool
    events: tuple[RewardEvent, ...]


@dataclass
class HeadlessCombatSimulator:
    """Deterministic, render-free combat environment for tests and RL work.

    It intentionally models the existing distance/cone combat first. The
    StrikeGeometry interface above is already available for the later phase
    where the live game and simulator switch to swept-fist contacts together.
    """

    seed: int = 0
    decision_dt: float = 0.05
    player: HeadlessFighter = field(init=False)
    enemy: HeadlessFighter = field(init=False)
    round_time: float = field(init=False, default=ROUND_SECONDS)
    done: bool = field(init=False, default=False)
    winner: str | None = field(init=False, default=None)
    _rng: random.Random = field(init=False)

    ARENA_MIN = 70.0
    ARENA_MAX = 520.0
    MOVE_STEP = 8.0
    DUCK_DISTANCE = 34.0
    BACKSTEP_DISTANCE = 38.0

    def __post_init__(self) -> None:
        self._rng = random.Random(self.seed)
        self.reset()

    def reset(self) -> tuple[CombatObservation, CombatObservation]:
        self.player = HeadlessFighter("player", 170.0, 295.0)
        self.enemy = HeadlessFighter("enemy", 420.0, 295.0, facing_x=-1.0)
        self.round_time = ROUND_SECONDS
        self.done = False
        self.winner = None
        self._update_facing()
        return self.observe(self.player, self.enemy), self.observe(self.enemy, self.player)

    def valid_actions(self, actor: HeadlessFighter) -> dict[str, bool]:
        free = actor.action_t >= actor.action_dur and actor.stagger <= 0
        return {
            action: (
                action == "wait"
                or free
                and (
                    action not in ATTACK_SPECS
                    or actor.stamina >= ATTACK_SPECS[action].stamina_cost
                )
            )
            for action in RL_ACTIONS
        }

    def observe(
        self, actor: HeadlessFighter, opponent: HeadlessFighter
    ) -> CombatObservation:
        distance = math.hypot(opponent.x - actor.x, opponent.y - actor.y)
        if distance > ATTACK_SPECS["jab"].attack_range + opponent.radius:
            distance_bucket = "far"
        elif distance > ATTACK_SPECS["cross"].attack_range + opponent.radius:
            distance_bucket = "jab"
        elif distance > ATTACK_SPECS["left_hook"].attack_range + opponent.radius:
            distance_bucket = "straight"
        elif distance > 34.0:
            distance_bucket = "close"
        else:
            distance_bucket = "clinch"

        to_opponent = _normalized(opponent.x - actor.x, opponent.y - actor.y)
        cross = actor.facing_x * to_opponent[1] - actor.facing_y * to_opponent[0]
        dot = actor.facing_x * to_opponent[0] + actor.facing_y * to_opponent[1]
        angle = math.degrees(math.atan2(cross, dot))
        angle_bucket = "front" if abs(angle) <= 20 else "left" if angle < 0 else "right"

        wall_distance = min(
            actor.x - self.ARENA_MIN,
            self.ARENA_MAX - actor.x,
            actor.y - self.ARENA_MIN,
            self.ARENA_MAX - actor.y,
        )
        wall_bucket = "corner" if wall_distance < 35 else "ropes" if wall_distance < 75 else "center"

        return CombatObservation(
            distance_bucket,
            angle_bucket,
            _resource_bucket(actor.hp, actor.max_hp),
            _resource_bucket(opponent.hp, opponent.max_hp),
            _resource_bucket(actor.stamina, actor.max_stamina),
            _resource_bucket(opponent.stamina, opponent.max_stamina),
            actor.action,
            opponent.action,
            actor.exposed > 0,
            opponent.exposed > 0,
            actor.stagger > 0,
            opponent.stagger > 0,
            wall_bucket,
            int(self.round_time // 10),
        )

    def step(self, player_action: str, enemy_action: str) -> StepResult:
        if self.done:
            raise RuntimeError("step() called after episode completion")

        events: list[RewardEvent] = []
        self._update_facing()
        self._apply_decision(self.player, self.enemy, player_action, events)
        self._apply_decision(self.enemy, self.player, enemy_action, events)
        self._advance_actor(self.player, self.enemy, events)
        self._advance_actor(self.enemy, self.player, events)
        self._update_facing()

        self.round_time = max(0.0, self.round_time - self.decision_dt)
        if self.player.hp <= 0 or self.enemy.hp <= 0 or self.round_time <= 0:
            self._finish_episode(events)

        player_reward = sum(event.amount for event in events if event.actor == "player")
        enemy_reward = sum(event.amount for event in events if event.actor == "enemy")
        return StepResult(
            self.observe(self.player, self.enemy),
            self.observe(self.enemy, self.player),
            player_reward,
            enemy_reward,
            self.done,
            tuple(events),
        )

    def run_episode(
        self,
        player_policy: Callable[[CombatObservation, dict[str, bool]], str],
        enemy_policy: Callable[[CombatObservation, dict[str, bool]], str],
        max_steps: int = 2_000,
    ) -> str:
        self.reset()
        for _ in range(max_steps):
            player_action = player_policy(
                self.observe(self.player, self.enemy), self.valid_actions(self.player)
            )
            enemy_action = enemy_policy(
                self.observe(self.enemy, self.player), self.valid_actions(self.enemy)
            )
            result = self.step(player_action, enemy_action)
            if result.done:
                return self.winner or "draw"
        self.done = True
        self.winner = "draw"
        return "draw"

    def _apply_decision(
        self,
        actor: HeadlessFighter,
        opponent: HeadlessFighter,
        action: str,
        events: list[RewardEvent],
    ) -> None:
        if action not in RL_ACTIONS or not self.valid_actions(actor).get(action, False):
            events.append(_reward(actor.name, "invalid_action"))
            return

        actor.defense = action if action in {"guard", "duck_left", "duck_right", "backstep"} else "wait"
        if action in ATTACK_SPECS:
            started = try_start_attack(actor, action)
            if started.stale_stage:
                events.append(
                    RewardEvent(
                        actor.name,
                        "stale_repeat",
                        REWARD_VALUES["stale_repeat"] * started.stale_stage,
                        started.stale_stage,
                    )
                )
            return

        if action == "wait":
            if actor.action_t >= actor.action_dur:
                events.append(_reward(actor.name, "idle"))
            return

        forward = _normalized(opponent.x - actor.x, opponent.y - actor.y)
        side = (-forward[1], forward[0])
        if action == "approach":
            self._move(actor, forward, self.MOVE_STEP)
        elif action == "retreat":
            self._move(actor, forward, -self.MOVE_STEP)
        elif action == "circle_left":
            self._move(actor, side, self.MOVE_STEP)
        elif action == "circle_right":
            self._move(actor, side, -self.MOVE_STEP)
        elif action in {"duck_left", "duck_right"}:
            # The headless environment models directional duck as a defense
            # state, not permanent locomotion. The live game may animate a
            # lateral shift, but hit eligibility remains strict by key.
            pass
        elif action == "backstep":
            self._move(actor, forward, -self.BACKSTEP_DISTANCE)
            actor.invuln = max(actor.invuln, 0.10)

    def _advance_actor(
        self,
        actor: HeadlessFighter,
        defender: HeadlessFighter,
        events: list[RewardEvent],
    ) -> None:
        dt = self.decision_dt
        actor.stamina = clamp(actor.stamina + dt * 17.0, 0.0, actor.max_stamina)
        actor.invuln = max(0.0, actor.invuln - dt)
        actor.exposed = max(0.0, actor.exposed - dt)
        actor.stagger = max(0.0, actor.stagger - dt)

        if actor.action_t >= actor.action_dur:
            return

        previous_t = actor.action_t
        actor.action_t += dt
        active_crossed = previous_t <= actor.active_b and actor.action_t >= actor.active_a
        if actor.action in ATTACK_SPECS and not actor.acted and active_crossed:
            actor.acted = self._attempt_hit(actor, defender, events)

        if actor.action_t >= actor.action_dur:
            if actor.action in ATTACK_SPECS and not actor.acted and not actor.whiff_penalized:
                actor.action_dur += WHIFF_RECOVERY
                actor.whiff_penalized = True
                actor.exposed = WHIFF_RECOVERY + 0.05
                events.append(_reward(actor.name, "whiff"))
            else:
                actor.action = "idle"

    def _attempt_hit(
        self,
        attacker: HeadlessFighter,
        defender: HeadlessFighter,
        events: list[RewardEvent],
    ) -> bool:
        if defender.invuln > 0:
            events.append(_reward(defender.name, "backstep_evade"))
            return False

        dx, dy = defender.x - attacker.x, defender.y - attacker.y
        distance = math.hypot(dx, dy)
        if distance > attacker.range + defender.radius:
            return False
        target = _normalized(dx, dy)
        dot = attacker.facing_x * target[0] + attacker.facing_y * target[1]
        if dot < math.cos(math.radians(attacker.half_angle_deg)):
            return False

        needed_duck = DUCK_EVADE_KEY.get(attacker.action)
        actual_duck = "q" if defender.defense == "duck_left" else "e" if defender.defense == "duck_right" else None
        if needed_duck and actual_duck == needed_duck:
            events.append(_reward(defender.name, "duck_evade"))
            return False

        punished_whiff = defender.exposed > 0
        damage = attacker.damage
        if punished_whiff:
            damage = int(round(damage * EXPOSED_DMG_MULT))
            events.append(_reward(attacker.name, "counter"))

        if defender.defense == "guard":
            damage = max(1, int(round(damage * GUARD_DAMAGE_MULT)))
            events.append(_reward(defender.name, "guard"))

        interrupted = defender.action in ATTACK_SPECS and defender.action_t < defender.action_dur and not defender.acted
        if interrupted:
            defender.action = "idle"
            defender.action_t = 0.0
            defender.action_dur = 0.0
            events.append(_reward(defender.name, "staggered"))

        defender.hp = int(clamp(defender.hp - damage, 0, defender.max_hp))
        defender.stagger = STAGGER_LOCK * (1.5 if interrupted else 1.0)
        defender.streak_count = 0
        events.append(RewardEvent(attacker.name, "damage_dealt", damage * REWARD_VALUES["damage_dealt"], damage))
        events.append(RewardEvent(defender.name, "damage_taken", damage * REWARD_VALUES["damage_taken"], damage))
        return True

    def _finish_episode(self, events: list[RewardEvent]) -> None:
        self.done = True
        if self.player.hp == self.enemy.hp:
            self.winner = "draw"
            return
        self.winner = "player" if self.player.hp > self.enemy.hp else "enemy"
        loser = "enemy" if self.winner == "player" else "player"
        ko = self.player.hp <= 0 or self.enemy.hp <= 0
        events.append(_reward(self.winner, "ko_win" if ko else "round_win"))
        events.append(_reward(loser, "ko_loss" if ko else "round_loss"))

    def _move(
        self, actor: HeadlessFighter, direction: tuple[float, float], amount: float
    ) -> None:
        actor.x = clamp(
            actor.x + direction[0] * amount,
            self.ARENA_MIN + actor.radius,
            self.ARENA_MAX - actor.radius,
        )
        actor.y = clamp(
            actor.y + direction[1] * amount,
            self.ARENA_MIN + actor.radius,
            self.ARENA_MAX - actor.radius,
        )

    def _update_facing(self) -> None:
        px, py = _normalized(self.enemy.x - self.player.x, self.enemy.y - self.player.y)
        self.player.facing_x, self.player.facing_y = px, py
        self.enemy.facing_x, self.enemy.facing_y = -px, -py


def _normalized(x: float, y: float) -> tuple[float, float]:
    magnitude = math.hypot(x, y)
    if magnitude <= 1e-9:
        return (1.0, 0.0)
    return (x / magnitude, y / magnitude)


def _resource_bucket(value: float, maximum: float) -> int:
    return min(4, int(clamp(value / max(maximum, 1e-9), 0.0, 0.999999) * 5))


def _reward(actor: str, kind: str) -> RewardEvent:
    return RewardEvent(actor, kind, REWARD_VALUES[kind])
