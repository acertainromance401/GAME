import pathlib
import sys
import tempfile
import unittest
import wave
from types import SimpleNamespace

ROOT = pathlib.Path(__file__).resolve().parents[1]
DESKTOP_GAME = ROOT / "desktop-pixel-boxing"
sys.path.insert(0, str(DESKTOP_GAME))

from audio_feedback import SOUND_LIBRARY, SoundManager, write_tone_wav  # noqa: E402
from game_settings import GameSettings  # noqa: E402
from pixel_boxing_topdown import TopDownPrototype  # noqa: E402


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
        game = TopDownPrototype.__new__(TopDownPrototype)
        game.modal_view = None
        game.modal_keys = set()
        game.keys = {"up", "q", "s"}
        game.player_duck_target = -1.0
        game.player_back_target = 1.0
        game._last_tick_time = 0.0
        game.settings = GameSettings()
        game.settings.save = lambda path=None: True
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
        self.game.play_sound = lambda name, min_interval=0.035: sounds.append(name)
        self.game.update_round_transition(0.02)
        self.assertEqual(self.game.state, "fight")
        self.assertEqual(sounds, ["round_bell"])
        self.assertIn("Round 2 fight.", self.game.log_messages)

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


if __name__ == "__main__":
    unittest.main()
