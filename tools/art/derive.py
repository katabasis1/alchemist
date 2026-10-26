#!/usr/bin/env python3
"""derive.py — производные ассеты из уже вырезанных PNG (контракт docs/art/ASSET_REGISTRY.md).

  fit   — вписать готовый PNG с альфой в холст реестра (опора center/bottom, поля pad):
          python tools/art/derive.py fit SRC.png assets/ui/icon_coin.png --canvas 256x256 --pivot center --pad 8
  bench — вырезать слой прилавка из фона (всё ниже линии прилавка), чтобы клиент стоял ЗА прилавком:
          python tools/art/derive.py bench [--bg assets/backgrounds/bg_workshop.png] [--top 756]
          → assets/backgrounds/bg_workshop_bench.png (1920×(1080-top)). top — первая строка контура
          края прилавка; при замене фона на финальный проверить и при необходимости поправить
          top в реестре и позицию узла Bench в scenes/workshop/workshop.tscn.
  front — передний край сосуда: всё, что ниже ближней кромки горлышка (эллипс cx,cy,rx,ry в пикселях
          исходника). Слой рисуется поверх содержимого, и ингредиенты оказываются «внутри» чаши:
          python tools/art/derive.py front assets/props/prop_mortar_bowl.png assets/props/prop_mortar_bowl_front.png \
              --ellipse 256,94,180,52
          После финальной картинки эллипс горлышка проверить (docs/art/ASSET_REGISTRY.md) и пересобрать слой.
Зависимости: Pillow; использует fit_canvas из tools/art/cutout.py.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cutout import fit_canvas  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def front_layer(img: Image.Image, cx: float, cy: float, rx: float, ry: float) -> Image.Image:
    """Оставить только пиксели ниже ближней кромки горлышка; кромка сглажена на 1,5 пикселя."""
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    px = mask.load()
    feather = 1.5
    for x in range(w):
        dx = (x + 0.5 - cx) / rx
        edge = cy + ry * (1.0 - dx * dx) ** 0.5 if abs(dx) < 1.0 else cy
        for y in range(h):
            t = (y + 0.5 - edge) / feather
            px[x, y] = 0 if t <= 0.0 else 255 if t >= 1.0 else int(255 * t)
    out = img.copy()
    alpha = Image.composite(img.getchannel("A"), Image.new("L", (w, h), 0), mask)
    out.putalpha(alpha)
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fit")
    f.add_argument("src", type=Path)
    f.add_argument("dst", type=Path)
    f.add_argument("--canvas", required=True)
    f.add_argument("--pivot", choices=["center", "bottom"], default="center")
    f.add_argument("--pad", type=int, default=8)
    b = sub.add_parser("bench")
    b.add_argument("--bg", type=Path, default=ROOT / "assets/backgrounds/bg_workshop.png")
    b.add_argument("--top", type=int, default=756)
    b.add_argument("--out", type=Path, default=ROOT / "assets/backgrounds/bg_workshop_bench.png")
    fr = sub.add_parser("front")
    fr.add_argument("src", type=Path)
    fr.add_argument("dst", type=Path)
    fr.add_argument("--ellipse", required=True, help="cx,cy,rx,ry горлышка (внутренний край) в пикселях исходника")
    a = ap.parse_args()
    if a.cmd == "front":
        cx, cy, rx, ry = (float(v) for v in a.ellipse.split(","))
        img = Image.open(a.src).convert("RGBA")
        out = front_layer(img, cx, cy, rx, ry)
        a.dst.parent.mkdir(parents=True, exist_ok=True)
        out.save(a.dst, optimize=True)
        print(f"{a.dst} {out.size}")
        return
    if a.cmd == "fit":
        w, h = (int(v) for v in a.canvas.lower().replace("×", "x").split("x"))
        img = fit_canvas(Image.open(a.src).convert("RGBA"), (w, h), a.pivot, a.pad)
        a.dst.parent.mkdir(parents=True, exist_ok=True)
        img.save(a.dst, optimize=True)
        print(f"{a.dst} {img.size}")
    else:
        bg = Image.open(a.bg).convert("RGBA")
        out = bg.crop((0, a.top, bg.width, bg.height))
        a.out.parent.mkdir(parents=True, exist_ok=True)
        out.save(a.out, optimize=True)
        print(f"{a.out} {out.size}")


if __name__ == "__main__":
    main()
