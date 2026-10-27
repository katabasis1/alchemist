#!/usr/bin/env python3
"""fx_textures.py — процедурные текстуры частиц (S2.3a): искра-звезда, мягкий ореол, облачко пыли, обломки трав.

Все текстуры белые (цвет даёт частица: CPUParticles2D.color / color_ramp), фон прозрачный, straight alpha.
Результат детерминирован (фиксированное зерно), поэтому файлы можно пересобрать в любой момент:

  python tools/art/fx_textures.py            # пишет assets/fx/*.png

Только numpy + Pillow. Собственный код проекта. Контракт холстов — docs/art/ASSET_REGISTRY.md (статус proc).
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "fx"
SS = 4  # суперсэмплинг для гладких краёв


def _grid(n: int):
    c = (np.arange(n) + 0.5) / n * 2.0 - 1.0
    return np.meshgrid(c, c)


def _save(rgb: np.ndarray, a: np.ndarray, name: str) -> None:
    img = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT / name, optimize=True)


def spark(n: int = 64) -> None:
    """Звёздочка: яркое ядро + 4 тонких луча + 4 коротких диагональных + мягкий ореол."""
    x, y = _grid(n)
    r = np.sqrt(x * x + y * y)
    core = np.exp(-(r / 0.09) ** 2)
    halo = np.exp(-(r / 0.38) ** 2) * 0.35
    ray = lambda u, v, w, ln: np.exp(-(u / w) ** 2) * np.clip(1 - np.abs(v) / ln, 0, 1) ** 2.2
    d1 = (x + y) / math.sqrt(2)
    d2 = (x - y) / math.sqrt(2)
    rays = ray(y, x, 0.035, 0.98) + ray(x, y, 0.035, 0.98) + 0.45 * (ray(d1, d2, 0.03, 0.55) + ray(d2, d1, 0.03, 0.55))
    a = np.clip(core + halo + rays, 0, 1)
    rgb = np.ones_like(a)[..., None].repeat(3, -1)
    _save(rgb, a, "fx_spark.png")


def glow(n: int = 64) -> None:
    """Мягкий ореол: светлячки и отсветы."""
    x, y = _grid(n)
    r = np.sqrt(x * x + y * y)
    a = np.exp(-(r / 0.42) ** 2) * 0.85 + np.exp(-(r / 0.12) ** 2) * 0.3
    a *= np.clip((1 - r) / 0.15, 0, 1)
    rgb = np.ones_like(a)[..., None].repeat(3, -1)
    _save(rgb, a, "fx_glow.png")


def smooth(t):
    return t * t * (3 - 2 * t)


def _vnoise(x, y, rng_tab):
    ix, iy = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - ix, y - iy
    wx, wy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    t = lambda i, j: rng_tab[(i * 17 + j * 131) % rng_tab.size]
    a, b, c, d = t(ix, iy), t(ix + 1, iy), t(ix, iy + 1), t(ix + 1, iy + 1)
    return (a * (1 - wx) + b * wx) * (1 - wy) + (c * (1 - wx) + d * wx) * wy


def puff(n: int = 64) -> None:
    """Облачко пыли: несколько круглых клубов, мягкий край, светлый верх и чуть темнее низ."""
    rng = np.random.default_rng(7)
    tab = rng.random(4096)
    x, y = _grid(n)
    blobs = [(-0.25, 0.12, 0.42), (0.22, 0.15, 0.4), (0.0, -0.18, 0.48), (-0.05, 0.3, 0.35)]
    f = np.zeros_like(x)
    for bx, by, br in blobs:
        f = np.maximum(f, 1 - np.sqrt((x - bx) ** 2 + (y - by) ** 2) / br)
    nz = _vnoise((x + 1) * 5, (y + 1) * 5, tab) * 0.6 + _vnoise((x + 1) * 11, (y + 1) * 11, tab) * 0.4
    f = np.clip(f, 0, 1)
    f = f * (0.8 + 0.4 * nz)
    a = smooth(np.clip(f / 0.55, 0, 1)) * 0.9
    a *= np.clip((1 - np.sqrt(x * x + y * y)) / 0.1, 0, 1)
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(2.5)),
                   np.float32) / 255.0
    shade = 0.82 + 0.18 * np.clip(-y * 0.8 + 0.5, 0, 1)
    rgb = np.repeat(shade[..., None], 3, -1)
    _save(rgb, a, "fx_puff.png")


def flakes(frame: int = 32, frames: int = 4) -> None:
    """Обломки трав — лента из 4 кадров (CanvasItemMaterial.particles_anim_h_frames = 4).
    Неровные осколки листа: белая заливка, светлый верх, жилка, тёмный контур (после умножения на цвет — темнее смеси)."""
    rng = np.random.default_rng(11)
    big = frame * SS
    sheet = Image.new("RGBA", (frame * frames * SS, big), (0, 0, 0, 0))
    for i in range(frames):
        k = 6 + i % 3
        ang = np.sort(rng.uniform(0, 2 * math.pi, k))
        rad = rng.uniform(0.55, 1.0, k) * (0.46 * big)
        stretch = 1.0 if i % 2 == 0 else 0.6
        cx = cy = big / 2
        pts = [(cx + math.cos(t) * r, cy + math.sin(t) * r * stretch) for t, r in zip(ang, rad)]
        tile = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        d = ImageDraw.Draw(tile)
        line = int(2.2 * SS)
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).polygon(pts, fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(SS * 1.6)).point(lambda v: 255 if v > 128 else 0)
        tile.paste((255, 255, 255, 255), (0, 0), mask)
        # светлый верх / тень снизу
        shade = Image.new("L", (big, big), 0)
        sd = ImageDraw.Draw(shade)
        sd.polygon([(p[0], p[1] + big * 0.12) for p in pts], fill=255)
        arr = np.asarray(tile, np.float32)
        sh = np.asarray(shade.filter(ImageFilter.GaussianBlur(SS * 1.5)), np.float32) / 255.0
        dark = (1 - sh) * (arr[..., 3] / 255.0)
        arr[..., :3] *= (1 - 0.28 * dark)[..., None]
        tile = Image.fromarray(arr.astype(np.uint8), "RGBA")
        # жилка листа — только внутри осколка
        vein = Image.new("L", (big, big), 0)
        a0 = ang[0]
        ImageDraw.Draw(vein).line([(cx - math.cos(a0) * big, cy - math.sin(a0) * big * stretch),
                                   (cx + math.cos(a0) * big, cy + math.sin(a0) * big * stretch)],
                                  fill=255, width=int(1.4 * SS))
        varr = np.asarray(vein, np.float32) / 255.0 * (np.asarray(tile, np.float32)[..., 3] / 255.0)
        arr = np.asarray(tile, np.float32)
        arr[..., :3] *= (1 - 0.22 * varr)[..., None]
        tile = Image.fromarray(arr.astype(np.uint8), "RGBA")
        # контур: кольцо по краю маски
        edge = np.asarray(mask, np.float32) / 255.0
        inner = np.asarray(mask.filter(ImageFilter.MinFilter(line * 2 + 1)), np.float32) / 255.0
        ring = np.clip(edge - inner, 0, 1)
        arr = np.asarray(tile, np.float32)
        arr[..., :3] = arr[..., :3] * (1 - ring[..., None]) + np.array([70, 66, 60], np.float32) * ring[..., None]
        tile = Image.fromarray(arr.astype(np.uint8), "RGBA")
        sheet.paste(tile, (i * big, 0), tile)
    sheet = sheet.resize((frame * frames, frame), Image.LANCZOS)
    sheet.save(OUT / "fx_flakes.png", optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    spark()
    glow()
    puff()
    flakes()
    print("fx:", ", ".join(sorted(p.name for p in OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
