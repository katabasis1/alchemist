#!/usr/bin/env python3
"""mortar_preview.py — макет ступки картинкой: слои mortar.tscn + numpy-копии шейдеров (S2.3a).

Godot в песочнице агента нет, поэтому вид шейдеров и поз проверяется этим скриптом. Координаты — как в
scenes/stations/mortar/mortar.tscn (узел Visual), функции shade_* повторяют .gdshader строка в строку:
поменял шейдер — поменяй и здесь, иначе макет врёт.

  python tools/art/mortar_preview.py --out /tmp/prev            # все кадры
  python tools/art/mortar_preview.py --out /tmp/prev --only rest,heap
  python tools/art/mortar_preview.py --pestle-check               # поза покоя и края помола: пестик не «проваливается»

Только Pillow + numpy. Собственный код проекта.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
S = 2.0                      # пикселей макета на пиксель сцены
VIEW = (-250.0, -440.0, 250.0, 30.0)   # область узла Visual: x0, y0, x1, y1

# Горлышко чаши в координатах Visual (холст 512, масштаб 0.7, offset (0,-256)) — см. docs/art/ASSET_REGISTRY.md.
MOUTH_C = (-2.45, -278.25)
MOUTH_R = (122.2, 56.35)


def canvas_size():
    x0, y0, x1, y1 = VIEW
    return int((x1 - x0) * S), int((y1 - y0) * S)


def to_px(x: float, y: float) -> tuple[float, float]:
    return (x - VIEW[0]) * S, (y - VIEW[1]) * S


def grid():
    """Координаты Visual для каждого пикселя макета (центры пикселей)."""
    w, h = canvas_size()
    xs = VIEW[0] + (np.arange(w) + 0.5) / S
    ys = VIEW[1] + (np.arange(h) + 0.5) / S
    return np.meshgrid(xs, ys)


def load(rel: str) -> np.ndarray:
    return np.asarray(Image.open(ROOT / rel).convert("RGBA"), dtype=np.float32) / 255.0


def sample(tex: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Билинейная выборка текстуры (premultiplied внутри), u,v в пикселях текстуры; снаружи — прозрачно."""
    h, w = tex.shape[:2]
    pm = tex.copy()
    pm[..., :3] *= pm[..., 3:4]
    x = u - 0.5
    y = v - 0.5
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    out = np.zeros(u.shape + (4,), np.float32)
    for dx, dy, wgt in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
        xi = x0 + dx
        yi = y0 + dy
        ok = (xi >= 0) & (xi < w) & (yi >= 0) & (yi < h)
        c = np.zeros(u.shape + (4,), np.float32)
        c[ok] = pm[yi[ok], xi[ok]]
        out += c * wgt
    a = out[..., 3:4]
    out[..., :3] = np.where(a > 1e-5, out[..., :3] / np.maximum(a, 1e-5), 0.0)
    return out


def sprite_layer(tex: np.ndarray, pos=(0.0, 0.0), rot=0.0, scale=1.0, offset=(0.0, 0.0), centered=True):
    """Sprite2D: узел в pos (Visual), поворот rot (рад, по часовой), масштаб, offset в пикселях текстуры."""
    X, Y = grid()
    dx = X - pos[0]
    dy = Y - pos[1]
    c, s = math.cos(-rot), math.sin(-rot)
    lx = (dx * c - dy * s) / scale - offset[0]
    ly = (dx * s + dy * c) / scale - offset[1]
    h, w = tex.shape[:2]
    if centered:
        lx = lx + w / 2
        ly = ly + h / 2
    return sample(tex, lx, ly)


def over(dst: np.ndarray, src: np.ndarray) -> np.ndarray:
    a = src[..., 3:4]
    out = dst.copy()
    out[..., :3] = src[..., :3] * a + dst[..., :3] * (1 - a)
    out[..., 3:4] = a + dst[..., 3:4] * (1 - a)
    return out


def add(dst: np.ndarray, rgb: np.ndarray, amount: np.ndarray) -> np.ndarray:
    out = dst.copy()
    out[..., :3] = np.clip(dst[..., :3] + rgb * amount[..., None], 0, 1)
    return out


def background():
    w, h = canvas_size()
    bg = np.zeros((h, w, 4), np.float32)
    t = np.linspace(0, 1, h)[:, None]
    bg[..., 0] = 0.36 - 0.12 * t
    bg[..., 1] = 0.25 - 0.09 * t
    bg[..., 2] = 0.17 - 0.06 * t
    bg[..., 3] = 1.0
    # стол
    X, Y = grid()
    table = Y > -40
    bg[table, 0] = 0.55
    bg[table, 1] = 0.36
    bg[table, 2] = 0.2
    return bg


def save(img: np.ndarray, path: Path) -> None:
    Image.fromarray((np.clip(img[..., :3], 0, 1) * 255).astype(np.uint8)).save(path)


# ---------------------------------------------------------------- шейдерные функции (как в .gdshader)
def fract(x):
    return x - np.floor(x)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


def hash12(px, py):
    """Hash without Sine (Dave Hoskins, MIT) — как в шейдерах."""
    p3x = fract(px * 0.1031)
    p3y = fract(py * 0.1031)
    p3z = fract(px * 0.1031)
    d = p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33)
    p3x, p3y, p3z = p3x + d, p3y + d, p3z + d
    return fract((p3x + p3y) * p3z)


def vnoise(px, py):
    ix, iy = np.floor(px), np.floor(py)
    fx, fy = px - ix, py - iy
    wx, wy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = hash12(ix, iy)
    b = hash12(ix + 1, iy)
    c = hash12(ix, iy + 1)
    d = hash12(ix + 1, iy + 1)
    return mix(mix(a, b, wx), mix(c, d, wx), wy)


def rgb(c):
    return np.array(c[:3], np.float32)


POWDER_DEFAULTS = dict(
    amount=0.0, powder_color=(0.62, 0.74, 0.42), fleck_color=(0.27, 0.46, 0.2), flecks=0.0, coat=0.0, glow=0.0,
    glow_color=(1.0, 0.86, 0.45), sparkle=0.6, spin=0.0, sin_tilt=0.461, depth=0.8, level_low=-0.68,
    level_high=-0.46, heap_low=0.06, heap_high=0.4, heap_width=0.52, heap_center=(0.0, 0.08),
    outline_color=(0.24, 0.13, 0.07), shadow_tint=(0.62, 0.6, 0.76), light_tint=(1.0, 0.95, 0.82),
    light_dir=(-0.5, 0.8, -0.35), outline_width=0.022,
)


def shade_powder(rect, prm: dict, time: float = 0.7, steps: int = 40):
    """Копия powder.gdshader. rect = (x0, y0, x1, y1) ColorRect в координатах Visual. Возвращает RGBA (straight)."""
    P = dict(POWDER_DEFAULTS)
    P.update(prm)
    X, Y = grid()
    U = (X - rect[0]) / (rect[2] - rect[0])
    V = (Y - rect[1]) / (rect[3] - rect[1])
    qx = U * 2 - 1
    qy = 1 - V * 2
    h_, w_ = X.shape
    prem = np.zeros((h_, w_, 4), np.float32)
    inside = (qx * qx + qy * qy < 1.0) & (U >= 0) & (U <= 1) & (V >= 0) & (V <= 1)
    if P["amount"] <= 0.001 or not inside.any():
        return prem
    qx, qy = qx[inside], qy[inside]
    st = P["sin_tilt"]
    ct = math.sqrt(1 - st * st)
    amount = P["amount"]
    lev = mix(P["level_low"], P["level_high"], amount)
    hp = mix(P["heap_low"], P["heap_high"], amount) * float(smoothstep(0.0, 0.3, amount))
    hcx, hcz = P["heap_center"]
    spin = P["spin"]

    def swirl(x, z):
        ang = spin * 0.5 + 0.6 * np.sqrt(x * x + z * z)
        c, s = np.cos(ang), np.sin(ang)
        return c * x - s * z, s * x + c * z

    def height(x, z):
        sx, sz = swirl(x, z)
        lumps = (vnoise(sx * 5, sz * 5) - 0.5) * 0.05 + (vnoise(sx * 11, sz * 11) - 0.5) * 0.018
        dx, dz = (x - hcx) / P["heap_width"], (z - hcz) / P["heap_width"]
        b = np.exp(-(dx * dx + dz * dz) * 1.6)
        return lev + hp * b + lumps * float(smoothstep(0.0, 0.15, amount))

    def wall_radius(y):
        k = y / P["depth"]
        return np.sqrt(np.maximum(0.0, 1 - k * k))

    qa = ct * ct + st * st / (P["depth"] ** 2)
    qb = 2 * qy * ct
    qc = qx * qx + qy * qy - 1
    s_exit = (-qb + np.sqrt(np.maximum(qb * qb - 4 * qa * qc, 0))) / (2 * qa)
    ds = s_exit / steps
    prev_gap = np.ones_like(qx)
    s_hit = -np.ones_like(qx)
    min_clear = np.full_like(qx, 10.0)
    done = np.zeros(qx.shape, bool)
    for i in range(1, steps + 1):
        s = ds * i
        py = -s * st
        pz = qy + s * ct
        gap = py - height(qx, pz)
        newhit = (~done) & (gap < 0)
        s_hit[newhit] = (s - ds * gap / (gap - prev_gap))[newhit]
        done |= newhit
        live = ~done
        min_clear[live] = np.minimum(min_clear[live], gap[live])
        prev_gap = np.where(live, gap, prev_gap)
    L = np.array(P["light_dir"], np.float32)
    L /= np.linalg.norm(L)
    pulse = 0.6 + 0.4 * math.sin(time * 3.2)
    out = np.zeros((qx.size, 4), np.float32)
    ow = P["outline_width"]
    base = rgb(P["powder_color"])
    shade = base * rgb(P["shadow_tint"])
    lit = mix(base * 1.12, rgb(P["light_tint"]), 0.3)
    glow_c = rgb(P["glow_color"])
    # --- попадание в порошок
    hm = s_hit > 0
    if hm.any():
        x = qx[hm]
        z = qy[hm] + s_hit[hm] * ct
        y = -s_hit[hm] * st
        e = 0.02
        hx = height(x + e, z) - height(x - e, z)
        hz = height(x, z + e) - height(x, z - e)
        n = np.stack([-hx, np.full_like(hx, 2 * e), -hz], -1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        ndl = n @ L
        band = 0.5 * smoothstep(0.6, 0.67, ndl) + 0.5 * smoothstep(0.87, 0.93, ndl)
        b2 = band[:, None]
        col = np.where(b2 < 0.5, mix(shade, base, b2 * 2), mix(base, lit, b2 * 2 - 1))
        sx, sz = swirl(x, z)
        grain = vnoise(sx * 26, sz * 26)
        col = col * (0.9 + 0.2 * grain)[:, None]
        dark = (vnoise(sx * 30 + 3.1, sz * 30 + 3.1) >= 0.9).astype(np.float32) * 0.5
        col = mix(col, shade * 0.8, dark[:, None])
        fl = vnoise(sx * 17 + 7.3, sz * 17 + 7.3)
        fk = P["flecks"]
        fmask = smoothstep(1 - fk * 0.3, 1.03 - fk * 0.3, fl)
        col = mix(col, rgb(P["fleck_color"]) * (0.75 + 0.35 * b2), fmask[:, None])
        gap_w = wall_radius(y) - np.sqrt(x * x + z * z)
        col = col * mix(0.55, 1.0, smoothstep(0.0, 0.2, gap_w))[:, None]
        line = 1 - smoothstep(ow * 0.4, ow, gap_w)
        top = smoothstep(lev, lev + hp + 0.02, y)
        col = mix(col, col * 1.25 + glow_c * 0.35, (P["glow"] * pulse * (0.35 + 0.65 * top))[:, None])
        col = mix(col, rgb(P["outline_color"]), line[:, None])
        spark = np.zeros_like(x)
        cu, cv = sx * 7, sz * 7
        cidx, cidz = np.floor(cu), np.floor(cv)
        for j in (-1, 0, 1):
            for k in (-1, 0, 1):
                cx_, cz_ = cidx + j, cidz + k
                rnd = hash12(cx_ * 1.37 + 11, cz_ * 1.37 + 11)
                jx, jz = hash12(cx_ + 3.7, cz_ + 3.7), hash12(cx_ + 9.1, cz_ + 9.1)
                cwx, cwz = (cx_ + jx) / 7, (cz_ + jz) / 7
                ang = -(spin * 0.5 + 0.6 * np.sqrt(cwx * cwx + cwz * cwz))
                cxx = np.cos(ang) * cwx - np.sin(ang) * cwz
                czz = np.sin(ang) * cwx + np.cos(ang) * cwz
                cyy = height(cxx, czz)
                dx = (x - cxx) * 24
                dy = (qy[hm] * st - (cyy * ct + czz * st)) * 24
                tw = np.maximum(0, np.sin(time * (1.5 + 2.5 * rnd) + rnd * 40)) ** 10
                star = np.exp(-(dx * dx + dy * dy) * 1.4) + 0.7 * np.exp(-np.abs(dx) * 1.1 - dy * dy * 9) \
                    + 0.7 * np.exp(-np.abs(dy) * 1.1 - dx * dx * 9)
                spark += np.where(rnd < 0.55, star * tw, 0)
        spark *= P["sparkle"] * (1 - line) * (0.6 + 0.4 * band + P["glow"])
        scol = mix(rgb(P["light_tint"]), glow_c, 0.5 + 0.5 * P["glow"])
        col = col + scol * spark[:, None]
        out[hm, :3] = col
        out[hm, 3] = 1
    # --- луч ушёл в стенку
    wm = ~hm
    if wm.any():
        x = qx[wm]
        z = qy[wm] + s_exit[wm] * ct
        y = -s_exit[wm] * st
        above = np.maximum(y - lev, 0)
        ang = np.arctan2(z, x)
        speck = vnoise(ang * 70 + 5, y * 110 + 5)
        cot = P["coat"]
        film = cot * 0.35 * np.exp(-above * 9)
        thr = 0.95 - 0.22 * cot * np.exp(-above * 4.5)
        dots = cot * smoothstep(thr, thr + 0.04, speck) * 0.8
        a = np.clip(film + dots, 0, 0.95)
        col = mix(base, rgb(P["light_tint"]), 0.25) * (0.85 + 0.2 * speck)[:, None]
        o = np.concatenate([col * a[:, None], a[:, None]], -1)
        line = 1 - smoothstep(ow * 0.45, ow, min_clear[wm])
        o = mix(o, np.concatenate([rgb(P["outline_color"]), [1.0]]).astype(np.float32), line[:, None])
        o[:, :3] += glow_c * (P["glow"] * pulse * 0.35 * np.exp(-above * 3.5))[:, None]
        out[wm] = o
    prem[inside] = out
    return prem


def over_premul(dst: np.ndarray, prem: np.ndarray) -> np.ndarray:
    """blend_premul_alpha: rgb + dst·(1 − a)."""
    out = dst.copy()
    out[..., :3] = np.clip(prem[..., :3] + dst[..., :3] * (1 - prem[..., 3:4]), 0, 1)
    return out


def hash22(px, py):
    p3x = fract(px * 0.1031)
    p3y = fract(py * 0.103)
    p3z = fract(px * 0.0973)
    d = p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33)
    p3x, p3y, p3z = p3x + d, p3y + d, p3z + d
    return fract((p3x + p3y) * p3z), fract((p3x + p3z) * p3y)


CRUMBLE_DEFAULTS = dict(crumble=0.0, crumb_color=(0.82, 0.72, 0.52), glint_color=(1.0, 0.93, 0.7), cells=6.0,
                        crack_width=0.06, edge_width=0.14, ragged=0.14, ragged_scale=26.0, spread=0.06, sink=0.32,
                        dust_tint=0.4)


def shade_crumble(tex: np.ndarray, prm: dict) -> np.ndarray:
    """Копия ingredient.gdshader (распад) над текстурой целиком; возвращает новую RGBA-текстуру."""
    P = dict(CRUMBLE_DEFAULTS)
    P.update(prm)
    cr = P["crumble"]
    if cr <= 0:
        return tex
    h, w = tex.shape[:2]
    U, V = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    cells = P["cells"]
    gx, gy = U * cells, V * cells
    gix, giy = np.floor(gx), np.floor(gy)
    fx, fy = gx - gix, gy - giy
    f1 = np.full(U.shape, 8.0)
    f2 = np.full(U.shape, 8.0)
    idx, idy = gix.copy(), giy.copy()
    sdx, sdy = np.full(U.shape, 0.5), np.full(U.shape, 0.5)
    for j in (-1, 0, 1):
        for k in (-1, 0, 1):
            hx, hy = hash22(gix + j, giy + k)
            spx, spy = j + 0.1 + 0.8 * hx, k + 0.1 + 0.8 * hy
            d = np.sqrt((spx - fx) ** 2 + (spy - fy) ** 2)
            closer = d < f1
            second = (~closer) & (d < f2)
            f2 = np.where(closer, f1, np.where(second, d, f2))
            f1 = np.where(closer, d, f1)
            idx = np.where(closer, gix + j, idx)
            idy = np.where(closer, giy + k, idy)
            sdx = np.where(closer, (gix + spx) / cells, sdx)
            sdy = np.where(closer, (giy + spy) / cells, sdy)
    edge_d = 0.5 * (f2 - f1) + (vnoise(U * P["ragged_scale"], V * P["ragged_scale"]) - 0.5) * P["ragged"]
    start = hash12(idx * 1.7 + 4.0, idy * 1.7 + 4.0) * 0.55
    e = np.clip((cr - start) / 0.45, 0, 1)
    cut = np.maximum(P["crack_width"] * float(smoothstep(0, 0.3, cr)), e * 0.6)
    shx = (sdx - 0.5) * P["spread"] * cr
    shy = (sdy - 0.55) * P["spread"] * cr + P["sink"] * cr ** 1.3
    su, sv = U - shx, V - shy
    tc = sample(tex, su * w, sv * h)
    inside = (su >= 0) & (su <= 1) & (sv >= 0) & (sv <= 1)
    vis = smoothstep(cut, cut + 0.03, edge_d) * inside
    band = 1 - smoothstep(cut, cut + P["edge_width"], edge_d)
    col = mix(tc[..., :3], rgb(P["crumb_color"]), np.clip(cr * P["dust_tint"] + band * 0.75, 0, 1)[..., None])
    glint = (1 - smoothstep(cut, cut + 0.05, edge_d)) * (e > 0.001)
    col = col + rgb(P["glint_color"]) * (glint * 0.55)[..., None]
    out = np.concatenate([np.clip(col, 0, 1), (tc[..., 3] * vis)[..., None]], -1).astype(np.float32)
    return out


# ---------------------------------------------------------------- частицы (CPUParticles2D из .tscn) и FX-шейдеры
def _parse_value(s: str):
    s = s.strip()
    if s in ("true", "false"):
        return s == "true"
    for pre in ("Vector2(", "Color(", "PackedFloat32Array(", "PackedColorArray("):
        if s.startswith(pre):
            return [float(x) for x in s[len(pre):-1].split(",") if x.strip()]
    if s.startswith("SubResource(") or s.startswith("ExtResource("):
        return ("ref", s.split('"')[1])
    if s.startswith("["):
        nums = s.replace("Vector2(", "").replace(")", "").strip("[] ").split(",")
        try:
            return [float(x) for x in nums if x.strip()]
        except ValueError:
            return s
    try:
        return float(s)
    except ValueError:
        return s.strip('"')


def parse_tscn(rel: str) -> dict:
    """Минимальный разбор .tscn: ext/sub ресурсы и узлы (только строки key = value)."""
    ext, sub, nodes = {}, {}, []
    cur = None
    for line in (ROOT / rel).read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            head = line.strip("[]")
            attrs = dict((k, v.strip('"')) for k, v in (a.split("=", 1) for a in
                                                        __import__("shlex").split(head)[1:] if "=" in a))
            if head.startswith("ext_resource"):
                ext[attrs["id"]] = attrs.get("path", "")
                cur = None
            elif head.startswith("sub_resource"):
                cur = {"_type": attrs.get("type")}
                sub[attrs["id"]] = cur
            elif head.startswith("node"):
                cur = {"_name": attrs.get("name"), "_type": attrs.get("type"), "_parent": attrs.get("parent", "")}
                nodes.append(cur)
            else:
                cur = None
        elif cur is not None and " = " in line:
            k, v = line.split(" = ", 1)
            cur[k.strip()] = _parse_value(v)
    return {"ext": ext, "sub": sub, "nodes": nodes}


def _curve(sub: dict | None, t: np.ndarray) -> np.ndarray:
    if sub is None:
        return np.ones_like(t)
    d = sub["_data"]
    pts = [(d[i], d[i + 1]) for i in range(0, len(d), 6)]   # x, y, lt, rt, lm, rm
    return np.interp(t, [p[0] for p in pts], [p[1] for p in pts])


def _gradient(sub: dict | None, t: np.ndarray) -> np.ndarray:
    if sub is None:
        return np.ones(t.shape + (4,), np.float32)
    offs = sub.get("offsets", [0.0, 1.0])
    cols = np.array(sub.get("colors", [0, 0, 0, 1, 1, 1, 1, 1]), np.float32).reshape(-1, 4)
    return np.stack([np.interp(t, offs, cols[:, i]) for i in range(4)], -1)


PARTICLE_DEFAULTS = {"amount": 8.0, "lifetime": 1.0, "explosiveness": 0.0, "randomness": 0.0, "direction": [1.0, 0.0],
                     "spread": 45.0, "gravity": [0.0, 980.0], "initial_velocity_min": 0.0, "initial_velocity_max": 0.0,
                     "damping_min": 0.0, "damping_max": 0.0, "angle_min": 0.0, "angle_max": 0.0,
                     "angular_velocity_min": 0.0, "angular_velocity_max": 0.0, "scale_amount_min": 1.0,
                     "scale_amount_max": 1.0, "color": [1.0, 1.0, 1.0, 1.0], "emission_shape": 0.0,
                     "emission_sphere_radius": 1.0, "emission_rect_extents": [1.0, 1.0], "anim_offset_min": 0.0,
                     "anim_offset_max": 0.0, "lifetime_randomness": 0.0}


def stamp(img: np.ndarray, tex: np.ndarray, pos, rot: float, scale: float, color, additive: bool) -> None:
    """Один спрайт частицы (центр в pos, координаты Visual) прямо в img: сложение или обычное смешивание."""
    h, w = tex.shape[:2]
    half = 0.5 * math.hypot(w, h) * scale * S + 1
    cx, cy = to_px(*pos)
    H, W = img.shape[:2]
    x0, x1 = max(int(cx - half), 0), min(int(cx + half) + 1, W)
    y0, y1 = max(int(cy - half), 0), min(int(cy + half) + 1, H)
    if x0 >= x1 or y0 >= y1 or scale <= 0:
        return
    px, py = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
    dx, dy = (px - cx) / S, (py - cy) / S
    c, s = math.cos(-rot), math.sin(-rot)
    u = (dx * c - dy * s) / scale + w / 2
    v = (dx * s + dy * c) / scale + h / 2
    smp = sample(tex, u, v)
    col = smp[..., :3] * np.array(color[:3], np.float32)
    a = smp[..., 3] * color[3]
    reg = img[y0:y1, x0:x1]
    if additive:
        reg[..., :3] = np.clip(reg[..., :3] + col * a[..., None], 0, 1)
    else:
        reg[..., :3] = col * a[..., None] + reg[..., :3] * (1 - a[..., None])


def particles_layer(img: np.ndarray, scene_rel: str, node: str, origin, t: float, color=(1, 1, 1, 1),
                    steady: bool = False, seed: int = 1, with_children: bool = True) -> np.ndarray:
    """Частицы CPUParticles2D узла node из сцены: выброс в origin (Visual) в момент 0, кадр через t секунд.
    steady — непрерывный излучатель (светлячки): возраст частиц равномерно по жизни. Дочерние CPUParticles2D
    (слои) стартуют вместе с узлом, как в BurstParticles; цвет события получает только сам узел."""
    sc = parse_tscn(scene_rel)
    targets = [n for n in sc["nodes"] if n["_name"] == node and n["_type"] == "CPUParticles2D"]
    if with_children:
        targets += [n for n in sc["nodes"] if n["_parent"].split("/")[-1] == node and n["_type"] == "CPUParticles2D"]
    out = img.copy()
    rng = np.random.default_rng(seed)
    for k, n in enumerate(targets):
        P = dict(PARTICLE_DEFAULTS)
        P.update({key: val for key, val in n.items() if not key.startswith("_")})
        ref = lambda key: sc["sub"].get(P[key][1]) if isinstance(P.get(key), tuple) else None  # noqa: E731
        tex = load(sc["ext"][P["texture"][1]].replace("res://", ""))
        mat = ref("material") or {}
        additive = mat.get("blend_mode", 0.0) == 1.0
        hframes = int(mat.get("particles_anim_h_frames", 1)) if mat.get("particles_animation") else 1
        frames = [tex[:, i * tex.shape[1] // hframes:(i + 1) * tex.shape[1] // hframes] for i in range(hframes)]
        base = np.array(P["color"], np.float32) * (np.array(color, np.float32) if k == 0 else 1.0)
        amount, life = int(P["amount"]), P["lifetime"]
        dirx, diry = P["direction"]
        dir_ang = math.atan2(diry, dirx)
        for i in range(amount):
            if steady:
                age = life * ((i + rng.random() * 0.5) / amount)
            else:
                age = t - i / amount * life * (1 - P["explosiveness"])
            if age < 0 or age > life:
                continue
            shape = int(P["emission_shape"])
            if shape in (1, 2):
                r = P["emission_sphere_radius"] * (math.sqrt(rng.random()) if shape == 1 else 1.0)
                a = rng.random() * math.tau
                ox, oy = r * math.cos(a), r * math.sin(a)
            elif shape == 3:
                ex, ey = P["emission_rect_extents"]
                ox, oy = (rng.random() * 2 - 1) * ex, (rng.random() * 2 - 1) * ey
            else:
                ox = oy = 0.0
            ang = dir_ang + math.radians(P["spread"]) * (rng.random() * 2 - 1)
            spd = P["initial_velocity_min"] + (P["initial_velocity_max"] - P["initial_velocity_min"]) * rng.random()
            vx, vy = math.cos(ang) * spd, math.sin(ang) * spd
            damp = P["damping_min"] + (P["damping_max"] - P["damping_min"]) * rng.random()
            x, y = origin[0] + ox, origin[1] + oy
            dt = 1 / 120
            for _ in range(int(age / dt)):
                vx += P["gravity"][0] * dt
                vy += P["gravity"][1] * dt
                sp = math.hypot(vx, vy)
                if damp > 0 and sp > 0:
                    k2 = max(sp - damp * dt, 0) / sp
                    vx, vy = vx * k2, vy * k2
                x += vx * dt
                y += vy * dt
            ph = age / life
            rot = math.radians(P["angle_min"] + (P["angle_max"] - P["angle_min"]) * rng.random())
            rot += math.radians(P["angular_velocity_min"] + (P["angular_velocity_max"] - P["angular_velocity_min"])
                                * rng.random()) * age
            scl = (P["scale_amount_min"] + (P["scale_amount_max"] - P["scale_amount_min"]) * rng.random())
            scl *= float(_curve(ref("scale_amount_curve"), np.array(ph)))
            col = base * _gradient(ref("color_ramp"), np.array(ph))
            fr = min(int((P["anim_offset_min"] + (P["anim_offset_max"] - P["anim_offset_min"]) * rng.random())
                         * hframes), hframes - 1)
            stamp(out, frames[fr], (x, y), rot, scl, col, additive)
    return out


def _gd_hash11(p):
    p = fract(p * 0.1031)
    p = p * (p + 33.33)
    p = p * (p + p)
    return fract(p)


def _gd_noise1(x):
    i = np.floor(x)
    f = x - i
    f = f * f * (3 - 2 * f)
    return mix(_gd_hash11(i), _gd_hash11(i + 1), f)


def shade_rect(rect, fn):
    """Шейдер на ColorRect: fn(UV-x, UV-y) → (rgb, a); вне прямоугольника — пусто. Возвращает (rgb, a) на холсте."""
    X, Y = grid()
    U = (X - rect[0]) / (rect[2] - rect[0])
    V = (Y - rect[1]) / (rect[3] - rect[1])
    inside = (U >= 0) & (U <= 1) & (V >= 0) & (V <= 1)
    rgb_, a = fn(U, V)
    return rgb_, np.where(inside, a, 0.0)


def shade_ring(rect, progress, color=(0.62, 1.0, 0.45, 1.0), time=0.7, start_radius=0.62, end_radius=0.9, width=0.08,
               glow=0.6, wobble=0.02, glitter=1.0, glitter_count=30.0, fill_flash=0.45, edge_fade=0.84):
    """Копия scenes/fx/fx_ring.gdshader."""
    def fn(U, V):
        px, py = (U - 0.5) * 2, (V - 0.5) * 2
        r = np.sqrt(px * px + py * py)
        ang = np.arctan2(py, px)
        e = 1 - (1 - progress) ** 3
        radius = mix(start_radius, end_radius, e) + wobble * (np.sin(ang * 5 + time * 6) * 0.6
                                                              + np.sin(ang * 9 - time * 9) * 0.4)
        w = width * (1 - 0.5 * progress)
        d = np.abs(r - radius)
        core = np.exp(-(d / (w * 0.35)) ** 2)
        halo = np.exp(-(d / (w * 1.8)) ** 2) * glow
        trail = smoothstep(radius - 0.22, radius, r) * (r <= radius) * 0.35 * (1 - progress)
        turns = (ang / 6.2831853 + 0.5) * glitter_count
        cell = np.floor(turns)
        local = turns - cell - 0.5
        h = _gd_hash11(cell + 7)
        tw = 0.5 + 0.5 * np.sin(time * (8 + h * 10) + h * 6.2831853)
        spark = np.exp(-(local / 0.12) ** 2) * np.exp(-(d / (w * 0.7)) ** 2) * (h >= 0.45) * tw * glitter
        flash = np.exp(-(r / 0.85) ** 2) * fill_flash * (1 - float(smoothstep(0, 0.35, progress)))
        fade = (1 - float(smoothstep(0.55, 1.0, progress))) * (1 - smoothstep(edge_fade, 1.0, r))
        hot = np.clip(core * 0.8 + spark, 0, 1)
        col = mix(np.array(color[:3], np.float32), np.ones(3, np.float32), hot[..., None])
        return col, np.clip(core + halo + trail + flash + spark, 0, 1) * fade * color[3]
    return shade_rect(rect, fn)


def shade_rays(rect, progress, color=(1.0, 0.9, 0.55, 1.0), time=0.7, ray_count=9.0, origin_below=0.4,
               base_width=0.7, intensity=0.6, speed=0.6, side_fade=0.18):
    """Копия scenes/fx/fx_rays.gdshader."""
    def fn(U, V):
        dx, dy = U - 0.5, V - (1 + origin_below)
        ang = np.arctan2(dx, -dy)
        h = 1 - V
        a = ang * ray_count * 3
        rays = _gd_noise1(a + time * speed) * 0.6 + _gd_noise1(a * 2.3 - time * speed * 1.7) * 0.4
        rays = smoothstep(0.35, 0.95, rays)
        max_ang = math.atan2(base_width * 0.5, origin_below)
        fan = 1 - smoothstep(max_ang * 0.6, max_ang, np.abs(ang))
        vfade = (1 - smoothstep(0.0, 1.0, h)) * smoothstep(0.0, 0.08, h)
        side = smoothstep(0.0, side_fade, U) * smoothstep(0.0, side_fade, 1 - U)
        env = float(smoothstep(0, 0.12, progress)) * (1 - float(smoothstep(0.3, 1.0, progress)))
        v = rays * fan * vfade * side * intensity * env
        hot = np.clip(v * (1 - h) * 1.5, 0, 1)
        col = mix(np.array(color[:3], np.float32), np.ones(3, np.float32), hot[..., None])
        return col, np.clip(v, 0, 1) * color[3]
    return shade_rect(rect, fn)


def add_layer(img: np.ndarray, layer) -> np.ndarray:
    """blend_add: dst + rgb·a."""
    col, a = layer
    out = img.copy()
    out[..., :3] = np.clip(img[..., :3] + col * a[..., None], 0, 1)
    return out


# ---------------------------------------------------------------- кадры
POWDER_RECT = (-124.65, -334.6, 119.75, -221.9)      # Visual/Powder
RING_RECT = (-197.95, -368.45, 193.05, -188.05)      # Ring
RAYS_RECT = (-202.45, -560.0, 197.55, -258.0)        # Rays
MOTES_POS = (-2.45, -262.0)                          # Motes
CENTER = (-2.0, -272.0)                              # Visual/GrindCenter
SLOTS = ((-56.0, -254.0), (32.0, -256.0))            # Slots/Two1, Two2
PESTLE_REST = ((20.0, -216.0), 0.5)               # Visual/Pestle в mortar.tscn
PESTLE_GRIND = ((-36.0, -210.0), -0.35)
POWDER_BASE = (0.86, 0.78, 0.6)
DUST_COLOR = (0.9, 0.87, 0.82)
RING_COLOR = (0.62, 1.0, 0.45, 1.0)
GLOW_COLOR = (1.0, 0.86, 0.45)


def _lerp3(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _lighten(c, t):
    return tuple(c[i] + (1 - c[i]) * t for i in range(3))


def frame(name: str) -> np.ndarray:
    """Один кадр: name — rest | land | grind | heap | perfect | overgrind."""
    bowl = load("assets/props/prop_mortar_bowl.png")
    front = load("assets/props/prop_mortar_bowl_front.png")
    pest = load("assets/props/prop_pestle.png")
    herbs = [load("assets/ingredients/ing_sage_bundle.png"), load("assets/ingredients/ing_moon_moss.png")]
    # Смесь шалфея и лунного мха: powder_base, подмешанный к цвету свойств (как MortarJuice.mix_color).
    mixc = _lerp3(POWDER_BASE, (0.38, 0.72, 0.48), 0.55)
    p = {"rest": 0.0, "land": 0.0, "grind": 0.35, "heap": 0.62, "perfect": 0.75, "overgrind": 1.0}[name]
    crumble = min(p / 0.7, 1.0)
    dusty = min(max((p - 0.85) / 0.15, 0.0), 1.0)
    amount = crumble if name != "rest" else 0.0
    prm = dict(amount=amount, powder_color=_lerp3(mixc, DUST_COLOR, dusty),
               fleck_color=tuple(c * 0.55 for c in mixc), flecks=1.0 - crumble, coat=0.8 * amount,
               sparkle=(1.0 if name == "perfect" else 0.55) * (1 - dusty), spin=6.0 * p,
               glow=1.0 if name == "perfect" else 0.0, glow_color=GLOW_COLOR)
    tip, rot = PESTLE_GRIND if name in ("grind", "overgrind") else PESTLE_REST
    img = background()
    img = over(img, sprite_layer(bowl, (0, 0), 0, 0.7, (0, -256)))
    img = over_premul(img, shade_powder(POWDER_RECT, prm, 0.7))
    if name != "rest":
        for tex, pos in zip(herbs, SLOTS):
            img = over(img, sprite_layer(shade_crumble(tex, dict(crumble=crumble, crumb_color=mixc)), pos, 0, 0.42))
    img = over(img, sprite_layer(pest, tip, rot, 0.55, (0, -248)))
    if name == "grind":
        img = particles_layer(img, "scenes/fx/fx_crumbs.tscn", "Emitter1", tip, 0.14, mixc + (1.0,), seed=3)
        img = particles_layer(img, "scenes/fx/fx_crumbs.tscn", "Emitter2", tip, 0.32, mixc + (1.0,), seed=5)
    img = over(img, sprite_layer(front, (0, 0), 0, 0.7, (0, -256)))
    if name == "land":
        img = particles_layer(img, "scenes/fx/fx_dust.tscn", "Emitter1", SLOTS[0], 0.25, POWDER_BASE + (0.45,))
    if name == "heap":
        img = particles_layer(img, "scenes/fx/fx_motes.tscn", "Idle", MOTES_POS, 0, _lighten(mixc, 0.55) + (1.0,),
                              steady=True, seed=7)
    if name == "perfect":
        img = add_layer(img, shade_rays(RAYS_RECT, 0.3))
        img = add_layer(img, shade_ring(RING_RECT, 0.3, RING_COLOR))
        img = particles_layer(img, "scenes/fx/fx_sparkle_burst.tscn", "Emitter1", CENTER, 0.28, seed=11)
        img = particles_layer(img, "scenes/fx/fx_motes.tscn", "Perfect", MOTES_POS, 0, steady=True, seed=13)
    if name == "overgrind":
        img = particles_layer(img, "scenes/fx/fx_dust.tscn", "Emitter1", CENTER, 0.3, DUST_COLOR + (1.0,), seed=17)
    return img


FRAMES = ("rest", "land", "grind", "heap", "perfect", "overgrind")
PESTLE_WOOD_ROWS = 364      # строки текстуры пестика выше этой — дерево (ручка и обойма), ниже — каменная головка
PESTLE_CLEARANCE = 6.0      # запас от переднего края, px Visual (перелёт TRANS_BACK, сглаживание следования)


def pestle_check() -> bool:
    """Поза покоя и крайние позы помола из mortar.tscn: дерево пестика не должно заходить под передний край
    (иначе пестик «проваливается» в ступу), головка — не уходить под боковые края горлышка (|dx| > 0.7 rx).
    Головке за ближней стенкой быть можно: она в полости."""
    from scipy.ndimage import maximum_filter
    sc = parse_tscn("scenes/stations/mortar/mortar.tscn")
    node = {n["_name"]: n for n in sc["nodes"]}
    pn = node["Pestle"]
    bottom = node["BowlBottom"]["position"]
    reach, lean = pn.get("tip_reach", [60.0, 14.0]), pn.get("max_lean", 0.55)
    pest = load("assets/props/prop_pestle.png")
    wood = pest.copy()
    wood[PESTLE_WOOD_ROWS:, :, 3] = 0
    fa = sprite_layer(load("assets/props/prop_mortar_bowl_front.png"), (0, 0), 0, 0.7, (0, -256))[..., 3]
    k = int(PESTLE_CLEARANCE * S) * 2 + 1
    fa_d = maximum_filter((fa > 0.3).astype(np.float32), size=k)
    X, _ = grid()
    side = np.abs(X - MOUTH_C[0]) > 0.7 * MOUTH_R[0]
    poses = [("покой", tuple(pn["position"]), pn["rotation"])]
    for name, ox in (("помол вправо", 1.0), ("помол влево", -1.0)):
        poses.append((name, (bottom[0] + ox * reach[0], bottom[1]), ox * lean))
    ok = True
    for name, tip, rot in poses:
        w = float((sprite_layer(wood, tip, rot, 0.55, (0, -248))[..., 3] * fa_d).sum()) / (S * S)
        h = float((sprite_layer(pest, tip, rot, 0.55, (0, -248))[..., 3] * fa * side).sum()) / (S * S)
        good = w < 1.0 and (name != "покой" or h < 1.0)
        ok &= good
        print(f"{'OK ' if good else 'BAD'} {name}: кончик ({tip[0]:.0f},{tip[1]:.0f}) поворот {rot:+.2f} — "
              f"дерево под передним краем {w:.0f} px², головка под боковым краем {h:.0f} px²")
    return ok


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default="/tmp/prev")
    ap.add_argument("--only", default="")
    ap.add_argument("--sheet", default="", help="ещё и лист всех кадров (jpg)")
    ap.add_argument("--pestle-check", action="store_true", help="только проверить позы пестика из mortar.tscn")
    a = ap.parse_args()
    if a.pestle_check:
        raise SystemExit(0 if pestle_check() else 1)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    names = [n for n in a.only.split(",") if n] or list(FRAMES)
    tiles = []
    for n in names:
        img = frame(n)
        save(img, out / f"mortar_{n}.png")
        tiles.append(Image.open(out / f"mortar_{n}.png"))
        print("ok", n)
    if a.sheet:
        from PIL import ImageDraw
        w, h = tiles[0].size
        cols = 3 if len(tiles) > 4 else 2
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (w * cols, h * rows))
        for i, (n, t) in enumerate(zip(names, tiles)):
            ImageDraw.Draw(t).text((8, 8), n, fill=(255, 255, 255))
            sheet.paste(t, ((i % cols) * w, (i // cols) * h))
        sheet.save(a.sheet, quality=88)


if __name__ == "__main__":
    main()
