#!/usr/bin/env python3
"""Сводка плейтеста M2 (S2.5): записи PlaytestRecorder против целей GDD §12 и STATIONS §5.

Вход — файлы и папки в любом сочетании:
  * user://playtest/session_<дата>.jsonl — файл сессии (строка = запись JSON);
  * скопированный Output Godot — берутся строки «PLAYTEST {…}» (строки «PLAYTEST-ИТОГ» пропускаются).
Тестер = имя файла без расширения, а если файлы лежат в своей папке тестера — имя этой папки
(раскладка `плейтест/<тестер>/session_*.jsonl`). Одна и та же сессия из файла и из лога считается один раз.

Запуск:
  python tools/playtest/summarize.py <папка или файлы> [--json сводка.json]
  python tools/playtest/summarize.py --self-test

Формат записей — docs/playtest/PLAYTEST_M2.md, «Формат записей».
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
import tempfile
from pathlib import Path

SCHEMA = 1
LOG_PREFIX = "PLAYTEST "
FILE_SUFFIXES = {".jsonl", ".txt", ".log"}

# Цели — GDD §12 и STATIONS §5 (числа живут там; здесь — копия для сравнения).
ORDER_MEDIAN_SEC = (35.0, 55.0)        # медиана времени заказа
ORDER_TOO_SLOW_SEC = 70.0              # > — ускорить шкалы и анимации
ORDER_TOO_FAST_SEC = 25.0              # < — усложнить заказы
ORDER_LONG_SEC = 90.0                  # допущение 1: доля заказов дольше 90 с
PERFECT_SEC = (4.0, 7.0)               # помол до «идеально»
PERFECT_STEP = 0.02                    # если провал — ±0,02 к приросту за круг
NOVICE_BATCHES = 3                     # «3 попытки новичка»
ZONE_HIT = (0.60, 0.80)                # попадание в зону «идеально»
ZONE_TOO_HARD = 0.50                   # < — зона шире на 0,03
ZONE_TOO_EASY = 0.90                   # > — зона уже
ZONE_STEP = 0.03


# --- чтение ---------------------------------------------------------------------------------------------------------

def _records_from_file(path: Path) -> list[dict]:
    out: list[dict] = []
    jsonl = path.suffix == ".jsonl"
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        text = line.strip()
        if text.startswith(LOG_PREFIX):
            text = text[len(LOG_PREFIX):].strip()
        elif not jsonl:
            continue
        if not text.startswith("{"):
            continue
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and "type" in value:
            out.append(value)
    return out


def _tester_of(path: Path, root: Path | None) -> str:
    if root is not None and path.parent != root:
        return path.parent.name
    return path.stem


def collect(inputs: list[str]) -> dict[str, list[list[dict]]]:
    """Тестер → список сессий; сессия — записи от шапки session до следующей шапки."""
    files: list[tuple[Path, Path | None]] = []
    for raw in inputs:
        p = Path(raw)
        if p.is_dir():
            files += [(f, p) for f in sorted(p.rglob("*")) if f.is_file() and f.suffix in FILE_SUFFIXES]
        elif p.is_file():
            files.append((p, None))
        else:
            print(f"[summarize] нет такого файла или папки: {raw}", file=sys.stderr)
    testers: dict[str, list[list[dict]]] = {}
    seen: set[tuple] = set()
    for path, root in files:
        current: list[dict] | None = None
        for rec in _records_from_file(path):
            if rec.get("type") == "session":
                key = (rec.get("date"), rec.get("version"), rec.get("os"), rec.get("locale"))
                if key in seen:
                    current = None  # эта сессия уже прочитана (файл + лог)
                    continue
                seen.add(key)
                if int(rec.get("schema", 0)) != SCHEMA:
                    print(f"[summarize] {path.name}: формат записей {rec.get('schema')}, ожидался {SCHEMA}",
                          file=sys.stderr)
                current = [rec]
                testers.setdefault(_tester_of(path, root), []).append(current)
            elif current is not None:
                current.append(rec)
    return testers


# --- расчёт ---------------------------------------------------------------------------------------------------------

def _median(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def _share(part: int, whole: int) -> float | None:
    return part / whole if whole else None


def summarize_sessions(sessions: list[list[dict]]) -> dict:
    orders = [r for s in sessions for r in s if r.get("type") == "order"]
    paid = [r for r in orders if r.get("result") == "paid"]
    batches = [r for s in sessions for r in s if r.get("type") == "batch"]
    ground = [b for b in batches if float(b.get("max_grind", 0.0)) > 0.0]
    perfect = [float(b["perfect_sec"]) for b in ground if b.get("perfect_sec") is not None]
    by_gesture = [float(b["perfect_active_sec"]) for b in ground
                  if b.get("perfect_active_sec") is not None and int(b.get("taps", 0)) == 0]
    hardness: dict[str, list[float]] = {}
    for b in ground:
        if b.get("perfect_sec") is not None:
            hardness.setdefault(str(b.get("hardness", "")), []).append(float(b["perfect_sec"]))
    novice: list[dict] = []
    for s in sessions:
        novice += [b for b in s if b.get("type") == "batch" and float(b.get("max_grind", 0.0)) > 0.0][:NOVICE_BATCHES]
    handed = [b for b in ground if b.get("outcome") == "handed"]
    order_secs = [float(r["order_sec"]) for r in paid]
    client_refusals: dict[str, int] = {}
    mortar_refusals: dict[str, int] = {}
    for r in orders:
        for field, total in (("client_refusals", client_refusals), ("mortar_refusals", mortar_refusals)):
            for reason, n in (r.get(field) or {}).items():
                total[reason] = total.get(reason, 0) + int(n)
    events = [r for s in sessions for r in s if r.get("type") == "event"]
    return {
        "sessions": len(sessions),
        "orders_paid": len(paid),
        "orders_left": len(orders) - len(paid),
        "order_sec_median": _median(order_secs),
        "orders_over_90s": _share(sum(1 for x in order_secs if x > ORDER_LONG_SEC), len(order_secs)),
        "stars_3_share": _share(sum(1 for r in paid if int(r.get("stars", 0)) >= 3), len(paid)),
        "wrong_effect": sum(int(r.get("wrong", 0)) for r in orders),
        "batches_ground": len(ground),
        "perfect_sec_median": _median(perfect),
        "perfect_gesture_sec_median": _median(by_gesture),
        "perfect_by_hardness": {k: _median(v) for k, v in sorted(hardness.items())},
        "novice_batches": len(novice),
        "novice_zone_hit": _share(sum(1 for b in novice if b.get("in_zone")), len(novice)),
        "overshoot_share": _share(sum(1 for b in ground if b.get("overshoot")), len(ground)),
        "handed_in_zone": _share(sum(1 for b in handed if b.get("in_zone")), len(handed)),
        "tap_batches": sum(1 for b in ground if int(b.get("taps", 0)) > 0),
        "client_refusals": client_refusals,
        "mortar_refusals": mortar_refusals,
        "pauses": sum(1 for e in events if e.get("event") == "pause" and e.get("on")),
        "layouts": sum(1 for e in events if e.get("event") == "layout"),
    }


def verdicts(s: dict) -> list[tuple[str, str, str]]:
    """(параметр, значение, вывод) — сравнение с целями."""
    out: list[tuple[str, str, str]] = []
    m = s["perfect_sec_median"]
    if m is None:
        out.append(("Помол до «идеально»", "—", "нет данных"))
    elif m > PERFECT_SEC[1]:
        out.append(("Помол до «идеально»", f"{m:.1f} с", f"дольше {PERFECT_SEC[1]:g} с → прирост за круг +{PERFECT_STEP}"))
    elif m < PERFECT_SEC[0]:
        out.append(("Помол до «идеально»", f"{m:.1f} с", f"быстрее {PERFECT_SEC[0]:g} с → прирост за круг −{PERFECT_STEP}"))
    else:
        out.append(("Помол до «идеально»", f"{m:.1f} с", f"в цели {PERFECT_SEC[0]:g}–{PERFECT_SEC[1]:g} с"))
    z = s["novice_zone_hit"]
    if z is None:
        out.append(("Попадание новичка в зону", "—", "нет данных"))
    else:
        shown = f"{z:.0%} ({s['novice_batches']} {_plural(s['novice_batches'], 'партия', 'партии', 'партий')})"
        if z < ZONE_TOO_HARD:
            out.append(("Попадание новичка в зону", shown, f"меньше {ZONE_TOO_HARD:.0%} → зона шире на {ZONE_STEP}"))
        elif z > ZONE_TOO_EASY:
            out.append(("Попадание новичка в зону", shown, f"больше {ZONE_TOO_EASY:.0%} → зона уже на {ZONE_STEP}"))
        elif ZONE_HIT[0] <= z <= ZONE_HIT[1]:
            out.append(("Попадание новичка в зону", shown, f"в цели {ZONE_HIT[0]:.0%}–{ZONE_HIT[1]:.0%}"))
        else:
            out.append(("Попадание новичка в зону", shown, "вне цели, но без правки — смотреть лист наблюдений"))
    o = s["order_sec_median"]
    if o is None:
        out.append(("Время заказа", "—", "нет данных"))
    else:
        if o > ORDER_TOO_SLOW_SEC:
            note = f"дольше {ORDER_TOO_SLOW_SEC:g} с → ускорить шкалы и анимации"
        elif o < ORDER_TOO_FAST_SEC:
            note = (f"короче {ORDER_TOO_FAST_SEC:g} с — на M2 ожидаемо: станция одна, цель "
                    f"{ORDER_MEDIAN_SEC[0]:g}–{ORDER_MEDIAN_SEC[1]:g} с — для лавки из трёх станций")
        elif ORDER_MEDIAN_SEC[0] <= o <= ORDER_MEDIAN_SEC[1]:
            note = f"в цели {ORDER_MEDIAN_SEC[0]:g}–{ORDER_MEDIAN_SEC[1]:g} с"
        else:
            note = "вне цели, без правки"
        out.append(("Время заказа (медиана)", f"{o:.1f} с", note))
    long_share = s["orders_over_90s"]
    out.append(("Заказы дольше 90 с", "—" if long_share is None else f"{long_share:.0%}",
                "допущение 1 (без таймера не скучно): чем меньше, тем лучше"))
    return out


# --- вывод ----------------------------------------------------------------------------------------------------------

SHARE_KEYS = {"orders_over_90s", "stars_3_share", "novice_zone_hit", "overshoot_share", "handed_in_zone"}


def _plural(n: int, one: str, few: str, many: str) -> str:
    if n % 10 == 1 and n % 100 != 11:
        return one
    if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14:
        return few
    return many


def _fmt(value, share: bool = False) -> str:
    if value is None:
        return "—"
    if share:
        return f"{value:.0%}"
    if isinstance(value, float):
        return f"{value:.2f}"
    if isinstance(value, dict):
        return ", ".join(f"{k} {_fmt(v)}" for k, v in value.items()) or "—"
    return str(value)


def report(testers: dict[str, list[list[dict]]]) -> tuple[str, dict]:
    lines: list[str] = []
    per_tester = {name: summarize_sessions(sessions) for name, sessions in sorted(testers.items())}
    everyone = summarize_sessions([s for sessions in testers.values() for s in sessions])
    lines.append(f"Плейтест M2: тестеров {len(testers)}, сессий {everyone['sessions']}, "
                 f"оплачено заказов {everyone['orders_paid']}, партий с помолом {everyone['batches_ground']}")
    lines.append("")
    lines.append("Цели GDD §12:")
    for name, value, note in verdicts(everyone):
        lines.append(f"  {name}: {value} — {note}")
    lines.append("")
    keys = [("orders_paid", "заказов"), ("order_sec_median", "заказ, с"), ("perfect_sec_median", "до идеально, с"),
            ("perfect_gesture_sec_median", "жестом, с"), ("novice_zone_hit", "новичок в зоне"),
            ("overshoot_share", "перетёр"), ("stars_3_share", "3★"), ("wrong_effect", "неверный эффект"),
            ("tap_batches", "партий тапами")]
    lines.append("По тестерам:")
    for name, s in per_tester.items():
        lines.append(f"  {name}: " + "; ".join(f"{label} {_fmt(s[key], key in SHARE_KEYS)}" for key, label in keys))
    lines.append("")
    lines.append(f"До «идеально» по твёрдости (медиана, с): {_fmt(everyone['perfect_by_hardness'])}")
    lines.append(f"Отказы клиента: {_fmt(everyone['client_refusals'])}; ступки: {_fmt(everyone['mortar_refusals'])}")
    lines.append(f"Пауз: {everyone['pauses']}, поворотов: {everyone['layouts']}, заказов без оплаты: {everyone['orders_left']}")
    return "\n".join(lines), {"all": everyone, "testers": per_tester}


# --- самопроверка ---------------------------------------------------------------------------------------------------

def _session(date: str) -> dict:
    return {"type": "session", "schema": SCHEMA, "t": 0.0, "version": "0.2.0", "date": date, "os": "Windows",
            "debug": True, "locale": "ru", "portrait": False, "perfect_from": 0.7, "perfect_to": 0.85}


def _batch(perfect: float | None, in_zone: bool, overshoot: bool, taps: int = 0, outcome: str = "handed") -> dict:
    top = 0.0 if outcome == "returned" else (1.0 if overshoot else 0.72)
    return {"type": "batch", "t": 1.0, "order": "ftue_1", "ingredients": ["ing_sage_bundle"], "hardness": "soft",
            "gestures": 0 if taps else 1, "taps": taps, "ends": {}, "circles": 6.0, "grind": 0.72 if in_zone else top,
            "max_grind": top, "in_zone": in_zone, "overshoot": overshoot, "dust": overshoot,
            "perfect_sec": perfect, "perfect_active_sec": (0.0 if taps else perfect), "active_sec": 1.0,
            "batch_sec": 2.0, "outcome": outcome}


def _order(sec: float, stars: int, wrong: int = 0, refusals: dict | None = None) -> dict:
    return {"type": "order", "order": "ftue_1", "client": "cl_baker", "ftue": True, "ftue_step": 0, "wrong": wrong,
            "client_refusals": refusals or {}, "mortar_refusals": {}, "batches": 1, "discarded": 0, "t": 1.0,
            "result": "paid", "order_sec": sec, "first_drop_sec": 1.0, "first_attempt_sec": sec, "attempts": [],
            "stars": stars, "pay": 30, "streak": 1, "coins": 30}


def self_test() -> int:
    failures: list[str] = []

    def check(title: str, ok: bool) -> None:
        print(("  OK   " if ok else "  FAIL ") + title)
        if not ok:
            failures.append(title)

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "anna").mkdir()
        a = [_session("2026-10-28T10:00:00"), _batch(5.0, True, False), _batch(6.0, True, False),
             _batch(9.0, False, True, outcome="discarded"), _order(20.0, 3), _batch(4.0, True, False, taps=24),
             _order(100.0, 2, wrong=1, refusals={"grind": 2}),
             {"type": "event", "event": "pause", "on": True, "t": 3.0},
             {"type": "event", "event": "pause", "on": False, "t": 3.0}]
        (root / "anna" / "session_1.jsonl").write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in a) + "\n",
                                                       encoding="utf-8")
        # Тот же сеанс в скопированном логе — не должен посчитаться дважды; строки ИТОГ и мусор пропускаются.
        log = ["Godot Engine v4.7", "PLAYTEST-ИТОГ: оплачено заказов 1"] + [LOG_PREFIX + json.dumps(r) for r in a]
        (root / "anna" / "output.txt").write_text("\n".join(log), encoding="utf-8")
        b = [_session("2026-10-28T11:00:00"), _batch(3.0, True, False), _batch(None, False, False, outcome="returned"),
             _order(40.0, 3)]
        (root / "boris.jsonl").write_text("\n".join(json.dumps(r) for r in b) + "\n{битая строка\n", encoding="utf-8")

        testers = collect([str(root)])
        check("тестеры: папка anna и файл boris", sorted(testers) == ["anna", "boris"])
        check("сессия из файла и лога — одна", len(testers.get("anna", [])) == 1)
        text, data = report(testers)
        s = data["all"]
        check("оплачено 3, медиана заказа 40 с", s["orders_paid"] == 3 and s["order_sec_median"] == 40.0)
        check("заказов дольше 90 с — треть", abs(s["orders_over_90s"] - 1 / 3) < 1e-9)
        check("партий с помолом 5 (без помола не считается), медиана до «идеально» 5 с",
              s["batches_ground"] == 5 and s["perfect_sec_median"] == 5.0)
        check("«жестом» — без партий тапами: медиана 5,5 с", s["perfect_gesture_sec_median"] == 5.5)
        check("новичок: первые 3 партии anna (2 в зоне) + 1 партия boris (в зоне) = 75 %",
              s["novice_batches"] == 4 and abs(s["novice_zone_hit"] - 0.75) < 1e-9)
        check("перетёр 1 из 5, отказы клиента grind 2, пауз 1", abs(s["overshoot_share"] - 0.2) < 1e-9
              and s["client_refusals"] == {"grind": 2} and s["pauses"] == 1)
        v = {name: note for name, _, note in verdicts(s)}
        check("вывод: помол и попадание в цели", v["Помол до «идеально»"].startswith("в цели")
              and v["Попадание новичка в зону"].startswith("в цели"))
        slow = verdicts(summarize_sessions([[_session("x"), _batch(9.0, False, True), _batch(8.0, False, True),
                                             _batch(8.5, False, False)]]))
        check("вывод: медленный помол → +0,02, попадание 0 % → зона шире",
              f"+{PERFECT_STEP}" in slow[0][2] and f"шире на {ZONE_STEP}" in slow[1][2])
        check("отчёт печатается", "Цели GDD §12" in text and "anna:" in text and "boris:" in text)
    print(f"SUMMARIZE self-test: {11 - len(failures)}/11 OK")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Сводка плейтеста M2 против целей GDD §12")
    parser.add_argument("inputs", nargs="*", help="файлы session_*.jsonl, логи Output или папки с ними")
    parser.add_argument("--json", metavar="FILE", help="записать сводку в JSON")
    parser.add_argument("--self-test", action="store_true", help="проверить скрипт на синтетических данных")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.inputs:
        parser.error("укажите файлы или папки с записями (или --self-test)")
    testers = collect(args.inputs)
    if not testers:
        print("[summarize] записей плейтеста не найдено", file=sys.stderr)
        return 1
    text, data = report(testers)
    print(text)
    if args.json:
        Path(args.json).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
