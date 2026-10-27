#!/usr/bin/env python3
"""Эталон правил алхимии (S3.1): копия data/alchemy/alchemy_rules.gd на Python + самопроверка.

Зачем: у агента нет Godot, а правила должны быть проверены до станций S4. Каждая функция здесь —
строка в строку функция AlchemyRules с тем же именем и тем же порядком операций (float — double и там,
и тут). Правишь правило — правь оба файла; самопроверка сверяет списки функций.

Данные берутся из проекта: data/catalog.tres (порядок свойств, ингредиентов, рецептов), .tres свойств,
ингредиентов, рецептов и EconomyConfig.

Запуск:
  python tools/alchemy/rules_model.py               # пути рецептов: что получилось, звёзды
  python tools/alchemy/rules_model.py --self-test   # все проверки; код возврата 1 при ошибке
  python tools/alchemy/rules_model.py --json out.json

Что проверяет --self-test:
  * числа GDD §3.2–3.3 (извлечение, прирост помола, порог, звёзды, слои, слив, температура, пар, дым);
  * каждый рецепт: его путь из RecipeData.hint_steps (= «Пример пути» GDD §5.1) даёт именно этот рецепт,
    плюс запасные пути из GDD (EXTRA_PATHS);
  * GDD §3.4: горелка снимает летучие по возрастанию температуры {Холод} → {Холод, Сон} → {+ Едкость};
  * шаг dt не меняет итог: горелка по одному и тому же расписанию огня с шагами 1/2/3/7/16 на тик и
    случайным дроблением; слив по кадрам = слив одним куском; помол частями = помол сразу;
  * детерминизм: порядок ключей смеси на входе не меняет слои и слив;
  * имена функций совпадают с alchemy_rules.gd.
Только stdlib.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GD_RULES = ROOT / "data" / "alchemy" / "alchemy_rules.gd"

# --- AlchemyRules: константы ---------------------------------------------------------------------------------------
EPSILON = 0.0001
KEY_TOP = "top"
KEY_BOTTOM = "bottom"

SOFT, MEDIUM, HARD = 0, 1, 2
NEVER = -1.0


# --- Данные (копии классов data/*) ---------------------------------------------------------------------------------
@dataclass
class EconomyConfig:
    values: dict

    def __getattr__(self, name: str):
        try:
            return self.__dict__["values"][name]
        except KeyError as exc:
            raise AttributeError(name) from exc

    def is_significant(self, amount_: float) -> bool:
        return amount_ >= self.significance_threshold

    def strength_stars(self, amount_: float) -> int:
        return self._stars(amount_, self.strength_thresholds)

    def purity_stars(self, purity_: float) -> int:
        return self._stars(purity_, self.purity_thresholds)

    def max_stars(self) -> int:
        return len(self.strength_thresholds)

    def extraction(self, grind: float) -> float:
        if grind < self.perfect_from:
            return self.extraction_floor + (1.0 - self.extraction_floor) * grind / self.perfect_from
        if grind <= self.perfect_to:
            return 1.0
        return 1.0 - self.overgrind_slope * (grind - self.perfect_to)

    def grind_per_circle(self, hardness: int) -> float:
        if hardness == MEDIUM:
            return self.grind_medium
        if hardness == HARD:
            return self.grind_hard
        return self.grind_soft

    @staticmethod
    def _stars(value: float, thresholds: list) -> int:
        return sum(1 for threshold in thresholds if value >= threshold)


@dataclass
class PropertyData:
    id: str
    density_rank: int = 1
    evaporate_temp: float = NEVER
    burn_temp: float = NEVER

    def evaporates_at(self, temp: float) -> bool:
        return self.evaporate_temp >= 0.0 and temp >= self.evaporate_temp

    def burns_at(self, temp: float) -> bool:
        return self.burn_temp >= 0.0 and temp >= self.burn_temp


@dataclass
class IngredientData:
    id: str
    properties: dict
    hardness: int = SOFT


@dataclass
class RecipeData:
    id: str
    property_set: list
    hint_steps: list
    tier: int = 1

    def matches(self, significant_: list) -> bool:
        if len(significant_) != len(self.property_set):
            return False
        return all(property_id in significant_ for property_id in self.property_set)


@dataclass
class DataCatalog:
    properties: list = field(default_factory=list)
    ingredients: list = field(default_factory=list)
    recipes: list = field(default_factory=list)
    economy: EconomyConfig | None = None

    def property(self, id_: str) -> PropertyData | None:
        return next((item for item in self.properties if item.id == id_), None)

    def ingredient(self, id_: str) -> IngredientData | None:
        return next((item for item in self.ingredients if item.id == id_), None)

    def recipe_for(self, significant_: list) -> RecipeData | None:
        return next((item for item in self.recipes if item.matches(significant_)), None)


# --- AlchemyRules: смесь (GDD §3.2) --------------------------------------------------------------------------------
def total(mixture: dict) -> float:
    sum_ = 0.0
    for property_id in mixture:
        sum_ += float(mixture[property_id])
    return sum_


def amount(mixture: dict, property_id: str) -> float:
    return float(mixture.get(property_id, 0.0))


def cleaned(mixture: dict) -> dict:
    result = {}
    for property_id in mixture:
        value = float(mixture[property_id])
        if value > EPSILON:
            result[property_id] = value
    return result


def combine(a: dict, b: dict) -> dict:
    result = {}
    for property_id in a:
        result[property_id] = float(a[property_id])
    for property_id in b:
        result[property_id] = result.get(property_id, 0.0) + float(b[property_id])
    return cleaned(result)


def scaled(mixture: dict, factor: float) -> dict:
    result = {}
    for property_id in mixture:
        result[property_id] = float(mixture[property_id]) * factor
    return cleaned(result)


def is_present(value: float, economy: EconomyConfig) -> bool:
    return economy.is_significant(value + EPSILON)


def significant(mixture: dict, economy: EconomyConfig) -> list:
    return [property_id for property_id in mixture if is_present(float(mixture[property_id]), economy)]


def traces(mixture: dict, economy: EconomyConfig) -> list:
    result = []
    for property_id in mixture:
        value = float(mixture[property_id])
        if value > EPSILON and not is_present(value, economy):
            result.append(property_id)
    return result


def strength_stars(value: float, economy: EconomyConfig) -> int:
    return economy.strength_stars(value + EPSILON)


def purity(mixture: dict, wanted: list) -> float:
    sum_ = total(mixture)
    if sum_ <= 0.0:
        return 0.0
    good = 0.0
    for property_id in wanted:
        good += amount(mixture, property_id)
    return good / sum_


def purity_stars(value: float, economy: EconomyConfig) -> int:
    return economy.purity_stars(value + EPSILON)


def weakest_stars(mixture: dict, wanted: list, economy: EconomyConfig) -> int:
    if not wanted:
        return 0
    weakest = economy.max_stars()
    for property_id in wanted:
        weakest = min(weakest, strength_stars(amount(mixture, property_id), economy))
    return weakest


def is_flawless(weakest: int, purity_stars_: int, economy: EconomyConfig) -> bool:
    top = economy.max_stars()
    return weakest >= top and purity_stars_ >= top


# --- AlchemyRules: помол (GDD §3.3) --------------------------------------------------------------------------------
def hardest(ingredients: list) -> int:
    result = SOFT
    for item in ingredients:
        if item is not None and item.hardness > result:
            result = item.hardness
    return result


def grind_per_circle(ingredients: list, economy: EconomyConfig) -> float:
    if not ingredients:
        return 0.0
    return economy.grind_per_circle(hardest(ingredients))


def _clampf(value: float, low: float, high: float) -> float:
    return low if value < low else high if value > high else value


def grind_after(grind: float, circles: float, ingredients: list, economy: EconomyConfig) -> float:
    return _clampf(grind + max(circles, 0.0) * grind_per_circle(ingredients, economy), 0.0, 1.0)


def extraction(grind: float, economy: EconomyConfig) -> float:
    return economy.extraction(_clampf(grind, 0.0, 1.0))


def extract(ingredients: list, k: float) -> dict:
    result = {}
    for item in ingredients:
        if item is None:
            continue
        for property_id in item.properties:
            result[property_id] = result.get(property_id, 0.0) + item.properties[property_id] * k
    return cleaned(result)


def ground(ingredients: list, grind: float, economy: EconomyConfig) -> dict:
    return extract(ingredients, extraction(grind, economy))


# --- AlchemyRules: отстаивание (GDD §3.3, §3.4) --------------------------------------------------------------------
def _lies_below(a: PropertyData, b: PropertyData) -> bool:
    if a.density_rank != b.density_rank:
        return a.density_rank < b.density_rank
    return a.id < b.id


def layers(mixture: dict, catalog: DataCatalog) -> list:
    result: list = []
    for property_id in cleaned(mixture):
        data = catalog.property(property_id)
        if data is None:
            continue
        at = len(result)
        while at > 0 and _lies_below(data, catalog.property(result[at - 1])):
            at -= 1
        result.insert(at, property_id)
    return result


def layer_heights(mixture: dict, catalog: DataCatalog, economy: EconomyConfig) -> list:
    ids = layers(mixture, catalog)
    count = len(ids)
    if count == 0:
        return []
    heights = [0.0] * count
    floor_height = economy.min_layer_height
    if floor_height * count >= 1.0:
        return [1.0 / count] * count
    pinned = [False] * count
    changed = True
    while changed:
        changed = False
        free_height = 1.0
        free_amount = 0.0
        for i in range(count):
            if pinned[i]:
                free_height -= floor_height
            else:
                free_amount += amount(mixture, ids[i])
        for i in range(count):
            if pinned[i]:
                heights[i] = floor_height
                continue
            heights[i] = free_height * amount(mixture, ids[i]) / free_amount
            if heights[i] < floor_height:
                pinned[i] = True
                changed = True
    return heights


def pour_top(mixture: dict, poured: float, catalog: DataCatalog, economy: EconomyConfig) -> dict:
    ids = layers(mixture, catalog)
    heights = layer_heights(mixture, catalog, economy)
    share = {}
    surface = 1.0
    cut = 1.0 - _clampf(poured, 0.0, 1.0)
    for i in range(len(ids) - 1, -1, -1):
        bottom_edge = surface - heights[i]
        share[ids[i]] = _clampf((surface - max(cut, bottom_edge)) / heights[i], 0.0, 1.0)
        surface = bottom_edge
    top = {}
    bottom = {}
    for property_id in mixture:
        value = float(mixture[property_id])
        part = share.get(property_id, 0.0)
        top[property_id] = value * part
        bottom[property_id] = value - value * part
    return {KEY_TOP: cleaned(top), KEY_BOTTOM: cleaned(bottom)}


def height_above_layer(mixture: dict, index: int, catalog: DataCatalog, economy: EconomyConfig) -> float:
    heights = layer_heights(mixture, catalog, economy)
    result = 0.0
    for i in range(len(heights) - 1, -1, -1):
        if i < index:
            break
        result += heights[i]
    return result


def pour_rate(held: float, economy: EconomyConfig) -> float:
    return economy.pour_speed_start if held < economy.pour_ramp_time else economy.pour_speed_full


def pour_height(held: float, economy: EconomyConfig) -> float:
    time = max(held, 0.0)
    slow = min(time, economy.pour_ramp_time)
    return economy.pour_speed_start * slow + economy.pour_speed_full * (time - slow)


def pour_tail(held: float, economy: EconomyConfig) -> float:
    return pour_rate(max(held, 0.0), economy) * economy.pour_stop_time * 0.5


# --- AlchemyRules: нагрев (GDD §3.3, §3.4) -------------------------------------------------------------------------
def temp_after(temp: float, heating: bool, dt: float, economy: EconomyConfig) -> float:
    start = _clampf(temp, economy.room_temp, economy.max_temp)
    if dt <= 0.0:
        return start
    if heating:
        return min(start + economy.heat_rate * dt, economy.max_temp)
    return max(start - economy.cool_rate * dt, economy.room_temp)


def time_at_or_above(threshold: float, temp: float, heating: bool, dt: float, economy: EconomyConfig) -> float:
    if dt <= 0.0 or threshold < 0.0:
        return 0.0
    start = _clampf(temp, economy.room_temp, economy.max_temp)
    rate = economy.heat_rate if heating else -economy.cool_rate
    limit = economy.max_temp if heating else economy.room_temp
    moving = dt
    if not math.isclose(rate, 0.0, abs_tol=1e-5):
        moving = _clampf((limit - start) / rate, 0.0, dt)
    finish = start + rate * moving
    result = 0.0
    if start >= threshold and finish >= threshold:
        result = moving
    elif start >= threshold:
        result = (start - threshold) / -rate
    elif finish >= threshold:
        result = moving - (threshold - start) / rate
    if finish >= threshold:
        result += dt - moving
    return _clampf(result, 0.0, dt)


def heat(mixture: dict, temp: float, heating: bool, dt: float, catalog: DataCatalog,
         economy: EconomyConfig) -> dict:
    result = {}
    for property_id in mixture:
        value = float(mixture[property_id])
        data = catalog.property(property_id)
        if data is not None:
            value -= economy.evaporate_rate * time_at_or_above(data.evaporate_temp, temp, heating, dt, economy)
            value -= economy.burn_rate * time_at_or_above(data.burn_temp, temp, heating, dt, economy)
        result[property_id] = max(value, 0.0)
    return cleaned(result)


def steaming(mixture: dict, temp: float, catalog: DataCatalog) -> list:
    result = []
    for property_id in cleaned(mixture):
        data = catalog.property(property_id)
        if data is not None and data.evaporates_at(temp):
            result.append(property_id)
    return result


def burning(mixture: dict, temp: float, catalog: DataCatalog) -> list:
    result = []
    for property_id in cleaned(mixture):
        data = catalog.property(property_id)
        if data is not None and data.burns_at(temp):
            result.append(property_id)
    return result


RULE_FUNCTIONS = [
    "total", "amount", "cleaned", "combine", "scaled", "is_present", "significant", "traces", "strength_stars",
    "purity", "purity_stars", "weakest_stars", "is_flawless", "hardest", "grind_per_circle", "grind_after", "extraction", "extract", "ground",
    "layers", "layer_heights", "pour_top", "height_above_layer", "pour_rate", "pour_height", "pour_tail",
    "temp_after", "time_at_or_above", "heat", "steaming", "burning", "_lies_below",
]


# --- Чтение .tres --------------------------------------------------------------------------------------------------
_LINE = re.compile(r"^([a-z_][a-z0-9_]*)\s*=\s*(.+)$")
_EXT = re.compile(r'^\[ext_resource [^\]]*path="res://([^"]+)"[^\]]*id="([^"]+)"')


def _value(raw: str):
    raw = raw.strip()
    if raw.startswith('&"') or raw.startswith('"'):
        return raw.split('"')[1]
    if raw in ("true", "false"):
        return raw == "true"
    match = re.match(r"^Array\[[A-Za-z]+\]\(\[(.*)\]\)$", raw)
    if match:
        body = match.group(1).strip()
        return [_value(part) for part in body.split(",")] if body else []
    match = re.match(r"^Dictionary\[[A-Za-z]+, [A-Za-z]+\]\(\{(.*)\}\)$", raw)
    if match:
        result = {}
        body = match.group(1).strip()
        for pair in body.split(",") if body else []:
            key, val = pair.split(":")
            result[_value(key)] = _value(val)
        return result
    try:
        return int(raw)
    except ValueError:
        pass
    try:
        return float(raw)
    except ValueError:
        return raw


def read_tres(path: Path) -> tuple[dict, dict]:
    """(поля [resource], ext_resource id → путь от res://)."""
    fields: dict = {}
    ext: dict = {}
    in_resource = False
    for line in path.read_text(encoding="utf-8").splitlines():
        match = _EXT.match(line)
        if match:
            ext[match.group(2)] = match.group(1)
            continue
        if line.startswith("["):
            in_resource = line.startswith("[resource]")
            continue
        match = _LINE.match(line)
        if in_resource and match:
            fields[match.group(1)] = match.group(2)
    return fields, ext


def _ext_list(raw: str, ext: dict) -> list:
    body = raw[raw.index("(["):] if "([" in raw else raw
    return [ext[ref] for ref in re.findall(r'ExtResource\("([^"]+)"\)', body)]


def load_catalog(root: Path = ROOT) -> DataCatalog:
    fields, ext = read_tres(root / "data" / "catalog.tres")
    economy_path = ext[re.search(r'ExtResource\("([^"]+)"\)', fields["economy"]).group(1)]
    economy_fields, _ = read_tres(root / economy_path)
    economy = EconomyConfig({key: _value(raw) for key, raw in economy_fields.items() if key != "script"})
    catalog = DataCatalog(economy=economy)
    for rel in _ext_list(fields["properties"], ext):
        f, _ = read_tres(root / rel)
        catalog.properties.append(PropertyData(_value(f["id"]), int(_value(f["density_rank"])),
                                               float(_value(f["evaporate_temp"])), float(_value(f["burn_temp"]))))
    for rel in _ext_list(fields["ingredients"], ext):
        f, _ = read_tres(root / rel)
        props = {key: float(val) for key, val in _value(f["properties"]).items()}
        catalog.ingredients.append(IngredientData(_value(f["id"]), props, int(_value(f.get("hardness", "0")))))
    for rel in _ext_list(fields["recipes"], ext):
        f, _ = read_tres(root / rel)
        catalog.recipes.append(RecipeData(_value(f["id"]), _value(f["property_set"]), _value(f["hint_steps"]),
                                          int(_value(f.get("tier", "1")))))
    return catalog


# --- Прохождение пути рецепта --------------------------------------------------------------------------------------
STEP_MORTAR = "mortar"
STEP_SETTLER_TOP = "settler_top"
STEP_SETTLER_BOTTOM = "settler_bottom"
BURNER_STEP = re.compile(r"^burner_(\d+)_(\d+)$")
TAP_CIRCLES = 0.25          # 1 тап = ¼ круга (GDD §3.3)
PLAYER_TICK = 0.25          # горелка: игрок решает «держать / отпустить» раз в 0,25 с
BURNER_LIMIT_SEC = 60.0     # дольше — путь не сработал
DT_SPLITS = (1, 2, 3, 7, 16)
DT_TOLERANCE = 1e-9

# Запасные пути из GDD §5.1 («или …»), кроме RecipeData.hint_steps.
EXTRA_PATHS = {
    "warming_balm": [["ing_sage_bundle", "ing_fire_bloom", STEP_MORTAR, "burner_75_89"]],
}


def grind_to_perfect(ingredients: list, economy: EconomyConfig) -> tuple[float, float]:
    """Помол тапами по ¼ круга до зоны «идеально»: (помол, круги)."""
    grind = 0.0
    circles = 0.0
    while extraction(grind, economy) < 1.0 and grind < 1.0:
        circles += TAP_CIRCLES
        grind = grind_after(grind, TAP_CIRCLES, ingredients, economy)
    return grind, circles


def burner_schedule(mixture: dict, low: int, high: int, catalog: DataCatalog, economy: EconomyConfig) -> list:
    """Расписание огня по тикам PLAYER_TICK: держать, пока не перескочим high; ждать, пока летучие с точкой ≤ low
    не уйдут; затем остыть до комнатной. Возвращает список bool (True — огонь держат)."""
    schedule: list = []
    temp = economy.room_temp
    wanted_gone = [p.id for p in catalog.properties if 0.0 <= p.evaporate_temp <= low]
    elapsed = 0.0
    while elapsed < BURNER_LIMIT_SEC:
        if not any(property_id in mixture for property_id in wanted_gone) and temp >= low:
            break
        heating = temp + economy.heat_rate * PLAYER_TICK <= high
        schedule.append(heating)
        mixture = heat(mixture, temp, heating, PLAYER_TICK, catalog, economy)
        temp = temp_after(temp, heating, PLAYER_TICK, economy)
        elapsed += PLAYER_TICK
    while temp > economy.room_temp:
        schedule.append(False)
        temp = temp_after(temp, False, PLAYER_TICK, economy)
    return schedule


def run_burner(mixture: dict, schedule: list, catalog: DataCatalog, economy: EconomyConfig,
               splits=1, rng: random.Random | None = None) -> tuple[dict, float]:
    """Прогнать расписание; каждый тик дробится на splits равных шагов или (rng) на случайные куски."""
    temp = economy.room_temp
    for heating in schedule:
        if rng is not None:
            cuts = sorted(rng.random() * PLAYER_TICK for _ in range(rng.randint(1, 9)))
            steps = [b - a for a, b in zip([0.0] + cuts, cuts + [PLAYER_TICK])]
        else:
            steps = [PLAYER_TICK / splits] * splits
        for dt in steps:
            mixture = heat(mixture, temp, heating, dt, catalog, economy)
            temp = temp_after(temp, heating, dt, economy)
    return mixture, temp


def settle_and_pick(mixture: dict, keep_top: bool, recipe_id: str, catalog: DataCatalog,
                    economy: EconomyConfig) -> tuple[dict, int]:
    """Слить верхние k целых слоёв (k = 1…n−1) и взять верх или низ. Первый k, который даёт рецепт; иначе k = 0."""
    ids = layers(mixture, catalog)
    fallback = None
    for k in range(1, len(ids)):
        poured = height_above_layer(mixture, len(ids) - k, catalog, economy)
        split = pour_top(mixture, poured, catalog, economy)
        vessel = split[KEY_TOP if keep_top else KEY_BOTTOM]
        found = catalog.recipe_for(significant(vessel, economy))
        if fallback is None:
            fallback = vessel
        if found is not None and found.id == recipe_id:
            return vessel, k
    return (fallback if fallback is not None else mixture), 0


def run_path(recipe: RecipeData, steps: list, catalog: DataCatalog) -> dict:
    economy = catalog.economy
    ingredients = [catalog.ingredient(step) for step in steps if step.startswith("ing_")]
    report: dict = {"recipe": recipe.id, "path": steps, "notes": []}
    if any(item is None for item in ingredients):
        report["error"] = "нет ингредиента в каталоге"
        return report
    if len(ingredients) > economy.mortar_slots:
        report["notes"].append("ступка с третьим слотом")
    mixture: dict = {}
    for step in steps:
        if step.startswith("ing_"):
            continue
        if step == STEP_MORTAR:
            grind, circles = grind_to_perfect(ingredients, economy)
            mixture = ground(ingredients, grind, economy)
            report["notes"].append("помол %.2f за %.2f круга" % (grind, circles))
        elif step in (STEP_SETTLER_TOP, STEP_SETTLER_BOTTOM):
            mixture, k = settle_and_pick(mixture, step == STEP_SETTLER_TOP, recipe.id, catalog, economy)
            report["notes"].append(("слить %d верхн. слоя" % k) if k else "ни один срез не дал рецепт")
        else:
            match = BURNER_STEP.match(step)
            if match is None:
                report["error"] = "неизвестный шаг %s" % step
                return report
            schedule = burner_schedule(mixture, int(match.group(1)), int(match.group(2)), catalog, economy)
            mixture, _ = run_burner(mixture, schedule, catalog, economy)
            report["notes"].append("горелка %.2f с" % (len(schedule) * PLAYER_TICK))
    sig = significant(mixture, economy)
    found = catalog.recipe_for(sig)
    report["mixture"] = {key: round(val, 6) for key, val in mixture.items()}
    report["significant"] = sig
    report["result"] = found.id if found else None
    report["ok"] = found is not None and found.id == recipe.id
    report["strength"] = min((strength_stars(amount(mixture, p), economy) for p in recipe.property_set), default=0)
    report["purity"] = round(purity(mixture, recipe.property_set), 4)
    report["purity_stars"] = purity_stars(purity(mixture, recipe.property_set), economy)
    return report


def all_paths(catalog: DataCatalog) -> list:
    reports = []
    for recipe in catalog.recipes:
        reports.append(run_path(recipe, recipe.hint_steps, catalog))
        for steps in EXTRA_PATHS.get(recipe.id, []):
            reports.append(run_path(recipe, steps, catalog))
    return reports


# --- Самопроверка --------------------------------------------------------------------------------------------------
class Checks:
    def __init__(self) -> None:
        self.passed = 0
        self.failed: list = []

    def check(self, name: str, ok: bool, detail: str = "") -> None:
        if ok:
            self.passed += 1
        else:
            self.failed.append(name + (" — " + detail if detail else ""))
            print("FAIL", name, detail)


def _near(a: float, b: float, tol: float = 1e-9) -> bool:
    return abs(a - b) <= tol


def _same_mix(a: dict, b: dict, tol: float = DT_TOLERANCE) -> bool:
    return list(a) == list(b) and all(_near(a[key], b[key], tol) for key in a)


def check_numbers(c: Checks, catalog: DataCatalog) -> None:
    e = catalog.economy
    ing = catalog.ingredient
    c.check("извлечение: p=0 → 0,4", _near(extraction(0.0, e), 0.4))
    c.check("извлечение: p=0,35 → 0,7", _near(extraction(0.35, e), 0.7))
    c.check("извлечение: 0,70…0,85 → 1", extraction(0.7, e) == 1.0 and extraction(0.85, e) == 1.0)
    c.check("извлечение: p=1 → 0,7 (пылит)", _near(extraction(1.0, e), 0.7))
    c.check("помол: мягкий +0,12, средний +0,09, твёрдый +0,07 за круг",
            grind_per_circle([ing("ing_sage_bundle")], e) == 0.12
            and grind_per_circle([ing("ing_rust_lichen")], e) == 0.09
            and grind_per_circle([ing("ing_golden_root")], e) == 0.07)
    c.check("помол: в смеси считается самый твёрдый",
            hardest([ing("ing_sage_bundle"), ing("ing_snow_lotus"), ing("ing_ember_nut")]) == HARD)
    c.check("помол: пустая ступка не мелется", grind_after(0.3, 5.0, [], e) == 0.3)
    c.check("помол: шкала стоит на 1", grind_after(0.95, 3.0, [ing("ing_sage_bundle")], e) == 1.0)
    c.check("смесь из ступки = доли × извлечение (порядок ключей — по ингредиентам)",
            list(ground([ing("ing_fire_bloom"), ing("ing_sage_bundle")], 0.35, e).items())
            == [("heat", 2.0 * 0.7), ("acid", 1.0 * 0.7), ("life", 2.0 * 0.7)])
    c.check("порог значимости: 0,3 есть, 0,29 — след",
            is_present(0.3, e) and not is_present(0.29, e)
            and significant({"life": 1.0, "acid": 0.29}, e) == ["life"]
            and traces({"life": 1.0, "acid": 0.29}, e) == ["acid"])
    c.check("сила: 0,99 → 0, 1,0 → ★, 2,0 → ★★, 3,0 → ★★★",
            [strength_stars(v, e) for v in (0.99, 1.0, 2.0, 3.0)] == [0, 1, 2, 3])
    c.check("сила: 0,7 × 3 доли (2,0999…) → ★★", strength_stars(3.0 * 0.7, e) == 2)
    c.check("чистота: 2,4 / 3,0 = 0,7999… → ★★ (допуск EPSILON)",
            purity({"life": 2.4, "acid": 0.6}, ["life"]) < 0.8
            and purity_stars(purity({"life": 2.4, "acid": 0.6}, ["life"]), e) == 2)
    c.check("чистота: пустая смесь — 0", purity({}, ["life"]) == 0.0)
    c.check("сложение смесей: ключи a, потом новые из b",
            list(combine({"heat": 1.0, "acid": 0.5}, {"life": 2.0, "heat": 1.0}).items())
            == [("heat", 2.0), ("acid", 0.5), ("life", 2.0)])
    c.check("масштаб и чистка нулей", scaled({"heat": 2.0, "acid": 0.00005}, 0.5) == {"heat": 1.0})
    c.check("слои по плотности: Едкость на дне, Свет сверху",
            layers({"light": 1.0, "cold": 1.0, "acid": 1.0, "life": 1.0}, catalog) == ["acid", "life", "cold", "light"])
    c.check("толщины ∝ долям: Едкость 1 + Жар 2 → 1/3, 2/3",
            all(_near(a, b) for a, b in zip(layer_heights({"heat": 2.0, "acid": 1.0}, catalog, e), [1 / 3, 2 / 3])))
    heights = layer_heights({"heat": 3.0, "life": 0.1}, catalog, e)
    c.check("тонкий слой не меньше 10 %: Жар 3 + Жизнь 0,1 → 0,9 / 0,1",
            _near(heights[0], 0.9) and _near(heights[1], 0.1), str(heights))
    many = {p.id: 1.0 for p in catalog.properties}
    many["light"] = 0.01
    many["acid"] = 0.02
    heights = layer_heights(many, catalog, e)
    c.check("два тонких слоя: оба по 10 %, сумма 1", _near(sum(heights), 1.0)
            and _near(heights[0], 0.1) and _near(heights[-1], 0.1), str(heights))
    thick = EconomyConfig(dict(e.values, min_layer_height=0.2))
    c.check("минимум не влезает (6 × 0,2 > 1) — все слои поровну",
            all(_near(h, 1 / 6) for h in layer_heights({p.id: 1.0 for p in catalog.properties}, catalog, thick)))
    split = pour_top({"heat": 2.0, "acid": 1.0}, 2 / 3, catalog, e)
    c.check("слив 2/3: Жар целиком сверху, Едкость внизу",
            _same_mix(split[KEY_TOP], {"heat": 2.0}, 1e-6) and _same_mix(split[KEY_BOTTOM], {"acid": 1.0}, 1e-6),
            str(split))
    split = pour_top({"heat": 2.0, "acid": 1.0}, 0.5, catalog, e)
    c.check("слив 0,5: из слоя уходит накрытая доля (Жар 1,5 / 0,5)",
            _same_mix(split[KEY_TOP], {"heat": 1.5}) and _same_mix(split[KEY_BOTTOM], {"heat": 0.5, "acid": 1.0}),
            str(split))
    split = pour_top({"heat": 2.0, "acid": 1.0}, 1.5, catalog, e)
    c.check("слив больше столба — всё наверху", split[KEY_BOTTOM] == {} and _same_mix(split[KEY_TOP],
            {"heat": 2.0, "acid": 1.0}))
    c.check("высота над слоем: снять Жар — 2/3, снять всё — 1",
            _near(height_above_layer({"heat": 2.0, "acid": 1.0}, 1, catalog, e), 2 / 3)
            and _near(height_above_layer({"heat": 2.0, "acid": 1.0}, 0, catalog, e), 1.0))
    c.check("струя: 0,5 с по 15 %, дальше 30 %",
            _near(pour_height(0.5, e), 0.075) and _near(pour_height(1.5, e), 0.375)
            and pour_rate(0.49, e) == 0.15 and pour_rate(0.5, e) == 0.3)
    c.check("хвост струи после отпускания за 0,1 с", _near(pour_tail(1.0, e), 0.015)
            and _near(pour_tail(0.2, e), 0.0075))
    c.check("температура: +20°/с, потолок 100°, −12°/с до 20°",
            temp_after(20.0, True, 3.0, e) == 80.0 and temp_after(90.0, True, 1.0, e) == 100.0
            and temp_after(80.0, False, 2.0, e) == 56.0 and temp_after(30.0, False, 5.0, e) == 20.0)
    c.check("время выше точки: рост 20→60 за 2 с, выше 35° — 1,25 с",
            _near(time_at_or_above(35.0, 20.0, True, 2.0, e), 1.25))
    c.check("время выше точки: остывание с 50° за 5 с, выше 35° — 1,25 с",
            _near(time_at_or_above(35.0, 50.0, False, 5.0, e), 1.25))
    c.check("время выше точки: на потолке 100° всё время; «никогда» — 0",
            time_at_or_above(90.0, 100.0, True, 3.0, e) == 3.0 and time_at_or_above(NEVER, 100.0, True, 3.0, e) == 0.0)
    c.check("пар: Холод 2 за 2 с нагрева с 20° теряет 1,2 × 1,25", _same_mix(
        heat({"cold": 2.0, "heat": 1.0}, 20.0, True, 2.0, catalog, e), {"cold": 2.0 - 1.5, "heat": 1.0}))
    c.check("дым: Жизнь с 90° сгорает 0,8 доли/с, Жар и Свет стойкие", _same_mix(
        heat({"life": 2.0, "heat": 1.0, "light": 1.0}, 90.0, True, 1.0, catalog, e),
        {"life": 1.2, "heat": 1.0, "light": 1.0}))
    c.check("пар и дым: кто уходит при 60° и 95°",
            steaming({"heat": 1.0, "cold": 1.0, "sleep": 1.0, "acid": 1.0}, 60.0, catalog) == ["cold", "sleep"]
            and burning({"life": 1.0, "heat": 1.0}, 95.0, catalog) == ["life"]
            and burning({"life": 1.0}, 89.9, catalog) == [])


def check_quality(c: Checks, catalog: DataCatalog) -> None:
    """GDD §5.3: сила — по самому слабому нужному свойству; «безупречно» — ★★★ силы у всех нужных и ★★★ чистоты."""
    e = catalog.economy
    c.check("слабейшее: {Жизнь 3, Жар 2} → ★★", weakest_stars({"life": 3.0, "heat": 2.0}, ["life", "heat"], e) == 2)
    c.check("слабейшее: нужного свойства нет → 0", weakest_stars({"life": 3.0}, ["life", "heat"], e) == 0)
    c.check("слабейшее: ничего не нужно → 0", weakest_stars({"life": 3.0}, [], e) == 0)
    c.check("слабейшее: 2,99995 → ★★★ (допуск EPSILON)", weakest_stars({"life": 2.99995}, ["life"], e) == 3)
    c.check("безупречно: ★★★ и ★★★", is_flawless(3, 3, e))
    c.check("не безупречно: ★★★ силы, ★★ чистоты", not is_flawless(3, 2, e))
    c.check("не безупречно: ★★ силы, ★★★ чистоты", not is_flawless(2, 3, e))
    near = {"life": 3.0, "heat": 0.15}
    c.check("Жизнь 3 + Жар 0,15: чистота 95,2 % → безупречно",
            is_flawless(weakest_stars(near, ["life"], e), purity_stars(purity(near, ["life"]), e), e))
    far = {"life": 3.0, "heat": 0.2}
    c.check("Жизнь 3 + Жар 0,2: чистота 93,75 % → нет",
            not is_flawless(weakest_stars(far, ["life"], e), purity_stars(purity(far, ["life"]), e), e))


def check_gdd_3_4(c: Checks, catalog: DataCatalog) -> None:
    volatile = sorted((p for p in catalog.properties if p.evaporate_temp >= 0.0), key=lambda p: p.evaporate_temp)
    c.check("GDD §3.4: летучие по возрастанию точки — Холод, Сон, Едкость",
            [p.id for p in volatile] == ["cold", "sleep", "acid"])
    stable = [p.id for p in catalog.properties if p.evaporate_temp < 0.0 and p.burn_temp < 0.0]
    c.check("GDD §3.1: стойкие — Жар и Свет", sorted(stable) == ["heat", "light"])
    everything = {p.id: 2.0 for p in catalog.properties}
    left = {}
    for low, high in ((35, 54), (55, 74), (75, 89)):
        schedule = burner_schedule(dict(everything), low, high, catalog, catalog.economy)
        mixture, _ = run_burner(dict(everything), schedule, catalog, catalog.economy)
        left[(low, high)] = [key for key in everything if key not in mixture]
    c.check("горелка снимает {Холод} → {Холод, Сон} → {Холод, Сон, Едкость}, Жизнь цела ниже 90°",
            left == {(35, 54): ["cold"], (55, 74): ["cold", "sleep"], (75, 89): ["acid", "cold", "sleep"]},
            str(left))


def check_paths(c: Checks, catalog: DataCatalog) -> list:
    reports = all_paths(catalog)
    for report in reports:
        c.check("путь %s: %s → %s" % (report["recipe"], " → ".join(report["path"]), report.get("result")),
                report.get("ok", False), report.get("error", str(report.get("significant"))))
    c.check("у каждого из %d рецептов есть путь" % len(catalog.recipes),
            {r["recipe"] for r in reports} == {r.id for r in catalog.recipes})
    return reports


def check_dt(c: Checks, catalog: DataCatalog) -> None:
    e = catalog.economy
    ing = catalog.ingredient
    # Каждый случай обрывает испарение на полпути: иначе всё летучее уходит целиком и сравнение пустое.
    cases = {
        "короткий нагрев до 45° (Холод уходит частично)": (
            ground([ing("ing_moon_moss")], 0.75, e), [True] * 5 + [False] * 12),
        "перегрев до 100° и остывание (Жизнь подгорает)": (
            ground([ing("ing_sage_bundle"), ing("ing_fire_bloom")], 0.75, e), [True] * 19 + [False] * 34),
        "рывки огня у точки Сна": (
            ground([ing("ing_drowse_herb"), ing("ing_snow_lotus")], 0.75, e),
            [True] * 8 + [False, True] + [False] * 30),
        "окно 75–89° по пути «Праздничных искр»": (
            ground([ing("ing_fire_bloom"), ing("ing_glow_flower")], 0.75, e), None),
    }
    rng = random.Random(31)
    for name, (mixture, schedule) in cases.items():
        if schedule is None:
            schedule = burner_schedule(dict(mixture), 75, 89, catalog, e)
        base, base_temp = run_burner(dict(mixture), schedule, catalog, e)
        partial = schedule is not None and any(0.0 < base.get(k, 0.0) < mixture[k] - EPSILON for k in mixture)
        ok = True
        worst = 0.0
        for splits in DT_SPLITS[1:]:
            mix, temp = run_burner(dict(mixture), schedule, catalog, e, splits)
            ok = ok and _same_mix(base, mix) and _near(temp, base_temp)
            worst = max([worst] + [abs(base[k] - mix.get(k, 0.0)) for k in base])
        for _ in range(5):
            mix, temp = run_burner(dict(mixture), schedule, catalog, e, rng=rng)
            ok = ok and _same_mix(base, mix) and _near(temp, base_temp)
            worst = max([worst] + [abs(base[k] - mix.get(k, 0.0)) for k in base])
        c.check("горелка, %s: шаг dt не меняет итог (макс. расхождение %.1e)" % (name, worst), ok)
        if name.startswith("окно"):
            c.check("горелка, %s: Сон и Едкость ушли, Жар и Свет целы" % name,
                    list(base) == ["heat", "light"] and base_temp == e.room_temp, str(base))
        else:
            c.check("горелка, %s: испарение оборвано на полпути (проверка не пустая)" % name, partial,
                    "%s → %s" % (mixture, base))
    # Слив: кадры по dt = формула за всё удержание; два удержания = одно той же суммарной высоты.
    for dt in (1 / 30, 1 / 60, 1 / 144, 0.07):
        held = 0.0
        poured = 0.0
        while held + dt <= 1.3 + 1e-12:
            poured += pour_height(held + dt, e) - pour_height(held, e)
            held += dt
        c.check("слив по кадрам dt=%.4f = pour_height" % dt, _near(poured, pour_height(held, e), 1e-12))
    mixture = ground([ing("ing_sage_bundle"), ing("ing_fire_bloom")], 0.75, e)
    first = pour_height(0.4, e) + pour_tail(0.4, e)
    second = pour_height(0.6, e) + pour_tail(0.6, e)
    once = pour_top(mixture, first + second, catalog, e)
    c.check("слив двумя удержаниями = одним на ту же высоту (считается от отстоянной смеси)",
            _same_mix(once[KEY_TOP], pour_top(mixture, second + first, catalog, e)[KEY_TOP]))
    # Помол: частями = сразу (ниже потолка).
    herbs = [ing("ing_golden_root"), ing("ing_sage_bundle")]
    by_taps = 0.0
    for _ in range(36):
        by_taps = grind_after(by_taps, TAP_CIRCLES, herbs, e)
    c.check("помол: 36 тапов = 9 кругов", _near(by_taps, grind_after(0.0, 9.0, herbs, e)))


def check_determinism(c: Checks, catalog: DataCatalog) -> None:
    e = catalog.economy
    mixture = {"light": 1.2, "acid": 0.4, "life": 2.0, "cold": 0.9, "sleep": 0.35, "heat": 1.1}
    keys = list(mixture)
    rng = random.Random(7)
    base_layers = layers(mixture, catalog)
    base_split = pour_top(mixture, 0.45, catalog, e)
    ok = True
    for _ in range(20):
        rng.shuffle(keys)
        shuffled = {key: mixture[key] for key in keys}
        split = pour_top(shuffled, 0.45, catalog, e)
        ok = ok and layers(shuffled, catalog) == base_layers
        ok = ok and all(_near(split[side].get(k, 0.0), base_split[side].get(k, 0.0))
                        for side in (KEY_TOP, KEY_BOTTOM) for k in mixture)
    c.check("порядок ключей на входе не меняет слои и слив", ok)
    c.check("повтор того же вызова — тот же результат (с порядком ключей)",
            pour_top(mixture, 0.45, catalog, e) == base_split)


def check_sync(c: Checks) -> None:
    if not GD_RULES.exists():
        c.check("alchemy_rules.gd на месте", False, str(GD_RULES))
        return
    text = GD_RULES.read_text(encoding="utf-8")
    gd = re.findall(r"^static func ([a-z_][a-z0-9_]*)\(", text, re.MULTILINE)
    c.check("функции AlchemyRules = функции эталона (%d)" % len(gd), sorted(gd) == sorted(RULE_FUNCTIONS),
            "только в .gd: %s; только в .py: %s" % (sorted(set(gd) - set(RULE_FUNCTIONS)),
                                                    sorted(set(RULE_FUNCTIONS) - set(gd))))
    gd_eps = re.search(r"const EPSILON: float = ([0-9.]+)", text)
    c.check("EPSILON совпадает", gd_eps is not None and float(gd_eps.group(1)) == EPSILON)


def self_test(catalog: DataCatalog) -> int:
    c = Checks()
    check_numbers(c, catalog)
    check_quality(c, catalog)
    check_gdd_3_4(c, catalog)
    check_paths(c, catalog)
    check_dt(c, catalog)
    check_determinism(c, catalog)
    check_sync(c)
    total_checks = c.passed + len(c.failed)
    print("RULES: %d/%d %s" % (c.passed, total_checks, "OK" if not c.failed else "FAIL"))
    return 0 if not c.failed else 1


def print_paths(reports: list) -> None:
    for r in reports:
        mark = "OK  " if r.get("ok") else "FAIL"
        stars = "сила %d★, чистота %.0f%% (%d★)" % (r.get("strength", 0), 100 * r.get("purity", 0.0),
                                                   r.get("purity_stars", 0))
        print("%s %-20s %s" % (mark, r["recipe"], " → ".join(r["path"])))
        print("     → %s; %s; %s" % (r.get("result"), stars, "; ".join(r["notes"])))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    catalog = load_catalog()
    if args.self_test:
        return self_test(catalog)
    reports = all_paths(catalog)
    print_paths(reports)
    if args.json:
        args.json.write_text(json.dumps(reports, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0 if all(r.get("ok") for r in reports) else 1


if __name__ == "__main__":
    sys.exit(main())
