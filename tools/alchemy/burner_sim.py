#!/usr/bin/env python3
"""burner_sim.py — Python-копия станции Горелки (S4.3) поверх эталона правил rules_model.py + самопроверка.

Зачем: у агента нет Godot. Станция scenes/stations/burner/burner.gd шагает смесь и T методом advance(dt);
здесь тот же advance строка в строку (состояния, «пок», «готово», свист, шипение, «буль»), чтобы:
  * проверить, что события и итог не зависят от частоты кадров (30/60/144 к/с и случайный шаг);
  * получить точные ожидания для стенда scenes/debug/burner_check (времена событий, остатки смеси, T).
Правишь burner.gd — правь и этот файл. Данные — из проекта (каталог, EconomyConfig, BurnerConfig).

Запуск:
  python tools/alchemy/burner_sim.py               # сценарии: события и итог при 60 к/с
  python tools/alchemy/burner_sim.py --self-test   # все проверки; код возврата 1 при ошибке
Только stdlib.
"""
from __future__ import annotations

import argparse
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rules_model as rm  # noqa: E402

ROOT = rm.ROOT
GD_CONFIG = ROOT / "data" / "burner" / "burner_config.gd"
TRES_CONFIG = ROOT / "data" / "burner" / "burner_round.tres"

EMPTY, IDLE, HEATING, COOLING = "Empty", "Idle", "Heating", "Cooling"
NEXT = {EMPTY: {IDLE}, IDLE: {HEATING, EMPTY}, HEATING: {COOLING, EMPTY}, COOLING: {HEATING, IDLE, EMPTY}}
REASON_TRASH, REASON_DRY = "trash", "dry"
FRAME_RATES = (30, 60, 144)
RHYTHM = {"whistle": "whistle_sec", "hiss": "smoke_shake_sec"}


def load_config() -> dict:
    """BurnerConfig: значения по умолчанию из burner_config.gd, поверх — burner_round.tres (только числа)."""
    values = {}
    for name, raw in re.findall(r"^@export\S*\s+var\s+(\w+)\s*:\s*float\s*=\s*([-0-9.]+)", GD_CONFIG.read_text(
            encoding="utf-8"), re.M):
        values[name] = float(raw)
    fields, _ = rm.read_tres(TRES_CONFIG)
    for name, raw in fields.items():
        if re.fullmatch(r"-?[0-9.]+", raw.strip()):
            values[name] = float(raw)
    return values


class BurnerSim:
    """Копия Burner.advance и методов владельца. Звуки и эффекты — записи в events: (время, имя, аргумент)."""

    def __init__(self, catalog: rm.DataCatalog, config: dict):
        self.catalog = catalog
        self.economy = catalog.economy
        self.config = config
        self.state = EMPTY
        self.mixture: dict = {}
        self.temp = self.economy.room_temp
        self.steaming_ids: list = []
        self.burning_ids: list = []
        self.crackle_left = 0.0
        self.glug_phase = 1.0
        self.whistle_left = 0.0
        self.shake_left = 0.0
        # Огонь: Flame.is_lit — сила > 0; гаснет твином flame_fade_sec после ухода из Heating.
        self.flame_off_left = 0.0
        self.time = 0.0
        self.events: list = []

    # --- служебное ---
    def _event(self, name: str, arg=None) -> None:
        self.events.append((self.time, name, arg))

    def _transition(self, to: str) -> bool:
        if to not in NEXT[self.state]:
            return False
        frm, self.state = self.state, to
        self._on_state_changed(frm, to)
        return True

    def _on_state_changed(self, frm: str, to: str) -> None:
        if frm == HEATING:
            self.flame_off_left = self.config["flame_fade_sec"]
        if to == EMPTY:
            self.mixture = {}
            self.steaming_ids = []
            self.burning_ids = []
            self._set_temp(self.economy.room_temp)
        elif to == HEATING:
            self._event("ignite")
            self.crackle_left = self.config["crackle_sec"]
            self.whistle_left = 0.0
        elif to == IDLE and frm == COOLING:
            self._event("idle")

    def _set_temp(self, value: float) -> None:
        self.temp = value

    # --- методы владельца ---
    def receive(self, mixture: dict) -> bool:
        clean = rm.cleaned(mixture)
        if self.state != EMPTY or not clean:
            self._event("refused")
            return False
        self.mixture = clean
        self._set_temp(self.economy.room_temp)
        self._event("received")
        self._transition(IDLE)
        return True

    def begin_heat(self) -> bool:
        return self.state in (IDLE, COOLING) and self._transition(HEATING)

    def end_heat(self) -> None:
        if self.state == HEATING:
            self._transition(COOLING)

    def empty_flask(self) -> None:
        if self.state not in (IDLE, COOLING):
            return
        self._transition(EMPTY)
        self._event("emptied", REASON_TRASH)

    def is_at_limit(self) -> bool:
        return self.state == HEATING and self.temp >= self.economy.max_temp - rm.EPSILON

    def advance(self, delta: float) -> None:
        if delta <= 0.0 or not self.mixture:
            self.time += max(delta, 0.0)
            return
        self.time += delta
        heating = self.state == HEATING
        if heating or self.state == COOLING:
            self._step_heat(heating, delta)
            if not self.mixture:
                return
        self._update_flame(heating, delta)
        self._update_boil(delta)
        self._update_limit(heating, delta)
        self._update_smoke(delta)

    # --- нагрев ---
    def _step_heat(self, heating: bool, delta: float) -> None:
        before = self.mixture
        hottest = self.temp
        self.mixture = rm.heat(self.mixture, self.temp, heating, delta, self.catalog, self.economy)
        self._set_temp(rm.temp_after(self.temp, heating, delta, self.economy))
        hottest = max(hottest, self.temp)
        gone_steam = False
        for property_id in before:
            if property_id in self.mixture:
                continue
            data = self.catalog.property(property_id)
            steamed = data is not None and data.evaporates_at(hottest)
            gone_steam = gone_steam or steamed
            self._event("pop", (property_id, not steamed))
        if not self.mixture:
            self._transition(EMPTY)
            self._event("emptied", REASON_DRY)
            return
        self._refresh_vapor(gone_steam)
        if not heating and self.temp <= self.economy.room_temp:
            self._transition(IDLE)

    def _refresh_vapor(self, gone_steam: bool) -> None:
        now_steaming = rm.steaming(self.mixture, self.temp, self.catalog)
        if now_steaming != self.steaming_ids:
            was_steaming = bool(self.steaming_ids)
            self.steaming_ids = now_steaming
            self._event("steam", tuple(now_steaming))
            if was_steaming and not self.steaming_ids and gone_steam:
                self._event("done")
        now_burning = rm.burning(self.mixture, self.temp, self.catalog)
        if now_burning != self.burning_ids:
            was_burning = bool(self.burning_ids)
            self.burning_ids = now_burning
            self._event("smoke", bool(now_burning))
            if not was_burning:
                self.shake_left = 0.0

    # --- отклик ---
    def _flame_lit(self) -> bool:
        return self.state == HEATING or self.flame_off_left > 0.0

    def _update_flame(self, heating: bool, delta: float) -> None:
        if not heating:
            lit = self.flame_off_left > 0.0
            self.flame_off_left = max(self.flame_off_left - delta, 0.0)
            if not lit:
                return
        self.crackle_left -= delta
        if self.crackle_left <= 0.0:
            self.crackle_left += self.config["crackle_sec"]
            self._event("crackle")

    def _update_boil(self, delta: float) -> None:
        span = self.config["boil_full_temp"] - self.config["boil_from_temp"]
        boil = min(max((self.temp - self.config["boil_from_temp"]) / span, 0.0), 1.0)
        if boil <= 0.0:
            self.glug_phase = 1.0
            return
        self.glug_phase += delta * boil / self.config["boil_glug_sec"]
        if self.glug_phase < 1.0:
            return
        self.glug_phase = self.glug_phase % 1.0
        self._event("glug")

    def _update_limit(self, heating: bool, delta: float) -> None:
        at_limit = heating and self.temp >= self.economy.max_temp - rm.EPSILON
        if not at_limit:
            self.whistle_left = 0.0
            return
        if self.whistle_left > 0.0:
            self.whistle_left -= delta
            if self.whistle_left > 0.0:
                return
        self.whistle_left += self.config["whistle_sec"]
        self._event("whistle")

    def _update_smoke(self, delta: float) -> None:
        if not self.burning_ids:
            return
        if self.shake_left > 0.0:
            self.shake_left -= delta
            if self.shake_left > 0.0:
                return
        self.shake_left += self.config["smoke_shake_sec"]
        self._event("hiss")


# --- Прогон сценария ----------------------------------------------------------------------------------------------

def frames(rate: int | None, seed: int = 0):
    """Бесконечный поток шагов кадра: ровные 1/rate или случайные 4–50 мс (rate = None)."""
    rng = random.Random(seed)
    while True:
        yield 1.0 / rate if rate else rng.uniform(0.004, 0.05)


def run(mixture: dict, actions: list, until: float, rate: int | None, catalog, config, seed: int = 0) -> BurnerSim:
    """actions: [(время, «heat_on» | «heat_off» | «trash» | «receive», аргумент)], по возрастанию времени.
    Кадр режется на моменте действия (как стенд: advance(dt) до нужной секунды), действия — до шага кадра."""
    sim = BurnerSim(catalog, config)
    sim.receive(mixture)
    pending = list(actions)
    stream = frames(rate, seed)
    dt_left = 0.0
    while sim.time < until - 1e-12:
        while pending and pending[0][0] <= sim.time + 1e-12:
            _, kind, arg = pending.pop(0)
            {"heat_on": lambda a: sim.begin_heat(), "heat_off": lambda a: sim.end_heat(),
             "trash": lambda a: sim.empty_flask(), "receive": lambda a: sim.receive(a)}[kind](arg)
        if dt_left <= 1e-15:
            dt_left = next(stream)
        stop = min(until, pending[0][0] if pending else until)
        step = min(dt_left, stop - sim.time)
        dt_left -= step
        sim.advance(step)
    return sim


# --- Сценарии и точные ожидания ----------------------------------------------------------------------------------

def scenarios(catalog) -> list:
    """(имя, смесь, действия, до какой секунды, ожидания). Числа — из GDD §3.3 / EconomyConfig, считаны вручную."""
    e = catalog.economy
    up = lambda t: e.room_temp + e.heat_rate * t           # noqa: E731
    reach = lambda temp: (temp - e.room_temp) / e.heat_rate  # noqa: E731
    cold, sleep, acid, life = (catalog.property(x) for x in ("cold", "sleep", "acid", "life"))
    t_cold = reach(cold.evaporate_temp) + 0.6 / e.evaporate_rate
    t_sleep = reach(sleep.evaporate_temp) + 0.5 / e.evaporate_rate
    t_acid = reach(acid.evaporate_temp) + 0.4 / e.evaporate_rate
    t_limit = reach(e.max_temp)
    t_life_on = reach(life.burn_temp)
    t_life = t_life_on + 1.0 / e.burn_rate
    # «Отпустил на 50°»: холод 0,75 с на нагреве + (50 − 35) / cool_rate на остывании.
    hold = 1.5
    t50 = up(hold)
    cool_above = (t50 - cold.evaporate_temp) / e.cool_rate
    cold_left = 3.0 - e.evaporate_rate * ((hold - reach(cold.evaporate_temp)) + cool_above)
    t_idle = hold + (t50 - e.room_temp) / e.cool_rate
    t_cool_pop = hold + cool_above - 0.005
    cold_gone_at_cooling = e.evaporate_rate * ((hold - reach(cold.evaporate_temp)) + (t_cool_pop - hold))
    return [
        ("volatiles", {"cold": 0.6, "sleep": 0.5, "acid": 0.4, "heat": 1.0}, [(0.0, "heat_on", None), (6.0, "heat_off", None)],
         6.0 + (e.max_temp - e.room_temp) / e.cool_rate + 0.5,
         {"mixture": {"heat": 1.0}, "state": IDLE, "temp": e.room_temp,
          "pops": [("cold", False, t_cold), ("sleep", False, t_sleep), ("acid", False, t_acid)],
          "done": [t_cold, t_sleep, t_acid], "whistle": [t_limit, t_limit + 1.2], "hiss": [], "emptied": [],
          "idle": [6.0 + (e.max_temp - e.room_temp) / e.cool_rate]}),
        ("life_burns", {"life": 1.0, "heat": 1.0}, [(0.0, "heat_on", None)], 5.0,
         {"mixture": {"heat": 1.0}, "state": HEATING, "temp": e.max_temp,
          "pops": [("life", True, t_life)], "done": [], "whistle": [t_limit], "hiss": [t_life_on, t_life_on + 0.9],
          "emptied": [], "idle": []}),
        ("release_cools", {"cold": 3.0, "heat": 1.0}, [(0.0, "heat_on", None), (hold, "heat_off", None)], 5.0,
         {"mixture": {"cold": cold_left, "heat": 1.0}, "state": IDLE, "temp": e.room_temp,
          "pops": [], "done": [], "whistle": [], "hiss": [], "emptied": [], "idle": [t_idle]}),
        # Холод кончается на остывании за 5 мс до того, как T опустится ниже 35°: в кадре, где он ушёл, T конца
        # шага уже ниже точки — «пок» паром (не «сгорел») решает самая высокая T шага.
        ("pop_while_cooling", {"cold": cold_gone_at_cooling, "heat": 1.0}, [(0.0, "heat_on", None),
                                                                           (hold, "heat_off", None)], 5.0,
         {"mixture": {"heat": 1.0}, "state": IDLE, "temp": e.room_temp,
          "pops": [("cold", False, t_cool_pop)], "done": [t_cool_pop], "whistle": [], "hiss": [], "emptied": [],
          "idle": [t_idle]}),
        ("boils_dry", {"cold": 0.3}, [(0.0, "heat_on", None)], 2.0,
         {"mixture": {}, "state": EMPTY, "temp": e.room_temp,
          "pops": [("cold", False, reach(cold.evaporate_temp) + 0.3 / e.evaporate_rate)], "done": [], "whistle": [],
          "hiss": [], "emptied": [(REASON_DRY, reach(cold.evaporate_temp) + 0.3 / e.evaporate_rate)], "idle": []}),
        ("trash_rules", {"sleep": 1.0}, [(0.0, "heat_on", None), (1.0, "trash", None), (1.5, "heat_off", None),
                                          (2.0, "trash", None), (2.5, "receive", {"cold": 1.0})], 3.0,
         {"mixture": {"cold": 1.0}, "state": IDLE, "temp": e.room_temp, "pops": [], "done": [], "whistle": [],
          "hiss": [], "emptied": [(REASON_TRASH, 2.0)], "idle": []}),
    ]


class Checks:
    """Свои проверки: check(ok, имя, что получили). (У rules_model.Checks другой порядок аргументов.)"""

    def __init__(self) -> None:
        self.passed = 0
        self.failed: list = []

    def check(self, ok: bool, name: str, got=None) -> None:
        if ok is True:
            self.passed += 1
        else:
            self.failed.append(f"{name} — получено {got}")


def check_scenario(checks, name, mixture, actions, until, expect, catalog, config) -> None:
    for rate, seed in [(r, 0) for r in FRAME_RATES] + [(None, 7), (None, 99)]:
        sim = run(mixture, actions, until, rate, catalog, config, seed)
        frame = 1.0 / rate if rate else 0.05
        tag = f"{name} @ {rate or 'random'}"
        got_mix = sim.mixture
        ok_mix = set(got_mix) == set(expect["mixture"]) and all(
            abs(got_mix[k] - v) < 1e-9 for k, v in expect["mixture"].items())
        checks.check(ok_mix, f"{tag}: смесь {expect['mixture']}", f"получено {got_mix}")
        checks.check(sim.state == expect["state"], f"{tag}: состояние {expect['state']}", sim.state)
        checks.check(abs(sim.temp - expect["temp"]) < 1e-9, f"{tag}: T {expect['temp']}", sim.temp)
        pops = [(t, a) for t, n, a in sim.events if n == "pop"]
        ok_pops = len(pops) == len(expect["pops"]) and all(
            a == (pid, burned) and t - frame - 1e-9 <= want <= t + 1e-9
            for (t, a), (pid, burned, want) in zip(pops, expect["pops"]))
        checks.check(ok_pops, f"{tag}: «пок» {[(p, b, round(w, 4)) for p, b, w in expect['pops']]}", pops)
        for kind in ("done", "whistle", "hiss", "idle"):
            got = [t for t, n, _ in sim.events if n == kind]
            ok = len(got) == len(expect[kind]) and all(t - frame - 1e-9 <= w <= t + 1e-9
                                                        for t, w in zip(got[:1], expect[kind]))
            if kind in RHYTHM:
                # Ритм: первый удар — не позже кадра после входа, дальше интервал period … period + кадр.
                period = config[RHYTHM[kind]]
                ok = ok and all(period - 1e-9 <= b - a <= period + frame + 1e-9 for a, b in zip(got, got[1:]))
            else:
                ok = ok and all(t - frame - 1e-9 <= w <= t + 1e-9 for t, w in zip(got, expect[kind]))
            checks.check(ok, f"{tag}: {kind} {[round(w, 4) for w in expect[kind]]}", [round(t, 4) for t in got])
        emptied = [(a, t) for t, n, a in sim.events if n == "emptied"]
        ok_e = len(emptied) == len(expect["emptied"]) and all(
            a == r and t - frame - 1e-9 <= w <= t + 1e-9 for (a, t), (r, w) in zip(emptied, expect["emptied"]))
        checks.check(ok_e, f"{tag}: вылито {expect['emptied']}", emptied)


def expected_glugs(actions: list, until: float, economy, config: dict) -> int:
    """Эталон числа «буль» без логики станции: T по точным формулам (огонь — между heat_on и heat_off),
    ∫ кипение dt шагом 1 мс; первый удар — как только закипело, дальше по одному на boil_glug_sec · 1."""
    step = 0.001
    on = sorted((t, kind) for t, kind, _ in actions if kind in ("heat_on", "heat_off"))
    temp, total, boiled, t = economy.room_temp, 0.0, False, 0.0
    while t < until - 1e-12:
        heating = any(kind == "heat_on" for when, kind in on if when <= t + 1e-12) and not any(
            kind == "heat_off" for when, kind in on if when <= t + 1e-12)
        temp = rm.temp_after(temp, heating, step, economy)
        boil = min(max((temp - config["boil_from_temp"]) / (config["boil_full_temp"] - config["boil_from_temp"]),
                       0.0), 1.0)
        boiled = boiled or boil > 0.0
        total += boil * step
        t += step
    return (1 + int(total / config["boil_glug_sec"])) if boiled else 0


def self_test() -> int:
    catalog = rm.load_catalog()
    config = load_config()
    checks = Checks()
    for name, mixture, actions, until, expect in scenarios(catalog):
        check_scenario(checks, name, mixture, actions, until, expect, catalog, config)
    # «Буль»: темп следует за кипением — число ударов не зависит от частоты кадров (±1 к эталону 1000 к/с);
    # на полном кипении (≥ boil_full_temp) интервал boil_glug_sec ± кадр.
    for name, mixture, actions, until, _ in scenarios(catalog):
        ref = sum(1 for _, n, _ in run(mixture, actions, until, 1000, catalog, config).events if n == "glug")
        want = expected_glugs(actions, until, catalog.economy, config)
        checks.check(abs(ref - want) <= 1, f"{name}: «буль» {want} ± 1 по интегралу кипения", ref)
        for rate, seed in [(r, 0) for r in FRAME_RATES] + [(None, 7)]:
            got = sum(1 for _, n, _ in run(mixture, actions, until, rate, catalog, config, seed).events if n == "glug")
            checks.check(abs(got - ref) <= 1, f"{name} @ {rate or 'random'}: «буль» {ref} ± 1", got)
    e = catalog.economy
    full_at = (config["boil_full_temp"] - e.room_temp) / e.heat_rate
    for rate in FRAME_RATES:
        sim = run({"life": 1.0, "heat": 1.0}, [(0.0, "heat_on", None)], 8.0, rate, catalog, config)
        beats = [t for t, n, _ in sim.events if n == "glug" and t > full_at + 1.0 / rate]
        gaps = [b - a for a, b in zip(beats, beats[1:])]
        checks.check(len(gaps) >= 5 and all(abs(g - config["boil_glug_sec"]) <= 1.0 / rate + 1e-9 for g in gaps),
                     f"полное кипение @ {rate}: «буль» раз в {config['boil_glug_sec']} с", [round(g, 4) for g in gaps])
    # Повторное «готово» не звенит: пар стих один раз, пока нагрев продолжается.
    sim = run({"cold": 0.6, "heat": 1.0}, [(0.0, "heat_on", None)], 5.0, 60, catalog, config)
    checks.check([n for _, n, _ in sim.events].count("done") == 1, "«готово» один раз за нагрев", sim.events)
    # Пустую смесь и вторую колбу не принять.
    sim = BurnerSim(catalog, config)
    checks.check(not sim.receive({}) and sim.state == EMPTY, "пустую смесь не принять", sim.state)
    checks.check(sim.receive({"cold": 1.0}) and not sim.receive({"sleep": 1.0}), "вторую колбу не принять",
                 sim.events)
    checks.check(not BurnerSim(catalog, config).begin_heat(), "в Empty огонь не зажечь", "")
    print(f"BURNER SIM: {checks.passed}/{checks.passed + len(checks.failed)} {'OK' if not checks.failed else 'FAIL'}")
    for line in checks.failed:
        print("  FAIL", line)
    return 0 if not checks.failed else 1


def report() -> int:
    catalog = rm.load_catalog()
    config = load_config()
    for name, mixture, actions, until, expect in scenarios(catalog):
        sim = run(mixture, actions, until, 60, catalog, config)
        print(f"== {name}: {mixture} {actions} до {until:.3f} с → {sim.state}, T {sim.temp:.3f}, смесь "
              f"{ {k: round(v, 6) for k, v in sim.mixture.items()} }")
        for t, n, a in sim.events:
            if n not in ("crackle", "glug"):
                print(f"   {t:7.4f}  {n}  {a if a is not None else ''}")
        counts = {k: sum(1 for _, n, _ in sim.events if n == k) for k in ("crackle", "glug")}
        print(f"   треск {counts['crackle']}, «буль» {counts['glug']}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    return self_test() if args.self_test else report()


if __name__ == "__main__":
    sys.exit(main())
