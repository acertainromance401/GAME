"""Dependency-free synthesized sound effects for Pixel Boxing Top-Down."""

from __future__ import annotations

import math
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import wave
from dataclasses import dataclass
from pathlib import Path

SAMPLE_RATE = 22_050


@dataclass(frozen=True)
class Tone:
    frequency: float
    duration: float
    volume: float = 0.35
    decay: float = 5.0


SOUND_LIBRARY: dict[str, tuple[Tone, ...]] = {
    "round_bell": (
        Tone(880.0, 0.15, 0.34, 3.0),
        Tone(1_320.0, 0.28, 0.26, 4.0),
    ),
    "round_end": (
        Tone(740.0, 0.17, 0.30, 3.5),
        Tone(520.0, 0.30, 0.27, 4.0),
    ),
    "hit_light": (
        Tone(150.0, 0.07, 0.42, 18.0),
        Tone(72.0, 0.10, 0.25, 15.0),
    ),
    "hit_heavy": (
        Tone(105.0, 0.11, 0.48, 13.0),
        Tone(52.0, 0.16, 0.32, 11.0),
    ),
    "block": (
        Tone(430.0, 0.06, 0.28, 24.0),
        Tone(220.0, 0.09, 0.22, 18.0),
    ),
    "counter": (
        Tone(980.0, 0.05, 0.22, 18.0),
        Tone(720.0, 0.11, 0.20, 12.0),
        Tone(420.0, 0.16, 0.15, 10.0),
    ),
    "evade": (Tone(610.0, 0.08, 0.18, 20.0),),
    "ko": (
        Tone(98.0, 0.18, 0.48, 7.0),
        Tone(62.0, 0.35, 0.38, 5.0),
    ),
}


class SoundManager:
    def __init__(self, enabled: bool = True, cache_dir: Path | None = None):
        self.enabled = enabled
        self.cache_dir = cache_dir or Path(tempfile.gettempdir()) / "pixel_boxing_audio"
        self._last_played: dict[str, float] = {}
        self._command = _audio_command()

    @property
    def available(self) -> bool:
        return self._command is not None or sys.platform.startswith("win")

    def play(self, name: str, min_interval: float = 0.035) -> bool:
        if not self.enabled or name not in SOUND_LIBRARY or not self.available:
            return False
        now = time.monotonic()
        if now - self._last_played.get(name, -1_000.0) < min_interval:
            return False
        self._last_played[name] = now
        path = self._ensure_sound(name)
        if path is None:
            return False
        if sys.platform.startswith("win"):
            try:
                import winsound

                winsound.PlaySound(
                    str(path), winsound.SND_FILENAME | winsound.SND_ASYNC
                )
            except (ImportError, RuntimeError):
                return False
            return True

        try:
            subprocess.Popen(
                [self._command, str(path)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            return False
        return True

    def _ensure_sound(self, name: str) -> Path | None:
        path = self.cache_dir / f"{name}.wav"
        if path.exists():
            return path
        try:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            write_tone_wav(path, SOUND_LIBRARY[name])
        except OSError:
            return None
        return path


def write_tone_wav(path: Path, tones: tuple[Tone, ...]) -> None:
    """Render layered sine/noise tones into a mono 16-bit WAV file."""

    duration = max((tone.duration for tone in tones), default=0.05)
    sample_count = max(1, int(duration * SAMPLE_RATE))
    frames = bytearray()
    for index in range(sample_count):
        t = index / SAMPLE_RATE
        value = 0.0
        for tone in tones:
            if t >= tone.duration:
                continue
            attack = min(1.0, t / 0.004)
            envelope = attack * math.exp(-tone.decay * t)
            fundamental = math.sin(2.0 * math.pi * tone.frequency * t)
            harmonic = 0.28 * math.sin(4.0 * math.pi * tone.frequency * t)
            value += tone.volume * envelope * (fundamental + harmonic)
        value = max(-1.0, min(1.0, value))
        frames.extend(struct.pack("<h", int(value * 32_767)))

    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)
        wav_file.writeframes(frames)


def _audio_command() -> str | None:
    if sys.platform == "darwin":
        return shutil.which("afplay")
    return shutil.which("paplay") or shutil.which("aplay")
