#!/usr/bin/env python3
"""liquid_preview.py — макет жидкости картинкой: numpy-копия components/liquid/liquid.gdshader (S4.1).

Godot в песочнице агента нет, поэтому вид шейдера проверяется этим скриптом. Функции повторяют .gdshader строка в
строку (имена те же): поменял шейдер — поменяй и здесь, иначе макет врёт. Значения uniform по умолчанию читаются
из самого .gdshader, слои — из эталона tools/alchemy/liquid_model.py (копия LiquidLayers.view).

  python tools/art/liquid_preview.py --out /tmp/prev                       # все кадры + лист сравнения
  python tools/art/liquid_preview.py --out /tmp/prev --flask путь/к/prop_flask_round.png
  python tools/art/liquid_preview.py --out /tmp/prev --only layers4,tilt

В рабочей копии агента PNG — прозрачные заглушки (AGENTS.md §2.3): для вида со стеклом передай настоящую колбу
через --flask. Только Pillow + numpy. Собственный код проекта.
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "alchemy"))
import liquid_model as L  # noqa: E402
import rules_model as R  # noqa: E402

SHADER = ROOT / "components" / "liquid" / "liquid.gdshader"
FLASK = ROOT / "assets" / "props" / "prop_flask_round.png"
MAX_LAYERS = 6
CAPACITY = 5.0               # как Liquid.capacity в liquid.tscn


# --- uniform по умолчанию из .gdshader ---------------------------------------------------------------------------
def shader_defaults() -> dict:
    out = {}
    for m in re.finditer(r"^uniform\s+(\w+)\s+(\w+)(?:\[\d+\])?[^=;]*(?:=\s*([^;]+))?;", SHADER.read_text("utf-8"), re.M):
        kind, name, raw = m.groups()
        if raw is None:
            continue
        body = raw[raw.index("(") + 1:] if "(" in raw else raw
        nums = [float(x) for x in re.findall(r"-?\d+\.?\d*", body)]
        out[name] = nums[0] if kind in ("float", "int") else np.array(nums if len(nums) > 1 else nums * 4)
    return out


# --- GLSL-помощники ------------------------------------------------------------------------------------------------
def fract(x):
    return x - np.floor(x)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


# hash12 — «Hash without Sine», Dave Hoskins, MIT: https://www.shadertoy.com/view/4djSRW (docs/THIRD_PARTY.md).
def hash12(px, py):
    p3x, p3y, p3z = fract(px * 0.1031), fract(py * 0.1031), fract(px * 0.1031)
    dot = p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33)
    p3x, p3y, p3z = p3x + dot, p3y + dot, p3z + dot
    return fract((p3x + p3y) * p3z)


def value_noise(px, py):
    ix, iy = np.floor(px), np.floor(py)
    fx, fy = px - ix, py - iy
    ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = mix(hash12(ix, iy), hash12(ix + 1, iy), ux)
    b = mix(hash12(ix, iy + 1), hash12(ix + 1, iy + 1), ux)
    return mix(a, b, uy)


def rotate(angle, x, y):
    """mat2(vec2(c, s), vec2(-s, c)) * vec2(x, y) — столбцы GLSL."""
    c, s = np.cos(angle), np.sin(angle)
    return c * x - s * y, s * x + c * y


def segment(px, py, ax, ay, bx, by):
    pax, pay, bax, bay = px - ax, py - ay, bx - ax, by - ay
    h = np.clip((pax * bax + pay * bay) / (bax * bax + bay * bay), 0.0, 1.0)
    return np.hypot(pax - bax * h, pay - bay * h)


# --- функции шейдера ------------------------------------------------------------------------------------------------
def chord(u, h):
    dy = h - u["bulb_radius"]
    ball = np.sqrt(np.maximum(u["bulb_radius"] ** 2 - dy * dy, 0.0))
    return np.maximum(ball, u["neck_half_width"] * (h >= u["bulb_radius"]))


def front_arc(u, s, h):
    w = np.maximum(chord(u, h), 1.0)
    k = np.clip(s / w, -1.0, 1.0)
    return u["surface_squash"] * w * np.sqrt(1.0 - k * k)


def boundary_wave(u, s, index, t):
    return u["idle_wave_px"] * np.sin(s * 0.045 + t * u["idle_wave_speed"] + index * 1.7)


def surface_wave(u, s, w, t):
    k = np.clip(s / np.maximum(w, 1.0), -1.0, 1.0)
    idle = u["idle_wave_px"] * np.sin(s * 0.05 - t * u["idle_wave_speed"] * 1.3)
    slosh = u["slosh_px"] * (k * math.cos(u["slosh_phase"]) + 0.35 * np.sin(k * 6.2832 - u["slosh_phase"] * 1.3))
    return idle + slosh


def pattern_mask(u, pattern, dx, dy, t):
    qx, qy = dx / u["pattern_px"], dy / u["pattern_px"]
    aa = 1.2 / u["pattern_px"]
    sp = u["pattern_speed"]
    if pattern == 1:
        qx = qx - t * sp * 2.0
        line = np.abs(fract(qy * 1.4 + 0.12 * np.sin(qx * 6.2832)) - 0.5) / 1.4 - 0.035
        return 1.0 - smoothstep(-aa, aa, line)
    if pattern == 0:
        qy = qy + t * sp * 2.5
    elif pattern == 2:
        qx, qy = qx - 0.4 * t * sp, qy - 1.0 * t * sp
    elif pattern == 3:
        qy = qy - t * sp
    elif pattern == 4:
        qx = qx + t * sp * 0.6
    else:
        qy = qy + t * sp * 0.6
    qx = qx + 0.5 * np.mod(np.floor(qy), 2.0)
    cx, cy = np.floor(qx), np.floor(qy)
    rnd = hash12(cx, cy)
    rnd2 = hash12(cx + 17.3, cy + 5.1)
    skip = hash12(cx + 3.7, cy + 11.9) < u["pattern_skip"]
    fx = fract(qx) - 0.5 - (rnd - 0.5) * 0.3
    fy = fract(qy) - 0.5 - (rnd2 - 0.5) * 0.3
    size = mix(0.75, 1.15, rnd2)
    if pattern == 0:
        ring = np.abs(np.hypot(fx, fy) - 0.17 * size) - 0.03
        glint = np.hypot(fx + 0.07 * size, fy + 0.07 * size) - 0.035 * size
        small = np.abs(np.hypot(fx - 0.2, fy - 0.17) - 0.06 * size) - 0.022
        dist = np.minimum(np.minimum(ring, glint), small)
    elif pattern == 2:
        gx, gy = rotate(rnd * 6.2832 + np.sin(t * 0.8 + rnd * 6.0) * 0.35, fx, fy)
        lens = np.maximum(np.hypot(gx - 0.15 * size, gy), np.hypot(gx + 0.15 * size, gy)) - 0.27 * size
        vein = np.abs(gx) - 0.012
        dist = np.maximum(lens, -vein)
        dist = np.minimum(dist, segment(gx, gy, 0.0, 0.18 * size, 0.0, 0.27 * size) - 0.016)
    elif pattern == 3:
        gx, gy = rotate(rnd + t * 0.25, fx, fy)
        angle = np.mod(np.arctan2(gy, gx) + math.pi / 6.0, math.pi / 3.0) - math.pi / 6.0
        ln = np.hypot(gx, gy)
        kx, ky = ln * np.cos(angle), ln * np.abs(np.sin(angle))
        r = 0.21 * size
        arm = segment(kx, ky, 0.0, 0.0, r, 0.0) - 0.022
        branch = segment(kx, ky, 0.5 * r, 0.0, 0.78 * r, 0.17 * r) - 0.018
        dist = np.minimum(arm, branch)
    elif pattern == 4:
        gx, gy = rotate(rnd * 0.8 - 0.4, fx, fy)
        dist = np.maximum(np.hypot(gx, gy) - 0.17 * size,
                          -(np.hypot(gx - 0.085 * size, gy + 0.055 * size) - 0.145 * size))
    else:
        twinkle = 0.7 + 0.3 * np.sin(t * 3.0 + rnd * 6.2832)
        r = 0.27 * size * twinkle
        gx, gy = np.abs(fx) / r, np.abs(fy) / r
        dist = (np.sqrt(gx) + np.sqrt(gy) - 1.0) * r * 0.5
        dist = np.minimum(dist, np.hypot(fx - 0.22, fy + 0.18) - 0.025 * twinkle)
    return np.where(skip, 0.0, 1.0 - smoothstep(-aa, aa, dist))


def shade_liquid(u, dx, dy, h, s, t):
    n = min(int(u["layer_count"]), MAX_LAYERS)
    tops, colors, patterns = u["layer_tops"], u["layer_colors"], u["layer_patterns"]
    surface0 = tops[n - 1] * u["column_height"]
    w = chord(u, np.float64(surface0))
    surface = surface0 + surface_wave(u, s, w, t)
    arc = front_arc(u, s, surface)
    alpha = 1.0 - smoothstep(-0.8, 0.8, h - (surface + arc))
    murk = u["turbidity"]
    sqx, sqy = (s * 0.45 + np.sin(h * 0.04 + t * 1.1) * 26.0) / u["murk_swirl_px"], h / u["murk_swirl_px"]
    swirl = value_noise(sqx + t * 0.15, sqy - t * 0.5) - 0.5
    swirl = swirl + 0.5 * (value_noise(sqx * 2.3 - t * 0.3, sqy * 2.3 + t * 0.2) - 0.5)
    hm = h + swirl * murk * u["column_height"] * 0.55
    index = np.zeros_like(h, dtype=int)
    seam = np.full_like(h, 100000.0)
    for i in range(MAX_LAYERS - 1):
        if i < n - 1:
            hb = tops[i] * u["column_height"]
            edge = hb - front_arc(u, s, np.float64(hb)) + boundary_wave(u, s, float(i), t)
            seam = np.minimum(seam, np.abs(hm - edge))
            index += (hm >= edge).astype(int)
    pal = np.array(colors)[:, :3]
    base = mix(pal[index], np.array(u["mixed_color"])[:3], smoothstep(0.0, 1.0, murk) * u["murk_blend"])
    light = mix(base, 1.0, u["center_glow"])
    deep = base * base
    r = np.hypot(dx, dy) / u["bulb_radius"]
    col = mix(light, deep, (smoothstep(0.3, 1.05, r) * u["edge_shade"])[..., None])
    clear = 1.0 - murk
    pat = np.zeros_like(h)
    for k in range(6):
        sel = np.array([patterns[j] == k for j in range(len(patterns))])[index]
        if sel.any():
            pat = np.where(sel, pattern_mask(u, k, dx, dy, t), pat)
    pattern = pat * u["pattern_alpha"] * clear * smoothstep(u["seam_px"], u["seam_px"] * 2.5, seam)
    col = mix(col, mix(base, 1.0, 0.6), pattern[..., None])
    glow = (1.0 - smoothstep(0.0, u["seam_px"], seam)) * u["seam_glow"] * clear
    col = mix(col, mix(base, 1.0, 0.75), glow[..., None])
    R0 = u["bulb_radius"]
    caustic = np.exp(-(dx / (0.42 * R0)) ** 2 - ((dy - 0.8 * R0) / (0.09 * R0)) ** 2)
    col = mix(col, light, (caustic * u["caustic_light"])[..., None])
    front = surface - arc
    across = np.clip((h - front) / np.maximum(2.0 * arc, 1.0), 0.0, 1.0)
    top = mix(mix(base, 1.0, u["top_light"]), mix(base, 1.0, u["top_light"] * 0.6), across[..., None])
    col = np.where((h > front)[..., None], top, col)
    rim = 1.0 - smoothstep(0.6, 2.4, np.abs(h - front))
    col = mix(col, 1.0, (rim * u["rim_light"])[..., None])
    side = smoothstep(0.8, 1.0, np.abs(s) / max(float(w), 1.0)) * (1.0 - smoothstep(0.0, 9.0, np.abs(h - surface)))
    col = mix(col, 1.0, (side * u["meniscus_light"])[..., None])
    return col, alpha


def fragment(u, glass: np.ndarray, t: float) -> np.ndarray:
    hgt, wid = glass.shape[:2]
    py, px = np.mgrid[0:hgt, 0:wid].astype(np.float64) + 0.5
    a = u["surface_angle"]
    upx, upy = math.sin(a), -math.cos(a)
    alx, aly = -upy, upx
    dx, dy = px - u["bulb_center"][0], py - u["bulb_center"][1]
    h = dx * upx + dy * upy + u["bulb_radius"]
    s = dx * alx + dy * aly
    in_bulb = 1.0 - smoothstep(u["bulb_radius"] - 1.0, u["bulb_radius"] + 1.0, np.hypot(dx, dy))
    in_neck = ((1.0 - smoothstep(u["neck_half_width"] - 1.0, u["neck_half_width"] + 1.0, np.abs(dx)))
               * (py >= u["neck_top"]) * (py <= u["bulb_center"][1]))
    cavity = np.maximum(in_bulb, in_neck)
    lrgb = np.zeros((hgt, wid, 3))
    la = np.zeros((hgt, wid))
    if u["layer_count"] > 0:
        lrgb, la = shade_liquid(u, dx, dy, h, s, t)
        la = la * cavity
    ga = glass[..., 3]
    out_a = ga + la * (1.0 - ga)
    rgb = (glass[..., :3] * ga[..., None] + lrgb * (la * (1.0 - ga))[..., None]) / np.maximum(out_a, 1e-4)[..., None]
    return np.dstack([np.clip(rgb, 0, 1), out_a])


# --- сцены ----------------------------------------------------------------------------------------------------------
def uniforms_for(mixture: dict, poured: float = 0.0, **extra) -> dict:
    catalog = R.load_catalog()
    v = L.view(mixture, poured, CAPACITY, catalog, catalog.economy)
    u = shader_defaults()
    n = len(v[L.KEY_TOPS])
    pad = MAX_LAYERS - n
    u.update(layer_count=n, layer_tops=list(v[L.KEY_TOPS]) + [0.0] * pad,
             layer_colors=[list(c) for c in v[L.KEY_COLORS]] + [[0, 0, 0, 0]] * pad,
             layer_patterns=list(v[L.KEY_PATTERNS]) + [0] * pad, mixed_color=list(v[L.KEY_MIXED]))
    u.setdefault("surface_angle", 0.0)
    u.update(extra)
    return u


SCENES = {
    # 4 слоя, как ref_liquid_layers_4: Едкость, Жизнь, Холод, Свет
    "layers4": dict(mixture={"acid": 1.0, "life": 1.1, "cold": 1.0, "light": 1.0}),
    "two": dict(mixture={"acid": 0.9, "heat": 1.8}),
    "six": dict(mixture={"acid": 0.8, "heat": 0.8, "life": 0.8, "cold": 0.8, "sleep": 0.8, "light": 0.8}),
    "murky": dict(mixture={"acid": 1.0, "life": 1.1, "cold": 1.0, "light": 1.0}, turbidity=0.75),
    "settling": dict(mixture={"acid": 1.0, "life": 1.1, "cold": 1.0, "light": 1.0}, turbidity=0.3),
    "tilt": dict(mixture={"heat": 1.2, "light": 1.4}, rotation=-0.45, slosh_px=7.0, slosh_phase=0.6),
    "poured": dict(mixture={"acid": 1.0, "life": 1.1, "cold": 1.0, "light": 1.0}, poured=0.4),
}
SINGLES = ["acid", "heat", "life", "cold", "sleep", "light"]


def background(w: int, h: int) -> np.ndarray:
    y = np.linspace(0, 1, h)[:, None, None]
    top, bottom = np.array([0.96, 0.87, 0.66]), np.array([0.86, 0.68, 0.45])
    img = np.ones((h, w, 3)) * mix(top, bottom, y)
    return np.dstack([img, np.ones((h, w))])


def over(dst: np.ndarray, src: np.ndarray) -> np.ndarray:
    a = src[..., 3:4]
    out = dst.copy()
    out[..., :3] = src[..., :3] * a + dst[..., :3] * (1 - a)
    return out


def render(scene: dict, glass: np.ndarray, t: float) -> Image.Image:
    params = dict(scene)
    mixture = params.pop("mixture")
    poured = params.pop("poured", 0.0)
    rot = params.pop("rotation", 0.0)
    u = uniforms_for(mixture, poured, surface_angle=-rot, **params)
    img = fragment(u, glass, t)
    pil = Image.fromarray((img * 255).astype(np.uint8), "RGBA")
    if rot:
        pil = pil.rotate(-math.degrees(rot), resample=Image.BICUBIC, expand=False)
    return pil


def on_bg(pil: Image.Image) -> Image.Image:
    arr = np.asarray(pil).astype(np.float64) / 255.0
    out = over(background(arr.shape[1], arr.shape[0]), arr)
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA").convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--flask", type=Path, default=FLASK)
    ap.add_argument("--only", default="")
    ap.add_argument("--time", type=float, default=0.8)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    glass = np.asarray(Image.open(args.flask).convert("RGBA")).astype(np.float64) / 255.0
    names = [n for n in args.only.split(",") if n] or list(SCENES) + ["singles"]
    frames = []
    for name in names:
        if name == "singles":
            tiles = [on_bg(render(dict(mixture={p: 3.0}), glass, args.time)) for p in SINGLES]
            sheet = Image.new("RGB", (tiles[0].width * 3, tiles[0].height * 2))
            for i, tile in enumerate(tiles):
                sheet.paste(tile, ((i % 3) * tile.width, (i // 3) * tile.height))
            sheet.save(args.out / "liquid_singles.png")
            print("liquid_singles.png")
            continue
        img = on_bg(render(SCENES[name], glass, args.time))
        img.save(args.out / ("liquid_%s.png" % name))
        frames.append(img)
        print("liquid_%s.png" % name)
    if len(frames) > 1:
        sheet = Image.new("RGB", (frames[0].width * len(frames), frames[0].height))
        for i, f in enumerate(frames):
            sheet.paste(f, (i * f.width, 0))
        sheet.save(args.out / "liquid_sheet.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
