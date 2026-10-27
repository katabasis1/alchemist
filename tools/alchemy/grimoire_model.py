#!/usr/bin/env python3
"""Эталон Гримуара (S3.2): копия data/alchemy/grimoire_rules.gd на Python + самопроверка.

Каждая функция — строка в строку функция GrimoireRules с тем же именем; правила смеси берутся из
rules_model.py (копия AlchemyRules). Правишь правило — правь оба файла; самопроверка сверяет списки
функций и ключи страницы.

Что решено (GDD §3.5):
  * рецепт узнаётся по набору значимых свойств зелья (≥ 0,3 доли), следы не мешают;
    нет такого набора — «Странная смесь» (None), страницы у неё нет;
  * зелье оценивается по своему рецепту, а не по заказу: сила — самое слабое свойство рецепта,
    чистота — доли свойств рецепта / все доли, «безупречно» — AlchemyRules.is_flawless;
  * страница: варок, лучшая сила, лучшая чистота (звёзды, каждая — свой рекорд), «безупречных»;
    открыта = страница есть; золотая = «безупречных» ≥ EconomyConfig.golden_page_flawless (не хранится).

Запуск:
  python tools/alchemy/grimoire_model.py               # пути рецептов: какой рецепт узнан, оценка варки
  python tools/alchemy/grimoire_model.py --self-test   # все проверки; код возврата 1 при ошибке
Только stdlib.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rules_model as R  # noqa: E402

GD_GRIMOIRE = R.ROOT / "data" / "alchemy" / "grimoire_rules.gd"

# Ключи страницы (в сохранении — строки) и итога варки.
KEY_BREWS = "brews"
KEY_BEST_STRENGTH = "best_strength"
KEY_BEST_PURITY = "best_purity"
KEY_FLAWLESS = "flawless"
PAGE_KEYS = (KEY_BREWS, KEY_BEST_STRENGTH, KEY_BEST_PURITY, KEY_FLAWLESS)
BREW_STRENGTH = "strength"
BREW_PURITY = "purity"
BREW_FLAWLESS = "flawless"


# --- GrimoireRules ---------------------------------------------------------------------------------------------------
def recognize(mixture: dict, catalog: R.DataCatalog):
    return catalog.recipe_for(R.significant(mixture, catalog.economy))


def brew(mixture: dict, recipe: R.RecipeData, economy: R.EconomyConfig) -> dict:
    strength = R.weakest_stars(mixture, recipe.property_set, economy)
    purity = R.purity_stars(R.purity(mixture, recipe.property_set), economy)
    return {BREW_STRENGTH: strength, BREW_PURITY: purity, BREW_FLAWLESS: R.is_flawless(strength, purity, economy)}


def parse_page(value) -> dict:
    source = value if isinstance(value, dict) else {}
    return {
        KEY_BREWS: _count(source.get(KEY_BREWS)),
        KEY_BEST_STRENGTH: _count(source.get(KEY_BEST_STRENGTH)),
        KEY_BEST_PURITY: _count(source.get(KEY_BEST_PURITY)),
        KEY_FLAWLESS: _count(source.get(KEY_FLAWLESS)),
    }


def parse_grimoire(value) -> dict:
    result: dict = {}
    if not isinstance(value, dict):
        return result
    for key in value:
        recipe_id = str(key)
        if recipe_id == "":
            continue
        result[recipe_id] = parse_page(value[key])
    return result


def after_brew(page, result: dict) -> dict:
    next_ = parse_page(page)
    next_[KEY_BREWS] += 1
    next_[KEY_BEST_STRENGTH] = max(next_[KEY_BEST_STRENGTH], int(result[BREW_STRENGTH]))
    next_[KEY_BEST_PURITY] = max(next_[KEY_BEST_PURITY], int(result[BREW_PURITY]))
    if bool(result[BREW_FLAWLESS]):
        next_[KEY_FLAWLESS] += 1
    return next_


def is_golden(page: dict, economy: R.EconomyConfig) -> bool:
    return _count(page.get(KEY_FLAWLESS)) >= economy.golden_page_flawless


# В GDScript bool — не int и не float: true в сохранении счётчиком не считается.
def _count(value) -> int:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return max(int(value), 0)
    return 0


GRIMOIRE_FUNCTIONS = ["recognize", "brew", "parse_page", "parse_grimoire", "after_brew", "is_golden", "_count"]


# --- Самопроверка -----------------------------------------------------------------------------------------------------
def _recipe_id(recipe) -> str | None:
    return recipe.id if recipe is not None else None


def check_recognition(c: R.Checks, catalog: R.DataCatalog) -> None:
    props = [p.id for p in catalog.properties]
    for recipe in catalog.recipes:
        pure = {p: 1.0 for p in recipe.property_set}
        c.check("узнан по своим свойствам: %s" % recipe.id, _recipe_id(recognize(pure, catalog)) == recipe.id)
        dirty = dict(pure)
        for other in props:
            if other not in dirty:
                dirty[other] = 0.29
        found = recognize(dirty, catalog)
        c.check("следы 0,29 не мешают: %s" % recipe.id, _recipe_id(found) == recipe.id,
                "узнано %s" % _recipe_id(found))
        backwards = dict(reversed(list(dirty.items())))
        c.check("порядок ключей не важен: %s" % recipe.id, _recipe_id(recognize(backwards, catalog)) == recipe.id)
    c.check("ровно 0,3 — свойство есть: Жизнь 1 + Жар 0,3 → Согревающий бальзам",
            _recipe_id(recognize({"life": 1.0, "heat": 0.3}, catalog)) == "warming_balm")
    c.check("0,2999 (в допуске EPSILON) — тоже есть", _recipe_id(recognize({"life": 1.0, "heat": 0.2999}, catalog))
            == "warming_balm")
    c.check("0,299 — след: Жизнь 1 + Жар 0,299 → Целебный бальзам",
            _recipe_id(recognize({"life": 1.0, "heat": 0.299}, catalog)) == "healing_balm")
    c.check("пустая смесь — «Странная смесь»", recognize({}, catalog) is None)
    c.check("одни следы — «Странная смесь»", recognize({"life": 0.2, "heat": 0.1}, catalog) is None)
    c.check("Едкость + Холод + Сон — «Странная смесь» (такого рецепта нет)",
            recognize({"acid": 1.0, "cold": 1.0, "sleep": 1.0}, catalog) is None)
    c.check("четыре значимых свойства — «Странная смесь»",
            recognize({"life": 1.0, "heat": 1.0, "light": 1.0, "cold": 1.0}, catalog) is None)
    sets = [tuple(sorted(r.property_set)) for r in catalog.recipes]
    c.check("наборы свойств рецептов не повторяются (иначе узнаётся первый)", len(sets) == len(set(sets)))


def check_paths(c: R.Checks, catalog: R.DataCatalog) -> list:
    reports = R.all_paths(catalog)
    for r in reports:
        recipe = next(item for item in catalog.recipes if item.id == r["recipe"])
        mixture = r.get("mixture", {})
        found = recognize(mixture, catalog)
        c.check("путь даёт свой рецепт: %s ← %s" % (recipe.id, " → ".join(r["path"])), _recipe_id(found) == recipe.id,
                "узнано %s" % _recipe_id(found))
        result = brew(mixture, recipe, catalog.economy)
        r["brew"] = result
        c.check("оценка варки = оценка пути: %s" % recipe.id,
                result[BREW_STRENGTH] == r["strength"] and result[BREW_PURITY] == r["purity_stars"],
                "%s против %d/%d" % (result, r["strength"], r["purity_stars"]))
    return reports


def check_brew(c: R.Checks, catalog: R.DataCatalog) -> None:
    e = catalog.economy
    balm = next(item for item in catalog.recipes if item.id == "healing_balm")
    pair = next(item for item in catalog.recipes if item.id == "warming_balm")
    c.check("Жизнь 3 — Целебный бальзам ★★★/★★★, безупречно",
            brew({"life": 3.0}, balm, e) == {BREW_STRENGTH: 3, BREW_PURITY: 3, BREW_FLAWLESS: True})
    c.check("Жизнь 3 + Жар 0,15 (95,2 %) — безупречно", brew({"life": 3.0, "heat": 0.15}, balm, e)[BREW_FLAWLESS])
    c.check("Жизнь 3 + Жар 0,2 (93,75 %) — ★★★/★★, не безупречно",
            brew({"life": 3.0, "heat": 0.2}, balm, e) == {BREW_STRENGTH: 3, BREW_PURITY: 2, BREW_FLAWLESS: False})
    c.check("пара: сила — по слабейшему (Жизнь 3, Жар 1,2 → ★)",
            brew({"life": 3.0, "heat": 1.2}, pair, e)[BREW_STRENGTH] == 1)
    c.check("пара: следы Холода 0,5 из 4,5 — чистота 88,9 % → ★★",
            brew({"life": 2.0, "heat": 2.0, "cold": 0.5}, pair, e)[BREW_PURITY] == 2)


def check_pages(c: R.Checks, catalog: R.DataCatalog) -> None:
    e = catalog.economy
    best = {BREW_STRENGTH: 3, BREW_PURITY: 3, BREW_FLAWLESS: True}
    weak = {BREW_STRENGTH: 1, BREW_PURITY: 2, BREW_FLAWLESS: False}
    pure_weak = {BREW_STRENGTH: 1, BREW_PURITY: 3, BREW_FLAWLESS: False}
    strong_dirty = {BREW_STRENGTH: 3, BREW_PURITY: 1, BREW_FLAWLESS: False}
    empty = {KEY_BREWS: 0, KEY_BEST_STRENGTH: 0, KEY_BEST_PURITY: 0, KEY_FLAWLESS: 0}
    c.check("новая страница — нули", parse_page(None) == empty and parse_page({}) == empty)
    first = after_brew(None, weak)
    c.check("первая варка: варок 1, рекорды ★/★★, безупречных 0",
            first == {KEY_BREWS: 1, KEY_BEST_STRENGTH: 1, KEY_BEST_PURITY: 2, KEY_FLAWLESS: 0})
    c.check("after_brew не меняет входную страницу", after_brew(first, best) is not first
            and first == {KEY_BREWS: 1, KEY_BEST_STRENGTH: 1, KEY_BEST_PURITY: 2, KEY_FLAWLESS: 0})
    split = after_brew(after_brew(None, pure_weak), strong_dirty)
    c.check("рекорды независимы: ★/★★★ и ★★★/★ → ★★★/★★★, но безупречных 0",
            split[KEY_BEST_STRENGTH] == 3 and split[KEY_BEST_PURITY] == 3 and split[KEY_FLAWLESS] == 0)
    worse = after_brew(after_brew(None, best), weak)
    c.check("слабая варка рекорд не снижает, варок 2",
            worse == {KEY_BREWS: 2, KEY_BEST_STRENGTH: 3, KEY_BEST_PURITY: 3, KEY_FLAWLESS: 1})
    need = e.golden_page_flawless
    c.check("золотая страница — после %d «безупречных» (GDD §3.5)" % need, need == 3)
    page = parse_page(None)
    golden_at = []
    for result in (best, weak, best, weak, best, weak):  # «безупречных» после каждой: 1, 1, 2, 2, 3, 3
        page = after_brew(page, result)
        golden_at.append(is_golden(page, e))
    c.check("золотая ровно на 3-й безупречной, слабая варка её не отнимает",
            golden_at == [False, False, False, False, True, True], str(golden_at))
    c.check("пустая страница не золотая", not is_golden(parse_page(None), e))


def check_parse(c: R.Checks) -> None:
    c.check("JSON-числа (float) → целые",
            parse_page({"brews": 2.0, "best_strength": 3.0, "best_purity": 1.0, "flawless": 1.0})
            == {KEY_BREWS: 2, KEY_BEST_STRENGTH: 3, KEY_BEST_PURITY: 1, KEY_FLAWLESS: 1})
    c.check("мусор → 0: отрицательные, строки, bool, None",
            parse_page({"brews": -4, "best_strength": "3", "best_purity": True, "flawless": None})
            == {KEY_BREWS: 0, KEY_BEST_STRENGTH: 0, KEY_BEST_PURITY: 0, KEY_FLAWLESS: 0})
    c.check("лишние ключи отброшены, старый формат S1.4 (best_stars) не мешает «безупречным»",
            parse_page({"best_stars": 2, "flawless": 1, "x": 9})
            == {KEY_BREWS: 0, KEY_BEST_STRENGTH: 0, KEY_BEST_PURITY: 0, KEY_FLAWLESS: 1})
    c.check("не словарь — пустой Гримуар", parse_grimoire(None) == {} and parse_grimoire([1, 2]) == {})
    book = parse_grimoire({"healing_balm": {"brews": 3.0, "flawless": 1.0}, "": {"brews": 1}, "smith_flux": 7})
    c.check("пустой ключ отброшен; страница-мусор = открыта с нулями",
            list(book) == ["healing_balm", "smith_flux"] and book["smith_flux"] == parse_page(None)
            and book["healing_balm"][KEY_BREWS] == 3)
    again = parse_grimoire(json.loads(json.dumps(book)))
    c.check("запись → JSON → чтение: то же самое", again == book)
    c.check("чтение повторно ничего не меняет (идемпотентно)", parse_grimoire(again) == again)


def check_sync(c: R.Checks) -> None:
    if not GD_GRIMOIRE.exists():
        c.check("grimoire_rules.gd на месте", False, str(GD_GRIMOIRE))
        return
    text = GD_GRIMOIRE.read_text(encoding="utf-8")
    gd = re.findall(r"^static func ([a-z_][a-z0-9_]*)\(", text, re.MULTILINE)
    c.check("функции GrimoireRules = функции эталона (%d)" % len(gd), sorted(gd) == sorted(GRIMOIRE_FUNCTIONS),
            "только в .gd: %s; только в .py: %s" % (sorted(set(gd) - set(GRIMOIRE_FUNCTIONS)),
                                                    sorted(set(GRIMOIRE_FUNCTIONS) - set(gd))))
    consts = dict(re.findall(r'^const ([A-Z_]+): (?:String|StringName) = &?"([a-z_]*)"', text, re.MULTILINE))
    mine = {name: value for name, value in globals().items() if re.fullmatch(r"(KEY|BREW)_[A-Z_]+", name)}
    c.check("ключи страницы и варки совпадают с .gd", consts == mine, "%s против %s" % (consts, mine))


def self_test(catalog: R.DataCatalog) -> int:
    c = R.Checks()
    check_recognition(c, catalog)
    check_paths(c, catalog)
    check_brew(c, catalog)
    check_pages(c, catalog)
    check_parse(c)
    check_sync(c)
    total_checks = c.passed + len(c.failed)
    print("GRIMOIRE: %d/%d %s" % (c.passed, total_checks, "OK" if not c.failed else "FAIL"))
    return 0 if not c.failed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    catalog = R.load_catalog()
    if args.self_test:
        return self_test(catalog)
    for r in R.all_paths(catalog):
        recipe = next(item for item in catalog.recipes if item.id == r["recipe"])
        found = recognize(r.get("mixture", {}), catalog)
        result = brew(r.get("mixture", {}), recipe, catalog.economy)
        print("%-20s → %-20s сила %d★, чистота %d★%s" % (recipe.id, _recipe_id(found), result[BREW_STRENGTH],
                                                         result[BREW_PURITY],
                                                         ", безупречно" if result[BREW_FLAWLESS] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
