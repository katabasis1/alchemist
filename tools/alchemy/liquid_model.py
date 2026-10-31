#!/usr/bin/env python3
"""Эталон слоёв жидкости (S4.1): копия components/liquid/liquid_layers.gd на Python + самопроверка.

Шейдер жидкости рисует то, что отдаёт LiquidLayers.view(): смесь → слои колбы снизу вверх. Каждая функция
здесь — строка в строку функция LiquidLayers с тем же именем; правила отстаивания берутся из rules_model.py
(копия AlchemyRules). Правишь — правь оба файла; самопроверка сверяет списки функций и ключи.

Что решено:
  * слой — одно свойство, порядок и толщины — AlchemyRules.layers / layer_heights (GDD §3.4); значит слоёв
    не больше, чем свойств: MAX_LAYERS = 6, под этот размер сделаны массивы шейдера;
  * уровень полной колбы — сумма долей / ёмкость (Liquid.capacity), не выше 1;
  * слив сверху на poured (доля столба, как в AlchemyRules.pour_top) срезает верх: нижние слои стоят на месте,
    целиком слитые слои пропадают; та же геометрия, что у pour_top, — самопроверка сверяет одно с другим;
  * tops — верх каждого слоя в долях полной колбы, по возрастанию; последний — поверхность;
  * mixed — цвет взболтанной смеси (муть при отстаивании): среднее цветов по видимой толщине слоёв,
    чтобы при расслаивании цвет не прыгал.

Запуск:
  python tools/alchemy/liquid_model.py               # слои для путей рецептов
  python tools/alchemy/liquid_model.py --self-test   # все проверки; код возврата 1 при ошибке
Только stdlib.
"""
from __future__ import annotations

import argparse
import itertools
import math
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rules_model as R  # noqa: E402

GD_LIQUID = R.ROOT / "components" / "liquid" / "liquid_layers.gd"
GD_SLOSH = R.ROOT / "data" / "liquid" / "liquid_slosh.gd"
TRES_SLOSH = R.ROOT / "data" / "liquid" / "liquid_slosh.tres"
SLOSH_FIELDS = ("stiffness", "damping", "per_accel", "rotation_drag", "max_angle", "bump_decay", "bump_frequency")
SLOSH_FUNCTIONS = ("target", "step", "fade")
GD_POUR_TILT = R.ROOT / "data" / "liquid" / "liquid_pour_tilt.gd"
TRES_POUR_TILT = R.ROOT / "data" / "liquid" / "pour_tilt_round.tres"
TRES_LIQUID_MATERIAL = R.ROOT / "components" / "liquid" / "liquid_material.tres"
POUR_TILT_FIELDS = ("lip", "dip_px", "dip_layer_share", "dip_min_px")
POUR_TILT_FUNCTIONS = ("angle",)

MAX_LAYERS = 6
KEY_COLORS = "colors"
KEY_PATTERNS = "patterns"
KEY_TOPS = "tops"
KEY_MIXED = "mixed"
VIEW_KEYS = (KEY_COLORS, KEY_PATTERNS, KEY_TOPS, KEY_MIXED)
CLEAR = (0.0, 0.0, 0.0, 0.0)
FLOAT32_TOL = 1e-6


# --- LiquidLayers ----------------------------------------------------------------------------------------------------
def level(mixture: dict, capacity: float) -> float:
    if capacity <= 0.0:
        return 0.0
    return R._clampf(R.total(mixture) / capacity, 0.0, 1.0)


def view(mixture: dict, poured: float, capacity: float, catalog: R.DataCatalog, economy: R.EconomyConfig) -> dict:
    ids = R.layers(mixture, catalog)
    heights = R.layer_heights(mixture, catalog, economy)
    full = level(mixture, capacity)
    cut = 1.0 - poured
    colors: list = []
    patterns: list = []
    tops: list = []
    mixed = [0.0, 0.0, 0.0, 0.0]
    bottom = 0.0
    for i in range(len(ids)):
        top = min(bottom + heights[i], cut)
        if (top - bottom) * full <= R.EPSILON:
            break
        data = catalog.property(ids[i])
        colors.append(data.color)
        patterns.append(data.pattern)
        tops.append(top * full)
        for channel in range(4):
            mixed[channel] += data.color[channel] * (top - bottom)
        bottom = top
    if bottom > 0.0:
        mixed = [channel / bottom for channel in mixed]
    return {KEY_COLORS: colors, KEY_PATTERNS: patterns, KEY_TOPS: tops,
            KEY_MIXED: tuple(mixed)}


LIQUID_FUNCTIONS = ("level", "view")


# --- LiquidSlosh -----------------------------------------------------------------------------------------------------
class LiquidSlosh:
    """Копия data/liquid/liquid_slosh.gd: настройки из liquid_slosh.tres + чистые шаги раскачки."""

    def __init__(self, fields: dict) -> None:
        for name in SLOSH_FIELDS:
            setattr(self, name, float(fields[name]))

    def target(self, accel_x: float) -> float:
        return max(-self.max_angle, min(self.max_angle, accel_x * self.per_accel))

    def step(self, state: tuple, target_angle: float, turn: float, delta: float) -> tuple:
        angle, speed = state
        speed += turn * self.rotation_drag * self.stiffness
        speed += (-self.stiffness * (angle - target_angle) - self.damping * speed) * delta
        angle += speed * delta
        if abs(angle) >= self.max_angle:
            angle = math.copysign(self.max_angle, angle)
            speed = 0.0
        return angle, speed

    def fade(self, px: float, delta: float) -> float:
        return px * math.exp(-self.bump_decay * delta)


def load_slosh() -> LiquidSlosh:
    return LiquidSlosh(R.read_tres(TRES_SLOSH)[0])


# --- LiquidPourTilt (S4.2, D22) --------------------------------------------------------------------------------------
class LiquidPourTilt:
    """Копия data/liquid/liquid_pour_tilt.gd: наклон колбы при сливе — от уровня, а не постоянный.

    liquid.gdshader держит высоты слоёв над центром шара по мировой вертикали (up = (sin a, −cos a),
    a = surface_angle = −θ), значит высота точки l (от центра шара, px холста) над центром = −lx·sinθ − ly·cosθ.
    Колба наклоняется так, чтобы видимая внутренняя кромка горла lip ушла под поверхность на dip:
    θ = acos((surface − R − dip) / |l|) − atan2(lx, −ly), dip = clamp(доля·толщина верхнего слоя, min, dip_px) —
    у кромки всегда цвет того слоя, что льётся.
    """

    def __init__(self, fields: dict) -> None:
        self.lip = tuple(float(v) for v in fields["lip"])
        for name in POUR_TILT_FIELDS[1:]:
            setattr(self, name, float(fields[name]))

    def angle(self, tops: list, column_height: float, bulb_center: tuple, bulb_radius: float) -> float:
        count = len(tops)
        surface = tops[count - 1] * column_height if count > 0 else 0.0
        below = tops[count - 2] * column_height if count > 1 else 0.0
        dip = min(self.dip_px, max(self.dip_min_px, (surface - below) * self.dip_layer_share))
        arm_x, arm_y = self.lip[0] - bulb_center[0], self.lip[1] - bulb_center[1]
        height = surface - bulb_radius - dip
        return math.acos(max(-1.0, min(1.0, height / math.hypot(arm_x, arm_y)))) - math.atan2(arm_x, -arm_y)


def _parse_vector2(text: str) -> tuple:
    m = re.fullmatch(r"Vector2\(\s*([-0-9.e]+)\s*,\s*([-0-9.e]+)\s*\)", str(text).strip())
    if not m:
        raise ValueError("не Vector2: %r" % (text,))
    return float(m.group(1)), float(m.group(2))


def load_pour_tilt() -> LiquidPourTilt:
    fields = dict(R.read_tres(TRES_POUR_TILT)[0])
    fields["lip"] = _parse_vector2(fields["lip"]) if isinstance(fields["lip"], str) else fields["lip"]
    return LiquidPourTilt(fields)


def flask_shape() -> dict:
    """Форма круглой колбы из liquid_material.tres: bulb_center, bulb_radius, column_height, neck_half_width."""
    text = TRES_LIQUID_MATERIAL.read_text(encoding="utf-8")
    shape = {}
    for name in ("bulb_center", "bulb_radius", "column_height", "neck_half_width", "neck_top"):
        m = re.search(r"^shader_parameter/%s = (.+)$" % name, text, re.MULTILINE)
        shape[name] = _parse_vector2(m.group(1)) if m.group(1).startswith("Vector2") else float(m.group(1))
    return shape


# --- Самопроверка ----------------------------------------------------------------------------------------------------
def _near(a: float, b: float, tol: float = 1e-9) -> bool:
    return abs(a - b) <= tol


def _near_color(a: tuple, b: tuple, tol: float = 1e-9) -> bool:
    return all(_near(x, y, tol) for x, y in zip(a, b))


def _color_of(catalog: R.DataCatalog, property_id: str) -> tuple:
    return catalog.property(property_id).color


def _fire_bloom(catalog: R.DataCatalog) -> dict:
    """Огнецвет, растёртый «идеально»: Жар и Едкость — два слоя (Едкость тяжелее, внизу)."""
    economy = catalog.economy
    ing = [i for i in catalog.ingredients if i.id == "ing_fire_bloom"]
    return R.ground(ing, R.grind_to_perfect(ing, economy)[0], economy)


def check_basics(c: R.Checks, catalog: R.DataCatalog) -> None:
    e = catalog.economy
    empty = view({}, 0.0, 4.0, catalog, e)
    c.check("пусто: ключи на месте", tuple(empty.keys()) == VIEW_KEYS, str(tuple(empty.keys())))
    c.check("пусто: слоёв нет", len(empty[KEY_TOPS]) == 0 and len(empty[KEY_COLORS]) == 0)
    c.check("пусто: муть прозрачная", empty[KEY_MIXED] == CLEAR)
    one = view({"cold": 2.0}, 0.0, 4.0, catalog, e)
    c.check("одно свойство: один слой цвета свойства", one[KEY_COLORS] == [_color_of(catalog, "cold")])
    c.check("одно свойство: узор свойства (Холод — снежинки)", one[KEY_PATTERNS] == [3])
    c.check("одно свойство: уровень 2/4 = 0,5", len(one[KEY_TOPS]) == 1 and _near(one[KEY_TOPS][0], 0.5))
    c.check("одно свойство: муть = цвет свойства", _near_color(one[KEY_MIXED], _color_of(catalog, "cold")))
    c.check("level: доли/ёмкость", _near(level({"cold": 1.0, "life": 2.0}, 4.0), 0.75))
    c.check("level: не выше 1", _near(level({"cold": 9.0}, 4.0), 1.0))
    c.check("level: ёмкость 0 — пусто", _near(level({"cold": 1.0}, 0.0), 0.0))
    full = view({"cold": 9.0}, 0.0, 4.0, catalog, e)
    c.check("перелив: поверхность = 1", _near(full[KEY_TOPS][-1], 1.0))
    c.check("ёмкость 0 — слоёв нет", len(view({"cold": 1.0}, 0.0, 0.0, catalog, e)[KEY_TOPS]) == 0)


def check_order(c: R.Checks, catalog: R.DataCatalog) -> None:
    e = catalog.economy
    mix = _fire_bloom(catalog)
    v = view(mix, 0.0, 4.0, catalog, e)
    c.check("Огнецвет: Едкость внизу, Жар сверху",
            v[KEY_COLORS] == [_color_of(catalog, "acid"), _color_of(catalog, "heat")])
    c.check("Огнецвет: узоры пузыри, волны", v[KEY_PATTERNS] == [0, 1])
    heights = R.layer_heights(mix, catalog, e)
    want, run = [], 0.0
    for h in heights:
        run += h
        want.append(run * level(mix, 4.0))
    c.check("tops = накопленные толщины × уровень", all(_near(a, b) for a, b in zip(v[KEY_TOPS], want)),
            "%s ≠ %s" % (v[KEY_TOPS], want))
    expect_mixed = tuple((heights[0] * a + heights[1] * b) for a, b in
                         zip(_color_of(catalog, "acid"), _color_of(catalog, "heat")))
    c.check("муть: цвета по толщине слоёв", _near_color(v[KEY_MIXED], expect_mixed), str(v[KEY_MIXED]))
    rainbow = {"light": 1.0, "acid": 1.0, "cold": 1.0, "heat": 1.0, "sleep": 1.0, "life": 1.0}
    v6 = view(rainbow, 0.0, 8.0, catalog, e)
    c.check("шесть свойств — шесть слоёв по плотности",
            v6[KEY_PATTERNS] == [0, 1, 2, 3, 4, 5], str(v6[KEY_PATTERNS]))
    c.check("MAX_LAYERS не меньше числа свойств", MAX_LAYERS >= len(catalog.properties))


def check_pour(c: R.Checks, catalog: R.DataCatalog) -> None:
    e = catalog.economy
    mix = {"acid": 1.0, "heat": 2.0, "cold": 0.5}
    lvl = level(mix, 5.0)
    heights = R.layer_heights(mix, catalog, e)
    ids = R.layers(mix, catalog)
    c.check("слив 1 — пусто", len(view(mix, 1.0, 5.0, catalog, e)[KEY_TOPS]) == 0)
    c.check("слив < 0 — как 0", view(mix, -0.5, 5.0, catalog, e) == view(mix, 0.0, 5.0, catalog, e))
    c.check("слив > 1 — пусто", len(view(mix, 1.5, 5.0, catalog, e)[KEY_TOPS]) == 0)
    half = view({"cold": 2.0}, 0.5, 4.0, catalog, e)
    c.check("слив половины одного свойства: муть = цвет свойства",
            _near_color(half[KEY_MIXED], _color_of(catalog, "cold")), str(half[KEY_MIXED]))
    for index in range(len(ids)):
        cut = R.height_above_layer(mix, index, catalog, e)
        v = view(mix, cut, 5.0, catalog, e)
        c.check("слив до слоя %d: остаются слои ниже (%d)" % (index, index), len(v[KEY_TOPS]) == index)
    poured = 0.2
    v = view(mix, poured, 5.0, catalog, e)
    c.check("слив 0,2: поверхность опустилась на 0,2 столба", _near(v[KEY_TOPS][-1], (1.0 - poured) * lvl))
    c.check("слив 0,2: нижние слои на месте",
            all(_near(v[KEY_TOPS][i], sum(heights[:i + 1]) * lvl) for i in range(len(v[KEY_TOPS]) - 1)))
    rng = random.Random(41)
    agree = 0
    tries = 0
    for _ in range(200):
        poured = rng.random()
        tries += 1
        agree += _agrees_with_pour_top(mix, poured, catalog)
    c.check("геометрия = AlchemyRules.pour_top (200 сливов)", agree == tries, "%d/%d" % (agree, tries))


def _agrees_with_pour_top(mix: dict, poured: float, catalog: R.DataCatalog) -> bool:
    """Видимая толщина каждого слоя / его полная толщина = доля свойства, оставшаяся после pour_top."""
    e = catalog.economy
    ids = R.layers(mix, catalog)
    heights = R.layer_heights(mix, catalog, e)
    lvl = level(mix, 5.0)
    v = view(mix, poured, 5.0, catalog, e)
    left = R.pour_top(mix, poured, catalog, e)[R.KEY_BOTTOM]
    bottom = 0.0
    for i, pid in enumerate(ids):
        seen = (v[KEY_TOPS][i] - bottom) if i < len(v[KEY_TOPS]) else 0.0
        bottom = v[KEY_TOPS][i] if i < len(v[KEY_TOPS]) else bottom
        share = left.get(pid, 0.0) / mix[pid]
        if not _near(seen / (heights[i] * lvl), share, 1e-6):
            return False
    return True


def check_all_mixes(c: R.Checks, catalog: R.DataCatalog) -> None:
    """Все смеси из 1…3 ингредиентов (ступка с улучшением), слив 0…1: инварианты формы данных."""
    e = catalog.economy
    bad = []
    count = 0
    for n in range(1, e.mortar_slots_upgraded + 1):
        for combo in itertools.combinations_with_replacement(catalog.ingredients, n):
            mix = R.ground(list(combo), 1.0, e)
            for step in range(11):
                count += 1
                v = view(mix, step / 10.0, 7.0, catalog, e)
                n_layers = len(v[KEY_TOPS])
                ok = n_layers <= MAX_LAYERS and len(v[KEY_COLORS]) == n_layers == len(v[KEY_PATTERNS])
                ok = ok and all(0 <= p <= 5 for p in v[KEY_PATTERNS])
                ok = ok and all(b - a > R.EPSILON * 0.5 for a, b in zip([0.0] + v[KEY_TOPS], v[KEY_TOPS]))
                ok = ok and (n_layers == 0 or v[KEY_TOPS][-1] <= 1.0 + 1e-12)
                if not ok:
                    bad.append((tuple(i.id for i in combo), step))
    c.check("смеси 1…3 ингредиентов × 11 сливов (%d): слоёв ≤ 6, толщины > 0, верх ≤ 1" % count, not bad,
            str(bad[:3]))


def check_determinism(c: R.Checks, catalog: R.DataCatalog) -> None:
    e = catalog.economy
    mix = {"light": 0.4, "acid": 1.2, "cold": 0.05, "life": 0.9}
    base = view(mix, 0.3, 4.0, catalog, e)
    rng = random.Random(7)
    same = True
    for _ in range(20):
        keys = list(mix)
        rng.shuffle(keys)
        same = same and _same_view(view({k: mix[k] for k in keys}, 0.3, 4.0, catalog, e), base)
    c.check("порядок ключей смеси не меняет слои (с точностью до округления суммы)", same)


def _run_slosh(s: LiquidSlosh, fps: int, seconds: float, state: tuple = (0.0, 0.0), accel_x: float = 0.0,
               turn_total: float = 0.0, turn_seconds: float = 0.0) -> tuple:
    """Кадры по 1/fps: поворот turn_total равномерно за первые turn_seconds. → (состояние, мин. угол, макс. |угол|)."""
    delta = 1.0 / fps
    frames = round(seconds * fps)
    turn_frames = round(turn_seconds * fps)
    low, high = state[0], abs(state[0])
    for frame in range(frames):
        turn = turn_total / turn_frames if frame < turn_frames else 0.0
        state = s.step(state, s.target(accel_x), turn, delta)
        low, high = min(low, state[0]), max(high, abs(state[0]))
    return state, low, high


def check_slosh(c: R.Checks, s: LiquidSlosh) -> None:
    c.check("разгон вправо: жидкость набегает на левую стенку (угол > 0)", s.target(1000.0) > 0.0)
    c.check("торможение: набегает на правую (угол < 0)", s.target(-1000.0) < 0.0)
    c.check("рывок не наклоняет сильнее предела", _near(s.target(1e9), s.max_angle) and _near(s.target(-1e9), -s.max_angle))
    c.check("поворот по часовой: стенки тянут поверхность за собой (угол > 0)",
            s.step((0.0, 0.0), 0.0, 0.05, 1.0 / 60.0)[0] > 0.0)
    state, low, _ = _run_slosh(s, 60, 3.0, state=(0.3, 0.0))
    c.check("качается: переходит через горизонт и обратно", low < -0.02, "мин. %.3f" % low)
    c.check("без толчков успокаивается за 3 с", abs(state[0]) < 0.01 and abs(state[1]) < 0.05, str(state))
    slow, _, _ = _run_slosh(s, 12, 3.0, state=(0.3, 0.0))
    c.check("на 12 кадрах/с (слабое устройство) тоже успокаивается", abs(slow[0]) < 0.01, str(slow))
    held, _, _ = _run_slosh(s, 60, 4.0, accel_x=800.0)
    c.check("постоянное ускорение: держит наклон target", _near(held[0], s.target(800.0), 1e-3), str(held))
    _, _, high = _run_slosh(s, 60, 1.0, turn_total=3.0, turn_seconds=0.05)
    c.check("резкий поворот не пробивает предел", high <= s.max_angle + 1e-12, "%.3f" % high)
    hit, _, _ = _run_slosh(s, 60, 0.5, turn_total=3.0, turn_seconds=0.05)
    c.check("после удара в предел не залипает: через 0,5 с отошла от предела", abs(hit[0]) < 0.8 * s.max_angle,
            "%.3f" % hit[0])
    ends = [_run_slosh(s, fps, 0.6, turn_total=0.3, turn_seconds=0.1)[0][0] for fps in (30, 60, 144)]
    c.check("не зависит от частоты кадров (30/60/144): угол через 0,6 с", max(ends) - min(ends) < 0.04,
            " ".join("%.3f" % e for e in ends))
    c.check("волна от толчка затухает по экспоненте", _near(s.fade(10.0, 1.0), 10.0 * math.exp(-s.bump_decay)))
    px = 10.0
    for _ in range(60):
        px = s.fade(px, 1.0 / 60.0)
    c.check("затухание волны не зависит от кадров", _near(px, s.fade(10.0, 1.0), 1e-9))
    c.check("настройки разумны: предел до 1 рад, всё > 0",
            0.0 < s.max_angle <= 1.0 and all(getattr(s, f) > 0.0 for f in SLOSH_FIELDS))


def check_slosh_sync(c: R.Checks) -> None:
    if not GD_SLOSH.exists():
        c.check("liquid_slosh.gd на месте", False, str(GD_SLOSH))
        return
    text = GD_SLOSH.read_text(encoding="utf-8")
    gd = re.findall(r"^func ([a-z_][a-z0-9_]*)\(", text, re.MULTILINE)
    c.check("функции LiquidSlosh = функции эталона", sorted(gd) == sorted(SLOSH_FUNCTIONS), str(gd))
    fields = re.findall(r"^@export var ([a-z_]+): float", text, re.MULTILINE)
    c.check("поля LiquidSlosh = поля эталона", tuple(fields) == SLOSH_FIELDS, str(fields))


def _lip_height(t: LiquidPourTilt, theta: float, center: tuple) -> float:
    lx, ly = t.lip[0] - center[0], t.lip[1] - center[1]
    return -lx * math.sin(theta) - ly * math.cos(theta)


def _pour_mixes(catalog: R.DataCatalog) -> list:
    """Смеси путей рецептов (как print_paths) + смесь макета станции: на них проверяется наклон."""
    e = catalog.economy
    mixes = [{"sleep": 1.0, "life": 1.1, "light": 1.0}]
    for recipe in catalog.recipes:
        steps = [s for s in recipe.hint_steps if s.startswith("ing_")]
        ings = [i for i in catalog.ingredients if i.id in steps]
        if ings:
            mixes.append(R.ground(ings, R.grind_to_perfect(ings, e)[0], e))
    return mixes


def check_pour_tilt(c: R.Checks, t: LiquidPourTilt, catalog: R.DataCatalog) -> None:
    shape = flask_shape()
    col, center, radius = shape["column_height"], shape["bulb_center"], shape["bulb_radius"]
    c.check("кромка — на видимой стенке горла: внутри полости шейдера, со стороны слива",
            center[0] < t.lip[0] <= center[0] + shape["neck_half_width"] and _near(t.lip[1], shape["neck_top"]),
            str(t.lip))
    c.check("настройки dip разумны: 0 < min ≤ max, 0 < доля < 1",
            0.0 < t.dip_min_px <= t.dip_px and 0.0 < t.dip_layer_share < 1.0)
    worst_geo, worst_drop, lo, hi, lip_in_top, n = 0.0, 0.0, 10.0, -10.0, True, 0
    for mix in _pour_mixes(catalog):
        prev = -10.0
        for k in range(0, 41):
            v = view(mix, k / 40.0, 5.0, catalog, catalog.economy)
            tops = v[KEY_TOPS]
            if not tops:
                continue
            theta = t.angle(tops, col, center, radius)
            surface = tops[-1] * col
            below = tops[-2] * col if len(tops) > 1 else 0.0
            dip = min(t.dip_px, max(t.dip_min_px, (surface - below) * t.dip_layer_share))
            worst_geo = max(worst_geo, abs(_lip_height(t, theta, center) - (surface - radius - dip)))
            worst_drop = max(worst_drop, prev - theta)
            prev = theta
            lo, hi = min(lo, theta), max(hi, theta)
            if surface - below >= t.dip_min_px / t.dip_layer_share:
                lip_in_top = lip_in_top and _lip_height(t, theta, center) >= below - radius - 1e-9
            n += 1
    c.check("кромка ровно на dip под поверхностью (геометрия шейдера), %d кадров" % n, worst_geo < 1e-9,
            "%.2e px" % worst_geo)
    c.check("по ходу слива колба только наклоняется дальше", worst_drop <= 1e-12, "%.2e рад" % worst_drop)
    c.check("наклон в пределах 70…120° (колба не переворачивается)",
            math.radians(70.0) <= lo and hi <= math.radians(120.0), "%.1f…%.1f°" % (math.degrees(lo), math.degrees(hi)))
    c.check("у кромки — верхний слой (кроме остатка тоньше min/доля)", lip_in_top)
    empty = t.angle([], col, center, radius)
    full = t.angle([1.0], col, center, radius)
    c.check("пустая колба — наклон больше, чем полная", empty > full,
            "%.1f° / %.1f°" % (math.degrees(empty), math.degrees(full)))
    lone = t.angle([0.4], col, center, radius)
    c.check("один слой: толщина от дна (как два слоя с нижним нулевым)",
            _near(lone, t.angle([0.0, 0.4], col, center, radius), 1e-12))


def check_pour_tilt_sync(c: R.Checks) -> None:
    if not GD_POUR_TILT.exists():
        c.check("liquid_pour_tilt.gd на месте", False, str(GD_POUR_TILT))
        return
    text = GD_POUR_TILT.read_text(encoding="utf-8")
    gd = re.findall(r"^func ([a-z_][a-z0-9_]*)\(", text, re.MULTILINE)
    c.check("функции LiquidPourTilt = функции эталона", sorted(gd) == sorted(POUR_TILT_FUNCTIONS), str(gd))
    fields = re.findall(r"^@export var ([a-z_]+): (?:float|Vector2)", text, re.MULTILINE)
    c.check("поля LiquidPourTilt = поля эталона", tuple(fields) == POUR_TILT_FIELDS, str(fields))


def _same_view(a: dict, b: dict) -> bool:
    return (a[KEY_COLORS] == b[KEY_COLORS] and a[KEY_PATTERNS] == b[KEY_PATTERNS]
            and len(a[KEY_TOPS]) == len(b[KEY_TOPS]) and all(_near(x, y, 1e-12) for x, y in zip(a[KEY_TOPS], b[KEY_TOPS]))
            and _near_color(a[KEY_MIXED], b[KEY_MIXED], 1e-12))


def check_sync(c: R.Checks) -> None:
    if not GD_LIQUID.exists():
        c.check("liquid_layers.gd на месте", False, str(GD_LIQUID))
        return
    text = GD_LIQUID.read_text(encoding="utf-8")
    gd = re.findall(r"^static func ([a-z_][a-z0-9_]*)\(", text, re.MULTILINE)
    c.check("функции LiquidLayers = функции эталона", sorted(gd) == sorted(LIQUID_FUNCTIONS), str(gd))
    gd_max = re.search(r"const MAX_LAYERS: int = (\d+)", text)
    c.check("MAX_LAYERS совпадает", gd_max is not None and int(gd_max.group(1)) == MAX_LAYERS)
    keys = re.findall(r'const KEY_[A-Z]+: StringName = &"([a-z]+)"', text)
    c.check("ключи view совпадают", tuple(keys) == VIEW_KEYS, str(keys))


def self_test(catalog: R.DataCatalog) -> int:
    c = R.Checks()
    for check in (check_basics, check_order, check_pour, check_all_mixes, check_determinism):
        try:
            check(c, catalog)
        except NotImplementedError:
            c.check(check.__name__, False, "не реализовано")
    check_sync(c)
    if TRES_SLOSH.exists():
        try:
            check_slosh(c, load_slosh())
        except NotImplementedError:
            c.check("check_slosh", False, "не реализовано")
    else:
        c.check("liquid_slosh.tres на месте", False, str(TRES_SLOSH))
    check_slosh_sync(c)
    if TRES_POUR_TILT.exists():
        check_pour_tilt(c, load_pour_tilt(), catalog)
    else:
        c.check("pour_tilt_round.tres на месте", False, str(TRES_POUR_TILT))
    check_pour_tilt_sync(c)
    total_checks = c.passed + len(c.failed)
    print("LIQUID: %d/%d %s" % (c.passed, total_checks, "OK" if not c.failed else "FAIL"))
    return 0 if not c.failed else 1


def print_paths(catalog: R.DataCatalog) -> None:
    e = catalog.economy
    for recipe in catalog.recipes:
        steps = [s for s in recipe.hint_steps if s.startswith("ing_")]
        ings = [i for i in catalog.ingredients if i.id in steps]
        mix = R.ground(ings, R.grind_to_perfect(ings, e)[0], e)
        v = view(mix, 0.0, 7.0, catalog, e)
        print("%-20s %-40s tops %s" % (recipe.id, " ".join(R.layers(mix, catalog)),
                                       " ".join("%.3f" % t for t in v[KEY_TOPS])))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    catalog = R.load_catalog()
    if args.self_test:
        return self_test(catalog)
    print_paths(catalog)
    return 0


if __name__ == "__main__":
    sys.exit(main())
