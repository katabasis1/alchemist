#!/usr/bin/env python3
"""thermometer_preview.py — термометр Горелки картинкой (S4.3): numpy-копия thermometer.gdshader.

Godot в песочнице агента нет, поэтому вид проверяется этим скриптом рядом с референсами
docs/art/refs/ref_burner_*.jpg (правило D20). fragment() повторяет components/thermometer/thermometer.gdshader
строка в строку (поменял шейдер — поменяй здесь); зоны — как Thermometer.set_zones из AlchemyRules.heat_zones
(tools/alchemy/rules_model.py); значения uniform по умолчанию читаются из .gdshader и thermometer_material.tres.

  python tools/art/thermometer_preview.py --out /tmp/prev               # лист: 20°, 45°, 65°, 82°, 100° + референс
  python tools/art/thermometer_preview.py --out /tmp/prev --temp 70

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
import liquid_preview as LP  # noqa: E402  — GLSL-помощники (smoothstep, mix)
sys.path.insert(0, str(ROOT / "tools" / "alchemy"))
import rules_model as RM  # noqa: E402

SHADER = ROOT / "components" / "thermometer" / "thermometer.gdshader"
MATERIAL = ROOT / "components" / "thermometer" / "thermometer_material.tres"
TEXTURE = ROOT / "assets" / "props" / "prop_thermometer.png"
ICONS = ROOT / "assets" / "ui"
REFS = ROOT / "docs" / "art" / "refs"
# Как в thermometer.tscn и BurnerConfig: цвет опасной зоны, иконки на планке.
DANGER = (0.62, 0.22, 0.13)
ICON_X = 89.0
ICON_PX = 24.0
ICON_LIGHTEN = 0.3


def defaults() -> dict:
    out = {}
    for m in re.finditer(r"^uniform\s+(\w+)\s+(\w+)(?:\[\d+\])?[^=;]*(?:=\s*([^;]+))?;", SHADER.read_text("utf-8"), re.M):
        kind, name, raw = m.groups()
        if raw is None:
            continue
        body = raw[raw.index("(") + 1:] if "(" in raw else raw
        nums = [float(x) for x in re.findall(r"-?\d+\.?\d*", body)]
        out[name] = nums[0] if kind in ("float", "int") else np.array(nums)
    for m in re.finditer(r"^shader_parameter/(\w+) = (.+)$", MATERIAL.read_text("utf-8"), re.M):
        name, raw = m.groups()
        body = raw[raw.index("(") + 1:] if "(" in raw else raw
        nums = [float(x) for x in re.findall(r"-?\d+\.?\d*", body)]
        out[name] = nums[0] if len(nums) == 1 else np.array(nums)
    return out


def zones_for(catalog, temp_min: float, temp_max: float) -> tuple[list, list, list]:
    starts, colors, icons = [], [], []
    for zone in RM.heat_zones(catalog):
        data = catalog.property(zone[RM.KEY_PROPERTY])
        starts.append((zone[RM.KEY_TEMP] - temp_min) / (temp_max - temp_min))
        colors.append(np.array(DANGER if zone[RM.KEY_BURNS] else data.color[:3]))
        icons.append(data.id)
    return starts, colors, icons


def fragment(tex: np.ndarray, u: dict) -> np.ndarray:
    smoothstep, mix = LP.smoothstep, LP.mix
    h, w = tex.shape[:2]
    py, px = np.mgrid[0:h, 0:w].astype(float)
    px += 0.5
    py += 0.5
    rgb_t, a_t = tex[..., :3], tex[..., 3:4]
    cx = (u["tube_x"][0] + u["tube_x"][1]) * 0.5
    half_w = (u["tube_x"][1] - u["tube_x"][0]) * 0.5
    d_tube = np.maximum(np.abs(px - cx) - half_w, u["tube_top"] - py)
    d_tube = np.maximum(d_tube, py - u["bulb_center"][1])
    d_bulb = np.hypot(px - u["bulb_center"][0], py - u["bulb_center"][1]) - u["bulb_radius"]
    cavity = 1.0 - smoothstep(-0.5, 0.5, np.minimum(d_tube, d_bulb))

    sb, st = u["scale_bottom"], u["scale_top"]
    s = (sb - py) / (sb - st)
    base = np.array(u["base_color"][:3])
    back = np.broadcast_to(base, (h, w, 3)).copy()
    starts, colors = u["zone_from"], u["zone_colors"]
    value = u["value"]
    active = -1
    for i, start in enumerate(starts):
        if value >= start:
            active = i
    for i, start in enumerate(starts):
        nxt = starts[i + 1] if i + 1 < len(starts) else 1e9
        mask = ((s >= start) & (s < nxt))[..., None]
        zone = mix(base, colors[i], u["zone_tint"])
        if i == active:
            zone = mix(zone, colors[i], u["active_glow"])
        back = np.where(mask, zone, back)
    uu = np.clip((px - cx) / half_w, -1.0, 1.0)
    back *= (1.0 - u["tube_shade"] * uu * uu * (py <= sb))[..., None]
    ticks = np.zeros((h, w))
    for start in starts:
        y = mix(sb, st, start)
        ticks = np.maximum(ticks, 1.0 - smoothstep(u["tick_px"] * 0.5, u["tick_px"] * 0.5 + 1.0, np.abs(py - y)))
    tick_c = np.array(u["tick_color"][:3])
    back = mix(back, tick_c, (ticks * u["tick_alpha"] * (py <= sb))[..., None])

    top_y = mix(sb, st, value)
    dx = np.abs(px - cx)
    r = u["column_half_px"]
    d_col_tube = np.where(py < top_y, np.hypot(dx, py - top_y) - r, dx - r)
    d_col_tube = np.maximum(d_col_tube, py - u["bulb_center"][1])
    rb = u["bulb_radius"] - u["bulb_gap_px"]
    d_col_bulb = np.hypot(px - u["bulb_center"][0], py - u["bulb_center"][1]) - rb
    d_col = np.minimum(d_col_tube, d_col_bulb)
    column = 1.0 - smoothstep(-0.5, 0.5, d_col)
    col = np.broadcast_to(np.array(u["column_color"][:3]), (h, w, 3)).copy()
    stripe = 1.0 - smoothstep(0.0, 0.45, np.abs((px - cx) / r + 0.4))
    in_bulb = 1.0 - smoothstep(-0.5, 0.5, d_col_bulb)
    gx, gy = u["bulb_center"][0] - 0.38 * rb, u["bulb_center"][1] - 0.38 * rb
    glint = 1.0 - smoothstep(0.0, rb * 0.42, np.hypot(px - gx, py - gy))
    col = mix(col, np.array(u["column_light"][:3]), (np.maximum(stripe * (1.0 - in_bulb), glint * in_bulb) * 0.85)[..., None])
    col *= mix(1.0 - u["column_edge_shade"], 1.0, smoothstep(0.0, 2.5, -d_col))[..., None]
    inner = mix(back, col, column[..., None])

    rgb = mix(rgb_t, mix(inner, rgb_t, a_t), cavity[..., None])
    alpha = np.maximum(cavity[..., None], a_t)
    on_plank = ((px >= u["plank_tick_x"][0]) & (px <= u["plank_tick_x"][1]))
    rgb = mix(rgb, tick_c, (ticks * on_plank)[..., None] * a_t)
    return np.concatenate([rgb, alpha], axis=-1)


def render(temp: float, catalog, temp_min: float = 20.0, temp_max: float = 100.0) -> Image.Image:
    tex = np.asarray(Image.open(TEXTURE).convert("RGBA"), dtype=float) / 255.0
    u = defaults()
    starts, colors, icons = zones_for(catalog, temp_min, temp_max)
    u["zone_from"], u["zone_colors"] = starts, colors
    u["value"] = float(np.clip((temp - temp_min) / (temp_max - temp_min), 0.0, 1.0))
    out = Image.fromarray((np.clip(fragment(tex, u), 0, 1) * 255).astype(np.uint8), "RGBA")
    for i, prop in enumerate(icons):
        nxt = starts[i + 1] if i + 1 < len(starts) else 1.0
        y = LP.mix(u["scale_bottom"], u["scale_top"], (starts[i] + nxt) * 0.5)
        icon = Image.open(ICONS / ("icon_prop_%s.png" % prop)).convert("RGBA").resize((int(ICON_PX), int(ICON_PX)))
        arr = np.asarray(icon, dtype=float) / 255.0
        arr[..., :3] *= LP.mix(colors[i], np.ones(3), ICON_LIGHTEN)
        icon = Image.fromarray((arr * 255).astype(np.uint8), "RGBA")
        out.alpha_composite(icon, (int(ICON_X - ICON_PX / 2), int(y - ICON_PX / 2)))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--temp", type=float)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    catalog = RM.load_catalog()
    temps = [args.temp] if args.temp is not None else [20.0, 45.0, 65.0, 82.0, 100.0]
    frames = [render(t, catalog) for t in temps]
    scale = 2
    ref = Image.open(REFS / "ref_burner_heating.jpg").convert("RGB")
    ref = ref.resize((int(ref.width * 512 * scale / ref.height), 512 * scale))
    sheet = Image.new("RGB", (len(frames) * (128 * scale + 16) + ref.width, 512 * scale), (92, 58, 34))
    for i, frame in enumerate(frames):
        big = frame.resize((128 * scale, 512 * scale), Image.LANCZOS)
        sheet.paste(big, (i * (128 * scale + 16), 0), big)
    sheet.paste(ref, (len(frames) * (128 * scale + 16), 0))
    path = args.out / "thermometer_preview.png"
    sheet.save(path)
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
