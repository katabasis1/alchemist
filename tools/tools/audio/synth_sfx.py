"""Синтез временных звуков MVP (AGENTS.md §4: numpy → ffmpeg, ogg/vorbis).

Звуки детерминированы (seed), повторный запуск даёт те же файлы.
Запуск: python tools/audio/synth_sfx.py [--out audio/sfx] [--only имя ...]
Список и назначение — docs/AUDIO.md. Финальные звуки заменяют эти под теми же именами.
"""
from __future__ import annotations

import argparse
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

RATE = 44100
ROOT = Path(__file__).resolve().parents[2]


def t_axis(sec: float) -> np.ndarray:
    return np.arange(int(RATE * sec)) / RATE


def env(sec: float, attack: float, decay: float) -> np.ndarray:
    """Быстрая атака + экспоненциальный спад."""
    t = t_axis(sec)
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    return a * np.exp(-t / decay)


def sweep(sec: float, f0: float, f1: float, curve: float = 1.0) -> np.ndarray:
    """Синус с глиссандо f0 → f1 (фаза — интеграл частоты)."""
    t = t_axis(sec)
    k = (t / sec) ** curve
    freq = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(freq) / RATE)


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    """Однополюсный фильтр нижних частот."""
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def bandnoise(rng: np.random.Generator, sec: float, lo: float, hi: float) -> np.ndarray:
    n = rng.standard_normal(int(RATE * sec))
    return lowpass(n, hi) - lowpass(n, lo)


def fade_tail(x: np.ndarray, sec: float = 0.01) -> np.ndarray:
    n = min(len(x), int(RATE * sec))
    x = x.copy()
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x


def normalize(x: np.ndarray, peak_db: float) -> np.ndarray:
    peak = np.max(np.abs(x)) or 1.0
    return x / peak * (10 ** (peak_db / 20))


# ---- звуки -------------------------------------------------------------------

def pickup(rng: np.random.Generator) -> np.ndarray:
    """Взять предмет: короткий мягкий шорох с подъёмом."""
    sec = 0.14
    noise = bandnoise(rng, sec, 900, 5000) * env(sec, 0.015, 0.045)
    tone = sweep(sec, 420, 640, 0.6) * env(sec, 0.005, 0.03) * 0.35
    return normalize(fade_tail(noise + tone), -9)


def drop_wood(rng: np.random.Generator, f0: float, decay: float) -> np.ndarray:
    """Поставить на прилавок: глухой «тук» по дереву."""
    sec = 0.22
    body = sweep(sec, f0, f0 * 0.62, 0.4) * env(sec, 0.002, decay)
    knock = sweep(sec, f0 * 2.7, f0 * 2.1) * env(sec, 0.001, decay * 0.35) * 0.4
    click = bandnoise(rng, sec, 1500, 7000) * env(sec, 0.0005, 0.006) * 0.6
    return normalize(fade_tail(body + knock + click), -6)


def reject(rng: np.random.Generator) -> np.ndarray:
    """«Нельзя»: два низких мягких «бум», второй ниже."""
    parts = []
    for f in (190.0, 150.0):
        sec = 0.11
        s = sweep(sec, f, f * 0.8) * env(sec, 0.003, 0.035)
        s += bandnoise(rng, sec, 200, 900) * env(sec, 0.001, 0.01) * 0.25
        parts.append(s)
        parts.append(np.zeros(int(RATE * 0.02)))
    return normalize(fade_tail(np.concatenate(parts)), -8)


def accept(rng: np.random.Generator) -> np.ndarray:
    """«Принято»: булькающий «блоп» вверх + тихий звон."""
    sec = 0.32
    blop = sweep(sec, 260, 720, 0.5) * env(sec, 0.004, 0.06)
    bell = (np.sin(2 * np.pi * 1320 * t_axis(sec)) + 0.4 * np.sin(2 * np.pi * 2640 * t_axis(sec))) * env(sec, 0.01, 0.09) * 0.25
    bubble = bandnoise(rng, sec, 300, 1800) * env(sec, 0.002, 0.02) * 0.15
    return normalize(fade_tail(blop + bell + bubble), -8)


SOUNDS = {
    "sfx_pickup": pickup,
    "sfx_drop_wood_1": lambda r: drop_wood(r, 150.0, 0.045),
    "sfx_drop_wood_2": lambda r: drop_wood(r, 132.0, 0.05),
    "sfx_drop_wood_3": lambda r: drop_wood(r, 168.0, 0.04),
    "sfx_reject": reject,
    "sfx_accept": accept,
}


def write_ogg(samples: np.ndarray, dst: Path) -> None:
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "x.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        dst.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "libvorbis",
                        "-q:a", "5", "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        str(dst)], check=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", type=Path, default=ROOT / "audio" / "sfx")
    ap.add_argument("--only", nargs="*", default=None)
    a = ap.parse_args()
    for i, (name, fn) in enumerate(SOUNDS.items()):
        if a.only and name not in a.only:
            continue
        samples = fn(np.random.default_rng(1000 + i))
        dst = a.out / f"{name}.ogg"
        write_ogg(samples, dst)
        print(f"{dst.relative_to(ROOT) if dst.is_relative_to(ROOT) else dst}  {len(samples) / RATE:.2f} с")


if __name__ == "__main__":
    main()
