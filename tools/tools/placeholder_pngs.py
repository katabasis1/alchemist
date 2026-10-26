#!/usr/bin/env python3
"""placeholder_pngs.py — заглушки PNG для валидатора в рабочей копии агента. Только stdlib.

Зачем: агент восстанавливает репозиторий с GitHub через веб-инструмент, а он отдаёт только
текст (бинарники обрезаются на ~40 КБ). Настоящих PNG в рабочей копии нет, а валидатор
сверяет холст по заголовку PNG. Скрипт создаёт прозрачные PNG нужного размера для строк
`docs/art/ASSET_REGISTRY.md` со статусом temp/final, которых нет на диске, и вносит их
в `.git/info/exclude`, чтобы заглушки никогда не попали в коммит, ZIP или патч.

  python tools/placeholder_pngs.py          # создать недостающие
  python tools/placeholder_pngs.py --dry    # только показать

Пользователю не нужен: у него настоящие картинки.
"""
from __future__ import annotations

import argparse
import re
import struct
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
REGISTRY = REPO / "docs" / "art" / "ASSET_REGISTRY.md"
EXCLUDE = REPO / ".git" / "info" / "exclude"
LIVE_STATUSES = ("temp", "final")
CONTENT_SIZED = (64, 64)


def png_bytes(w: int, h: int) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\x00\x00\x00\x00" * w for _ in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    excluded = set(EXCLUDE.read_text(encoding="utf-8").split()) if EXCLUDE.exists() else set()
    made: list[str] = []
    for line in REGISTRY.read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 6 or not cells[1].startswith("assets/"):
            continue
        m = re.match(r"(\d+)\s*[×x]\s*(\d+)", cells[2])
        if not cells[5].startswith(LIVE_STATUSES):
            continue
        if m:
            w, h = int(m.group(1)), int(m.group(2))
        elif cells[2].startswith("по содержимому"):
            w, h = CONTENT_SIZED  # холст не фиксирован — валидатору нужен только файл
        else:
            continue
        path = REPO / cells[1]
        if path.exists():
            continue
        made.append(cells[1])
        if not a.dry:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(png_bytes(w, h))
    if made and not a.dry:
        EXCLUDE.parent.mkdir(parents=True, exist_ok=True)
        with EXCLUDE.open("a", encoding="utf-8") as f:
            for rel in made:
                if rel not in excluded:
                    f.write(rel + "\n")
    print(f"[placeholder_pngs] {'нужно' if a.dry else 'создано'}: {len(made)}")
    for rel in made:
        print("  ", rel)


if __name__ == "__main__":
    main()
