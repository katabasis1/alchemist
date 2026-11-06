#!/usr/bin/env python3
"""flame_preview.py — пламя спиртовки картинкой (S4.3): numpy-копия components/flame/flame.gdshader.

Godot в песочнице агента нет, поэтому вид проверяется этим скриптом рядом с референсом
docs/art/refs/ref_burner_flame_boil.jpg (правило D20). tongue() и fragment() повторяют шейдер строка в строку
(поменял шейдер — поменяй здесь); значения uniform по умолчанию читаются из .gdshader и flame_material.tres.
Пламя ставится на горелку как в flame.tscn: низ-середина прямоугольника — фитиль BurnerConfig.wick_px.

  python tools/art/flame_preview.py --out /tmp/prev                  # лист: сила 0 / 0,3 / 0,55 / 0,8 / 1, станция с колбой
                                                                      # + flame_closeup.png (крупно, два момента качания)
  python tools/art/flame_preview.py --out /tmp/prev --time 1.7

Только Pillow + numpy. Собственный код проекта.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "art"))
import liquid_preview as LP  # noqa: E402  — GLSL-помощники

SHADER = ROOT / "components" / "flame" / "flame.gdshader"
MATERIAL = ROOT / "components" / "flame" / "flame_material.tres"
BURNER = ROOT / "assets" / "props" / "prop_burner.png"
BURNER_FRONT = ROOT / "assets" / "props" / "prop_burner_front.png"
REFS = ROOT / "docs" / "art" / "refs"
SCENE = ROOT / "components" / "flame" / "flame.tscn"
GLOW = ROOT / "assets" / "fx" / "fx_glow.png"
FLASK = ROOT / "assets" / "props" / "prop_flask_round.png"
WICK = (193.0, 202.0)   # BurnerConfig.wick_px (burner_round.tres)
RING = (193.0, 103.0)   # середина просвета кольца на холсте prop_burner (HANDOFF, геометрия S4.3)
BURNER_SCALE = 0.75     # горелка 0,75 при колбе 0,8: низ шара на 55 px ниже кольца, до фитиля ≈ 20 px
FLASK_SCALE = 0.8
BULB_BELOW_RING = 55.0
FLASK_BULB = (189.0, 355.0)   # liquid.gdshader: bulb_center
FLASK_BULB_R = 124.0          # liquid.gdshader: bulb_radius


def _numbers(raw: str) -> list:
    body = raw[raw.index("(") + 1:] if "(" in raw else raw
    body = body[body.index("{") + 1:] if "{" in body else body
    return [float(x) for x in re.findall(r"-?\d+\.?\d*", body)]


def defaults() -> dict:
    out = {}
    for m in re.finditer(r"^uniform\s+(\w+)\s+(\w+)(\[\d+\])?[^=;]*(?:=\s*([^;]+))?;", SHADER.read_text("utf-8"), re.M):
        kind, name, array, raw = m.groups()
        if raw is None:
            continue
        nums = _numbers(raw)
        out[name] = np.array(nums) if array or kind not in ("float", "int") else nums[0]
    if MATERIAL.exists():
        for m in re.finditer(r"^shader_parameter/(\w+) = (.+)$", MATERIAL.read_text("utf-8"), re.M):
            nums = _numbers(m.group(2))
            out[m.group(1)] = nums[0] if len(nums) == 1 else np.array(nums)
    return out


def tongue(px, py, i, height, width, t, u):
    h = height * u["tongue_h"][i] * (1.0 + u["flicker"] * np.sin(t * u["flicker_speed"] + u["tongue_phase"][i] * 3.0))
    v = py / h
    up = np.maximum(v, 0.0)
    sway = np.sin(t * u["sway_speed"] + u["tongue_phase"][i] + v * u["sway_wave"]) * u["sway_px"] * up * up * u["strength"]
    lean = u["tongue_lean"][i] * u["base_width"] * up ** u["lean_power"]
    x = px - u["tongue_x"][i] * u["base_width"] - lean - sway
    e = (u["belly"] - v) / (u["belly"] + u["bottom_depth"])
    bottom = np.sqrt(np.maximum(1.0 - e * e, 0.0))
    top = np.clip((1.0 - v) / (1.0 - u["belly"]), 0.0, 1.0) ** u["tip_power"]
    hw = width * u["tongue_w"][i] * np.where(v >= u["belly"], top, bottom)
    q = x / np.maximum(hw, 0.001)
    return (1.0 - q * q) * np.clip(1.0 - up, 0.0, 1.0) ** u["core_falloff"]


def fragment(u: dict, t: float) -> np.ndarray:
    smoothstep, mix = LP.smoothstep, LP.mix
    w, h = int(u["rect_size"][0]), int(u["rect_size"][1])
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    px = (xx + 0.5) - 0.5 * w
    py = h - (yy + 0.5) - u["wick_up_px"]
    height = u["base_height"] * mix(u["min_height"], 1.0, u["strength"])
    width = u["base_width"] * mix(u["min_width"], 1.0, u["strength"])
    heat = np.full((h, w), -1.0)
    for i in range(5):
        heat = np.maximum(heat, tongue(px, py, i, height, width, t, u))
    gy, gx = np.gradient(heat)
    e = np.maximum(np.abs(gx) + np.abs(gy), 0.002) * u["edge_soft"]
    lv = u["band_levels"]
    inner = smoothstep(lv[1] - e, lv[1] + e, heat)
    alpha = (smoothstep(lv[0] - e, lv[0] + e, heat) * mix(u["outer_alpha"], 1.0, inner)
             * smoothstep(0.0, 0.08, u["strength"]))
    c = mix(np.array(u["outer_color"][:3]), np.array(u["mid_color"][:3]), inner[..., None])
    for level, name in zip(lv[2:], ("inner_color", "core_color")):
        c = mix(c, np.array(u[name][:3]), smoothstep(level - e, level + e, heat)[..., None])
    return np.concatenate([c, alpha[..., None]], axis=-1)


def scene_props() -> dict:
    """Ореол и прямоугольник огня из flame.tscn, сила-зависимые доли — из flame.gd (как Flame._apply)."""
    text = SCENE.read_text("utf-8")
    def node(name):
        return text.split(f'[node name="{name}"', 1)[1].split("[node", 1)[0]
    glow, fire = node("Glow"), node("Fire")
    num = lambda block, key: _numbers(re.search(rf"^{key} = (.+)$", block, re.M).group(1))
    script = (SHADER.parent / "flame.gd").read_text("utf-8")
    gmin = float(re.search(r"var glow_min_scale: float = ([\d.]+)", script).group(1))
    return dict(glow_pos=num(glow, "position"), glow_scale=num(glow, "scale"), glow_mod=num(glow, "modulate"),
                glow_min=gmin, fire_left=num(fire, "offset_left")[0], fire_top=num(fire, "offset_top")[0])


def flame_layer(strength: float, t: float, size: tuple, wick: tuple, scale: float) -> tuple:
    """Огонь (обычное наложение) и ореол (сложение) на холсте size; wick — верх фитиля на холсте, scale — масштаб узла."""
    u = defaults()
    u["strength"] = strength
    sp = scene_props()
    fire = Image.fromarray((np.clip(fragment(u, t), 0, 1) * 255).astype(np.uint8), "RGBA")
    fire = fire.resize((max(1, round(fire.width * scale)), max(1, round(fire.height * scale))), Image.LANCZOS)
    fire_layer = Image.new("RGBA", size, (0, 0, 0, 0))
    fire_layer.alpha_composite(fire, (round(wick[0] + sp["fire_left"] * scale), round(wick[1] + sp["fire_top"] * scale)))
    glow = np.zeros((size[1], size[0], 3))
    if strength > 0.0:
        k = LP.mix(sp["glow_min"], 1.0, strength)
        g = Image.open(GLOW).convert("RGBA")
        gw, gh = round(g.width * sp["glow_scale"][0] * k * scale), round(g.height * sp["glow_scale"][1] * k * scale)
        g = np.asarray(g.resize((gw, gh), Image.LANCZOS)).astype(float) / 255.0
        cx, cy = wick[0] + sp["glow_pos"][0] * scale, wick[1] + sp["glow_pos"][1] * scale
        x0, y0 = round(cx - gw / 2), round(cy - gh / 2)
        mod = np.array(sp["glow_mod"])
        add = g[..., :3] * mod[:3] * (g[..., 3] * mod[3] * strength)[..., None]
        xs, ys = max(0, x0), max(0, y0)
        xe, ye = min(size[0], x0 + gw), min(size[1], y0 + gh)
        glow[ys:ye, xs:xe] += add[ys - y0:ye - y0, xs - x0:xe - x0]
    return fire_layer, glow


STATION_W, STATION_H = 400, 520


def layout(headroom: int = 0) -> dict:
    """Где на холсте станции (STATION_W × STATION_H + headroom сверху) горелка и колба: левые верхние углы
    картинок b0 (горелка) и f0 (колба). headroom — запас над горлом для пара (vapor_preview.py)."""
    w, h = STATION_W, STATION_H + headroom
    ox, oy = w / 2, h - 10                            # начало станции — низ горелки
    bw = round(384 * BURNER_SCALE)
    b0 = (round(ox - bw / 2), round(oy - bw))
    ring_y = b0[1] + RING[1] * BURNER_SCALE
    bulb_bottom = ring_y + BULB_BELOW_RING
    f0 = (round(ox - FLASK_BULB[0] * FLASK_SCALE), round(bulb_bottom - (FLASK_BULB[1] + FLASK_BULB_R) * FLASK_SCALE))
    return dict(w=w, h=h, b0=b0, f0=f0)


def station(strength: float, t: float, mixture: dict | None, boil: float = 0.0, headroom: int = 0,
            bg: np.ndarray | None = None) -> Image.Image:
    """Горелка 0,75 + колба 0,8 в кольце (+ смесь, кипение boil) + пламя + передний край кольца — порядок слоёв станции.
    headroom — запас холста над горлом (см. layout), bg — свой фон (RGBA h × w), иначе светлый фон макетов."""
    lay = layout(headroom)
    w, h, b0, f0 = lay["w"], lay["h"], lay["b0"], lay["f0"]
    img = LP.background(w, h) if bg is None else bg.copy()
    burner = Image.open(BURNER).convert("RGBA")
    bs = burner.resize((round(384 * BURNER_SCALE), round(384 * BURNER_SCALE)), Image.LANCZOS)
    def put(src):
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        layer.alpha_composite(src[0], src[1])
        return np.asarray(layer).astype(float) / 255.0
    img = LP.over(img, put((bs, b0)))
    glass = np.asarray(Image.open(FLASK).convert("RGBA")).astype(float) / 255.0
    u = LP.uniforms_for(mixture) if mixture else dict(LP.shader_defaults(), layer_count=0, surface_angle=0.0)
    u["boil"] = boil
    flask = Image.fromarray((LP.fragment(u, glass, t) * 255).astype(np.uint8), "RGBA")
    fs = flask.resize((round(384 * FLASK_SCALE), round(512 * FLASK_SCALE)), Image.LANCZOS)
    img = LP.over(img, put((fs, f0)))
    wick = (b0[0] + WICK[0] * BURNER_SCALE, b0[1] + WICK[1] * BURNER_SCALE)
    fire, glow = flame_layer(strength, t, (w, h), wick, BURNER_SCALE)
    img[..., :3] = np.clip(img[..., :3] + glow, 0, 1)
    img = LP.over(img, np.asarray(fire).astype(float) / 255.0)
    front = Image.open(BURNER_FRONT).convert("RGBA").resize(bs.size, Image.LANCZOS)
    img = LP.over(img, put((front, b0)))
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").convert("RGB")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--time", type=float, default=0.8)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    mixture = {"sleep": 1.3, "life": 1.4, "light": 1.3}   # три слоя, колба почти полна до плеч
    # сила огня и кипение как у станции: огонь 0,55 → 1, кипение 30° → 95° (BurnerConfig)
    frames = [station(s, args.time, mixture, b) for s, b in ((0.0, 0.0), (0.3, 0.15), (0.55, 0.4), (0.8, 0.7), (1.0, 1.0))]
    ref = Image.open(REFS / "ref_burner_flame_boil.jpg").convert("RGB")
    ref = ref.resize((round(ref.width * frames[0].height / ref.height), frames[0].height))
    sheet = Image.new("RGB", (sum(f.width for f in frames) + ref.width, frames[0].height), (92, 58, 34))
    x = 0
    for frame in frames:
        sheet.paste(frame, (x, 0))
        x += frame.width
    sheet.paste(ref, (x, 0))
    path = args.out / "flame_preview.png"
    sheet.save(path)
    # крупно: пламя при 0,55 и 1 в разные моменты (качание)
    crops = [station(s, tt, mixture, b).crop((60, 120, 340, 400)).resize((360, 360), Image.LANCZOS)
             for s, tt, b in ((0.55, 0.3, 0.4), (0.55, 1.1, 0.4), (1.0, 0.3, 1.0), (1.0, 1.1, 1.0))]
    close = Image.new("RGB", (360 * len(crops), 360))
    for i, c in enumerate(crops):
        close.paste(c, (i * 360, 0))
    close.save(args.out / "flame_closeup.png")
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
