"""Одноразовая выгрузка данных GDD v1 в .tres (S1.6).

Источник правды после выгрузки — сами .tres в data/ (их правят в редакторе Godot).
Скрипт НЕ перезаписывает существующие файлы; --force перезапишет всё (потеряются правки баланса!).

Перед записью — упрощённая проверка решаемости (идеальный помол, идеальный срез слоёв,
горелка держит нужную полосу температур; несколько замесов в одной колбе не смешиваются):
  * путь-подсказка каждого рецепта даёт ровно его набор свойств;
  * каждый шаблон заказа решается на своём min_rank теми ингредиентами и станциями,
    что к этому рангу можно открыть. Полный перебор с потерями — стенд S3.3.

Запуск: python tools/data/bootstrap_gdd_v1.py [--check] [--force]
"""
from __future__ import annotations

import argparse
import itertools
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data"

# ---------- GDD §3.1 свойства: id, цвет, узор (enum Pattern), плотность, испарение, горение
PROPERTIES = [
    ("acid", "9B5DE5", 0, 1, 75.0, -1.0),
    ("heat", "FF6B2C", 1, 2, -1.0, -1.0),
    ("life", "7ED957", 2, 3, -1.0, 90.0),
    ("cold", "5BC8F5", 3, 4, 35.0, -1.0),
    ("sleep", "6C7BD9", 4, 5, 55.0, -1.0),
    ("light", "FFE066", 5, 6, -1.0, -1.0),
]
SOFT, MEDIUM, HARD = 0, 1, 2
# ---------- GDD §4 ингредиенты: id, свойства, твёрдость, цена за штуку, ранг, цена открытия, редкий
INGREDIENTS = [
    ("ing_sage_bundle", {"life": 2}, SOFT, 0, 1, 0, False),
    ("ing_fire_bloom", {"heat": 2, "acid": 1}, SOFT, 0, 1, 0, False),
    ("ing_moon_moss", {"cold": 2, "sleep": 1}, SOFT, 4, 2, 40, False),
    ("ing_drowse_herb", {"sleep": 2, "life": 1}, SOFT, 4, 2, 40, False),
    ("ing_golden_root", {"light": 2, "life": 1}, HARD, 6, 2, 60, False),
    ("ing_rust_lichen", {"acid": 2, "light": 1}, MEDIUM, 5, 3, 60, False),
    ("ing_frost_berry", {"cold": 2, "life": 1}, SOFT, 6, 3, 70, False),
    ("ing_glow_flower", {"light": 2, "sleep": 1}, SOFT, 7, 3, 80, False),
    ("ing_ember_nut", {"heat": 2, "sleep": 1}, HARD, 6, 3, 70, False),
    ("ing_sun_petal", {"light": 1, "heat": 1, "life": 1}, MEDIUM, 10, 4, 120, False),
    ("ing_snow_lotus", {"cold": 1, "light": 1, "acid": 1}, MEDIUM, 10, 4, 120, False),
    ("ing_star_crystal", {"light": 3}, HARD, 30, 4, 0, True),
]
M, ST, SB = "mortar", "settler_top", "settler_bottom"
B35, B55, B75 = "burner_35_54", "burner_55_74", "burner_75_89"
# ---------- GDD §5.1 рецепты: id, свойства, ранг, путь
RECIPES = [
    ("healing_balm", ["life"], 1, ["ing_sage_bundle", M]),
    ("warming_ointment", ["heat"], 1, ["ing_fire_bloom", M, ST]),
    ("smith_flux", ["heat", "acid"], 1, ["ing_fire_bloom", M]),
    ("warming_balm", ["life", "heat"], 1, ["ing_sage_bundle", "ing_fire_bloom", M, ST]),
    ("cooling_tonic", ["cold"], 2, ["ing_moon_moss", M, SB]),
    ("sleepy_drops", ["sleep"], 2, ["ing_drowse_herb", M, ST]),
    ("glow_solution", ["light"], 2, ["ing_golden_root", M, ST]),
    ("burn_salve", ["life", "cold"], 2, ["ing_sage_bundle", "ing_moon_moss", M, SB]),
    ("restful_draught", ["life", "sleep"], 2, ["ing_drowse_herb", M]),
    ("vigor_elixir", ["life", "light"], 2, ["ing_golden_root", M]),
    ("summer_night_drops", ["cold", "sleep"], 2, ["ing_moon_moss", M]),
    ("clear_dream_elixir", ["life", "sleep", "light"], 2, ["ing_drowse_herb", "ing_golden_root", M]),
    ("snow_peace_draught", ["life", "cold", "sleep"], 2, ["ing_moon_moss", "ing_drowse_herb", M]),
    ("rust_remover", ["acid"], 3, ["ing_rust_lichen", M, SB]),
    ("armor_polish", ["light", "acid"], 3, ["ing_rust_lichen", M]),
    ("festive_sparks", ["heat", "light"], 3, ["ing_fire_bloom", "ing_glow_flower", M, B75]),
    ("cozy_brew", ["heat", "sleep"], 3, ["ing_ember_nut", M]),
    ("freshness_elixir", ["life", "cold", "light"], 3, ["ing_frost_berry", "ing_golden_root", M]),
    ("sun_elixir", ["life", "heat", "light"], 3, ["ing_sage_bundle", "ing_fire_bloom", "ing_golden_root", M, ST]),
    ("frost_lantern_oil", ["cold", "light"], 4, ["ing_snow_lotus", M, ST]),
]
RECIPE_PROPS = {r[0]: r[1] for r in RECIPES}

# ---------- GDD §7 покупки: id, вид (enum Kind), цена, ранг
STATION, KNOWLEDGE, UPGRADE = 0, 1, 2
TOOLS = [
    ("settler", STATION, 90, 1),
    ("indicator_paper", KNOWLEDGE, 180, 2),
    ("burner", STATION, 350, 3),
    ("thermometer", KNOWLEDGE, 250, 3),
    ("mortar_third_slot", UPGRADE, 200, 3),
    ("sprout_checker", KNOWLEDGE, 500, 4),
]
RANKS = [(1, 0), (2, 15), (3, 50), (4, 120), (5, 250)]

ECONOMY = {
    "significance_threshold": 0.3,
    "strength_thresholds": [1.0, 2.0, 3.0],
    "purity_thresholds": [0.6, 0.8, 0.95],
    "mortar_slots": 2, "mortar_slots_upgraded": 3,
    "grind_soft": 0.12, "grind_medium": 0.09, "grind_hard": 0.07,
    "taps_per_circle": 4, "perfect_from": 0.7, "perfect_to": 0.85,
    "extraction_floor": 0.4, "overgrind_slope": 2.0,
    "settle_time": 1.2, "min_layer_height": 0.1,
    "pour_speed_start": 0.15, "pour_speed_full": 0.3, "pour_ramp_time": 0.5, "pour_stop_time": 0.1,
    "heat_rate": 20.0, "cool_rate": 12.0, "room_temp": 20.0, "max_temp": 100.0,
    "evaporate_rate": 1.2, "burn_rate": 0.8,
    "pay_by_stars": [0.4, 0.75, 1.0], "flawless_tip": 0.2,
    "streak_tip_step": 0.05, "streak_tip_max": 0.25, "flawless_reputation_bonus": 1,
    "base_pay_flat": 10, "base_pay_per_strength": 15, "base_pay_per_purity": 10,
    "orders_per_day": 6, "interstitial_first_day": 3, "free_hints_per_day": 1,
    "merchant_gift_min_rank": 4, "merchant_gift_crystals": 1,
    "golden_page_flawless": 3, "start_coins": 0,
}
DAILY = {"coins": [40, 60, 0, 100, 150, 0, 300], "crystals": [0, 0, 1, 0, 0, 2, 0], "restart_after_last": True}


def base_pay(n: int, s: int, p: int) -> int:
    e = ECONOMY
    return e["base_pay_flat"] + e["base_pay_per_strength"] * n * s + e["base_pay_per_purity"] * p


# ---------- шаблоны заказов (GDD §5.4): рецепт, сила, чистота, мин. ранг
def T(recipe: str, s: int, p: int, rank: int) -> tuple:
    return (f"{recipe}_s{s}_p{p}", recipe, s, p, rank)


ORDERS = [
    # ранг 1: Жизнь, Жар, Жизнь + Жар — ★, чистота ★–★★
    T("healing_balm", 1, 1, 1), T("healing_balm", 1, 2, 1),
    T("warming_ointment", 1, 1, 1), T("warming_ointment", 1, 2, 1),
    T("warming_balm", 1, 1, 1), T("warming_balm", 1, 2, 1),
    # ранг 2: + Холод, Сон, Свет, флюс, пары с Жизнью, Холод + Сон — ★–★★, чистота ★★
    T("healing_balm", 2, 2, 2), T("warming_ointment", 2, 2, 2), T("warming_balm", 2, 2, 2),
    T("cooling_tonic", 1, 2, 2), T("cooling_tonic", 2, 2, 2),
    T("sleepy_drops", 1, 2, 2), T("sleepy_drops", 2, 2, 2),
    T("glow_solution", 1, 2, 2), T("glow_solution", 2, 2, 2),
    T("smith_flux", 1, 2, 2), T("smith_flux", 2, 2, 2),
    T("burn_salve", 1, 2, 2), T("restful_draught", 1, 2, 2), T("vigor_elixir", 1, 2, 2),
    T("summer_night_drops", 1, 2, 2),
    # ранг 3: + Едкость, полироль, искры, уютный отвар — ★–★★, чистота ★★–★★★
    T("rust_remover", 1, 2, 3), T("rust_remover", 2, 3, 3),
    T("armor_polish", 1, 2, 3), T("armor_polish", 1, 3, 3),
    T("festive_sparks", 1, 2, 3), T("festive_sparks", 2, 3, 3),
    T("cozy_brew", 1, 2, 3), T("cozy_brew", 2, 3, 3),
    T("burn_salve", 2, 3, 3), T("vigor_elixir", 2, 3, 3),
    # ранг 4: + тройные, ледяной фонарь — ★★–★★★, чистота ★★–★★★
    T("frost_lantern_oil", 2, 2, 4),
    T("clear_dream_elixir", 2, 2, 4), T("snow_peace_draught", 2, 2, 4),
    T("freshness_elixir", 2, 2, 4), T("sun_elixir", 2, 2, 4),
    T("festive_sparks", 3, 3, 4),
    # ранг 5: королевский гонец — тройные ★★★/★★★
    T("sun_elixir", 3, 3, 5),
]
ORDER_BY_ID = {o[0]: o for o in ORDERS}

# ---------- GDD §9 FTUE: id, свойства, сила, чистота, база (фиксированная)
FTUE = [
    ("ftue_1", ["life"], 1, 1, 30),
    ("ftue_2", ["life"], 2, 1, 40),
    ("ftue_3", ["heat"], 1, 2, 40),
    ("ftue_4", ["heat"], 1, 3, 45),
    ("ftue_5", ["life", "heat"], 1, 3, 65),
]

# ---------- GDD §6 клиенты: id, ранг, множитель оплаты, визитов в день, портреты, заказы
CLIENTS = [
    ("baker", 1, 1.0, 0, {"neutral": "res://assets/characters/client_baker_neutral.png"}, [
        "healing_balm_s1_p1", "healing_balm_s1_p2", "warming_ointment_s1_p1",
        "warming_balm_s1_p1", "warming_balm_s1_p2",
        "healing_balm_s2_p2", "warming_balm_s2_p2", "burn_salve_s1_p2",
        "cozy_brew_s1_p2", "festive_sparks_s1_p2", "burn_salve_s2_p3"]),
    ("smith", 1, 1.0, 0, {}, [
        "warming_ointment_s1_p1", "warming_ointment_s1_p2",
        "warming_ointment_s2_p2", "smith_flux_s1_p2", "smith_flux_s2_p2",
        "rust_remover_s1_p2", "rust_remover_s2_p3", "armor_polish_s1_p2", "armor_polish_s1_p3"]),
    ("guard", 2, 1.0, 0, {}, [
        "healing_balm_s2_p2", "glow_solution_s1_p2", "glow_solution_s2_p2",
        "vigor_elixir_s1_p2", "sleepy_drops_s1_p2", "restful_draught_s1_p2",
        "vigor_elixir_s2_p3", "frost_lantern_oil_s2_p2"]),
    ("gardener", 2, 1.0, 0, {}, [
        "cooling_tonic_s1_p2", "cooling_tonic_s2_p2", "burn_salve_s1_p2",
        "summer_night_drops_s1_p2", "burn_salve_s2_p3", "freshness_elixir_s2_p2"]),
    ("librarian", 3, 1.0, 0, {}, [
        "sleepy_drops_s1_p2", "sleepy_drops_s2_p2", "glow_solution_s2_p2",
        "restful_draught_s1_p2", "clear_dream_elixir_s2_p2"]),
    ("mage", 4, 1.0, 0, {}, [
        "festive_sparks_s2_p3", "cozy_brew_s2_p3", "clear_dream_elixir_s2_p2",
        "snow_peace_draught_s2_p2", "sun_elixir_s2_p2", "festive_sparks_s3_p3"]),
    ("herald", 5, 2.0, 1, {}, ["sun_elixir_s3_p3"]),
]
TEXTURES = {i: f"res://assets/ingredients/{i}.png" for i in
            ("ing_sage_bundle", "ing_fire_bloom", "ing_moon_moss", "ing_golden_root")}

# =====================================================================================
# Упрощённый решатель
PROP = {p[0]: p for p in PROPERTIES}
ING = {i[0]: i for i in INGREDIENTS}
BURNER_BANDS = {B35: 35.0, B55: 55.0, B75: 75.0}


def significant(mix: dict) -> set:
    return {k for k, v in mix.items() if v >= ECONOMY["significance_threshold"] - 1e-9}


def settler(mix: dict, top: bool, k: int) -> dict:
    present = sorted((p for p in mix if mix[p] > 1e-9), key=lambda p: PROP[p][3])
    keep = present[-k:] if top else present[:k]
    return {p: mix[p] for p in keep}


def burner(mix: dict, temp: float) -> dict:
    out = {}
    for p, v in mix.items():
        evap, burn = PROP[p][4], PROP[p][5]
        if (evap >= 0 and temp >= evap) or (burn >= 0 and temp >= burn):
            continue
        out[p] = v
    return out


def mix_of(ings) -> dict:
    mix: dict = {}
    for i in ings:
        for p, v in ING[i][1].items():
            mix[p] = mix.get(p, 0.0) + v
    return mix


def apply_step(mix: dict, step: str) -> dict:
    if step == ST or step == SB:  # подсказка: срез по первой границе, где отделяется лишнее
        raise ValueError
    return burner(mix, BURNER_BANDS[step])


def run_hint(steps: list) -> dict:
    ings = [s for s in steps if s.startswith("ing_")]
    mix = mix_of(ings)
    ops = [s for s in steps if not s.startswith("ing_") and s != M]
    return mix, ops


def outcomes(mix: dict, settler_ok: bool, burner_ok: bool, depth: int = 2):
    """Все смеси, достижимые не более чем depth операциями."""
    yield mix, []
    if depth == 0:
        return
    n = len([p for p in mix if mix[p] > 1e-9])
    if settler_ok:
        for k in range(1, n):
            for top in (True, False):
                nxt = settler(mix, top, k)
                for m2, path in outcomes(nxt, settler_ok, burner_ok, depth - 1):
                    yield m2, [(ST if top else SB) + f"({k})"] + path
    if burner_ok:
        for t in (35.0, 55.0, 75.0, 90.0):
            nxt = burner(mix, t)
            if nxt != mix:
                for m2, path in outcomes(nxt, settler_ok, burner_ok, depth - 1):
                    yield m2, [f"burner{int(t)}"] + path


def evaluate(mix: dict, required: list, s: int, p: int) -> bool:
    sig = significant(mix)
    if not set(required) <= sig:
        return False
    if any(mix[r] < ECONOMY["strength_thresholds"][s - 1] - 1e-9 for r in required):
        return False
    total = sum(mix.values())
    return total > 0 and sum(mix[r] for r in required) / total >= ECONOMY["purity_thresholds"][p - 1] - 1e-9


def solve(required: list, s: int, p: int, rank: int):
    pool = [i for i in ING if ING[i][4] <= rank]
    slots = ECONOMY["mortar_slots_upgraded"] if rank >= 3 else ECONOMY["mortar_slots"]
    settler_ok = rank >= 1
    burner_ok = rank >= 3
    best = None
    for n in range(1, slots + 1):
        for combo in itertools.combinations_with_replacement(pool, n):
            cost = sum(ING[i][3] for i in combo)
            for mix, path in outcomes(mix_of(combo), settler_ok, burner_ok):
                if evaluate(mix, required, s, p) and (best is None or cost < best[0]):
                    best = (cost, combo, path)
    return best


def check() -> list[str]:
    errors = []
    # пути рецептов
    for rid, props, tier, steps in RECIPES:
        ings = [x for x in steps if x.startswith("ing_")]
        if any(ING[i][4] > tier for i in ings):
            errors.append(f"рецепт {rid}: ингредиент пути открывается позже ранга {tier}")
        mix = mix_of(ings)
        for st in steps:
            if st in (ST, SB):
                # срез на границе, после которой остаются ровно свойства рецепта
                cands = [settler(mix, st == ST, k) for k in range(1, len(mix))]
                ok = [c for c in cands if significant(c) == set(props)]
                mix = ok[0] if ok else {}
            elif st in BURNER_BANDS:
                mix = burner(mix, BURNER_BANDS[st])
        if significant(mix) != set(props):
            errors.append(f"рецепт {rid}: путь даёт {sorted(significant(mix))}, нужно {sorted(props)}")
    if len({frozenset(r[1]) for r in RECIPES}) != len(RECIPES):
        errors.append("наборы свойств рецептов повторяются")
    # заказы
    print(f"{'шаблон':28} ранг  база  решение (дешевле всего)")
    for oid, rid, s, p, rank in ORDERS:
        sol = solve(RECIPE_PROPS[rid], s, p, rank)
        if sol is None:
            errors.append(f"заказ {oid}: не решается на ранге {rank}")
            print(f"{oid:28} {rank:>4} {base_pay(len(RECIPE_PROPS[rid]), s, p):>5}  НЕТ")
        else:
            print(f"{oid:28} {rank:>4} {base_pay(len(RECIPE_PROPS[rid]), s, p):>5}  "
                  f"{'+'.join(i[4:] for i in sol[1])} → {' → '.join(sol[2]) or 'ступка'} ({sol[0]} мон.)")
    for fid, req, s, p, _ in FTUE:
        if solve(req, s, p, 1) is None:
            errors.append(f"FTUE {fid}: не решается")
    used = {o for c in CLIENTS for o in c[5]}
    for oid in ORDER_BY_ID:
        if oid not in used:
            errors.append(f"заказ {oid} не назначен ни одному клиенту")
    for c in CLIENTS:
        for oid in c[5]:
            if oid not in ORDER_BY_ID:
                errors.append(f"клиент {c[0]}: нет шаблона {oid}")
    # FTUE-гарантия: 3★ + 2★ + 2★ в первых трёх заказах хватает на Отстойник
    pay = [round(FTUE[0][4] * ECONOMY["pay_by_stars"][2]), round(FTUE[1][4] * ECONOMY["pay_by_stars"][1]),
           round(FTUE[2][4] * ECONOMY["pay_by_stars"][1])]
    if sum(pay) < TOOLS[0][2]:
        errors.append(f"FTUE: после трёх заказов {sum(pay)} < цены Отстойника {TOOLS[0][2]}")
    return errors


# =====================================================================================
# Запись .tres
def sn(v: str) -> str:
    return f'&"{v}"'


def fnum(v: float) -> str:
    s = repr(float(v))
    return s


def color(hexv: str) -> str:
    r, g, b = (int(hexv[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"Color({r:.6g}, {g:.6g}, {b:.6g}, 1)"


def sn_array(items) -> str:
    return "Array[StringName]([" + ", ".join(sn(x) for x in items) + "])"


class Tres:
    def __init__(self, script_class: str, script_path: str):
        self.script_class = script_class
        self.ext: list[tuple[str, str, str]] = []
        self.props: list[tuple[str, str]] = []
        self.script = self.add_ext("Script", script_path)

    def add_ext(self, typ: str, path: str) -> str:
        for t, p, i in self.ext:
            if p == path:
                return i
        rid = f"{len(self.ext) + 1}_{Path(path).stem[:24]}"
        self.ext.append((typ, path, rid))
        return rid

    def ref(self, typ: str, path: str) -> str:
        return f'ExtResource("{self.add_ext(typ, path)}")'

    def set(self, key: str, value: str) -> None:
        self.props.append((key, value))

    def text(self) -> str:
        out = [f'[gd_resource type="Resource" script_class="{self.script_class}" format=3]', ""]
        for typ, path, rid in self.ext:
            out.append(f'[ext_resource type="{typ}" path="{path}" id="{rid}"]')
        out += ["", "[resource]", f'script = ExtResource("{self.script}")']
        out += [f"{k} = {v}" for k, v in self.props]
        return "\n".join(out) + "\n"


def res(rel: str) -> str:
    return "res://data/" + rel


def typed_array(t: Tres, script_path: str, paths: list[str]) -> str:
    sid = t.add_ext("Script", script_path)
    items = ", ".join(t.ref("Resource", p) for p in paths)
    return f'Array[ExtResource("{sid}")]([{items}])'


SCRIPTS = {
    "property": res("properties/property_data.gd"),
    "ingredient": res("ingredients/ingredient_data.gd"),
    "recipe": res("recipes/recipe_data.gd"),
    "order": res("orders/order_template.gd"),
    "client": res("clients/client_data.gd"),
    "tool": res("equipment/tool_data.gd"),
    "rank": res("ranks/rank_data.gd"),
    "economy": res("economy/economy_config.gd"),
    "daily": res("daily/daily_reward_config.gd"),
    "catalog": res("data_catalog.gd"),
}


def build() -> dict[str, str]:
    files: dict[str, str] = {}
    paths: dict[str, list[str]] = {k: [] for k in ("property", "ingredient", "recipe", "client", "tool", "rank", "ftue")}

    for pid, hexv, pattern, density, evap, burn in PROPERTIES:
        t = Tres("PropertyData", SCRIPTS["property"])
        t.set("id", sn(pid)); t.set("name_key", sn(f"PROPERTY_{pid.upper()}_NAME"))
        t.set("color", color(hexv)); t.set("pattern", str(pattern)); t.set("density_rank", str(density))
        t.set("evaporate_temp", fnum(evap)); t.set("burn_temp", fnum(burn))
        rel = f"properties/{pid}.tres"; files[rel] = t.text(); paths["property"].append(res(rel))

    for iid, props, hardness, cost, rank, price, rare in INGREDIENTS:
        t = Tres("IngredientData", SCRIPTS["ingredient"])
        t.set("id", sn(iid)); t.set("name_key", sn(f"ING_{iid[4:].upper()}_NAME"))
        if iid in TEXTURES:
            t.set("texture", t.ref("Texture2D", TEXTURES[iid]))
        body = ", ".join(f"{sn(k)}: {fnum(v)}" for k, v in props.items())
        t.set("properties", f"Dictionary[StringName, float]({{{body}}})")
        t.set("hardness", str(hardness)); t.set("cost_per_use", str(cost))
        t.set("unlock_rank", str(rank)); t.set("unlock_price", str(price))
        t.set("is_rare", "true" if rare else "false")
        rel = f"ingredients/{iid}.tres"; files[rel] = t.text(); paths["ingredient"].append(res(rel))

    for rid, props, tier, steps in RECIPES:
        t = Tres("RecipeData", SCRIPTS["recipe"])
        t.set("id", sn(rid)); t.set("name_key", sn(f"RECIPE_{rid.upper()}_NAME"))
        t.set("desc_key", sn(f"RECIPE_{rid.upper()}_DESC")); t.set("property_set", sn_array(props))
        t.set("tier", str(tier)); t.set("hint_steps", sn_array(steps))
        rel = f"recipes/{rid}.tres"; files[rel] = t.text(); paths["recipe"].append(res(rel))

    def order(oid: str, req: list, s: int, p: int, pay: int, rank: int, weight: float, line: str, rel: str):
        t = Tres("OrderTemplate", SCRIPTS["order"])
        t.set("id", sn(oid)); t.set("required", sn_array(req))
        t.set("strength_req", str(s)); t.set("purity_req", str(p)); t.set("base_pay", str(pay))
        t.set("min_rank", str(rank)); t.set("weight", fnum(weight)); t.set("line_key", sn(line))
        files[rel] = t.text()

    for oid, rid, s, p, rank in ORDERS:
        req = RECIPE_PROPS[rid]
        order(oid, req, s, p, base_pay(len(req), s, p), rank, 1.0, f"ORDER_{rid.upper()}_LINE", f"orders/{oid}.tres")
    for fid, req, s, p, pay in FTUE:
        rel = f"orders/ftue/{fid}.tres"
        order(fid, req, s, p, pay, 1, 0.0, f"ORDER_{fid.upper()}_LINE", rel)
        paths["ftue"].append(res(rel))

    for cid, rank, mult, visits, portraits, orders in CLIENTS:
        t = Tres("ClientData", SCRIPTS["client"])
        t.set("id", sn(cid)); t.set("name_key", sn(f"CLIENT_{cid.upper()}_NAME"))
        for mood, path in portraits.items():
            t.set(f"portrait_{mood}", t.ref("Texture2D", path))
        t.set("min_rank", str(rank))
        t.set("orders", typed_array(t, SCRIPTS["order"], [res(f"orders/{o}.tres") for o in orders]))
        t.set("pay_multiplier", fnum(mult)); t.set("visits_per_day", str(visits))
        rel = f"clients/{cid}.tres"; files[rel] = t.text(); paths["client"].append(res(rel))

    for tid, kind, price, rank in TOOLS:
        t = Tres("ToolData", SCRIPTS["tool"])
        t.set("id", sn(tid)); t.set("kind", str(kind)); t.set("price", str(price)); t.set("unlock_rank", str(rank))
        t.set("name_key", sn(f"TOOL_{tid.upper()}_NAME")); t.set("desc_key", sn(f"TOOL_{tid.upper()}_DESC"))
        rel = f"equipment/{tid}.tres"; files[rel] = t.text(); paths["tool"].append(res(rel))

    for idx, threshold in RANKS:
        t = Tres("RankData", SCRIPTS["rank"])
        t.set("index", str(idx)); t.set("name_key", sn(f"RANK_{idx}_NAME")); t.set("threshold", str(threshold))
        rel = f"ranks/rank_{idx}.tres"; files[rel] = t.text(); paths["rank"].append(res(rel))

    t = Tres("EconomyConfig", SCRIPTS["economy"])
    for k, v in ECONOMY.items():
        if isinstance(v, list):
            t.set(k, "Array[float]([" + ", ".join(fnum(x) for x in v) + "])")
        elif isinstance(v, float):
            t.set(k, fnum(v))
        else:
            t.set(k, str(v))
    files["economy/economy_config.tres"] = t.text()

    t = Tres("DailyRewardConfig", SCRIPTS["daily"])
    t.set("coins", "Array[int]([" + ", ".join(map(str, DAILY["coins"])) + "])")
    t.set("crystals", "Array[int]([" + ", ".join(map(str, DAILY["crystals"])) + "])")
    t.set("crystal_item", t.ref("Resource", res("ingredients/ing_star_crystal.tres")))
    t.set("restart_after_last", "true" if DAILY["restart_after_last"] else "false")
    files["daily/daily_reward_config.tres"] = t.text()

    t = Tres("DataCatalog", SCRIPTS["catalog"])
    for key, field in (("property", "properties"), ("ingredient", "ingredients"), ("recipe", "recipes"),
                       ("client", "clients"), ("tool", "tools"), ("rank", "ranks")):
        t.set(field, typed_array(t, SCRIPTS[key], paths[key]))
    t.set("ftue_orders", typed_array(t, SCRIPTS["order"], paths["ftue"]))
    t.set("economy", t.ref("Resource", res("economy/economy_config.tres")))
    t.set("daily_rewards", t.ref("Resource", res("daily/daily_reward_config.tres")))
    files["catalog.tres"] = t.text()
    return files


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="только проверка, без записи")
    ap.add_argument("--force", action="store_true", help="перезаписать существующие .tres")
    a = ap.parse_args()
    errors = check()
    for e in errors:
        print("ОШИБКА:", e)
    if errors:
        return 1
    print("проверка: OK")
    if a.check:
        return 0
    written = skipped = 0
    for rel, text in build().items():
        path = DATA / rel
        if path.exists() and not a.force:
            skipped += 1
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        written += 1
    print(f"записано {written}, пропущено (уже есть) {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
