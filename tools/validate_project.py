#!/usr/bin/env python3
"""validate_project.py — статический валидатор проекта «Лавка алхимика» (Godot 4.7) без запуска Godot.

Зачем: у Computer нет Godot и сети, поэтому ошибки в сценах, ресурсах, скриптах, локализации
и контракте ассетов ловим до того, как пользователь откроет проект. Только стандартная
библиотека Python 3.10+ (работает и у пользователя без установки пакетов).

Запуск (из корня репозитория):
  python tools/validate_project.py                 # отчёт; код возврата 1, если есть ошибки
  python tools/validate_project.py --strict        # предупреждения тоже валят проверку
  python tools/validate_project.py --json          # машиночитаемый отчёт
  python tools/validate_project.py --self-test     # прогон на фикстурах tools/validator_tests/
  python tools/validate_project.py --rules         # список кодов проверок
  python tools/validate_project.py --mark-humanized KEY [KEY ...]
        # после humanizer: записать хеши текстов ключей в localization/humanized.txt

Подавить предупреждение «магическое число» в строке GDScript: комментарий `# noqa: magic`.
Коды: P — project.godot/export, T — .tscn/.tres, G — GDScript, S — шейдеры, L — локализация,
A — ассеты, N — имена файлов, F — сторонние материалы, X — служебные файлы Godot.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

# --------------------------------------------------------------------------------------------
# Контракт проекта (меняется только вместе с docs/PLAN.md / AGENTS.md)
# --------------------------------------------------------------------------------------------
EXPECTED_SETTINGS: dict[tuple[str, str], str] = {
    ("rendering", "renderer/rendering_method"): '"gl_compatibility"',
    ("rendering", "renderer/rendering_method.mobile"): '"gl_compatibility"',
    ("display", "window/size/viewport_width"): "1920",
    ("display", "window/size/viewport_height"): "1080",
    ("display", "window/stretch/mode"): '"canvas_items"',
    ("display", "window/stretch/aspect"): '"expand"',
}
ENGINE_VERSION = "4.7"
REQUIRED_LOCALES = ("ru", "en")
STRINGS_CSV = "localization/strings.csv"
HUMANIZED_TXT = "localization/humanized.txt"
REGISTRY_MD = "docs/art/ASSET_REGISTRY.md"
PROMPTS_MD = "docs/art/PROMPTS.md"
THIRD_PARTY_MD = "docs/THIRD_PARTY.md"
ASSETS_DIR = "assets"
LINT_SKIP_PREFIXES = ("addons/",)  # сторонний код: только разбор, без стиля
SKIP_DIRS = {".git", ".godot", ".import", "export", "build", "__pycache__", "node_modules"}
ROOT_NAME_WHITELIST = {
    "README.md", "AGENTS.md", "LICENSE", "LICENSE.md", "CHANGELOG.md", "project.godot",
    "export_presets.cfg", "icon.svg", ".gitignore", ".gitattributes", ".editorconfig",
}
SNAKE_RE = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)*$")
KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
ALLOWED_NUMBERS = {"0", "1", "2", "0.0", "1.0", "2.0", "0.5", ".5"}
MAX_MAGIC_PER_FILE = 12

MODERATION_WORDS = [  # Яндекс 3.4.2 / 3.4.3 / 3.4.5 — повод перечитать текст, не запрет
    r"череп", r"скелет", r"пентаграм", r"демон", r"сатан", r"дьявол", r"бес\b", r"кров[ьи]",
    r"убий", r"убить", r"смерт", r"\bяд\b", r"\bяда\b", r"\bядом\b", r"отрав", r"проклят",
    r"некромант", r"колдовств", r"чёрн\w* маг", r"черн\w* маг", r"мучени", r"пытк",
    r"skull", r"skeleton", r"pentagram", r"demon", r"satan", r"devil", r"blood", r"\bkill",
    r"death", r"poison", r"curse", r"necromanc", r"black magic", r"torture",
]

NODE_CLASSES = set("""
Node Node2D Node3D CanvasItem CanvasLayer CanvasModulate Control Container BoxContainer VBoxContainer
HBoxContainer GridContainer CenterContainer MarginContainer PanelContainer ScrollContainer
AspectRatioContainer FlowContainer HFlowContainer VFlowContainer SplitContainer HSplitContainer
VSplitContainer TabContainer SubViewportContainer Label RichTextLabel Button TextureButton
CheckBox CheckButton LinkButton MenuButton OptionButton ColorPickerButton TextureRect ColorRect
NinePatchRect ReferenceRect Panel ProgressBar TextureProgressBar HSlider VSlider SpinBox LineEdit
TextEdit CodeEdit ItemList Tree TabBar HSeparator VSeparator ScrollBar HScrollBar VScrollBar
VideoStreamPlayer GraphEdit GraphNode ColorPicker Window Popup PopupMenu PopupPanel AcceptDialog
ConfirmationDialog FileDialog SubViewport Sprite2D AnimatedSprite2D Area2D CollisionShape2D
CollisionPolygon2D CharacterBody2D RigidBody2D StaticBody2D AnimatableBody2D Camera2D Timer
AudioStreamPlayer AudioStreamPlayer2D AudioListener2D GPUParticles2D CPUParticles2D Line2D
Polygon2D Path2D PathFollow2D AnimationPlayer AnimationTree AnimationMixer Marker2D
RemoteTransform2D VisibleOnScreenNotifier2D VisibleOnScreenEnabler2D PointLight2D
DirectionalLight2D LightOccluder2D BackBufferCopy ParallaxBackground ParallaxLayer Parallax2D
TileMap TileMapLayer Skeleton2D Bone2D MeshInstance2D MultiMeshInstance2D TouchScreenButton
RayCast2D ShapeCast2D NavigationAgent2D NavigationRegion2D NavigationObstacle2D HTTPRequest
ResourcePreloader WorldEnvironment ShaderGlobalsOverride MultiplayerSpawner
MultiplayerSynchronizer StatusIndicator MissingNode InstancePlaceholder Viewport
""".split())
_PARENTS = """
CanvasItem:Node Node2D:CanvasItem Control:CanvasItem CanvasLayer:Node Timer:Node AudioStreamPlayer:Node
AnimationMixer:Node AnimationPlayer:AnimationMixer AnimationTree:AnimationMixer HTTPRequest:Node
ResourcePreloader:Node WorldEnvironment:Node Viewport:Node SubViewport:Viewport Window:Viewport
MultiplayerSpawner:Node MultiplayerSynchronizer:Node ShaderGlobalsOverride:Node StatusIndicator:Node
NavigationAgent2D:Node InstancePlaceholder:Node MissingNode:Node ParallaxBackground:CanvasLayer
Sprite2D:Node2D AnimatedSprite2D:Node2D CollisionObject2D:Node2D Area2D:CollisionObject2D
PhysicsBody2D:CollisionObject2D StaticBody2D:PhysicsBody2D AnimatableBody2D:StaticBody2D
CharacterBody2D:PhysicsBody2D RigidBody2D:PhysicsBody2D CollisionShape2D:Node2D CollisionPolygon2D:Node2D
Camera2D:Node2D AudioStreamPlayer2D:Node2D AudioListener2D:Node2D GPUParticles2D:Node2D
CPUParticles2D:Node2D Line2D:Node2D Polygon2D:Node2D Path2D:Node2D PathFollow2D:Node2D Marker2D:Node2D
RemoteTransform2D:Node2D VisibleOnScreenNotifier2D:Node2D VisibleOnScreenEnabler2D:VisibleOnScreenNotifier2D
Light2D:Node2D PointLight2D:Light2D DirectionalLight2D:Light2D LightOccluder2D:Node2D BackBufferCopy:Node2D
CanvasModulate:Node2D Parallax2D:Node2D ParallaxLayer:Node2D TileMap:Node2D TileMapLayer:Node2D
Skeleton2D:Node2D Bone2D:Node2D MeshInstance2D:Node2D MultiMeshInstance2D:Node2D TouchScreenButton:Node2D
RayCast2D:Node2D ShapeCast2D:Node2D NavigationRegion2D:Node2D NavigationObstacle2D:Node2D
Container:Control BoxContainer:Container VBoxContainer:BoxContainer HBoxContainer:BoxContainer
GridContainer:Container CenterContainer:Container MarginContainer:Container PanelContainer:Container
ScrollContainer:Container AspectRatioContainer:Container FlowContainer:Container HFlowContainer:FlowContainer
VFlowContainer:FlowContainer SplitContainer:Container HSplitContainer:SplitContainer
VSplitContainer:SplitContainer TabContainer:Container SubViewportContainer:Container GraphNode:Container
ColorPicker:VBoxContainer Label:Control RichTextLabel:Control BaseButton:Control Button:BaseButton
CheckBox:Button CheckButton:Button MenuButton:Button OptionButton:Button ColorPickerButton:Button
LinkButton:BaseButton TextureButton:BaseButton TextureRect:Control ColorRect:Control NinePatchRect:Control
ReferenceRect:Control Panel:Control Range:Control ProgressBar:Range TextureProgressBar:Range Slider:Range
HSlider:Slider VSlider:Slider SpinBox:Range ScrollBar:Range HScrollBar:ScrollBar VScrollBar:ScrollBar
LineEdit:Control TextEdit:Control CodeEdit:TextEdit ItemList:Control Tree:Control TabBar:Control
Separator:Control HSeparator:Separator VSeparator:Separator VideoStreamPlayer:Control GraphEdit:Control
Popup:Window PopupMenu:Popup PopupPanel:Popup AcceptDialog:Window ConfirmationDialog:AcceptDialog
FileDialog:ConfirmationDialog
"""
CLASS_PARENT: dict[str, str] = dict(pair.split(":") for pair in _PARENTS.split())
NODE_CLASSES |= set(CLASS_PARENT) | {"Node"}


def is_subclass(child: str, base: str) -> bool | None:
    """True/False, если оба класса известны; None — если судить нельзя."""
    if base == child or base == "Node" and child in NODE_CLASSES or base == "Object":
        return True
    if child not in CLASS_PARENT and child != "Node":
        return None
    cur: str | None = child
    while cur is not None:
        if cur == base:
            return True
        cur = CLASS_PARENT.get(cur)
    return False if (base in CLASS_PARENT or base in ("Node", "RefCounted", "Resource")) else None


TEXTURE_TYPES = {"Texture2D", "CompressedTexture2D", "Texture", "ImageTexture",
                 "PortableCompressedTexture2D", "AtlasTexture"}
EXT_EXPECTED_TYPES: dict[str, set[str]] = {
    ".gd": {"Script", "GDScript"},
    ".tscn": {"PackedScene"}, ".scn": {"PackedScene"},
    ".png": TEXTURE_TYPES, ".jpg": TEXTURE_TYPES, ".jpeg": TEXTURE_TYPES, ".webp": TEXTURE_TYPES,
    ".svg": TEXTURE_TYPES,
    ".gdshader": {"Shader"}, ".gdshaderinc": {"ShaderInclude"},
    ".ogg": {"AudioStream", "AudioStreamOggVorbis"}, ".wav": {"AudioStream", "AudioStreamWAV"},
    ".mp3": {"AudioStream", "AudioStreamMP3"},
    ".ttf": {"FontFile", "Font"}, ".otf": {"FontFile", "Font"}, ".woff": {"FontFile", "Font"},
    ".woff2": {"FontFile", "Font"},
}
BUILTIN_SIGNALS = set("""
pressed button_down button_up toggled timeout ready tree_entered tree_exiting tree_exited renamed
child_entered_tree child_exiting_tree child_order_changed visibility_changed draw hidden
item_rect_changed resized gui_input mouse_entered mouse_exited focus_entered focus_exited
size_flags_changed minimum_size_changed theme_changed input_event area_entered area_exited
area_shape_entered area_shape_exited body_entered body_exited body_shape_entered body_shape_exited
finished animation_finished animation_started animation_changed animation_looped frame_changed
sprite_frames_changed value_changed changed text_changed text_submitted item_selected
item_activated id_pressed index_pressed screen_entered screen_exited request_completed
tab_changed tab_selected popup_hide about_to_popup confirmed canceled close_requested
scroll_started scroll_ended drag_started drag_ended meta_clicked loop_finished step_finished
texture_changed script_changed property_list_changed editor_description_changed
""".split())
BUILTIN_METHODS = set("""
queue_free hide show set_visible play stop start set_process set_physics_process emit_signal
call_deferred grab_focus release_focus restart set_disabled pause popup popup_centered
accept_event queue_redraw reset_size set_deferred
""".split())
GODOT3_PATTERNS = [
    (r"^\s*(export|onready)\s+var\b", "Godot 3: используйте @export / @onready"),
    (r"\byield\s*\(", "Godot 3: yield → await"),
    (r"\bsetget\b", "Godot 3: setget → синтаксис set/get у var"),
    (r"^tool\s*$", "Godot 3: tool → @tool"),
    (r"\.instance\(\s*\)", "Godot 3: instance() → instantiate()"),
    (r"\.connect\(\s*\"[^\"]*\"\s*,\s*self\b", "Godot 3: connect(\"sig\", self, \"m\") → sig.connect(m)"),
    (r"\b(PoolStringArray|PoolIntArray|PoolRealArray|PoolVector2Array|PoolColorArray|PoolByteArray"
     r"|KinematicBody2D|Position2D|YSort|Particles2D|Light2D|VisibilityNotifier2D|TextureProgress"
     r"|Navigation2D|ToolButton)\b", "Godot 3: класс переименован/удалён в Godot 4"),
    (r"\b(deg2rad|rad2deg|stepify|rand_range|str2var|var2str|parse_json|to_json|funcref)\b",
     "Godot 3: функция переименована в Godot 4"),
    (r"\bOS\.get_ticks_msec\b", "Godot 3: OS.get_ticks_msec → Time.get_ticks_msec"),
    (r"\.change_scene\(", "Godot 3: change_scene → change_scene_to_file / change_scene_to_packed"),
    (r"\.empty\(\s*\)", "Godot 3: empty() → is_empty()"),
]

RULES: dict[str, str] = {
    "P001": "project.godot отсутствует или не разбирается",
    "P002": "настройка проекта не соответствует контракту (Compatibility, 1920×1080, canvas_items/expand)",
    "P003": "главная сцена не задана или не найдена",
    "P004": "файл автозагрузки не найден",
    "P005": "перевод в настройках не найден / CSV-перевод не подключён",
    "P006": "раскладка аудиошин не найдена",
    "P007": "Web-экспорт: потоки должны быть выключены (variant/thread_support=false)",
    "P008": "в config/features нет версии движка " + ENGINE_VERSION,
    "T001": "ошибка разбора .tscn/.tres",
    "T002": "неверный заголовок файла (gd_scene/gd_resource, format=3|4)",
    "T003": "повторяющийся id ресурса",
    "T004": "ext_resource: файл не найден",
    "T005": "ссылка на неопределённый ExtResource/SubResource",
    "T006": "родитель узла не найден",
    "T007": "повторяющееся имя среди соседних узлов",
    "T008": "узел без type/instance вне инстанцированной сцены",
    "T009": "instance= ссылается не на PackedScene",
    "T010": "NodePath не разрешается",
    "T011": "connection: узел from/to не найден",
    "T012": "connection: метод не найден в скрипте получателя",
    "T013": "uid:// не найден (возможно, выдуман) — Godot откатится на path",
    "T014": "тип ext_resource не соответствует расширению файла",
    "T015": "свойство из node_paths не объявлено как @export в скрипте узла",
    "T016": "connection: сигнал не найден ни в скрипте, ни в списке встроенных",
    "T017": "SubResource используется раньше, чем определён",
    "T018": "NodePath указывает за пределы сцены",
    "T019": "type= с class_name проекта (нужно: базовый тип + script)",
    "T020": "неизвестный тип узла (проверьте написание)",
    "T021": "script_class ресурса не найден среди class_name проекта",
    "T022": "скрипт нельзя повесить на узел этого типа (extends не предок типа узла)",
    "G001": "переменная без типа (нужно `: Тип` или `:=`)",
    "G002": "параметр функции без типа",
    "G003": "функция без типа возврата (`-> void` и т. п.)",
    "G004": "наследование от класса/скрипта проекта (только композиция)",
    "G005": "создание узла кодом (X.new()/Tween.new()) — только сцены и instantiate()",
    "G006": "add_child() не для instantiate()/duplicate() — проверьте правило «никаких объектов кодом»",
    "G007": "нет шапки `##` (назначение, сигналы, зависимости)",
    "G008": "$Path / get_node() — ссылки на узлы через @export",
    "G009": "магическое число — вынести в ресурс/константу",
    "G010": "res:// путь из строки не найден",
    "G011": "синтаксис/API Godot 3",
    "G012": "после `:` ожидается блок с отступом",
    "G013": "несбалансированные скобки",
    "G014": "смешаны табы и пробелы в отступах",
    "G015": "ключ локализации из tr() не найден в strings.csv",
    "G016": "лишний отступ: перенос выражения без скобок или `\\` (Godot: Expected statement, found \"Indent\")",
    "S001": "нет shader_type",
    "S002": "синтаксис шейдеров Godot 3 (hint_color, SCREEN_TEXTURE …)",
    "S003": "несбалансированные скобки в шейдере",
    "S004": "заимствованный шейдер не записан в docs/THIRD_PARTY.md",
    "L001": "strings.csv отсутствует или неверный формат (keys,ru,en)",
    "L002": "повторяющийся ключ локализации",
    "L003": "пустой перевод",
    "L004": "ключ не прошёл humanizer (нет в humanized.txt)",
    "L005": "текст изменён после humanizer (хеш не совпадает)",
    "L006": "humanized.txt: ключа больше нет в strings.csv",
    "L007": "ключ локализации из сцены не найден в strings.csv",
    "L008": "текст, видимый игроку, задан не ключом локализации",
    "L009": "слово, на которое может среагировать модерация Яндекса",
    "L010": "ключ локализации не в формате UPPER_SNAKE_CASE",
    "L011": "ключ локализации из данных (свойство *_key в .tres/.tscn) не найден в strings.csv",
    "A001": "реестр ассетов не найден",
    "A002": "ассет со статусом temp/final отсутствует",
    "A003": "размер холста ассета не совпадает с реестром",
    "A004": "у ассета нет промпта или промпт не найден в PROMPTS.md",
    "A005": "изображение в assets/ не записано в реестр",
    "A006": "ассет не в формате PNG",
    "A007": "статус planned, а файл уже лежит в проекте (поставьте temp)",
    "A008": "повтор ID или пути в реестре",
    "N001": "имя файла/папки не в snake_case (web-экспорт чувствителен к регистру)",
    "F001": "шрифт не записан в docs/THIRD_PARTY.md",
    "X001": ".import/.uid без исходного файла",
}


# --------------------------------------------------------------------------------------------
# Отчёт
# --------------------------------------------------------------------------------------------
@dataclass
class Issue:
    level: str  # ERROR | WARN
    code: str
    path: str
    line: int
    msg: str


class Report:
    def __init__(self) -> None:
        self.issues: list[Issue] = []
        self._seen: set[tuple[str, str, str, int, str]] = set()

    def add(self, level: str, code: str, path: str, line: int, msg: str) -> None:
        key = (level, code, path, line, msg)
        if key in self._seen:
            return
        self._seen.add(key)
        self.issues.append(Issue(level, code, path, line, msg))

    def err(self, code: str, path: str, line: int, msg: str) -> None:
        self.add("ERROR", code, path, line, msg)

    def warn(self, code: str, path: str, line: int, msg: str) -> None:
        self.add("WARN", code, path, line, msg)

    @property
    def errors(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "ERROR"]

    @property
    def warnings(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "WARN"]


# --------------------------------------------------------------------------------------------
# Разбор текстового формата Godot (.tscn / .tres / project.godot / .import / export_presets.cfg)
# --------------------------------------------------------------------------------------------
@dataclass
class Section:
    tag: str
    attrs: dict[str, str]
    line: int
    props: list[tuple[str, str, int]] = field(default_factory=list)

    def prop(self, key: str) -> str | None:
        for k, v, _ in self.props:
            if k == key:
                return v
        return None


class ParseError(Exception):
    def __init__(self, line: int, msg: str) -> None:
        super().__init__(msg)
        self.line = line


def _skip_string(text: str, i: int) -> int:
    """i указывает на открывающую кавычку; вернуть индекс после закрывающей."""
    n = len(text)
    j = i + 1
    while j < n:
        c = text[j]
        if c == "\\":
            j += 2
            continue
        if c == '"':
            return j + 1
        j += 1
    raise ParseError(text.count("\n", 0, i) + 1, "незакрытая строка")


def _scan(text: str, i: int, stop_chars: str) -> int:
    """Сканировать значение до stop_chars на нулевой глубине скобок (строки учитываются)."""
    n = len(text)
    depth = 0
    while i < n:
        c = text[i]
        if c == '"':
            i = _skip_string(text, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0 and c in stop_chars:
                return i
            depth -= 1
            if depth < 0:
                raise ParseError(text.count("\n", 0, i) + 1, f"лишняя закрывающая скобка «{c}»")
        elif depth == 0 and c in stop_chars:
            return i
        i += 1
    if depth != 0:
        raise ParseError(text.count("\n", 0, i) + 1, "незакрытая скобка")
    return i


def parse_godot_text(text: str) -> list[Section]:
    sections: list[Section] = [Section("", {}, 1)]
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
            continue
        line = text.count("\n", 0, i) + 1
        if c == ";":
            j = text.find("\n", i)
            i = n if j == -1 else j
            continue
        if c == "[":
            end = _scan(text, i + 1, "]")
            if end >= n:
                raise ParseError(line, "незакрытый заголовок секции")
            sections.append(_parse_header(text[i + 1:end], line))
            i = end + 1
            continue
        eq = text.find("=", i)
        nl = text.find("\n", i)
        if eq == -1 or (nl != -1 and nl < eq):
            raise ParseError(line, "ожидалось «ключ = значение»")
        key = text[i:eq].strip()
        if key.startswith('"') and key.endswith('"'):
            key = key[1:-1]
        j = eq + 1
        while j < n and text[j] in " \t":
            j += 1
        end = _scan(text, j, "\n")
        sections[-1].props.append((key, text[j:end].strip(), line))
        i = end
    return sections


def _parse_header(body: str, line: int) -> Section:
    body = body.strip()
    m = re.match(r"([A-Za-z_][\w.]*)", body)
    if not m:
        raise ParseError(line, f"пустой или неверный заголовок секции: [{body[:40]}]")
    tag = m.group(1)
    attrs: dict[str, str] = {}
    i, n = m.end(), len(body)
    while i < n:
        while i < n and body[i] in " \t\r\n":
            i += 1
        if i >= n:
            break
        eq = body.find("=", i)
        if eq == -1:
            raise ParseError(line, f"неверный атрибут в заголовке [{tag} …]")
        key = body[i:eq].strip()
        end = _scan(body, eq + 1, " \t\r\n")
        attrs[key] = body[eq + 1:end].strip()
        i = end
    return Section(tag, attrs, line)


def unquote(raw: str | None) -> str | None:
    if raw is None:
        return None
    raw = raw.strip()
    if raw[:1] in "&^" and raw[1:2] == '"':
        raw = raw[1:]
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        s = raw[1:-1]
        return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)
    return None


REF_RE = re.compile(r"\b(ExtResource|SubResource)\(\s*\"([^\"]*)\"\s*\)")
REF_OLD_RE = re.compile(r"\b(ExtResource|SubResource)\(\s*\d+\s*\)")
NODEPATH_RE = re.compile(r"NodePath\(\s*\"((?:[^\"\\]|\\.)*)\"\s*\)")
PSA_ITEM_RE = re.compile(r"\"((?:[^\"\\]|\\.)*)\"")


def png_size(path: Path) -> tuple[int, int] | None:
    try:
        with path.open("rb") as f:
            head = f.read(24)
    except OSError:
        return None
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    w, h = struct.unpack(">II", head[16:24])
    return int(w), int(h)


# --------------------------------------------------------------------------------------------
# GDScript: маскирование строк/комментариев, логические строки, сведения о скрипте
# --------------------------------------------------------------------------------------------
@dataclass
class GdString:
    start: int
    end: int
    value: str
    line: int


@dataclass
class LogicalLine:
    line: int
    indent: str
    code: str  # маскированный код (строки → пробелы, комментарии убраны), склеенный в одну строку
    raw: str
    start: int  # смещение начала в тексте


@dataclass
class ScriptInfo:
    path: str
    extends: str | None = None
    extends_line: int = 0
    class_name: str | None = None
    funcs: set[str] = field(default_factory=set)
    signals: set[str] = field(default_factory=set)
    exports: set[str] = field(default_factory=set)
    masked: str = ""
    strings: list[GdString] = field(default_factory=list)
    lines: list[LogicalLine] = field(default_factory=list)
    unbalanced: tuple[int, str] | None = None


def mask_gd(text: str) -> tuple[str, list[GdString]]:
    out = list(text)
    strings: list[GdString] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "#":
            j = text.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if c in "\"'":
            q = text[i:i + 3] if text[i:i + 3] in ('"""', "'''") else c
            raw_prefix = i > 0 and text[i - 1] == "r" and (i < 2 or not (text[i - 2].isalnum() or text[i - 2] == "_"))
            j = i + len(q)
            while j < n:
                if text[j] == "\\" and not raw_prefix:
                    j += 2
                    continue
                if text.startswith(q, j):
                    break
                if len(q) == 1 and text[j] == "\n":
                    break
                j += 1
            end = min(n, j + len(q))
            strings.append(GdString(i, end, text[i + len(q):j], text.count("\n", 0, i) + 1))
            for k in range(i + len(q), min(j, n)):
                if out[k] != "\n":
                    out[k] = " "
            i = end
            continue
        i += 1
    return "".join(out), strings


def analyze_gd(rel: str, text: str) -> ScriptInfo:
    info = ScriptInfo(rel)
    masked, strings = mask_gd(text)
    info.masked, info.strings = masked, strings
    m_lines = masked.split("\n")
    r_lines = text.split("\n")
    depth = 0
    cur: LogicalLine | None = None
    offset = 0
    for idx, (ml, rl) in enumerate(zip(m_lines, r_lines)):
        if cur is None:
            indent = re.match(r"[ \t]*", rl).group(0)
            cur = LogicalLine(idx + 1, indent, "", "", offset)
        cur.code += " " + ml.strip() if cur.code else ml.strip()
        cur.raw += ("\n" if cur.raw else "") + rl
        for ch in ml:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
                if depth < 0 and info.unbalanced is None:
                    info.unbalanced = (idx + 1, f"лишняя «{ch}»")
                    depth = 0
        offset += len(rl) + 1
        if depth > 0 or ml.rstrip().endswith("\\"):
            continue
        info.lines.append(cur)
        cur = None
    if cur is not None:
        info.lines.append(cur)
    if depth > 0 and info.unbalanced is None:
        info.unbalanced = (len(r_lines), "незакрытая скобка в конце файла")

    pending: list[str] = []
    for ll in info.lines:
        code = ll.code.strip()
        if not code:
            continue
        m = re.match(r"^(?:class_name\s+(\w+)\s*)?(?:extends\s+(.+?))?\s*$", code)
        if ll.indent == "" and m and (m.group(1) or m.group(2)) and re.match(r"^(class_name|extends)\b", code):
            if m.group(1):
                info.class_name = m.group(1)
            if m.group(2):
                ext = m.group(2).strip()
                # строковый путь маскирован — восстановим из исходника
                rm = re.search(r"extends\s+(\S.*)$", ll.raw.split("\n")[0])
                info.extends = rm.group(1).strip() if rm else ext
                info.extends_line = ll.line
            continue
        body, annotations = strip_annotations(code)
        if not body:
            pending += annotations
            continue
        annotations, pending = pending + annotations, []
        fm = re.match(r"^(?:static\s+)?func\s+(\w+)", body)
        if fm and ll.indent == "":
            info.funcs.add(fm.group(1))
        sm = re.match(r"^signal\s+(\w+)", body)
        if sm:
            info.signals.add(sm.group(1))
        vm = re.match(r"^(?:static\s+)?var\s+(\w+)", body)
        if vm and ll.indent == "" and any(a.startswith("@export") for a in annotations):
            info.exports.add(vm.group(1))
    return info


def strip_annotations(code: str) -> tuple[str, list[str]]:
    anns: list[str] = []
    body = code
    while True:
        m = re.match(r"^(@\w+)(\s*\([^)]*\))?\s*", body)
        if not m:
            break
        anns.append(m.group(1))
        body = body[m.end():]
    return body, anns


def indent_width(indent: str) -> int:
    return len(indent.expandtabs(4))


def split_top_level(s: str, sep: str = ",") -> list[str]:
    parts, depth, cur = [], 0, []
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts


def match_paren(s: str, i: int) -> int:
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "(":
            depth += 1
        elif s[j] == ")":
            depth -= 1
            if depth == 0:
                return j
    return -1


def gd_string_at(info: ScriptInfo, pos: int) -> GdString | None:
    for s in info.strings:
        if s.start == pos or (s.start == pos + 1 and info.masked[pos] in "&^"):
            return s
        if s.start > pos + 1:
            return None
    return None


# --------------------------------------------------------------------------------------------
# Шейдеры
# --------------------------------------------------------------------------------------------
def mask_shader(text: str) -> str:
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


# --------------------------------------------------------------------------------------------
# Модель проекта
# --------------------------------------------------------------------------------------------
@dataclass
class NodeInfo:
    path: str
    name: str
    type: str | None
    script: str | None  # res-относительный путь .gd
    instance: str | None  # res-относительный путь .tscn
    unique: bool = False
    from_instance: bool = False


@dataclass
class SceneInfo:
    rel: str
    nodes: dict[str, NodeInfo] = field(default_factory=dict)
    ok: bool = True


class Project:
    def __init__(self, root: Path, report: Report) -> None:
        self.root = root.resolve()
        self.r = report
        self.files: list[str] = []
        self.dirs: list[str] = []
        self._discover()
        self.fileset = set(self.files)
        self.uid_map: dict[str, str] = {}
        self._build_uid_map()
        self.scripts: dict[str, ScriptInfo] = {}
        for rel in self.files:
            if rel.endswith(".gd"):
                self.scripts[rel] = analyze_gd(rel, self.read(rel))
        self.class_names: dict[str, str] = {
            s.class_name: rel for rel, s in self.scripts.items() if s.class_name
        }
        self.scene_cache: dict[str, SceneInfo] = {}
        self.csv_keys: dict[str, dict[str, str]] | None = None
        self.third_party_text = self.read_opt(THIRD_PARTY_MD) or ""

    # ---- файлы
    def _discover(self) -> None:
        def walk(d: Path, rel: str) -> None:
            if rel and (d / ".gdignore").exists():
                return
            for p in sorted(d.iterdir(), key=lambda x: x.name):
                prel = f"{rel}/{p.name}" if rel else p.name
                if p.is_dir():
                    if p.name in SKIP_DIRS:
                        continue
                    self.dirs.append(prel)
                    walk(p, prel)
                else:
                    self.files.append(prel)
        walk(self.root, "")

    def read(self, rel: str) -> str:
        return (self.root / rel).read_text(encoding="utf-8-sig", errors="replace")

    def read_opt(self, rel: str) -> str | None:
        p = self.root / rel
        return p.read_text(encoding="utf-8-sig", errors="replace") if p.is_file() else None

    def res_to_rel(self, res: str) -> str | None:
        if res.startswith("res://"):
            return res[len("res://"):].split("::")[0]
        return None

    def exists(self, rel: str) -> bool:
        return (self.root / rel).exists()

    def _build_uid_map(self) -> None:
        for rel in self.files:
            try:
                if rel.endswith(".uid"):
                    uid = self.read(rel).strip()
                    if uid.startswith("uid://"):
                        self.uid_map[uid] = rel[:-4]
                elif rel.endswith(".import"):
                    m = re.search(r'^uid="(uid://[^"]+)"', self.read(rel), re.M)
                    if m:
                        self.uid_map[m.group(1)] = rel[:-7]
                elif rel.endswith((".tscn", ".tres")):
                    head = self.read(rel)[:400]
                    m = re.match(r'\s*\[gd_(?:scene|resource)[^\]]*uid="(uid://[^"]+)"', head)
                    if m:
                        self.uid_map[m.group(1)] = rel
            except OSError:
                continue

    def resolve_ref(self, path_raw: str | None, uid_raw: str | None, where: str, line: int,
                    code_missing: str) -> str | None:
        """Вернуть rel путь ресурса (или None) с учётом uid и path."""
        path = unquote(path_raw) if path_raw else None
        uid = unquote(uid_raw) if uid_raw else None
        rel = self.res_to_rel(path) if path else None
        if uid:
            if uid in self.uid_map:
                target = self.uid_map[uid]
                if rel and rel != target and not self.exists(rel):
                    return target
                return rel or target
            if rel and self.exists(rel):
                self.r.warn("T013", where, line, f"{uid} не найден в .uid/.import/заголовках — "
                            f"Godot возьмёт path {path}")
                return rel
        if rel is None:
            if path and path.startswith("uid://"):
                if path in self.uid_map:
                    return self.uid_map[path]
                self.r.err(code_missing, where, line, f"не найден ресурс {path}")
                return None
            self.r.err(code_missing, where, line, f"нет пути res:// (path={path_raw})")
            return None
        if not self.exists(rel):
            self.r.err(code_missing, where, line, f"файл не найден: res://{rel}")
            return None
        return rel

    def is_lint_target(self, rel: str) -> bool:
        return not rel.startswith(LINT_SKIP_PREFIXES)

    # ---- локализация
    def load_csv(self) -> dict[str, dict[str, str]] | None:
        if self.csv_keys is not None:
            return self.csv_keys
        text = self.read_opt(STRINGS_CSV)
        if text is None:
            return None
        rows = list(csv.reader(io.StringIO(text)))
        keys: dict[str, dict[str, str]] = {}
        if not rows:
            self.r.err("L001", STRINGS_CSV, 1, "пустой файл")
            self.csv_keys = keys
            return keys
        header = [h.strip() for h in rows[0]]
        if header[0] != "keys":
            self.r.err("L001", STRINGS_CSV, 1, "первая колонка должна называться keys")
        for loc in REQUIRED_LOCALES:
            if loc not in header:
                self.r.err("L001", STRINGS_CSV, 1, f"нет колонки {loc}")
        for ln, row in enumerate(rows[1:], start=2):
            if not row or not row[0].strip():
                continue
            key = row[0].strip()
            if len(row) != len(header):
                self.r.err("L001", STRINGS_CSV, ln, f"{key}: {len(row)} колонок вместо {len(header)}")
            if key in keys:
                self.r.err("L002", STRINGS_CSV, ln, f"повтор ключа {key}")
            if not KEY_RE.match(key):
                self.r.warn("L010", STRINGS_CSV, ln, key)
            vals = {header[i]: (row[i] if i < len(row) else "") for i in range(1, len(header))}
            for loc in REQUIRED_LOCALES:
                if loc in vals and not vals[loc].strip():
                    self.r.err("L003", STRINGS_CSV, ln, f"{key}: пустой {loc}")
            vals["__line__"] = str(ln)
            keys[key] = vals
        self.csv_keys = keys
        return keys

    # ---- сцены
    def scene(self, rel: str, stack: tuple[str, ...] = ()) -> SceneInfo:
        if rel in self.scene_cache:
            return self.scene_cache[rel]
        info = SceneInfo(rel)
        self.scene_cache[rel] = info
        if rel in stack or not self.exists(rel):
            info.ok = False
            return info
        try:
            sections = parse_godot_text(self.read(rel))
        except ParseError:
            info.ok = False
            return info
        exts = {unquote(s.attrs.get("id")): s for s in sections if s.tag == "ext_resource"}

        def ext_path(raw: str | None) -> str | None:
            if not raw:
                return None
            m = REF_RE.search(raw)
            if not m or m.group(1) != "ExtResource" or m.group(2) not in exts:
                return None
            s = exts[m.group(2)]
            p = unquote(s.attrs.get("path"))
            u = unquote(s.attrs.get("uid"))
            if u and u in self.uid_map:
                return self.uid_map[u]
            return self.res_to_rel(p) if p else None

        for s in sections:
            if s.tag != "node":
                continue
            name = unquote(s.attrs.get("name")) or "?"
            parent = unquote(s.attrs.get("parent"))
            path = "." if parent is None else (name if parent == "." else f"{parent}/{name}")
            node = NodeInfo(path, name, unquote(s.attrs.get("type")), ext_path(s.prop("script")),
                            ext_path(s.attrs.get("instance")),
                            unique=(s.prop("unique_name_in_owner") == "true"))
            if path in info.nodes and info.nodes[path].from_instance:
                old = info.nodes[path]
                node.script = node.script or old.script
                node.from_instance = True
            info.nodes[path] = node
            if node.instance:
                sub = self.scene(node.instance, stack + (rel,))
                for sp, sn in sub.nodes.items():
                    if sp == ".":
                        if not node.script:
                            node.script = sn.script
                        if not node.type:
                            node.type = sn.type
                        continue
                    full = sp if path == "." else f"{path}/{sp}"
                    info.nodes.setdefault(full, NodeInfo(full, sn.name, sn.type, sn.script, sn.instance,
                                                          False, True))
        return info

    def script_of(self, node: NodeInfo | None) -> ScriptInfo | None:
        if node is None or not node.script:
            return None
        return self.scripts.get(node.script)


# --------------------------------------------------------------------------------------------
# Проверки
# --------------------------------------------------------------------------------------------
def check_project_godot(p: Project) -> None:
    r = p.r
    rel = "project.godot"
    text = p.read_opt(rel)
    if text is None:
        r.err("P001", rel, 1, "нет project.godot в корне")
        return
    try:
        sections = parse_godot_text(text)
    except ParseError as e:
        r.err("P001", rel, e.line, str(e))
        return
    by: dict[str, Section] = {}
    for s in sections:
        by.setdefault(s.tag, s)
    glob = sections[0]
    if glob.prop("config_version") != "5":
        r.err("P001", rel, 1, "config_version должен быть 5 (Godot 4)")
    for (sec, key), want in EXPECTED_SETTINGS.items():
        s = by.get(sec)
        got = s.prop(key) if s else None
        if got != want:
            r.err("P002", rel, s.line if s else 1, f"[{sec}] {key}={got} (нужно {want})")
    app = by.get("application")
    feats = app.prop("config/features") if app else None
    if not feats or f'"{ENGINE_VERSION}"' not in feats:
        r.warn("P008", rel, app.line if app else 1, f"config/features={feats}")
    ms_raw = app.prop("run/main_scene") if app else None
    ms = unquote(ms_raw)
    if not ms:
        r.err("P003", rel, app.line if app else 1, "run/main_scene не задан")
    else:
        target = p.uid_map.get(ms) if ms.startswith("uid://") else p.res_to_rel(ms)
        if not target or not p.exists(target):
            r.err("P003", rel, app.line if app else 1, f"главная сцена не найдена: {ms}")
    al = by.get("autoload")
    if al:
        for k, v, ln in al.props:
            path = (unquote(v) or "").lstrip("*")
            target = p.uid_map.get(path) if path.startswith("uid://") else p.res_to_rel(path)
            if not target or not p.exists(target):
                r.err("P004", rel, ln, f"автозагрузка {k}: не найден {path}")
    i18n = by.get("internationalization")
    listed = i18n.prop("locale/translations") if i18n else None
    listed_paths = PSA_ITEM_RE.findall(listed or "")
    for res in listed_paths:
        trel = p.res_to_rel(res) or ""
        if p.exists(trel):
            continue
        m = re.match(r"(.+)\.([a-zA-Z_]+)\.translation$", trel)
        if not (m and p.exists(m.group(1) + ".csv")):
            r.err("P005", rel, i18n.line, f"перевод не найден и нет исходного CSV: {res}")
    if p.exists(STRINGS_CSV):
        stem = STRINGS_CSV[:-4]
        for loc in REQUIRED_LOCALES:
            want = f"res://{stem}.{loc}.translation"
            if want not in listed_paths:
                r.warn("P005", rel, i18n.line if i18n else 1, f"в locale/translations нет {want}")
    audio = by.get("audio")
    bus = unquote(audio.prop("buses/default_bus_layout")) if audio else None
    if bus:
        brel = p.res_to_rel(bus)
        if not brel or not p.exists(brel):
            r.err("P006", rel, audio.line, f"нет {bus}")
    # экспорт
    ep = p.read_opt("export_presets.cfg")
    if ep:
        try:
            esec = parse_godot_text(ep)
        except ParseError as e:
            r.err("P001", "export_presets.cfg", e.line, str(e))
            return
        presets = {s.tag: s for s in esec}
        for s in esec:
            if re.fullmatch(r"preset\.\d+", s.tag) and unquote(s.prop("platform")) == "Web":
                opts = presets.get(s.tag + ".options")
                ts = opts.prop("variant/thread_support") if opts else None
                if ts != "false":
                    r.err("P007", "export_presets.cfg", (opts or s).line,
                          f"{unquote(s.prop('name'))}: variant/thread_support={ts}")


def check_resource_file(p: Project, rel: str) -> None:
    r = p.r
    is_scene = rel.endswith(".tscn")
    try:
        sections = parse_godot_text(p.read(rel))
    except ParseError as e:
        r.err("T001", rel, e.line, str(e))
        return
    body = [s for s in sections[1:]]
    if not body:
        r.err("T002", rel, 1, "пустой файл")
        return
    head = body[0]
    want = "gd_scene" if is_scene else "gd_resource"
    if head.tag != want:
        r.err("T002", rel, head.line, f"первая секция [{head.tag}], нужно [{want}]")
    elif head.attrs.get("format") not in ("3", "4"):
        r.err("T002", rel, head.line, f"format={head.attrs.get('format')} (нужно 3 или 4 — Godot 4)")
    if not is_scene:
        sc = unquote(head.attrs.get("script_class"))
        if sc and sc not in p.class_names:
            r.warn("T021", rel, head.line, f"script_class={sc}")
        if not any(s.tag == "resource" for s in body):
            r.err("T002", rel, head.line, "нет секции [resource]")
    hu = unquote(head.attrs.get("uid"))
    if hu and p.uid_map.get(hu) != rel:
        r.warn("T013", rel, head.line, f"uid {hu} указывает на другой файл")

    ext: dict[str, tuple[Section, str | None]] = {}
    sub_order: dict[str, int] = {}
    for idx, s in enumerate(body):
        if s.tag == "ext_resource":
            sid = unquote(s.attrs.get("id"))
            if sid is None:
                r.err("T001", rel, s.line, "ext_resource без строкового id (format=3)")
                continue
            if sid in ext:
                r.err("T003", rel, s.line, f"повтор ext_resource id={sid}")
            target = p.resolve_ref(s.attrs.get("path"), s.attrs.get("uid"), rel, s.line, "T004")
            ext[sid] = (s, target)
            typ = unquote(s.attrs.get("type"))
            if target:
                exp = EXT_EXPECTED_TYPES.get(Path(target).suffix.lower())
                if exp and typ not in exp:
                    r.warn("T014", rel, s.line, f"type={typ} для {Path(target).name}")
        elif s.tag == "sub_resource":
            sid = unquote(s.attrs.get("id"))
            if sid is None:
                r.err("T001", rel, s.line, "sub_resource без строкового id")
                continue
            if sid in sub_order:
                r.err("T003", rel, s.line, f"повтор sub_resource id={sid}")
            sub_order[sid] = idx
    # ссылки
    for idx, s in enumerate(body):
        values = [(v, ln) for _, v, ln in s.props] + [(v, s.line) for v in s.attrs.values()]
        for v, ln in values:
            if REF_OLD_RE.search(v):
                r.err("T001", rel, ln, "числовой id ресурса (формат Godot 3)")
            for kind, rid in REF_RE.findall(v):
                if kind == "ExtResource" and rid not in ext:
                    r.err("T005", rel, ln, f'ExtResource("{rid}") не определён')
                if kind == "SubResource":
                    if rid not in sub_order:
                        r.err("T005", rel, ln, f'SubResource("{rid}") не определён')
                    elif sub_order[rid] >= idx:
                        r.err("T017", rel, ln, f'SubResource("{rid}") определён ниже')
    if is_scene:
        check_scene_nodes(p, rel, body, ext)


def check_scene_nodes(p: Project, rel: str, body: list[Section],
                      ext: dict[str, tuple[Section, str | None]]) -> None:
    r = p.r
    info = p.scene(rel)
    declared: dict[str, Section] = {}
    instanced_roots: set[str] = set()
    children: dict[str, set[str]] = {}
    root_seen = False
    for s in body:
        if s.tag != "node":
            continue
        name = unquote(s.attrs.get("name"))
        if not name:
            r.err("T001", rel, s.line, "узел без name")
            continue
        parent = unquote(s.attrs.get("parent"))
        if parent is None:
            if root_seen:
                r.err("T006", rel, s.line, f"второй корневой узел {name} (нет parent)")
            root_seen = True
            path = "."
        else:
            if not root_seen:
                r.err("T006", rel, s.line, f"{name}: узел с parent раньше корня")
            path = name if parent == "." else f"{parent}/{name}"
            if parent not in info.nodes:
                r.err("T006", rel, s.line, f"{name}: родитель «{parent}» не найден")
            sib = children.setdefault(parent, set())
            if name in sib and not info.nodes.get(path, NodeInfo("", "", None, None, None)).from_instance:
                r.err("T007", rel, s.line, f"повтор имени {name} у «{parent}»")
            sib.add(name)
        declared[path] = s
        typ = unquote(s.attrs.get("type"))
        inst = s.attrs.get("instance")
        if inst:
            m = REF_RE.search(inst)
            if m and m.group(2) in ext:
                es, _ = ext[m.group(2)]
                if unquote(es.attrs.get("type")) != "PackedScene":
                    r.err("T009", rel, s.line, f"{name}: instance не PackedScene")
            instanced_roots.add(path)
        if typ:
            if typ in p.class_names:
                r.err("T019", rel, s.line, f"{name}: type=\"{typ}\" — укажите базовый тип и script")
            elif typ not in NODE_CLASSES:
                r.warn("T020", rel, s.line, f"{name}: type=\"{typ}\"")
        if not typ and not inst:
            node = info.nodes.get(path)
            inside = node is not None and node.from_instance
            if not inside and s.attrs.get("instance_placeholder") is None:
                r.err("T008", rel, s.line, f"{name}: нет type/instance")
        scr = s.prop("script")
        if scr:
            m = REF_RE.search(scr)
            if m and m.group(2) in ext:
                es, target = ext[m.group(2)]
                if unquote(es.attrs.get("type")) not in ("Script", "GDScript"):
                    r.warn("T014", rel, s.line, f"{name}: script ссылается на {es.attrs.get('type')}")
                sinfo = p.scripts.get(target or "")
                node = info.nodes.get(path)
                if sinfo and node and node.type:
                    base = (sinfo.extends or "RefCounted").strip()
                    if is_subclass(node.type, base) is False:
                        r.err("T022", rel, s.line, f"{name} ({node.type}) ← {sinfo.path} (extends {base})")
    # NodePath и экспортируемые свойства
    for path, s in declared.items():
        node = info.nodes.get(path)
        sinfo = p.script_of(node)
        np_props = PSA_ITEM_RE.findall(s.attrs.get("node_paths", ""))
        for prop in np_props:
            if s.prop(prop) is None:
                continue
            if sinfo and prop not in sinfo.exports:
                r.warn("T015", rel, s.line, f"{node.name}.{prop}: нет @export var {prop} в {sinfo.path}")
        for key, val, ln in s.props:
            for np in NODEPATH_RE.findall(val):
                check_nodepath(p, rel, info, path, np, ln, f"{node.name if node else path}.{key}")
    # соединения
    for s in body:
        if s.tag != "connection":
            continue
        sig = unquote(s.attrs.get("signal")) or ""
        frm = unquote(s.attrs.get("from")) or ""
        to = unquote(s.attrs.get("to")) or ""
        meth = unquote(s.attrs.get("method")) or ""
        fnode = info.nodes.get(frm)
        tnode = info.nodes.get(to)
        if fnode is None:
            r.err("T011", rel, s.line, f"from=\"{frm}\" не найден")
        if tnode is None:
            r.err("T011", rel, s.line, f"to=\"{to}\" не найден")
            continue
        tscript = p.script_of(tnode)
        if not ((tscript and meth in tscript.funcs) or meth in BUILTIN_METHODS):
            where = tscript.path if tscript else "узел без скрипта"
            r.err("T012", rel, s.line, f"{sig} → «{to}».{meth}(): метода нет ({where})")
        fscript = p.script_of(fnode)
        if fscript and fscript.signals and sig not in fscript.signals and sig not in BUILTIN_SIGNALS:
            r.warn("T016", rel, s.line, f"{frm}.{sig}")


def check_nodepath(p: Project, rel: str, info: SceneInfo, base: str, np: str, line: int, what: str) -> None:
    target = np.split(":")[0]
    if target == "" or target.startswith("/"):
        return
    if target.startswith("%"):
        uname = target[1:].split("/")[0]
        if not any(n.unique and n.name == uname and not n.from_instance for n in info.nodes.values()):
            p.r.err("T010", rel, line, f"{what}: %{uname} — нет узла с unique_name_in_owner")
        return
    segs = [] if base == "." else base.split("/")
    for seg in target.split("/"):
        if seg in (".", ""):
            continue
        if seg == "..":
            if not segs:
                p.r.warn("T018", rel, line, f"{what}: NodePath(\"{np}\") выходит за корень сцены")
                return
            segs.pop()
        else:
            segs.append(seg)
    full = "/".join(segs) or "."
    if full not in info.nodes:
        p.r.err("T010", rel, line, f"{what}: NodePath(\"{np}\") → «{full}» не найден")


NUM_RE = re.compile(r"(?<![\w.])(\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?(?![\w.])")


def check_gdscript(p: Project, rel: str) -> None:
    r = p.r
    info = p.scripts[rel]
    lint = p.is_lint_target(rel)
    if info.unbalanced:
        r.err("G013", rel, info.unbalanced[0], info.unbalanced[1])
    raw_lines = p.read(rel).split("\n")
    # extends — только встроенные классы
    if info.extends:
        ext = info.extends.strip()
        if ext.startswith(("'", '"')) or ext in p.class_names:
            r.err("G004", rel, info.extends_line, f"extends {ext}")
    # шапка
    if lint and not any(l.lstrip().startswith("##") for l in raw_lines[:20]):
        r.warn("G007", rel, 1, "добавьте `## Назначение / Сигналы / Зависимости` в начало файла")
    # отступы
    kinds: set[str] = set()
    for ll in info.lines:
        if not ll.code.strip():
            continue
        if "\t" in ll.indent and " " in ll.indent:
            r.err("G014", rel, ll.line, "в одной строке табы и пробелы")
        elif "\t" in ll.indent:
            kinds.add("tab")
        elif " " in ll.indent:
            kinds.add("space")
    if len(kinds) > 1:
        r.err("G014", rel, 1, "в файле есть отступы и табами, и пробелами")
    code_lines = [ll for ll in info.lines if ll.code.strip()]
    instantiated: set[str] = set()
    for m in re.finditer(r"\b(\w+)\s*(?::\s*[\w.\[\]]+\s*)?:?=\s*[^\n]*?\.(instantiate|duplicate)\(", info.masked):
        instantiated.add(m.group(1))
    magic_count = 0
    pending_anns: list[str] = []
    for k, ll in enumerate(code_lines):
        code = ll.code.strip()
        raw_first = raw_lines[ll.line - 1] if ll.line - 1 < len(raw_lines) else ""
        # перенос выражения без скобок: строка глубже предыдущей, а та не кончается двоеточием
        if k > 0:
            prev = code_lines[k - 1]
            if (indent_width(ll.indent) > indent_width(prev.indent) and not prev.code.strip().endswith(":")
                    and '"""' not in prev.raw and "'''" not in prev.raw):
                r.err("G016", rel, ll.line, f"{code[:50]} — оберните выражение в ( ) или поставьте \\ в конце строки {prev.line}")
        # блок после двоеточия
        if code.endswith(":"):
            nxt = code_lines[k + 1] if k + 1 < len(code_lines) else None
            if nxt is None or indent_width(nxt.indent) <= indent_width(ll.indent):
                r.err("G012", rel, ll.line, code[:60])
        for pat, msg in GODOT3_PATTERNS:
            if re.search(pat, code, re.M):
                r.err("G011", rel, ll.line, msg)
        for m in re.finditer(r"\b([A-Z]\w*)\.new\(", code):
            cls = m.group(1)
            base = None
            if cls in p.class_names:
                base = (p.scripts[p.class_names[cls]].extends or "").strip()
            if cls in NODE_CLASSES or cls == "Tween" or (base in NODE_CLASSES):
                r.err("G005", rel, ll.line, f"{cls}.new() — используйте сцену .tscn + instantiate()"
                      if cls != "Tween" else "Tween.new() — используйте create_tween()")
        if re.search(r"\bClassDB\.instantiate\(", code):
            r.err("G005", rel, ll.line, "ClassDB.instantiate()")
        if not lint:
            continue
        for m in re.finditer(r"\badd_child\(\s*([^),]*)", code):
            arg = m.group(1).strip()
            if not arg or "instantiate(" in arg or "duplicate(" in arg:
                continue
            if re.fullmatch(r"\w+", arg) and arg in instantiated:
                continue
            r.warn("G006", rel, ll.line, f"add_child({arg})")
        if "$" in code or re.search(r"\bget_node(_or_null)?\(", code):
            r.warn("G008", rel, ll.line, code[:60])
        body, anns = strip_annotations(code)
        if not body:
            pending_anns += anns
            continue
        anns, pending_anns = pending_anns + anns, []
        # типизация
        vm = re.match(r"^(?:static\s+)?var\s+(\w+)\s*(.*)$", body)
        if vm and not vm.group(2).strip().startswith(":"):
            r.err("G001", rel, ll.line, f"var {vm.group(1)}")
        fm = re.match(r"^(?:static\s+)?func\s+(\w+)\s*\(", body)
        if fm:
            open_i = body.index("(", fm.start(1))
            close_i = match_paren(body, open_i)
            if close_i == -1:
                r.err("G013", rel, ll.line, f"func {fm.group(1)}: незакрытая скобка")
            else:
                params = body[open_i + 1:close_i]
                for prm in split_top_level(params):
                    prm = prm.strip()
                    if not prm or prm.startswith("..."):
                        continue
                    if not re.match(r"^\w+\s*:", prm):
                        r.err("G002", rel, ll.line, f"func {fm.group(1)}: параметр «{prm.split('=')[0].strip()}»")
                tail = body[close_i + 1:].lstrip()
                if not tail.startswith("->"):
                    r.err("G003", rel, ll.line, f"func {fm.group(1)}")
        # магические числа
        if (body.startswith(("const ", "enum ", "enum{")) or any(a.startswith("@export") for a in anns)
                or "noqa: magic" in raw_first or "noqa" in raw_first and "magic" in raw_first):
            continue
        if re.match(r"^(case\b|\S.*:$)", body) and not re.match(r"^(if|elif|while|for|func|static)\b", body):
            # шаблоны match — числа допустимы
            if re.match(r"^[\w\s,.\-\"\[\]]+:$", body):
                continue
        for m in NUM_RE.finditer(code):
            prev = code[max(0, m.start() - 2):m.start()]
            if prev.endswith("0x") or m.group(0) in ALLOWED_NUMBERS:
                continue
            magic_count += 1
            if magic_count <= MAX_MAGIC_PER_FILE:
                r.warn("G009", rel, ll.line, m.group(0))
    if magic_count > MAX_MAGIC_PER_FILE:
        r.warn("G009", rel, 0, f"ещё {magic_count - MAX_MAGIC_PER_FILE} чисел не показано")
    # строки: res:// и tr()
    csv_keys = p.load_csv()
    for s in info.strings:
        v = s.value
        if v.startswith("res://") and not re.search(r"[%{}*]", v):
            target = v[len("res://"):].split("::")[0]
            ok = (p.root / target).is_dir() if target.endswith("/") or target == "" else p.exists(target)
            if not ok:
                r.err("G010", rel, s.line, v)
    for m in re.finditer(r"\btr(?:_n)?\(\s*", info.masked):
        st = gd_string_at(info, m.end())
        if st is None:
            continue
        line = info.masked.count("\n", 0, m.start()) + 1
        if csv_keys is None:
            r.err("G015", rel, line, f"{st.value}: нет {STRINGS_CSV}")
        elif st.value not in csv_keys:
            r.err("G015", rel, line, st.value)
    if lint:
        for m in re.finditer(r"(?:\.|\b)(text|tooltip_text|placeholder_text)\s*=\s*", info.masked):
            st = gd_string_at(info, m.end())
            if st and re.search(r"[A-Za-zА-Яа-яЁё]", st.value) and not KEY_RE.match(st.value):
                r.warn("L008", rel, st.line, f"{m.group(1)} = \"{st.value[:40]}\" — используйте tr(\"KEY\")")


def check_shader(p: Project, rel: str) -> None:
    r = p.r
    text = p.read(rel)
    code = mask_shader(text)
    if rel.endswith(".gdshader") and not re.search(
            r"\bshader_type\s+(canvas_item|spatial|particles|sky|fog)\s*;", code):
        r.err("S001", rel, 1, "первая инструкция — shader_type canvas_item;")
    for pat, msg in [(r"\bhint_color\b", "hint_color → source_color"),
                     (r"\b(SCREEN_TEXTURE|DEPTH_TEXTURE|NORMAL_TEXTURE)\b",
                      "SCREEN_TEXTURE и др. → uniform sampler2D … : hint_screen_texture"),
                     (r"\bhint_albedo\b", "hint_albedo → source_color")]:
        for m in re.finditer(pat, code):
            r.err("S002", rel, code.count("\n", 0, m.start()) + 1, msg)
    for o, c in ("{}", "()", "[]"):
        if code.count(o) != code.count(c):
            r.err("S003", rel, 1, f"«{o}» {code.count(o)} ≠ «{c}» {code.count(c)}")
    if re.search(r"godotshaders\.com|shadertoy\.com|(Source|Источник)\s*:", text, re.I):
        if rel not in p.third_party_text:
            r.err("S004", rel, 1, f"добавьте строку про {rel} в {THIRD_PARTY_MD}")


def check_scene_texts(p: Project, rel: str) -> None:
    try:
        sections = parse_godot_text(p.read(rel))
    except ParseError:
        return
    keys = p.load_csv()
    for s in sections:
        if s.tag != "node":
            continue
        for k, v, ln in s.props:
            if k not in ("text", "placeholder_text", "tooltip_text", "title"):
                continue
            val = unquote(v)
            if not val or not re.search(r"[A-Za-zА-Яа-яЁё]", val):
                continue
            if KEY_RE.match(val):
                if keys is None or val not in keys:
                    p.r.err("L007", rel, ln, val)
            else:
                p.r.warn("L008", rel, ln, f"{k} = \"{val[:40]}\"")


def check_data_keys(p: Project, rel: str) -> None:
    """Свойства *_key (name_key, desc_key, line_key, tip_key…) в ресурсах и сценах — ключи strings.csv."""
    try:
        sections = parse_godot_text(p.read(rel))
    except ParseError:
        return
    keys = p.load_csv()
    for s in sections:
        for k, v, ln in s.props:
            if not k.endswith("_key"):
                continue
            val = unquote(v.lstrip("&")) if v.startswith(("&\"", "\"")) else None
            if not val or not KEY_RE.match(val):
                continue
            if keys is None or val not in keys:
                p.r.err("L011", rel, ln, f"{k} = {val}")


def text_hash(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8")).hexdigest()[:10]


def read_humanized(p: Project) -> dict[str, dict[str, str]]:
    text = p.read_opt(HUMANIZED_TXT) or ""
    out: dict[str, dict[str, str]] = {}
    for ln, line in enumerate(text.splitlines(), start=1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        hashes = {"__line__": str(ln)}
        for part in parts[1:]:
            if "=" in part:
                a, b = part.split("=", 1)
                hashes[a] = b
        out[parts[0]] = hashes
    return out


def check_localization(p: Project) -> None:
    keys = p.load_csv()
    if keys is None:
        return
    hum = read_humanized(p)
    if p.read_opt(HUMANIZED_TXT) is None and keys:
        p.r.err("L004", HUMANIZED_TXT, 1, "файла нет — тексты не прошли humanizer")
    for key, vals in keys.items():
        ln = int(vals["__line__"])
        h = hum.get(key)
        if h is None:
            p.r.err("L004", STRINGS_CSV, ln, key)
        else:
            for loc in REQUIRED_LOCALES:
                if loc in vals and h.get(loc) != text_hash(vals[loc]):
                    p.r.err("L005", STRINGS_CSV, ln, f"{key} [{loc}] — прогоните humanizer и --mark-humanized")
        for loc in REQUIRED_LOCALES:
            for w in MODERATION_WORDS:
                if re.search(w, vals.get(loc, ""), re.I):
                    p.r.warn("L009", STRINGS_CSV, ln, f"{key} [{loc}]: «{w}»")
    for key, h in hum.items():
        if key not in keys:
            p.r.warn("L006", HUMANIZED_TXT, int(h["__line__"]), key)


def parse_md_table(text: str, must_have: str) -> list[tuple[int, dict[str, str]]]:
    rows: list[tuple[int, dict[str, str]]] = []
    header: list[str] | None = None
    for ln, line in enumerate(text.splitlines(), start=1):
        if not line.startswith("|"):
            header = None if not line.strip() else header
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if header is None:
            if any(must_have == c for c in cells):
                header = cells
            continue
        if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
            continue
        rows.append((ln, {header[i]: cells[i] if i < len(cells) else "" for i in range(len(header))}))
    return rows


def _col(row: dict[str, str], prefix: str) -> str:
    for k, v in row.items():
        if k.lower().startswith(prefix.lower()):
            return v.strip("` ")
    return ""


def check_assets(p: Project) -> None:
    r = p.r
    reg = p.read_opt(REGISTRY_MD)
    images = [f for f in p.files if f.startswith(ASSETS_DIR + "/")
              and Path(f).suffix.lower() in (".png", ".jpg", ".jpeg", ".webp", ".svg")]
    if reg is None:
        if images:
            r.warn("A001", REGISTRY_MD, 1, "реестра нет, ассеты не проверены")
        return
    prompts = set(re.findall(r"^##+\s+(P-[A-Z]+-\d+)", p.read_opt(PROMPTS_MD) or "", re.M))
    seen_ids: set[str] = set()
    reg_paths: set[str] = set()
    for ln, row in parse_md_table(reg, "ID"):
        aid = _col(row, "ID")
        path = _col(row, "Путь") or _col(row, "Path")
        canvas = _col(row, "Холст") or _col(row, "Canvas")
        status = (_col(row, "Статус") or _col(row, "Status")).lower()
        prompt = _col(row, "Промпт") or _col(row, "Prompt")
        if not aid or not path:
            continue
        if aid in seen_ids or path in reg_paths:
            r.err("A008", REGISTRY_MD, ln, f"{aid} / {path}")
        seen_ids.add(aid)
        reg_paths.add(path)
        st = status.split()[0] if status else ""
        if st == "probe":
            continue
        if st in ("temp", "final", "planned"):
            pm = re.search(r"P-[A-Z]+-\d+", prompt)
            if not pm:
                r.err("A004", REGISTRY_MD, ln, f"{aid}: нет промпта")
            elif pm.group(0) not in prompts:
                r.err("A004", REGISTRY_MD, ln, f"{aid}: {pm.group(0)} нет в {PROMPTS_MD}")
        exists = p.exists(path)
        if st in ("temp", "final"):
            if not exists:
                r.err("A002", REGISTRY_MD, ln, f"{aid}: {path}")
                continue
            cm = re.match(r"(\d+)\s*[×xX]\s*(\d+)", canvas)
            if cm and path.lower().endswith(".png"):
                size = png_size(p.root / path)
                want = (int(cm.group(1)), int(cm.group(2)))
                if size != want:
                    r.err("A003", REGISTRY_MD, ln, f"{aid}: {size} ≠ {want}")
        elif st == "planned" and exists:
            r.warn("A007", REGISTRY_MD, ln, f"{aid}: {path}")
    for f in images:
        if f not in reg_paths:
            r.err("A005", f, 0, "добавьте строку в " + REGISTRY_MD)
        if not f.lower().endswith(".png"):
            r.warn("A006", f, 0, "контракт: PNG")


def check_names(p: Project) -> None:
    for rel in p.dirs + p.files:
        name = rel.rsplit("/", 1)[-1]
        if "/" not in rel and (name in ROOT_NAME_WHITELIST or name.startswith(".")):
            continue
        if name in (".gdignore", ".gitkeep"):
            continue
        base = name
        for suf in (".import", ".uid"):
            if base.endswith(suf):
                base = base[: -len(suf)]
        if not SNAKE_RE.match(base):
            p.r.err("N001", rel, 0, name)


def check_misc(p: Project) -> None:
    for rel in p.files:
        if rel.endswith(".import") and not p.exists(rel[:-7]):
            p.r.warn("X001", rel, 0, "исходного файла нет")
        if rel.endswith(".uid") and not p.exists(rel[:-4]):
            p.r.warn("X001", rel, 0, "исходного файла нет")
        if rel.startswith(ASSETS_DIR + "/") and rel.lower().endswith((".ttf", ".otf", ".woff", ".woff2")):
            if Path(rel).name not in p.third_party_text:
                p.r.err("F001", rel, 0, "добавьте источник и лицензию (OFL/CC0/MIT)")


def run(root: Path) -> Report:
    report = Report()
    p = Project(root, report)
    check_project_godot(p)
    for rel in p.files:
        if rel.endswith((".tscn", ".tres")):
            check_resource_file(p, rel)
            check_data_keys(p, rel)
            if rel.endswith(".tscn"):
                check_scene_texts(p, rel)
        elif rel.endswith(".gd"):
            check_gdscript(p, rel)
        elif rel.endswith((".gdshader", ".gdshaderinc")):
            check_shader(p, rel)
    check_localization(p)
    check_assets(p)
    check_names(p)
    check_misc(p)
    return report


# --------------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------------
def print_report(report: Report, root: Path) -> None:
    by_file: dict[str, list[Issue]] = {}
    for i in report.issues:
        by_file.setdefault(i.path, []).append(i)
    for path in sorted(by_file):
        print(f"\n{path}")
        for i in sorted(by_file[path], key=lambda x: (x.line, x.code)):
            loc = f":{i.line}" if i.line else ""
            print(f"  {i.level:5} {i.code}{loc:6} {i.msg}")
    e, w = len(report.errors), len(report.warnings)
    print(f"\nИтог ({root}): ошибок {e}, предупреждений {w}" + (" — OK" if e == 0 else ""))


def mark_humanized(root: Path, keys: list[str]) -> int:
    report = Report()
    p = Project(root, report)
    csv_keys = p.load_csv()
    if csv_keys is None:
        print(f"нет {STRINGS_CSV}")
        return 1
    hum = read_humanized(p)
    missing = [k for k in keys if k not in csv_keys]
    if missing:
        print("нет в strings.csv:", ", ".join(missing))
        return 1
    for k in keys:
        hum[k] = {loc: text_hash(csv_keys[k][loc]) for loc in REQUIRED_LOCALES}
    lines = ["# humanized.txt — ключи, тексты которых прошли humanizer (ru: tools/humanizer/ru, en: tools/humanizer/en).",
             "# Формат: KEY ru=<sha1[:10]> en=<sha1[:10]>. Писать только через:",
             "#   python tools/validate_project.py --mark-humanized KEY ...",
             "# Если текст в strings.csv изменится, валидатор выдаст L005 — нужен повторный humanizer."]
    for k in sorted(hum):
        lines.append(k + "".join(f" {loc}={hum[k][loc]}" for loc in REQUIRED_LOCALES if loc in hum[k]))
    out = root / HUMANIZED_TXT
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"отмечено: {', '.join(keys)} → {HUMANIZED_TXT}")
    return 0


def self_test(tests_dir: Path) -> int:
    ok = True
    good = tests_dir / "good"
    rep = run(good)
    if rep.issues:
        ok = False
        print("[FAIL] good: ожидалось 0 замечаний")
        print_report(rep, good)
    else:
        print("[ OK ] good: 0 замечаний")
    covered: set[str] = set()
    for bad in sorted(d for d in tests_dir.iterdir() if d.is_dir() and d.name.startswith("bad")):
        rep = run(bad)
        expected = set((bad / "expected_codes.txt").read_text(encoding="utf-8").split())
        covered |= expected
        found = {i.code for i in rep.issues}
        miss, extra = sorted(expected - found), sorted(found - expected)
        if miss:
            ok = False
            print(f"[FAIL] {bad.name}: не сработали {miss}")
        else:
            print(f"[ OK ] {bad.name}: сработали все {len(expected)} ожидаемых кодов")
        if extra:
            ok = False
            print(f"[FAIL] {bad.name}: лишние коды {extra}")
            print_report(rep, bad)
    untested = sorted(set(RULES) - covered)
    print(f"[info] покрыто фикстурами {len(set(RULES) & covered)}/{len(RULES)} правил"
          + (f"; без фикстуры: {' '.join(untested)}" if untested else ""))
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--rules", action="store_true")
    ap.add_argument("--mark-humanized", nargs="+", metavar="KEY")
    a = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if a.rules:
        for k, v in RULES.items():
            print(f"{k}  {v}")
        return 0
    if a.self_test:
        return self_test(Path(__file__).resolve().parent / "validator_tests")
    if a.mark_humanized:
        return mark_humanized(a.root, a.mark_humanized)
    report = run(a.root)
    if a.json:
        print(json.dumps({"errors": len(report.errors), "warnings": len(report.warnings),
                          "issues": [i.__dict__ for i in report.issues]}, ensure_ascii=False, indent=1))
    else:
        print_report(report, a.root)
    fail = bool(report.errors) or (a.strict and bool(report.warnings))
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
