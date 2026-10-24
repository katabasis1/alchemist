#!/usr/bin/env python3
"""cutout.py — вырезка фона у сгенерированной графики (хромакей) для «Лавки алхимика».

Назначение: превратить картинку на однотонном фоне (#FF00FF или #00FF00) в PNG с альфой,
корректно обработав полупрозрачное стекло и сглаженные края (unmix + despill), обрезать по
содержимому и вписать в холст по контракту ассета (docs/art/ASSET_REGISTRY.md).

Режимы:
  --mode flood   (по умолчанию) прозрачным становится только фон, связанный с краем картинки;
                 замкнутые контуром области не трогаются (для непрозрачных предметов).
  --mode global  ключ применяется ко всей картинке (для стекла: фон, видимый сквозь колбу,
                 становится прозрачным/полупрозрачным).
  --split        разрезать лист на отдельные спрайты (связные области), порядок: строки сверху вниз,
                 внутри строки слева направо. Имена: <out>_01.png, <out>_02.png ...

Холст:
  --canvas WxH   вписать в холст заданного размера (сохраняя пропорции);
  --pivot center|bottom  выравнивание внутри холста (bottom — предмет «стоит» на нижней кромке);
  --pad N        отступ в пикселях внутри холста (по умолчанию 8).

Пример:
  python tools/art/cutout.py in.png -o assets/props/mortar.png --canvas 512x512 --pivot bottom
  python tools/art/cutout.py flask.png -o flask.png --mode global --canvas 384x512
  python tools/art/cutout.py sheet.png -o assets/ingredients/ing --split --canvas 256x256
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


def detect_key(rgb: np.ndarray) -> str:
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]).astype(np.int32)
    med = np.median(border, axis=0)
    r, g, b = med
    if g > r + 60 and g > b + 60:
        return "green"
    if r > g + 60 and b > g + 60:
        return "magenta"
    sys.exit(f"Не удалось определить цвет фона по краю (медиана {med}). Укажите --key.")


def keyness(rgbf: np.ndarray, key: str) -> np.ndarray:
    """0..1 — насколько пиксель похож на цвет фона (по «хроме», а не по яркости)."""
    r, g, b = rgbf[..., 0], rgbf[..., 1], rgbf[..., 2]
    if key == "magenta":
        k = np.minimum(r, b) - g
    else:
        k = g - np.maximum(r, b)
    return np.clip(k, 0.0, 1.0)


def compute_alpha(rgbf: np.ndarray, key: str, lo: float, hi: float) -> np.ndarray:
    k = keyness(rgbf, key)
    # k >= hi → полностью фон; k <= lo → полностью предмет
    a = 1.0 - np.clip((k - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    return a


def unmix(rgbf: np.ndarray, alpha: np.ndarray, key: str, tol: float = 0.05) -> np.ndarray:
    """Убирает примесь цвета фона: P = a*F + (1-a)*K  ->  F = (P - (1-a)K) / a,
    затем despill только в зоне края (2 px вокруг полупрозрачных пикселей)."""
    K = np.array([1.0, 0.0, 1.0]) if key == "magenta" else np.array([0.0, 1.0, 0.0])
    a = np.clip(alpha, 1e-3, 1.0)[..., None]
    f = np.clip((rgbf - (1.0 - a) * K) / a, 0.0, 1.0)
    edge = (alpha < 0.98).astype(np.uint8)
    edge = cv2.dilate(edge, np.ones((7, 7), np.uint8)).astype(bool)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    if key == "magenta":
        spill = np.clip(np.minimum(r, b) - g - tol, 0.0, 1.0) * edge
        f[..., 0] = r - spill
        f[..., 2] = b - spill
    else:
        spill = np.clip(g - np.maximum(r, b) - tol, 0.0, 1.0) * edge
        f[..., 1] = g - spill
    return np.clip(f, 0.0, 1.0)


def flood_restrict(alpha: np.ndarray, k: np.ndarray, strong: float) -> np.ndarray:
    """Прозрачность у фона, связанного с краем. Замкнутые области делаются непрозрачными,
    КРОМЕ «карманов» чистого цвета фона (keyness >= strong) — например, просветов между лепестками."""
    bg = (alpha < 0.5).astype(np.uint8)
    n, labels = cv2.connectedComponents(bg, connectivity=4)
    edge_labels = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])))
    edge_labels.discard(0)
    outside = np.isin(labels, list(edge_labels))
    # сглаженный край оставляем как есть; внутренние «дыры» делаем непрозрачными
    inner_holes = (bg == 1) & (~outside) & (k < strong)
    out = alpha.copy()
    out[inner_holes] = 1.0
    return out


def components(alpha: np.ndarray, min_area: int, merge_px: int) -> list[tuple[int, int, int, int]]:
    mask = (alpha > 0.1).astype(np.uint8)
    if merge_px > 0:
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (merge_px * 2 + 1, merge_px * 2 + 1))
        mask = cv2.dilate(mask, k)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    boxes = []
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if area >= min_area:
            boxes.append((x, y, w, h))
    if not boxes:
        return boxes
    # сортировка: строки (по центру Y с допуском), затем X
    hmed = float(np.median([b[3] for b in boxes]))
    boxes.sort(key=lambda b: (round((b[1] + b[3] / 2) / max(hmed * 0.6, 1)), b[0]))
    return boxes


def fit_canvas(img: Image.Image, canvas: tuple[int, int] | None, pivot: str, pad: int) -> Image.Image:
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    if canvas is None:
        return img
    cw, ch = canvas
    scale = min((cw - 2 * pad) / img.width, (ch - 2 * pad) / img.height)
    nw, nh = max(1, round(img.width * scale)), max(1, round(img.height * scale))
    img = img.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    x = (cw - nw) // 2
    y = (ch - nh) // 2 if pivot == "center" else ch - pad - nh
    out.alpha_composite(img, (x, y))
    return out


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("input")
    p.add_argument("-o", "--output", required=True, help="файл .png или префикс при --split")
    p.add_argument("--key", choices=["magenta", "green", "auto"], default="auto")
    p.add_argument("--mode", choices=["flood", "global"], default="flood")
    p.add_argument("--lo", type=float, default=0.12, help="порог «точно предмет» (0..1)")
    p.add_argument("--hi", type=float, default=0.55, help="порог «точно фон» (0..1)")
    p.add_argument("--strong", type=float, default=0.6, help="flood: карманы с keyness выше — прозрачные")
    p.add_argument("--split", action="store_true")
    p.add_argument("--min-area", type=int, default=1500)
    p.add_argument("--merge-px", type=int, default=6, help="склейка мелких частей одного спрайта")
    p.add_argument("--canvas", type=str, default=None, help="WxH, например 512x512")
    p.add_argument("--pivot", choices=["center", "bottom"], default="center")
    p.add_argument("--pad", type=int, default=8)
    a = p.parse_args()

    src = Image.open(a.input).convert("RGB")
    rgb = np.asarray(src)
    key = detect_key(rgb) if a.key == "auto" else a.key
    rgbf = rgb.astype(np.float64) / 255.0
    alpha = compute_alpha(rgbf, key, a.lo, a.hi)
    if a.mode == "flood":
        alpha = flood_restrict(alpha, keyness(rgbf, key), a.strong)
    color = unmix(rgbf, alpha, key)
    # лёгкая чистка «пыли» альфы
    alpha[alpha < 0.03] = 0.0
    rgba = np.dstack([color, alpha])
    full = Image.fromarray((rgba * 255).round().astype(np.uint8), "RGBA")
    canvas = tuple(int(v) for v in a.canvas.lower().split("x")) if a.canvas else None

    out = Path(a.output)
    if a.split:
        boxes = components(alpha, a.min_area, a.merge_px)
        out.parent.mkdir(parents=True, exist_ok=True)
        for i, (x, y, w, h) in enumerate(boxes, 1):
            piece = full.crop((x, y, x + w, y + h))
            piece = fit_canvas(piece, canvas, a.pivot, a.pad)
            path = out.parent / f"{out.stem}_{i:02d}.png"
            piece.save(path, optimize=True)
            print(f"{path}  {piece.size}")
    else:
        out.parent.mkdir(parents=True, exist_ok=True)
        img = fit_canvas(full, canvas, a.pivot, a.pad)
        img.save(out, optimize=True)
        print(f"{out}  {img.size}  key={key} mode={a.mode}")


if __name__ == "__main__":
    main()
