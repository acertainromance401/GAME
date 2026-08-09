import math
import pathlib
import random
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
DESKTOP_GAME = ROOT / "desktop-pixel-boxing"
sys.path.insert(0, str(DESKTOP_GAME))

from boxing_core import (  # noqa: E402
    ATTACK_ACTIONS,
    ATTACK_SPECS,
    HeadlessCombatSimulator,
    HeadlessFighter,
    Hurtbox,
    RL_ACTIONS,
    StrikeGeometry,
    diagnose_fighter,
    frame_delta,
    first_strike_contact,
    try_start_attack,
)
from pixel_boxing_topdown import (  # noqa: E402
    COMMENTARY_LINES,
    Fighter,
    TopDownPrototype,
)


class AttackSpecTests(unittest.TestCase):
    def test_all_eight_attacks_keep_canonical_values(self):
        expected = {
            "jab": (0.24, 0.08, 0.15, 6, 78.0, 26.0, 6),
            "cross": (0.34, 0.14, 0.24, 11, 60.0, 20.0, 11),
            "left_body": (0.32, 0.12, 0.22, 9, 54.0, 40.0, 9),
            "right_body": (0.35, 0.14, 0.24, 10, 56.0, 38.0, 10),
            "left_hook": (0.36, 0.16, 0.26, 11, 50.0, 56.0, 11),
            "right_hook": (0.38, 0.17, 0.28, 12, 52.0, 50.0, 12),
            "left_uppercut": (0.40, 0.18, 0.30, 13, 44.0, 26.0, 13),
            "right_uppercut": (0.42, 0.19, 0.31, 14, 46.0, 24.0, 14),
        }
        self.assertEqual(set(ATTACK_ACTIONS), set(expected))
        for name, values in expected.items():
            spec = ATTACK_SPECS[name]
            actual = (
                spec.action_dur,
                spec.active_a,
                spec.active_b,
                spec.damage,
                spec.attack_range,
                spec.half_angle_deg,
                spec.stamina_cost,
            )
            self.assertEqual(actual, values, name)

    def test_attack_start_applies_spec_and_stamina(self):
        fighter = HeadlessFighter("player", 0.0, 0.0)
        result = try_start_attack(fighter, "cross")
        self.assertTrue(result.started)
        self.assertEqual(fighter.action, "cross")
        self.assertEqual(fighter.damage, 11)
        self.assertEqual(fighter.range, 60.0)
        self.assertEqual(fighter.half_angle_deg, 20.0)
        self.assertEqual(fighter.stamina, 89.0)

    def test_repeating_same_move_stales_from_third_use(self):
        fighter = HeadlessFighter("player", 0.0, 0.0)
        damages = []
        stages = []
        for _ in range(5):
            fighter.action_t = fighter.action_dur
            fighter.stamina = fighter.max_stamina
            result = try_start_attack(fighter, "jab")
            damages.append(fighter.damage)
            stages.append(result.stale_stage)
        self.assertEqual(stages, [0, 0, 1, 2, 3])
        self.assertEqual(damages, [6, 6, 5, 4, 4])

    def test_low_stamina_rejects_attack_without_mutation(self):
        fighter = HeadlessFighter("player", 0.0, 0.0, stamina=5.0)
        result = try_start_attack(fighter, "jab")
        self.assertFalse(result.started)
        self.assertEqual(result.reason, "low_stamina")
        self.assertEqual(fighter.action, "idle")


class DiagnosticsTests(unittest.TestCase):
    def test_frame_delta_uses_real_elapsed_time_and_clamps_stalls(self):
        self.assertAlmostEqual(frame_delta(10.0, 10.016), 0.016)
        self.assertEqual(frame_delta(10.0, 10.5), 0.05)
        self.assertEqual(frame_delta(10.0, 9.0), 0.0)

    def test_fighter_diagnostics_report_invalid_state(self):
        fighter = HeadlessFighter("broken", math.nan, 0.0, hp=101, stamina=-1.0)
        fighter.action = "teleport"
        errors = diagnose_fighter(fighter)
        self.assertTrue(any(error.startswith("hp_out_of_bounds") for error in errors))
        self.assertTrue(any(error.startswith("stamina_out_of_bounds") for error in errors))
        self.assertIn("non_finite_position_or_facing", errors)
        self.assertIn("unknown_action:teleport", errors)

    def test_fighter_diagnostics_accept_normal_state(self):
        self.assertEqual(diagnose_fighter(HeadlessFighter("ok", 100.0, 100.0)), ())


class StrikeGeometryTests(unittest.TestCase):
    def test_swept_fist_hits_matching_hurtbox_at_contact_point(self):
        strike = StrikeGeometry((0.0, 0.0), (10.0, 0.0), 2.0, "head", "jab", 0.5)
        head = Hurtbox((8.0, 2.5), 1.0, "head")
        contact = first_strike_contact(strike, [head])
        self.assertIsNotNone(contact)
        self.assertEqual(contact.zone, "head")
        self.assertAlmostEqual(contact.point[0], 8.0)
        self.assertAlmostEqual(contact.point[1], 0.0)

    def test_target_zone_prevents_head_strike_from_hitting_body(self):
        strike = StrikeGeometry((0.0, 0.0), (10.0, 0.0), 3.0, "head", "jab", 0.5)
        body = Hurtbox((8.0, 0.0), 3.0, "body")
        self.assertIsNone(first_strike_contact(strike, [body]))

    def test_swept_fist_misses_distant_hurtbox(self):
        strike = StrikeGeometry((0.0, 0.0), (10.0, 0.0), 2.0, "head", "jab", 0.5)
        head = Hurtbox((8.0, 4.1), 2.0, "head")
        self.assertIsNone(first_strike_contact(strike, [head]))


class HeadlessSimulatorTests(unittest.TestCase):
    def setUp(self):
        self.sim = HeadlessCombatSimulator(seed=7)

    def _put_in_range(self):
        self.sim.player.x, self.sim.player.y = 200.0, 295.0
        self.sim.enemy.x, self.sim.enemy.y = 250.0, 295.0
        self.sim._update_facing()

    def test_rl_action_space_has_seventeen_actions_and_masks_low_stamina(self):
        self.assertEqual(len(RL_ACTIONS), 17)
        self.sim.player.stamina = 0.0
        mask = self.sim.valid_actions(self.sim.player)
        self.assertTrue(mask["wait"])
        self.assertTrue(mask["approach"])
        for attack in ATTACK_ACTIONS:
            self.assertFalse(mask[attack], attack)

    def test_jab_lands_and_emits_damage_rewards(self):
        self._put_in_range()
        self.sim.step("jab", "wait")
        result = self.sim.step("wait", "wait")
        kinds = {(event.actor, event.kind) for event in result.events}
        self.assertIn(("player", "damage_dealt"), kinds)
        self.assertIn(("enemy", "damage_taken"), kinds)
        self.assertEqual(self.sim.enemy.hp, 94)

    def test_correct_direction_duck_evades_jab(self):
        self._put_in_range()
        self.sim.step("wait", "jab")
        result = self.sim.step("duck_right", "wait")
        self.assertIn("duck_evade", [event.kind for event in result.events])
        self.assertEqual(self.sim.player.hp, 100)

    def test_wrong_direction_duck_does_not_evade_jab(self):
        self._put_in_range()
        self.sim.step("wait", "jab")
        result = self.sim.step("duck_left", "wait")
        self.assertNotIn("duck_evade", [event.kind for event in result.events])
        self.assertLess(self.sim.player.hp, 100)

    def test_guard_reduces_cross_damage(self):
        self._put_in_range()
        self.sim.step("wait", "cross")
        self.sim.step("guard", "wait")
        result = self.sim.step("guard", "wait")
        self.assertIn("guard", [event.kind for event in result.events])
        self.assertEqual(self.sim.player.hp, 96)

    def test_far_attack_becomes_whiff_and_exposes_attacker(self):
        events = []
        result = self.sim.step("jab", "wait")
        events.extend(result.events)
        for _ in range(5):
            result = self.sim.step("wait", "wait")
            events.extend(result.events)
        self.assertIn("whiff", [event.kind for event in events])
        self.assertTrue(self.sim.player.whiff_penalized)
        self.assertGreater(self.sim.player.exposed, 0.0)

    def test_counter_hit_gets_bonus_damage_and_reward(self):
        self._put_in_range()
        self.sim.enemy.exposed = 0.3
        self.sim.step("cross", "wait")
        self.sim.step("wait", "wait")
        result = self.sim.step("wait", "wait")
        self.assertIn("counter", [event.kind for event in result.events])
        self.assertEqual(self.sim.enemy.hp, 85)

    def test_episode_runs_without_renderer(self):
        def policy(observation, mask):
            if observation.distance_bucket == "far" and mask["approach"]:
                return "approach"
            if mask["jab"]:
                return "jab"
            return "wait"

        winner = self.sim.run_episode(policy, policy, max_steps=1_100)
        self.assertIn(winner, {"player", "enemy", "draw"})
        self.assertTrue(self.sim.done)


class LiveGameRegressionTests(unittest.TestCase):
    def setUp(self):
        game = TopDownPrototype.__new__(TopDownPrototype)
        game.player = Fighter("Player", 200.0, 295.0, "#65d1ff")
        game.enemy = Fighter("Enemy", 250.0, 295.0, "#ff6b8f", facing_x=-1.0)
        game.keys = set()
        game.duck_max = 34.0
        game.player_duck_offset = 0.0
        game.player_duck_world_x = 0.0
        game.player_duck_world_y = 0.0
        game.hitstop_timer = 0.0
        game.shake_timer = 0.0
        game.shake_mag = 0.0
        game.particles = []
        game.feedback_text = ""
        game.commentary_text = ""
        game.show_feedback = lambda text: setattr(game, "feedback_text", text)
        game.show_commentary = lambda *args, **kwargs: None
        game.spawn_hit_particles = lambda *args, **kwargs: None
        game.end_round = lambda *args, **kwargs: None
        self.game = game

    def _configure_attack(self, attacker, name):
        attacker.action_t = attacker.action_dur
        attacker.stamina = attacker.max_stamina
        self.assertTrue(self.game.start_attack(attacker, name))

    def test_live_game_uses_core_attack_specs_for_all_moves(self):
        for name in ATTACK_ACTIONS:
            fighter = Fighter("Player", 0.0, 0.0, "#fff")
            self.assertTrue(self.game.start_attack(fighter, name))
            spec = ATTACK_SPECS[name]
            self.assertEqual(fighter.damage, spec.damage)
            self.assertEqual(fighter.range, spec.attack_range)
            self.assertEqual(fighter.half_angle_deg, spec.half_angle_deg)

    def test_live_correct_duck_evades_and_wrong_duck_is_hit(self):
        self._configure_attack(self.game.enemy, "jab")
        self.game.player_duck_offset = 34.0
        self.game.player_duck_world_y = -34.0
        self.game.player.y = 261.0
        self.assertFalse(self.game.attempt_hit(self.game.enemy, self.game.player))
        self.assertEqual(self.game.player.hp, 100)

        self.game.player_duck_offset = -34.0
        self.game.player_duck_world_y = 34.0
        self.game.player.y = 329.0
        self.assertTrue(self.game.attempt_hit(self.game.enemy, self.game.player))
        self.assertEqual(self.game.player.hp, 94)

    def test_live_guard_reduces_damage(self):
        self._configure_attack(self.game.enemy, "cross")
        self.game.keys = {"w"}
        self.assertTrue(self.game.attempt_hit(self.game.enemy, self.game.player))
        self.assertEqual(self.game.player.hp, 96)

    def test_live_far_miss_triggers_whiff_exposure(self):
        self.game.player.x = 170.0
        self.game.enemy.x = 420.0
        self._configure_attack(self.game.player, "jab")
        for _ in range(5):
            self.game.update_actor_timers(self.game.player, 0.05)
        self.assertTrue(self.game.player.whiff_penalized)
        self.assertGreater(self.game.player.exposed, 0.0)

    def test_live_counter_applies_bonus_damage(self):
        self._configure_attack(self.game.player, "cross")
        self.game.enemy.exposed = 0.3
        self.assertTrue(self.game.attempt_hit(self.game.player, self.game.enemy))
        self.assertEqual(self.game.enemy.hp, 85)

    def test_every_commentary_template_formats_without_key_error(self):
        for key, lines in COMMENTARY_LINES.items():
            for line in lines:
                with self.subTest(key=key, line=line):
                    text = line.format(atk="Player", def_="Enemy")
                    self.assertIsInstance(text, str)
                    self.assertTrue(text)


if __name__ == "__main__":
    random.seed(0)
    unittest.main()
