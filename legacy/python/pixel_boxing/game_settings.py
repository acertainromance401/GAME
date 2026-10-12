"""Persistent user-facing settings for Pixel Boxing Top-Down."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass
class GameSettings:
    sound_enabled: bool = True
    commentary_enabled: bool = True
    camera_shake_enabled: bool = True

    @classmethod
    def load(cls, path: Path | None = None) -> "GameSettings":
        settings_path = path or default_settings_path()
        try:
            raw = json.loads(settings_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, TypeError):
            return cls()

        defaults = cls()
        return cls(
            sound_enabled=_bool_value(raw, "sound_enabled", defaults.sound_enabled),
            commentary_enabled=_bool_value(
                raw, "commentary_enabled", defaults.commentary_enabled
            ),
            camera_shake_enabled=_bool_value(
                raw, "camera_shake_enabled", defaults.camera_shake_enabled
            ),
        )

    def save(self, path: Path | None = None) -> bool:
        settings_path = path or default_settings_path()
        try:
            settings_path.parent.mkdir(parents=True, exist_ok=True)
            settings_path.write_text(
                json.dumps(asdict(self), ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
        except OSError:
            return False
        return True

    def toggle(self, name: str) -> bool:
        if name not in {
            "sound_enabled",
            "commentary_enabled",
            "camera_shake_enabled",
        }:
            raise KeyError(name)
        value = not getattr(self, name)
        setattr(self, name, value)
        return value


def default_settings_path() -> Path:
    return Path.home() / ".pixel_boxing" / "settings.json"


def _bool_value(raw: object, key: str, default: bool) -> bool:
    if not isinstance(raw, dict):
        return default
    value = raw.get(key, default)
    return value if isinstance(value, bool) else default
