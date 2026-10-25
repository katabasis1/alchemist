#!/usr/bin/env python3
"""build_fonts.py — шрифты игры из исходников OFL (tools/fonts/src/) → assets/fonts/. Нужен fontTools (есть в Computer).

  python tools/fonts/build_fonts.py           # собрать шрифты и проверить покрытие strings.csv
  python tools/fonts/build_fonts.py --check   # только проверить: все символы ru/en есть в каждом шрифте

Что делает:
  * Nunito (вариативный, ось wght 200–1000, по умолчанию 200 — слишком тонкий) → два статичных
    начертания: nunito_semibold (600, основной текст) и nunito_extrabold (800, кнопки, числа, имена);
  * Kurale (заголовки) — как есть;
  * все три урезаются до латиницы, кириллицы и типографских знаков (web-сборка легче);
  * лицензии OFL копируются рядом (assets/fonts/*_ofl.txt).
OFL разрешает менять шрифт; Reserved Font Name у Kurale и Nunito нет, поэтому имена оставлены.
Код выхода 1 — в строках есть символ, которого нет в шрифте (замените символ или расширьте UNICODES).
"""
from __future__ import annotations

import argparse
import csv
import shutil
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "tools" / "fonts" / "src"
OUT = REPO / "assets" / "fonts"
STRINGS = REPO / "localization" / "strings.csv"

# (исходник, результат, вес по оси wght или None, лицензия)
FONTS = [
    ("kurale_regular.ttf", "kurale_regular.ttf", None, "kurale_ofl.txt"),
    ("nunito_variable.ttf", "nunito_semibold.ttf", 600, "nunito_ofl.txt"),
    ("nunito_variable.ttf", "nunito_extrabold.ttf", 800, "nunito_ofl.txt"),
]
STYLE_NAMES = {600: "SemiBold", 800: "ExtraBold"}

UNICODES = [
    *range(0x0020, 0x007F),  # базовая латиница
    *range(0x00A0, 0x0100),  # латиница-1: « » ° × ·  и неразрывный пробел
    *range(0x0400, 0x0460),  # кириллица (с Ё и ё)
    *range(0x2010, 0x2028),  # тире, кавычки, многоточие, маркеры
    *range(0x2030, 0x203B),  # ‰ ‹ ›
    0x2116,                  # №
]


def rename(font: TTFont, style: str) -> None:
    """Имя начертания в таблице name (Godot показывает его в инспекторе)."""
    name = font["name"]
    family = name.getDebugName(16) or name.getDebugName(1) or "Font"
    for rec in list(name.names):
        if rec.nameID in (1, 2, 4, 6, 16, 17):
            name.removeNames(nameID=rec.nameID)
    full = f"{family} {style}"
    ps = f"{family.replace(' ', '')}-{style}"
    for nid, val in ((1, full), (2, "Regular"), (4, full), (6, ps), (16, family), (17, style)):
        name.setName(val, nid, 3, 1, 0x409)


def build() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.hinting = False
    opts.drop_tables += ["DSIG"]
    for src, dst, wght, lic in FONTS:
        font = TTFont(SRC / src)
        if wght is not None:
            font = instancer.instantiateVariableFont(font, {"wght": wght})
            rename(font, STYLE_NAMES[wght])
        sub = subset.Subsetter(opts)
        sub.populate(unicodes=UNICODES)
        sub.subset(font)
        font.save(OUT / dst)
        shutil.copyfile(SRC / lic, OUT / lic)
        print(f"[fonts] {dst}: {(OUT / dst).stat().st_size // 1024} КБ")


def check() -> int:
    if not STRINGS.exists():
        print("[fonts] нет localization/strings.csv — проверять нечего")
        return 0
    chars: dict[str, list[str]] = {}
    with STRINGS.open(encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    for row in rows[1:]:
        for text in row[1:]:
            for ch in text:
                if ch not in "\n\t":
                    chars.setdefault(ch, []).append(row[0])
    bad = 0
    for _, dst, _, _ in FONTS:
        path = OUT / dst
        if not path.exists():
            print(f"[fonts] нет {path.relative_to(REPO)} — запустите без --check")
            return 1
        cmap = TTFont(path).getBestCmap()
        missing = sorted(ch for ch in chars if ord(ch) not in cmap)
        for ch in missing:
            bad += 1
            print(f"[fonts] {dst}: нет символа «{ch}» U+{ord(ch):04X} (ключи: {', '.join(chars[ch][:3])})")
    print(f"[fonts] символов в строках: {len(chars)}, шрифтов: {len(FONTS)}, нехватает: {bad}")
    return 1 if bad else 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="только проверить покрытие символов")
    a = ap.parse_args()
    if not a.check:
        build()
    sys.exit(check())


if __name__ == "__main__":
    main()
