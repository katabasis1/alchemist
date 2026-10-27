#!/usr/bin/env python3
"""fit_final.py — финальная картинка (PNG с альфой) → холст из ASSET_REGISTRY.md (AGENTS.md §3.7, D16).

Финальная графика приходит большим квадратом (обычно 1254×1254) с запасом по краям и шумом в альфе.
Скрипт чистит альфу (alpha < --alpha-floor → 0), обрезает по силуэту, при --upright ставит вытянутый предмет
вертикально (главная ось по моментам маски; тяжёлый конец — вниз) и вписывает в холст с опорой center/bottom.
Уменьшение — LANCZOS по premultiplied-альфе (Pillow делает это сам для RGBA).

  python tools/art/fit_final.py inbox/art/mortar_bowl_final.png assets/props/prop_mortar_bowl.png \
         --canvas 512x512 --pivot bottom
  python tools/art/fit_final.py inbox/art/pestle_final.png assets/props/prop_pestle.png \
         --canvas 256x512 --pivot center --upright

Печатает масштаб и сдвиг (источник → холст): по ним пересчитываются координаты, снятые с исходника.
Только Pillow + numpy. Собственный код проекта.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cutout import fit_canvas  # noqa: E402


def clean_alpha(img: Image.Image, floor: int) -> Image.Image:
    arr = np.array(img.convert("RGBA"))
    arr[arr[..., 3] < floor] = 0
    return Image.fromarray(arr, "RGBA")


def principal_angle(img: Image.Image) -> tuple[float, float]:
    """Угол главной оси силуэта (градусы, от вертикали) и знак: где больше массы — +1 внизу после поворота."""
    a = np.array(img.getchannel("A"), dtype=np.float64) / 255.0
    ys, xs = np.nonzero(a > 0.5)
    w = a[ys, xs]
    cx, cy = np.average(xs, weights=w), np.average(ys, weights=w)
    dx, dy = xs - cx, ys - cy
    cov = np.cov(np.vstack([dx, dy]), aweights=w)
    vals, vecs = np.linalg.eigh(cov)
    vx, vy = vecs[:, int(np.argmax(vals))]
    # Тонкий конец: длинный «хвост» распределения вдоль оси (третий момент > 0 в его сторону).
    proj = dx * vx + dy * vy
    skew = float(np.average(proj ** 3, weights=w))
    if skew < 0:
        vx, vy = -vx, -vy  # ось смотрит к тонкому концу
    # Повернуть так, чтобы ось (к тонкому концу) смотрела вверх: (0, -1).
    angle = math.degrees(math.atan2(vx, -vy))
    return angle, skew


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--canvas", required=True, help="WxH, например 512x512")
    p.add_argument("--pivot", choices=["center", "bottom"], default="bottom")
    p.add_argument("--pad", type=int, default=8)
    p.add_argument("--alpha-floor", type=int, default=12)
    p.add_argument("--upright", action="store_true", help="поставить вытянутый предмет вертикально")
    a = p.parse_args()
    img = clean_alpha(Image.open(a.input), a.alpha_floor)
    if a.upright:
        angle, _ = principal_angle(img)
        # PIL rotate: положительный угол — против часовой; наш angle — по часовой от вертикали.
        img = img.rotate(angle, resample=Image.BICUBIC, expand=True)
        img = clean_alpha(img, a.alpha_floor)
        print(f"[fit_final] повёрнуто на {angle:.2f}° (по часовой → вертикаль)")
    cw, ch = (int(v) for v in a.canvas.lower().split("x"))
    bbox = img.getbbox()
    crop = img.crop(bbox)
    scale = min((cw - 2 * a.pad) / crop.width, (ch - 2 * a.pad) / crop.height)
    out = fit_canvas(img, (cw, ch), a.pivot, a.pad)
    nw, nh = round(crop.width * scale), round(crop.height * scale)
    ox = (cw - nw) // 2
    oy = (ch - nh) // 2 if a.pivot == "center" else ch - a.pad - nh
    Path(a.output).parent.mkdir(parents=True, exist_ok=True)
    out.save(a.output)
    print(f"[fit_final] {a.input} → {a.output} {cw}×{ch}; bbox {bbox}; scale {scale:.5f}; "
          f"canvas = (src - ({bbox[0]}, {bbox[1]})) * scale + ({ox}, {oy})")


if __name__ == "__main__":
    main()
