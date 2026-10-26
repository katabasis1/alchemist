#!/usr/bin/env python3
"""derive.py — производные ассеты из уже вырезанных PNG (контракт docs/art/ASSET_REGISTRY.md).

  fit   — вписать готовый PNG с альфой в холст реестра (опора center/bottom, поля pad):
          python tools/art/derive.py fit SRC.png assets/ui/icon_coin.png --canvas 256x256 --pivot center --pad 8
  bench — вырезать слой прилавка из фона (всё ниже линии прилавка), чтобы клиент стоял ЗА прилавком:
          python tools/art/derive.py bench [--bg assets/backgrounds/bg_workshop.png] [--top 756]
          → assets/backgrounds/bg_workshop_bench.png (1920×(1080-top)). top — первая строка контура
          края прилавка; при замене фона на финальный проверить и при необходимости поправить
          top в реестре и позицию узла Bench в scenes/workshop/workshop.tscn.
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
    a = ap.parse_args()
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
