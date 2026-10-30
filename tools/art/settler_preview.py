#!/usr/bin/env python3
"""settler_preview.py — макет станции Отстойника картинкой (S4.2): колба наклонена, струя, Приёмник.

Godot в песочнице агента нет, поэтому вид проверяется этим скриптом рядом с референсами
docs/art/refs/ref_settler_*.jpg (правило D20). Струя — numpy-копия components/pour_stream/pour_stream.gdshader
(функция stream_fragment повторяет fragment() строка в строку: поменял шейдер — поменяй здесь); жидкости —
tools/art/liquid_preview.py; раскладка и форма дуги — как в scenes/stations/settler/settler.tscn и PourStream.arc_points.
Значения uniform по умолчанию читаются из .gdshader.

  python tools/art/settler_preview.py --out /tmp/prev               # кадр станции + крупный план + лист с референсами
  python tools/art/settler_preview.py --out /tmp/prev --time 1.3
  python tools/art/settler_preview.py --out /tmp/prev --angle 85   # постоянный наклон вместо угла от уровня
  python tools/art/settler_preview.py --out /tmp/prev --levels     # лист: четыре уровня слива, угол от уровня

Только Pillow + numpy. Собственный код проекта.
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
sys.path.insert(0, str(ROOT / "tools" / "art"))
import liquid_preview as LP  # noqa: E402

STREAM_SHADER = ROOT / "components" / "pour_stream" / "pour_stream.gdshader"
FLASK = ROOT / "assets" / "props" / "prop_flask_round.png"
RECEIVER = ROOT / "assets" / "props" / "prop_receiver_beaker.png"
REFS = ROOT / "docs" / "art" / "refs"

# --- раскладка: как в settler.tscn (координаты станции, начало — колба на прилавке) ------------------------------
FLASK_SCALE = 0.8
FLASK_PIVOT_TEX = (189.0, 355.0)      # центр шара колбы на холсте 384×512 (liquid.gdshader: bulb_center)
FLASK_MOUTH_TEX = (252.0, 24.0)       # носик — край венчика со стороны слива (вправо)
REST_PIVOT = (0.0, -99.0)
POUR_LIFT = 170.0
POUR_ANGLE = math.radians(100.0)     # только для --angle; по умолчанию угол считается от уровня (pour_angle)
# Видимая внутренняя кромка горла со стороны слива на холсте 384×512. Полость шейдера шире (neck_half_width = 40,
# до x = 229), но стекло prop_flask_round на x = 214…242 непрозрачно и закрывает жидкость; чистое стекло — до x = 213.
LIP_INNER_TEX = (213.0, 60.0)
POUR_DIP_PX = 15.0                    # на сколько кромка уходит под поверхность (px холста): видно из-под венчика…
POUR_DIP_LAYER_SHARE = 0.7            # …но не глубже этой доли верхнего слоя: у кромки всегда цвет того, что льётся
POUR_DIP_MIN_PX = 2.0
RECEIVER_POS = (370.0, 0.0)           # опора снизу
RECEIVER_SCALE = 0.6
# Полость Приёмника на холсте 320×384 (scenes/stations/settler/receiver_liquid_material.tres)
RECEIVER_CAVITY = dict(bulb_center=np.array([160.0, 238.0]), bulb_radius=140.0, neck_half_width=60.0,
                       neck_top=84.0, column_height=236.0)
# PourStream (pour_stream.tscn): ширина, изгиб, точки, сужение width_curve
WIDTH_FULL = 26.0
BEND = (0.85, 0.12)
SEGMENTS = 18
TAPER_END = 0.55
FIXED_ANGLE = False                   # --angle задаёт постоянный наклон вместо pour_angle


def shader_defaults(path: Path) -> dict:
    out = {}
    for m in re.finditer(r"^uniform\s+(\w+)\s+(\w+)[^=;]*(?:=\s*([^;]+))?;", path.read_text("utf-8"), re.M):
        kind, name, raw = m.groups()
        if raw is None:
            continue
        nums = [float(x) for x in re.findall(r"-?\d+\.?\d*(?:e-?\d+)?", raw)]
        out[name] = nums[0] if kind in ("float", "int") else np.array(nums)
    return out


def hash12(px, py):
    p3x, p3y, p3z = (px * 0.1031) % 1.0, (py * 0.1031) % 1.0, (px * 0.1031) % 1.0
    d = p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33)
    p3x, p3y, p3z = p3x + d, p3y + d, p3z + d
    return ((p3x + p3y) * p3z) % 1.0


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# --- копия pour_stream.gdshader -------------------------------------------------------------------------------------
def stream_fragment(u, uv_x, uv_y, fw, t):
    x = np.where(u["light_side"] > 0.5, 1.0 - uv_y, uv_y) * 2.0 - 1.0
    across = np.abs(x)
    tube = np.sqrt(np.maximum(1.0 - across * across, 0.0))
    aa = np.maximum(fw * 2.0, 1e-4)
    edge = 1.0 - smoothstep(1.0 - aa * 2.0, 1.0, across)
    shown = smoothstep(u["head"], u["head"] + u["end_soft"], uv_x) * (1.0 - smoothstep(u["reach"] - u["end_soft"], u["reach"], uv_x))
    base = np.array(u["stream_color"][:3])
    light = base + (1.0 - base) * u["core_light"]
    dark = base * (1.0 + (base - 1.0) * u["edge_saturate"]) * (1.0 - u["edge_dark"])
    k = (tube ** 1.4)[..., None]
    col = dark + (light - dark) * k
    along = uv_x * u["length_px"] - t * u["flow_px"]
    q = (x * 0.5 + 0.5) * 3.0
    lane = np.floor(q)
    lane_x = (q % 1.0) * 2.0 - 1.0
    phase = hash12(lane, 7.0) * 6.2832
    wave = 0.5 + 0.5 * np.sin(along / u["streak_px"] * 6.2832 * (0.8 + 0.4 * hash12(lane, 3.0)) + phase)
    lines = wave ** 6.0 * (1.0 - smoothstep(0.2, 0.75, np.abs(lane_x))) * tube
    col = col + (u["streak"] * lines)[..., None]
    hx = -1.0 + u["highlight_at"] + 0.04 * np.sin(along / u["streak_px"] * 2.1)
    shine = np.exp(-((x - hx) / u["highlight_width"]) ** 2)
    col = col + (1.0 - col) * np.clip(shine * u["highlight"], 0.0, 1.0)[..., None]
    cpx, cpy = along / u["sparkle_px"], (x * 0.5 + 0.5) * 2.0
    cx, cy = np.floor(cpx), np.floor(cpy)
    pick = hash12(cx + 11.0, cy + 11.0)
    lx, ly = cpx % 1.0 - 0.5, cpy % 1.0 - 0.5
    star = np.maximum(1.0 - np.hypot(lx, ly) * 4.0, 0.0)
    star += np.maximum(1.0 - np.abs(lx) * 14.0, 0.0) * np.maximum(1.0 - np.abs(ly) * 3.0, 0.0) * 0.5
    star += np.maximum(1.0 - np.abs(ly) * 14.0, 0.0) * np.maximum(1.0 - np.abs(lx) * 3.0, 0.0) * 0.5
    twinkle = 0.5 + 0.5 * np.sin(t * 9.0 + pick * 40.0)
    col = col + (u["sparkle"] * (pick >= 1.0 - u["sparkle_density"]) * star * twinkle * tube)[..., None]
    alpha = u["edge_alpha"] + (u["core_alpha"] - u["edge_alpha"]) * tube + shine * u["highlight"] * 0.2
    a = np.clip(alpha, 0, 1) * edge * shown * u["stream_color"][3]
    return np.clip(col, 0, 1), a


# --- PourStream: дуга и растр Line2D --------------------------------------------------------------------------------
def arc_points(a, b, bend, count):
    c = (a[0] + (b[0] - a[0]) * bend[0], a[1] + (b[1] - a[1]) * bend[1])
    pts = []
    for i in range(count):
        t = i / (count - 1)
        p0 = (a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t)
        p1 = (c[0] + (b[0] - c[0]) * t, c[1] + (b[1] - c[1]) * t)
        pts.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))
    return pts


def taper(t):
    # Curve (0,1) → (1, TAPER_END) с наклонами −0.6 / −0.3: близко к плавному спаду, макету хватает кубики Эрмита
    m0, m1 = -0.6, -0.3
    h00, h10, h01, h11 = 2 * t**3 - 3 * t**2 + 1, t**3 - 2 * t**2 + t, -2 * t**3 + 3 * t**2, t**3 - t**2
    return h00 * 1.0 + h10 * m0 + h01 * TAPER_END + h11 * m1


def raster_stream(canvas_w, canvas_h, origin, pts, width, u, t):
    """UV Line2D: x — доля длины, y — 0 на стороне along.orthogonal() = (y, −x)."""
    P = np.array([(p[0] + origin[0], p[1] + origin[1]) for p in pts])
    seg = P[1:] - P[:-1]
    seglen = np.hypot(seg[:, 0], seg[:, 1])
    cum = np.concatenate([[0], np.cumsum(seglen)])
    total = cum[-1]
    py, px = np.mgrid[0:canvas_h, 0:canvas_w].astype(np.float64) + 0.5
    best = np.full(px.shape, np.inf)
    uvx = np.zeros(px.shape)
    sd = np.zeros(px.shape)
    for i in range(len(seg)):
        ax, ay = P[i]
        dx, dy = seg[i] / seglen[i]
        rx, ry = px - ax, py - ay
        tt = np.clip(rx * dx + ry * dy, 0.0, seglen[i])
        qx, qy = rx - tt * dx, ry - tt * dy
        dist = np.hypot(qx, qy)
        m = dist < best
        best = np.where(m, dist, best)
        uvx = np.where(m, (cum[i] + tt) / total, uvx)
        ox, oy = dy, -dx                     # orthogonal()
        sd = np.where(m, qx * ox + qy * oy, sd)
    hw = 0.5 * width * taper(uvx)
    inside = best <= hw + 1.0
    uvy = 0.5 - sd / (2.0 * np.maximum(hw, 1e-3))
    fw = 1.0 / (2.0 * np.maximum(hw, 1e-3))
    uu = dict(u)
    uu["length_px"] = total
    mid = len(P) // 2
    along = (P[mid] - P[mid - 1]) / np.hypot(*(P[mid] - P[mid - 1]))
    uu["light_side"] = 0.0 if (along[1] * -1.0 + -along[0] * -1.0) >= 0.0 else 1.0
    col, a = stream_fragment(uu, uvx, np.clip(uvy, -0.05, 1.05), fw, t)
    a = a * inside * (np.abs(uvy - 0.5) <= 0.5 + fw)
    return np.dstack([col, a])


# --- кадр станции ---------------------------------------------------------------------------------------------------
def rotate_about(img: Image.Image, pivot, angle_rad, canvas, at):
    """Кладёт img так, чтобы pivot (пиксели img) оказался в точке at холста canvas, и поворачивает по часовой."""
    m = max(img.size)                                   # запас: колба не обрезается до поворота
    big = Image.new("RGBA", (canvas[0] + 2 * m, canvas[1] + 2 * m), (0, 0, 0, 0))
    big.paste(img, (int(round(at[0] - pivot[0])) + m, int(round(at[1] - pivot[1])) + m), img)
    big = big.rotate(-math.degrees(angle_rad), resample=Image.BICUBIC, center=(at[0] + m, at[1] + m))
    return big.crop((m, m, m + canvas[0], m + canvas[1]))


def pour_angle(uf: dict) -> float:
    """Наклон колбы, при котором кромка горла уходит под поверхность верхнего слоя на dip.

    liquid.gdshader держит высоту слоёв над центром шара по мировой вертикали (объём при наклоне не
    пересчитывается), поэтому высота кромки над центром = -lx·sinθ - ly·cosθ, а поверхность — на
    s = surface0 - bulb_radius. Решение: θ = acos((s - dip) / |l|) - atan2(lx, -ly).
    dip = clamp(доля·толщина верхнего слоя, MIN, DIP_PX): у кромки не показывается следующий слой.
    """
    n = uf["layer_count"]
    tops, col = uf["layer_tops"], uf["column_height"]
    surface0 = tops[n - 1] * col if n else 0.0
    thick = (tops[n - 1] - (tops[n - 2] if n > 1 else 0.0)) * col if n else 0.0
    dip = min(POUR_DIP_PX, max(POUR_DIP_MIN_PX, thick * POUR_DIP_LAYER_SHARE))
    s = surface0 - uf["bulb_radius"] - dip
    lx, ly = LIP_INNER_TEX[0] - uf["bulb_center"][0], LIP_INNER_TEX[1] - uf["bulb_center"][1]
    a = math.hypot(lx, ly)
    return math.acos(max(-1.0, min(1.0, s / a))) - math.atan2(lx, -ly)


def station_frame(t: float, mixture: dict, poured: float, receiver_mix: dict, flow: float, zoom: float = 1.0):
    W, H, ox, oy = 640, 520, 130.0, 470.0           # начало станции на холсте
    flask_glass = np.asarray(Image.open(FLASK).convert("RGBA")).astype(np.float64) / 255.0
    recv_glass = np.asarray(Image.open(RECEIVER).convert("RGBA")).astype(np.float64) / 255.0
    pivot = (REST_PIVOT[0], REST_PIVOT[1] - POUR_LIFT)
    ang = POUR_ANGLE if FIXED_ANGLE else pour_angle(LP.uniforms_for(mixture, poured))
    uf = LP.uniforms_for(mixture, poured, surface_angle=-ang, slosh_px=4.0, slosh_phase=t * 3.0)
    flask = Image.fromarray((LP.fragment(uf, flask_glass, t) * 255).astype(np.uint8), "RGBA")
    fs = flask.resize((int(384 * FLASK_SCALE), int(512 * FLASK_SCALE)), Image.LANCZOS)
    at = (ox + pivot[0], oy + pivot[1])
    flask_layer = rotate_about(fs, (FLASK_PIVOT_TEX[0] * FLASK_SCALE, FLASK_PIVOT_TEX[1] * FLASK_SCALE), ang, (W, H), at)
    mvx, mvy = (FLASK_MOUTH_TEX[0] - FLASK_PIVOT_TEX[0]) * FLASK_SCALE, (FLASK_MOUTH_TEX[1] - FLASK_PIVOT_TEX[1]) * FLASK_SCALE
    mouth = (pivot[0] + mvx * math.cos(ang) - mvy * math.sin(ang), pivot[1] + mvx * math.sin(ang) + mvy * math.cos(ang))
    # Приёмник
    ur = LP.uniforms_for(receiver_mix, 0.0, turbidity=0.45, **RECEIVER_CAVITY) if receiver_mix else dict(LP.shader_defaults(), layer_count=0)
    level = ur.get("layer_tops", [0])[ur["layer_count"] - 1] if ur["layer_count"] else 0.0
    recv = Image.fromarray((LP.fragment(ur, recv_glass, t) * 255).astype(np.uint8), "RGBA")
    rs = recv.resize((int(320 * RECEIVER_SCALE), int(384 * RECEIVER_SCALE)), Image.LANCZOS)
    rx0, ry0 = ox + RECEIVER_POS[0] - 160 * RECEIVER_SCALE, oy + RECEIVER_POS[1] - 384 * RECEIVER_SCALE
    recv_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    recv_layer.paste(rs, (int(rx0), int(ry0)), rs)
    surf_tex_y = RECEIVER_CAVITY["bulb_center"][1] + RECEIVER_CAVITY["bulb_radius"] - level * RECEIVER_CAVITY["column_height"]
    target = (RECEIVER_POS[0], RECEIVER_POS[1] - (384 - surf_tex_y) * RECEIVER_SCALE + 6.0)
    u = shader_defaults(STREAM_SHADER)
    u["stream_color"] = np.array(LP.uniforms_for(mixture, poured)["layer_colors"][LP.uniforms_for(mixture, poured)["layer_count"] - 1])
    pts = arc_points(mouth, target, BEND, SEGMENTS)
    stream = raster_stream(W, H, (ox, oy), pts, WIDTH_FULL * flow, u, t)
    bg = LP.background(W, H)
    img = LP.over(bg, np.asarray(flask_layer).astype(np.float64) / 255.0)
    img = LP.over(img, stream)
    img = LP.over(img, np.asarray(recv_layer).astype(np.float64) / 255.0)
    pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").convert("RGB")
    if zoom != 1.0:
        cx, cy = ox + (mouth[0] + target[0]) / 2, oy + (mouth[1] + target[1]) / 2
        w2, h2 = W / zoom / 2, H / zoom / 2
        pil = pil.crop((int(cx - w2), int(cy - h2), int(cx + w2), int(cy + h2))).resize((W, H), Image.LANCZOS)
    return pil


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--time", type=float, default=0.8)
    ap.add_argument("--angle", type=float, help="постоянный наклон колбы, градусы (по умолчанию — от уровня)")
    ap.add_argument("--levels", action="store_true", help="лист: слито 0 / 0.12 / 0.3 / 0.5 с углом от уровня")
    args = ap.parse_args()
    if args.angle is not None:
        globals().update(POUR_ANGLE=math.radians(args.angle), FIXED_ANGLE=True)
    args.out.mkdir(parents=True, exist_ok=True)
    mixture = {"sleep": 1.0, "life": 1.1, "light": 1.0}
    receiver = {"light": 1.5}
    if args.levels:
        frames = [station_frame(args.time, mixture, p, receiver, 1.0) for p in (0.0, 0.12, 0.3, 0.5)]
        lv = Image.new("RGB", (sum(f.width for f in frames), frames[0].height), "white")
        for i, f in enumerate(frames):
            lv.paste(f, (i * f.width, 0))
        lv.save(args.out / "settler_levels.png")
        for p in (0.0, 0.12, 0.3, 0.5):
            print(f"слито {p:.2f}: наклон {math.degrees(pour_angle(LP.uniforms_for(mixture, p))):.1f}°")
    a = station_frame(args.time, mixture, 0.12, receiver, 1.0)
    b = station_frame(args.time, mixture, 0.12, receiver, 1.0, zoom=2.2)
    a.save(args.out / "settler_pour.png")
    b.save(args.out / "settler_stream_zoom.png")
    refs = [Image.open(REFS / n).convert("RGB") for n in ("ref_settler_pour.jpg", "ref_settler_stream_closeup.jpg")]
    refs = [r.resize((int(r.width * a.height / r.height), a.height)) for r in refs]
    sheet = Image.new("RGB", (a.width + b.width + sum(r.width for r in refs), a.height), "white")
    x = 0
    for im in (a, refs[0], b, refs[1]):
        sheet.paste(im, (x, 0))
        x += im.width
    sheet.save(args.out / "settler_sheet.png")
    print("settler_pour.png, settler_stream_zoom.png, settler_sheet.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
