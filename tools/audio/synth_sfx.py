"""synth_sfx.py — временные звуки проекта, синтез офлайн (numpy + scipy → ffmpeg, OGG Vorbis, моно 44,1 кГц).

Собственная работа проекта (не заимствование), поэтому в docs/THIRD_PARTY.md не вносится.
Генерация детерминирована (seed у каждого звука): повторный запуск даёт те же сэмплы.
Финальный звук заменяет временный под тем же именем, сцены не правятся (docs/AUDIO.md).

  python tools/audio/synth_sfx.py            # создать недостающие файлы из таблицы SOUNDS
  python tools/audio/synth_sfx.py --force    # перезаписать все файлы из таблицы
  python tools/audio/synth_sfx.py --list     # что умеет

Рецепты звуков S1 (sfx_pickup, sfx_drop_wood_*, sfx_accept, sfx_reject) в этой версии скрипта не восстановлены:
исходник потерялся вместе с Pod, сами файлы лежат в audio/sfx/ и не перегенерируются.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
from scipy import signal

RATE = 44100
ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "audio" / "sfx"


def _t(sec: float) -> np.ndarray:
    return np.arange(int(sec * RATE)) / RATE


def _band(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, [lo, hi], btype="bandpass", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def _low(x: np.ndarray, hi: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, hi, btype="lowpass", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def _fade(x: np.ndarray, fade_in: float = 0.002, fade_out: float = 0.01) -> np.ndarray:
    n_in, n_out = max(int(fade_in * RATE), 1), max(int(fade_out * RATE), 1)
    y = x.copy()
    y[:n_in] *= np.linspace(0.0, 1.0, n_in)
    y[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return y


def _norm(x: np.ndarray, peak_db: float) -> np.ndarray:
    peak = float(np.max(np.abs(x))) or 1.0
    return x / peak * (10.0 ** (peak_db / 20.0))


def crunch(seed: int) -> np.ndarray:
    """Хруст помола: 4–7 сухих щелчков-зёрен (шум в полосе 1,2–6 кГц) + короткий глухой удар пестика."""
    rng = np.random.default_rng(seed)
    length = 0.13 + 0.03 * rng.random()
    out = np.zeros(int(length * RATE))
    for _ in range(int(rng.integers(4, 8))):
        start = int(rng.uniform(0.0, length * 0.55) * RATE)
        dur = rng.uniform(0.012, 0.035)
        n = int(dur * RATE)
        grain = rng.standard_normal(n) * np.exp(-np.arange(n) / RATE / (dur * 0.25))
        grain *= rng.uniform(0.4, 1.0)
        end = min(start + n, out.size)
        out[start:end] += grain[: end - start]
    out = _band(out, 1200.0 + 300.0 * rng.random(), 6000.0)
    t = _t(length)
    thump_freq = rng.uniform(140.0, 190.0)
    thump = np.sin(2 * np.pi * thump_freq * t) * np.exp(-t / 0.025) * 0.5
    out = out / (np.max(np.abs(out)) or 1.0) + thump
    return _norm(_fade(out, 0.001, 0.02), -8.0)


def perfect() -> np.ndarray:
    """Звон «идеально»: колокольчик из двух нот (ми и си) с негармоничными обертонами."""
    t = _t(0.7)
    out = np.zeros_like(t)
    for delay, base in ((0.0, 1318.5), (0.07, 1975.5)):
        tt = np.clip(t - delay, 0.0, None)
        on = (t >= delay).astype(float)
        for ratio, amp, decay in ((1.0, 1.0, 0.28), (2.76, 0.35, 0.12), (5.4, 0.15, 0.05)):
            out += on * amp * np.sin(2 * np.pi * base * ratio * tt) * np.exp(-tt / decay)
    return _norm(_fade(out, 0.003, 0.05), -9.0)


def overgrind() -> np.ndarray:
    """«Пфф» — перетёр: мягкий выдох шума, полоса уходит вниз (ниже тоном, чем хруст)."""
    rng = np.random.default_rng(31)
    t = _t(0.42)
    noise = rng.standard_normal(t.size)
    env = np.minimum(t / 0.04, 1.0) * np.exp(-t / 0.13)
    # Полоса сползает вниз: смесь «светлой» и «тёмной» версии шума.
    bright = _band(noise, 500.0, 2400.0)
    dark = _band(noise, 150.0, 700.0)
    k = np.clip(t / 0.3, 0.0, 1.0)
    out = (bright * (1.0 - k) + dark * k * 1.6) * env
    return _norm(_fade(out, 0.004, 0.06), -10.0)


def dull(seed: int) -> np.ndarray:
    """Глухой звук при p = 1: пестик трёт пыль — мягкий удар и приглушённый шорох, без щелчков."""
    rng = np.random.default_rng(seed)
    t = _t(0.16)
    noise = _low(rng.standard_normal(t.size), 900.0)
    env = np.minimum(t / 0.01, 1.0) * np.exp(-t / 0.05)
    thump = np.sin(2 * np.pi * rng.uniform(95.0, 120.0) * t) * np.exp(-t / 0.03)
    out = noise * env * 0.6 + thump * 0.8
    return _norm(_fade(out, 0.002, 0.03), -12.0)


SOUNDS = {
    "sfx_grind_crunch_1.ogg": lambda: crunch(101),
    "sfx_grind_crunch_2.ogg": lambda: crunch(202),
    "sfx_grind_crunch_3.ogg": lambda: crunch(303),
    "sfx_grind_crunch_4.ogg": lambda: crunch(404),
    "sfx_grind_crunch_5.ogg": lambda: crunch(505),
    "sfx_grind_dull_1.ogg": lambda: dull(11),
    "sfx_grind_dull_2.ogg": lambda: dull(22),
    "sfx_perfect.ogg": perfect,
    "sfx_overgrind.ogg": overgrind,
}


def write_ogg(samples: np.ndarray, path: Path) -> None:
    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "x.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        # -fflags +bitexact и -map_metadata -1: без случайного серийного номера и метаданных — файл повторяем.
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-map_metadata", "-1", "-fflags", "+bitexact",
               "-flags:a", "+bitexact", "-c:a", "libvorbis", "-q:a", "5", str(path)]
        subprocess.run(cmd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="перезаписать существующие файлы")
    parser.add_argument("--list", action="store_true", help="показать таблицу звуков")
    args = parser.parse_args()
    if args.list:
        for name, fn in SOUNDS.items():
            print(f"{name:28s} {(fn.__doc__ or '').strip() if not isinstance(fn, type(lambda: 0)) else ''}")
        return 0
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, fn in SOUNDS.items():
        path = OUT_DIR / name
        if path.exists() and not args.force:
            print(f"[synth] есть: {name}")
            continue
        samples = fn()
        write_ogg(samples, path)
        peak = 20.0 * np.log10(float(np.max(np.abs(samples))) or 1e-9)
        print(f"[synth] {name}: {samples.size / RATE:.2f} с, пик {peak:.1f} dBFS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
