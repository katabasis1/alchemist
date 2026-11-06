#!/usr/bin/env python3
"""vapor_preview.py — пар и дым над Горелкой картинкой (S4.3): numpy-копия частиц components/vapor/vapor.tscn.

Godot в песочнице агента нет, поэтому вид пара, иконок, дыма и «пок» сверяется этим скриптом с референсами
docs/art/refs/ref_burner_heating.jpg и ref_burner_overheat_smoke.jpg (правило D20).
Параметры излучателей (CPUParticles2D) и кривые читаются из vapor.tscn, полёт иконок — из @export vapor.gd,
частота — из BurnerConfig (burner_round.tres). Движение частиц повторяет CPUParticles2D: сила (gravity) → затухание
скорости (damping) → сдвиг; размер = scale_amount × scale_amount_curve, цвет = color × color_ramp × color_initial_ramp.
Станция под паром — flame_preview.station (горелка, колба со смесью, пламя) с запасом холста сверху.

  python tools/art/vapor_preview.py --out /tmp/prev        # лист: пар Холода, пар трёх свойств, «пок», дым Жизни
                                                            # + референсы; vapor_closeup.png — горло крупно

Только Pillow + numpy. Собственный код проекта. Случайность — с фиксированным зерном: картинка повторяется.
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "art"))
import flame_preview as FP  # noqa: E402
import liquid_preview as LP  # noqa: E402

SCENE = ROOT / "components" / "vapor" / "vapor.tscn"
SCRIPT = ROOT / "components" / "vapor" / "vapor.gd"
CONFIG = ROOT / "data" / "burner" / "burner_round.tres"
PROPS = ROOT / "data" / "properties"
ICONS = ROOT / "assets" / "ui"
REFS = ROOT / "docs" / "art" / "refs"
HEADROOM = 300
DT = 1.0 / 60.0
SHOP_TOP, SHOP_BOTTOM = np.array([0.42, 0.29, 0.19]), np.array([0.55, 0.38, 0.24])   # тёплое дерево лавки


# ---------- разбор .tscn / .tres / .gd ----------

def _nums(raw: str) -> list:
    """Числа из записи Godot; имена типов перед скобкой (Vector2, PackedFloat32Array) — не числа."""
    raw = re.sub(r"[A-Za-z_]\w*(?=\()", "", raw)
    return [float(x) for x in re.findall(r"-?\d+\.?\d*(?:e-?\d+)?", raw)]


def parse_scene(path: Path = SCENE) -> tuple:
    """Подресурсы (Curve, Gradient), внешние ресурсы и узлы сцены: (sub, ext, nodes); узел — dict свойств."""
    text = path.read_text("utf-8")
    ext = {m.group(2): m.group(1) for m in re.finditer(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"\]', text)}
    sub, nodes = {}, {}
    for block in re.split(r"\n(?=\[)", text):
        head = block.split("\n", 1)[0]
        props = dict(re.findall(r"^(\w+) = (.+)$", block, re.M))
        m = re.match(r'\[sub_resource type="(\w+)" id="([^"]+)"\]', head)
        if m:
            kind, rid = m.groups()
            if kind == "Curve":
                d = _nums(props["_data"])
                sub[rid] = [(d[i], d[i + 1]) for i in range(0, len(d), 6)]   # x, y, left, right, left_mode, right_mode
            elif kind == "Gradient":
                sub[rid] = dict(offsets=_nums(props["offsets"]), colors=np.array(_nums(props["colors"])).reshape(-1, 4),
                                constant=props.get("interpolation_mode") == "1")
            continue
        m = re.match(r'\[node name="(\w+)" type="(\w+)"(?: parent="([^"]*)")?', head)
        if m:
            name, kind, parent = m.groups()
            path_ = name if parent in (None, ".") else f"{parent}/{name}"
            nodes[path_ if parent is not None else "."] = dict(props, _type=kind)
    return sub, ext, nodes


def script_exports(path: Path = SCRIPT) -> dict:
    return {m.group(1): float(m.group(2))
            for m in re.finditer(r"^@export[^\n]*var (\w+): float = (-?[\d.]+)", path.read_text("utf-8"), re.M)}


def tres_floats(path: Path) -> dict:
    return {k: float(v) for k, v in re.findall(r"^(\w+) = (-?[\d.]+)$", path.read_text("utf-8"), re.M)}


def prop_color(pid: str) -> np.ndarray:
    raw = re.search(r"^color = Color\(([^)]+)\)", (PROPS / f"{pid}.tres").read_text("utf-8"), re.M).group(1)
    return np.array(_nums(raw))


# ---------- кривые и градиенты как в Godot ----------

def curve_at(points: list | None, t: float) -> float:
    if not points:
        return 1.0
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    return float(np.interp(t, xs, ys))


def gradient_at(g: dict | None, t: float) -> np.ndarray:
    if g is None:
        return np.ones(4)
    offs, cols = g["offsets"], g["colors"]
    if g.get("constant"):
        i = max([k for k, o in enumerate(offs) if o <= t] or [0])
        return cols[i]
    return np.array([np.interp(t, offs, cols[:, c]) for c in range(4)])


# ---------- излучатель ----------

class Emitter:
    """Один CPUParticles2D из сцены: свойства, текстура, кривые."""

    def __init__(self, node: dict, sub: dict, ext: dict, amount: int | None = None):
        g = lambda k, d: node.get(k, d)
        f = lambda k, d: float(_nums(g(k, str(d)))[0])
        v2 = lambda k, d: tuple(_nums(g(k, f"Vector2({d[0]}, {d[1]})")))
        ref = lambda k: (re.search(r'"([^"]+)"', node[k]).group(1) if k in node else None)
        self.amount = amount or int(f("amount", 8))
        self.lifetime = f("lifetime", 1.0)
        self.life_rand = f("lifetime_randomness", 0.0)
        self.one_shot = g("one_shot", "false") == "true"
        self.explosiveness = f("explosiveness", 0.0)
        self.shape = int(f("emission_shape", 0))
        self.sphere = f("emission_sphere_radius", 1.0)
        self.rect = v2("emission_rect_extents", (1, 1))
        d = v2("direction", (1, 0))
        self.dir_angle = math.atan2(d[1], d[0])
        self.spread = math.radians(f("spread", 45.0))
        self.gravity = np.array(v2("gravity", (0, 980)))
        self.vel = (f("initial_velocity_min", 0.0), f("initial_velocity_max", 0.0))
        self.damp = (f("damping_min", 0.0), f("damping_max", 0.0))
        self.angle = (f("angle_min", 0.0), f("angle_max", 0.0))
        self.spin = (f("angular_velocity_min", 0.0), f("angular_velocity_max", 0.0))
        self.scale = (f("scale_amount_min", 1.0), f("scale_amount_max", 1.0))
        self.scale_curve = sub.get(ref("scale_amount_curve"))
        self.color = np.array(_nums(g("color", "Color(1, 1, 1, 1)")))
        self.ramp = sub.get(ref("color_ramp"))
        self.initial_ramp = sub.get(ref("color_initial_ramp"))
        self.frames = 4 if "material" in node and "flakes" in node.get("material", "").lower() else 1
        tex = ext[re.search(r'"([^"]+)"', node["texture"]).group(1)].replace("res://", "")
        self.texture = Image.open(ROOT / tex).convert("RGBA")

    def particles(self, t_end: float, emit_from: float, emit_to: float, origin, rng) -> list:
        """Частицы, живые в момент t_end: излучение с emit_from до emit_to (секунды), origin(t) — точка излучателя."""
        out = []
        if self.one_shot:
            spawns = [(emit_from, i) for i in range(self.amount)]
        else:
            step = self.lifetime / self.amount
            spawns, k = [], 0
            while emit_from + k * step < min(emit_to, t_end):
                spawns.append((emit_from + k * step, k))
                k += 1
        for t0, idx in spawns:
            r = np.random.default_rng(rng * 7919 + idx)
            life = self.lifetime * (1.0 - r.random() * self.life_rand)
            age = t_end - t0
            if age < 0 or age >= life:
                continue
            if self.shape == 3:
                pos = np.array(origin(t0)) + (r.random(2) * 2 - 1) * np.array(self.rect)
            elif self.shape == 1:
                a, rr = r.random() * math.tau, math.sqrt(r.random()) * self.sphere
                pos = np.array(origin(t0)) + rr * np.array([math.cos(a), math.sin(a)])
            else:
                pos = np.array(origin(t0), float)
            ang = self.dir_angle + (r.random() * 2 - 1) * self.spread
            vel = np.array([math.cos(ang), math.sin(ang)]) * LP.mix(self.vel[0], self.vel[1], r.random())
            damp = LP.mix(self.damp[0], self.damp[1], r.random())
            rot = LP.mix(self.angle[0], self.angle[1], r.random())
            spin = LP.mix(self.spin[0], self.spin[1], r.random())
            base = LP.mix(self.scale[0], self.scale[1], r.random())
            tint = gradient_at(self.initial_ramp, r.random())
            frame = int(r.random() * self.frames) % self.frames
            tt = 0.0
            while tt < age:
                vel = vel + self.gravity * DT
                speed = float(np.linalg.norm(vel))
                if damp > 0 and speed > 0:
                    vel = vel / speed * max(0.0, speed - damp * DT)
                pos = pos + vel * DT
                tt += DT
            u = age / life
            color = self.color * gradient_at(self.ramp, u) * tint
            out.append(dict(pos=pos, rot=rot + spin * age, scale=base * curve_at(self.scale_curve, u), color=color,
                            frame=frame))
        return out

    def draw(self, canvas: np.ndarray, parts: list) -> np.ndarray:
        fw = self.texture.width // self.frames
        for p in parts:
            tex = self.texture.crop((p["frame"] * fw, 0, (p["frame"] + 1) * fw, self.texture.height))
            canvas = blit(canvas, tex, p["pos"], p["scale"], p["rot"], p["color"])
        return canvas


def blit(canvas: np.ndarray, tex: Image.Image, pos, scale: float, rot_deg: float, color) -> np.ndarray:
    """Наложение текстуры с центром в pos: масштаб, поворот (по часовой, как в Godot), умножение на цвет."""
    size = (max(1, round(tex.width * scale)), max(1, round(tex.height * scale)))
    img = tex.resize(size, Image.LANCZOS).rotate(-rot_deg, resample=Image.BICUBIC, expand=True)
    a = np.asarray(img).astype(float) / 255.0
    a[..., :3] *= np.array(color[:3])
    a[..., 3] *= color[3]
    h, w = canvas.shape[:2]
    x0, y0 = round(pos[0] - img.width / 2), round(pos[1] - img.height / 2)
    xs, ys, xe, ye = max(0, x0), max(0, y0), min(w, x0 + img.width), min(h, y0 + img.height)
    if xs >= xe or ys >= ye:
        return canvas
    src = a[ys - y0:ye - y0, xs - x0:xe - x0]
    layer = np.zeros_like(canvas)
    layer[ys:ye, xs:xe] = src
    return LP.over(canvas, layer)


# ---------- сцена Vapor ----------

class Vapor:
    def __init__(self, mouth: tuple):
        self.sub, self.ext, self.nodes = parse_scene()
        self.ex = script_exports()
        self.cfg = tres_floats(CONFIG)
        self.mouth = mouth
        steam_node = self.nodes["Steam"]
        life = float(_nums(steam_node["lifetime"])[0])
        self.steam = Emitter(steam_node, self.sub, self.ext, max(1, round(self.cfg["steam_per_sec"] * life)))
        smoke_node = self.nodes["Smoke"]
        life = float(_nums(smoke_node["lifetime"])[0])
        self.smoke = [Emitter(smoke_node, self.sub, self.ext, max(1, round(self.cfg["smoke_per_sec"] * life))),
                      Emitter(self.nodes["Ash"], self.sub, self.ext), Emitter(self.nodes["Leaves"], self.sub, self.ext)]
        self.pop_emitter = Emitter(self.nodes["PopBurst/Emitter1"], self.sub, self.ext)

    def sway(self, t: float) -> tuple:
        return (self.mouth[0] + math.sin(t * math.tau / self.ex["sway_sec"]) * self.ex["sway_px"], self.mouth[1])

    def steam_layer(self, canvas, props: list, t: float, seed: int = 1):
        """Пар свойств props (id) с момента 0 до t: клубы и иконки (как Vapor.set_steam + _process)."""
        cols = [prop_color(p) for p in props]
        whiten = self.ex["steam_whiten"]
        n = len(cols)
        self.steam.initial_ramp = dict(offsets=[i / n for i in range(n)], constant=True,
                                       colors=np.array([LP.mix(c, np.ones(4), whiten) for c in cols]))
        parts = self.steam.particles(t, 0.0, t, self.sway, seed)
        canvas = self.steam.draw(canvas, parts)
        # иконки: первая через icon_first_sec, дальше раз в steam_icon_sec, свойства по кругу
        ex, k, ts = self.ex, 0, self.ex["icon_first_sec"]
        while ts <= t:
            u = (t - ts) / ex["icon_rise_sec"]
            if u < 1.0:
                phase = math.tau * (k % 3) / 3
                rise = 1 - (1 - u) ** 2
                pos = (self.mouth[0] + math.sin(u * math.tau * ex["icon_sway_turns"] + phase) * ex["icon_sway_px"],
                       self.mouth[1] - ex["icon_rise_px"] * rise)
                alpha = min(min(u / ex["icon_fade_in"], 1.0), min((1 - u) / ex["icon_fade_out"], 1.0))
                tex = Image.open(ICONS / f"icon_prop_{props[k % n]}.png").convert("RGBA")
                scale = LP.mix(ex["icon_scale_from"], ex["icon_scale_to"], u)
                canvas = blit(canvas, tex, pos, scale, 0.0, (1, 1, 1, alpha))
            k += 1
            ts += self.cfg["steam_icon_sec"]
        return canvas

    def smoke_layer(self, canvas, t: float, seed: int = 2):
        for i, em in enumerate(self.smoke):
            canvas = em.draw(canvas, em.particles(t, 0.0, t, lambda _t: self.mouth, seed + i))
        return canvas

    def pop_layer(self, canvas, prop: str, since: float, seed: int = 3):
        """«Пок» через since секунд после pop(): иконка выскакивает (TRANS_BACK), потом облачко."""
        ex = self.ex
        tex = Image.open(ICONS / f"icon_prop_{prop}.png").convert("RGBA")
        if since < ex["pop_sec"]:
            u = since / ex["pop_sec"]
            c1, c3 = 1.70158, 2.70158
            back = 1 + c3 * (u - 1) ** 3 + c1 * (u - 1) ** 2          # Tween.TRANS_BACK, EASE_OUT
            pos = (self.mouth[0], self.mouth[1] - ex["pop_rise_px"] * back)
            scale = LP.mix(ex["icon_scale_to"], ex["pop_scale"], back)
            return blit(canvas, tex, pos, scale, 0.0, (1, 1, 1, 1))
        color = LP.mix(prop_color(prop), np.ones(4), ex["steam_whiten"])
        em = self.pop_emitter
        em.color = np.array(color)
        center = (self.mouth[0], self.mouth[1] - ex["pop_rise_px"])
        return em.draw(canvas, em.particles(since - ex["pop_sec"], 0.0, 1.0, lambda _t: center, seed))


def shop_bg(w: int, h: int) -> np.ndarray:
    y = np.linspace(0, 1, h)[:, None, None]
    img = np.ones((h, w, 3)) * LP.mix(SHOP_TOP, SHOP_BOTTOM, y)
    return np.dstack([img, np.ones((h, w))])


def frame(kind: str, t: float, mixture: dict, strength: float, boil: float, props=(), pop=None) -> Image.Image:
    lay = FP.layout(HEADROOM)
    mouth_px = tres_vec(CONFIG, "mouth_px")
    mouth = (lay["f0"][0] + mouth_px[0] * FP.FLASK_SCALE, lay["f0"][1] + mouth_px[1] * FP.FLASK_SCALE)
    base = FP.station(strength, t, mixture, boil, HEADROOM, shop_bg(lay["w"], lay["h"]))
    canvas = np.asarray(base.convert("RGBA")).astype(float) / 255.0
    vapor = Vapor(mouth)
    if kind == "smoke":
        canvas = vapor.smoke_layer(canvas, t)
    if props:
        canvas = vapor.steam_layer(canvas, list(props), t)
    if pop:
        canvas = vapor.pop_layer(canvas, pop[0], pop[1])
    return Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8), "RGBA").convert("RGB")


def tres_vec(path: Path, key: str) -> tuple:
    return tuple(_nums(re.search(rf"^{key} = Vector2\(([^)]+)\)", path.read_text("utf-8"), re.M).group(1)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--time", type=float, default=3.0)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    t = args.time
    frames = [
        frame("steam", t, {"cold": 1.2, "life": 1.2, "acid": 1.0}, 0.8, 0.7, props=("cold",)),
        frame("steam", t + 0.7, {"cold": 0.8, "sleep": 1.0, "acid": 1.0}, 1.0, 1.0, props=("cold", "sleep", "acid")),
        frame("steam", t, {"sleep": 1.0, "acid": 1.0}, 0.8, 0.7, props=("sleep",), pop=("cold", 0.2)),
        frame("steam", t, {"sleep": 1.0, "acid": 1.0}, 0.8, 0.7, props=("sleep",), pop=("cold", 0.5)),
        frame("smoke", t, {"life": 1.6, "light": 1.0}, 1.0, 1.0),
    ]
    refs = [Image.open(REFS / f"ref_burner_{n}.jpg").convert("RGB") for n in ("heating", "overheat_smoke")]
    h = frames[0].height
    refs = [r.resize((round(r.width * h / r.height), h)) for r in refs]
    sheet = Image.new("RGB", (sum(f.width for f in frames + refs), h), (60, 40, 28))
    x = 0
    for im in frames + refs:
        sheet.paste(im, (x, 0))
        x += im.width
    path = args.out / "vapor_preview.png"
    sheet.save(path)
    crops = [f.crop((40, 0, 360, 420)) for f in (frames[1], frames[2], frames[4])]
    close = Image.new("RGB", (sum(c.width for c in crops), crops[0].height))
    for i, c in enumerate(crops):
        close.paste(c, (i * c.width, 0))
    close.save(args.out / "vapor_closeup.png")
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
