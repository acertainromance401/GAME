import pathlib
import sys
import tempfile
import unittest
import wave
from types import SimpleNamespace
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
DESKTOP_GAME = ROOT / "desktop-pixel-boxing"
sys.path.insert(0, str(DESKTOP_GAME))

from audio_feedback import SOUND_LIBRARY, SoundManager, write_tone_wav  # noqa: E402
from game_settings import GameSettings  # noqa: E402
from pixel_boxing_topdown import ARENA, FIGHTER_RING_MARGIN, Fighter, TopDownPrototype  # noqa: E402


class SettingsTests(unittest.TestCase):
    def test_settings_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "settings.json"
            settings = GameSettings(False, False, True)
            self.assertTrue(settings.save(path))
            self.assertEqual(GameSettings.load(path), settings)

    def test_invalid_settings_file_falls_back_to_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "settings.json"
            path.write_text("not-json", encoding="utf-8")
            self.assertEqual(GameSettings.load(path), GameSettings())

    def test_toggle_rejects_unknown_setting(self):
        with self.assertRaises(KeyError):
            GameSettings().toggle("unknown")


class AudioTests(unittest.TestCase):
    def test_every_sound_renders_as_valid_wav(self):
        with tempfile.TemporaryDirectory() as directory:
            for name, tones in SOUND_LIBRARY.items():
                with self.subTest(name=name):
                    path = pathlib.Path(directory) / f"{name}.wav"
                    write_tone_wav(path, tones)
                    with wave.open(str(path), "rb") as wav_file:
                        self.assertEqual(wav_file.getnchannels(), 1)
                        self.assertEqual(wav_file.getsampwidth(), 2)
                        self.assertGreater(wav_file.getnframes(), 0)

    def test_disabled_sound_manager_never_spawns_player(self):
        manager = SoundManager(enabled=False)
        self.assertFalse(manager.play("round_bell"))


class PhaseTwoUiStateTests(unittest.TestCase):
    def setUp(self):
        game: Any = TopDownPrototype.__new__(TopDownPrototype)
        game.modal_view = None
        game.modal_keys = set()
        game.keys = {"up", "q", "s"}
        game.player_duck_target = -1.0
        game.player_back_target = 1.0
        game._last_tick_time = 0.0
        game.back_max = 42.0
        game.back_smooth = 18.0
        game.player_back_offset = 0.0
        game.player_back_risk_applied = False
        game.player = Fighter("Player", 220.0, 220.0, "#65d1ff")
        game.settings = GameSettings()
        game.settings.save = lambda path=None: (path, True)[1]
        game.sound = SoundManager(enabled=False)
        game.commentary_text = "active"
        game.commentary_timer = 1.0
        game.shake_timer = 1.0
        game.shake_x = 2.0
        game.shake_y = -2.0
        game.round_transition_timer = 0.0
        game.state = "intro"
        game.log_messages = []
        game.push_log = game.log_messages.append
        self.game = game

    def test_open_modal_clears_live_inputs(self):
        self.game.open_modal("pause")
        self.assertEqual(self.game.modal_view, "pause")
        self.assertEqual(self.game.keys, set())
        self.assertEqual(self.game.player_duck_target, 0.0)
        self.assertEqual(self.game.player_back_target, 0.0)

    def test_fighter_position_keeps_full_sprite_inside_ring(self):
        x, y = self.game.clamp_fighter_to_ring(self.game.player, -100.0, 999.0)

        self.assertGreater(FIGHTER_RING_MARGIN, self.game.player.radius)
        self.assertEqual(x, ARENA[0] + FIGHTER_RING_MARGIN)
        self.assertEqual(y, ARENA[3] - FIGHTER_RING_MARGIN)

    def test_crowd_uses_one_canvas_item_per_spectator(self):
        calls = []
        game: Any = TopDownPrototype.__new__(TopDownPrototype)
        game.crowd_seats = [(100.0, 120.0, "#5f7394", 0)]
        game.project_world = lambda x, y: (x, y, 1.0, 0.0)
        game.sprite_scale = lambda perspective: perspective
        game.canvas = SimpleNamespace(
            create_line=lambda *args, **kwargs: calls.append((args, kwargs))
        )

        game.draw_crowd()

        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1]["capstyle"], "round")

    def test_close_cancels_scheduled_frame_once(self):
        cancelled = []
        destroyed = []
        self.game._running = True
        self.game._tick_after_id = "after#1"
        self.game.root = SimpleNamespace(
            after_cancel=cancelled.append,
            destroy=lambda: destroyed.append(True),
        )

        self.game.close()
        self.game.close()

        self.assertEqual(cancelled, ["after#1"])
        self.assertEqual(destroyed, [True])
        self.assertFalse(self.game._running)
        self.assertIsNone(self.game._tick_after_id)

    def test_invalid_modal_name_is_rejected(self):
        with self.assertRaises(ValueError):
            self.game.open_modal("inventory")

    def test_setting_toggles_apply_runtime_side_effects(self):
        self.assertTrue(self.game.toggle_setting("1"))
        self.assertFalse(self.game.settings.sound_enabled)
        self.assertFalse(self.game.sound.enabled)

        self.assertTrue(self.game.toggle_setting("2"))
        self.assertFalse(self.game.settings.commentary_enabled)
        self.assertEqual(self.game.commentary_timer, 0.0)
        self.assertEqual(self.game.commentary_text, "")

        self.assertTrue(self.game.toggle_setting("3"))
        self.assertFalse(self.game.settings.camera_shake_enabled)
        self.assertEqual(self.game.shake_timer, 0.0)
        self.assertEqual((self.game.shake_x, self.game.shake_y), (0.0, 0.0))

    def test_round_intro_transitions_to_fight_and_plays_bell(self):
        sounds = []
        self.game.state = "round_intro"
        self.game.round_transition_timer = 0.01
        self.game.round = 2
        self.game.play_sound = lambda name, min_interval=0.035: (min_interval, sounds.append(name))[1]
        self.game.update_round_transition(0.02)
        self.assertEqual(self.game.state, "fight")
        self.assertEqual(sounds, ["round_bell"])
        self.assertIn("Round 2 fight.", self.game.log_messages)

    def test_end_round_keeps_counting_rounds_without_match_cap(self):
        sounds = []
        self.game.state = "fight"
        self.game.round = 10
        self.game.score_player = 4
        self.game.score_enemy = 5
        self.game.enemy_adaptation = 0.64
        self.game.ensure_adaptation_state = lambda: None
        self.game.play_sound = lambda name, min_interval=0.035: (min_interval, sounds.append(name))[1]
        self.game.set_overlay = lambda title, body: setattr(self.game, "overlay", (title, body))

        self.game.end_round("enemy", "Time")

        self.assertEqual(self.game.state, "round_break")
        self.assertEqual(self.game.round, 11)
        self.assertEqual(self.game.score_enemy, 6)
        self.assertEqual(sounds, ["round_end"])
        self.assertEqual(self.game.round_result_delay, 0.0)
        self.assertEqual(self.game.overlay[0], "ROUND 10 - ENEMY (Time)")
        self.assertIn("AI READ 064%", self.game.overlay[1])
        self.assertIn("Space: next round", self.game.overlay[1])

    def test_ko_result_waits_for_knockdown_animation(self):
        sounds = []
        self.game.state = "fight"
        self.game.round = 4
        self.game.score_player = 1
        self.game.score_enemy = 1
        self.game.enemy_adaptation = 0.5
        self.game.ensure_adaptation_state = lambda: None
        self.game.play_sound = lambda name, min_interval=0.035: (min_interval, sounds.append(name))[1]
        self.game.set_overlay = lambda title, body: setattr(self.game, "overlay", (title, body))

        self.game.end_round("player", "KO")

        self.assertEqual(self.game.state, "round_break")
        self.assertEqual(self.game.round_result_delay, 1.25)
        self.assertEqual(sounds, [])
        self.assertEqual(self.game.overlay[0], "ROUND 4 - PLAYER (KO)")

    def test_commentary_setting_suppresses_new_caption(self):
        self.game.settings.commentary_enabled = False
        self.game.show_commentary("jab")
        self.assertEqual(self.game.commentary_text, "active")
        self.assertEqual(self.game.commentary_timer, 1.0)

    def test_ui_key_repeat_does_not_immediately_close_modal(self):
        self.game.state = "fight"
        h_event = SimpleNamespace(keysym="h")
        self.game.on_key_down(h_event)
        self.assertEqual(self.game.modal_view, "controls")

        # macOS/Tk key-repeat can emit another KeyPress before KeyRelease.
        self.game.on_key_down(h_event)
        self.assertEqual(self.game.modal_view, "controls")

        self.game.on_key_up(h_event)
        self.game.on_key_down(h_event)
        self.assertIsNone(self.game.modal_view)

    def test_pause_key_opens_pause_and_clears_gameplay_keys(self):
        self.game.state = "fight"
        self.game.keys = {"up", "a"}
        self.game.on_key_down(SimpleNamespace(keysym="p"))
        self.assertEqual(self.game.modal_view, "pause")
        self.assertEqual(self.game.keys, set())

    def test_backstep_key_repeat_does_not_refresh_invuln_or_double_spend_stamina(self):
        self.game.state = "fight"
        self.game.keys = set()
        self.game.player.stamina = 100.0
        self.game.player_back_target = 0.0
        press = SimpleNamespace(keysym="s")

        self.game.on_key_down(press)
        self.assertEqual(self.game.player.stamina, 69.0)
        self.game.player.invuln = 0.03

        self.game.on_key_down(press)
        self.assertEqual(self.game.player.stamina, 69.0)
        self.assertEqual(self.game.player.invuln, 0.03)

    def test_backstep_is_blocked_when_stamina_is_below_heavy_cost(self):
        self.game.state = "fight"
        self.game.keys = set()
        self.game.player.stamina = 30.0
        self.game.player_back_target = 0.0

        self.game.on_key_down(SimpleNamespace(keysym="s"))

        self.assertEqual(self.game.player.stamina, 30.0)
        self.assertEqual(self.game.player_back_target, 0.0)

    def test_backstep_release_creates_short_exposed_recovery_window(self):
        self.game.state = "fight"
        self.game.keys = set()
        self.game.player.stamina = 100.0
        self.game.player.invuln = 0.0
        self.game.player.exposed = 0.0
        self.game.player_back_target = 0.0
        self.game.player_back_offset = self.game.back_max * 0.5
        self.game.player_back_risk_applied = False

        self.game.update_player_backstep(0.016)

        self.assertGreaterEqual(self.game.player.exposed, 0.16)
        self.assertTrue(self.game.player_back_risk_applied)

    def test_spending_last_backstep_stamina_triggers_exhaustion_lock(self):
        self.game.state = "fight"
        self.game.keys = set()
        self.game.player.stamina = 31.0
        self.game.player_back_target = 0.0

        self.game.on_key_down(SimpleNamespace(keysym="s"))

        self.assertEqual(self.game.player.stamina, 0.0)
        self.assertGreater(self.game.player.exhausted, 0.0)
        self.assertGreaterEqual(self.game.player.exposed, 0.28)

    def test_exhausted_player_cannot_move_or_attack(self):
        self.game.state = "fight"
        self.game.keys = {"up"}
        self.game.player.exhausted = 0.4
        self.game.player_stance_x = self.game.player.x
        self.game.player_stance_y = self.game.player.y
        start = (self.game.player.x, self.game.player.y)

        self.game.update_player_movement(0.1)
        self.game.on_key_down(SimpleNamespace(keysym="a"))

        self.assertEqual((self.game.player.x, self.game.player.y), start)
        self.assertEqual(self.game.player.action, "idle")


if __name__ == "__main__":
    unittest.main()
