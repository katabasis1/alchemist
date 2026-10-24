#!/usr/bin/env python3
"""pod_sync.py — «Протокол сохранения» (AGENTS.md §2.1) одной командой. Только stdlib.

Для агента в Computer: репозиторий в /tmp/work/repo, Pod смонтирован в /files/pod.
Пользователю этот скрипт не нужен.

  python tools/pod_sync.py --quick
        # страховка после любого коммита: только archive/alchemist_repo.bundle (секунды)
  python tools/pod_sync.py --id S1.2 --slug minimal_project
        # полный протокол после подэтапа:
        #   1) рабочее дерево чистое, валидатор без ошибок
        #   2) archive/alchemist_latest.zip            — `git archive HEAD` (без .git)
        #   3) archive/history/alchemist_v<ver>_<ID>_<slug>.zip (хранятся последние 10)
        #   4) archive/alchemist_repo.bundle           — `git bundle --all` (с тегами)
        #   5) outbox/patches/v<ver>/*.patch            — с прошлой выдачи (outbox/patches/LAST_PATCHED)
        #      outbox/alchemist_update_v<ver>.zip       — те же изменения файлами (распаковать поверх)
        #   6) project/ — зеркало дерева; docs/, tools/ и AGENTS.md в корне Pod — тоже зеркало
        #   7) archive/LAST_SYNC.txt                    — что и когда выгружено

Версия берётся из project.godot (config/version). Ничего не коммитит и не тегирует:
коммит и тег `v<ver>` агент делает сам до запуска.
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
POD_DEFAULT = Path("/files/pod")
HISTORY_KEEP = 10
MIRROR_TO_ROOT = ("docs", "tools", "AGENTS.md")


def git(*args: str, cwd: Path = REPO) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def project_version() -> str:
    text = (REPO / "project.godot").read_text(encoding="utf-8")
    m = re.search(r'^config/version="([^"]+)"', text, re.M)
    if not m:
        sys.exit("[pod_sync] в project.godot нет config/version")
    return m.group(1)


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)


def mirror_tree(src: Path, dst: Path) -> int:
    """Сделать dst точной копией src (лишнее удалить, неизменённое не трогать — Pod медленный)."""
    changed = 0
    dst.mkdir(parents=True, exist_ok=True)
    src_items = {p.relative_to(src) for p in src.rglob("*")}
    for p in sorted(dst.rglob("*"), reverse=True):
        rel = p.relative_to(dst)
        if rel not in src_items:
            if p.is_dir():
                shutil.rmtree(p, ignore_errors=True)
            else:
                p.unlink(missing_ok=True)
            changed += 1
    for rel in sorted(src_items):
        s, d = src / rel, dst / rel
        if s.is_dir():
            d.mkdir(parents=True, exist_ok=True)
            continue
        if d.exists() and d.stat().st_size == s.stat().st_size and d.read_bytes() == s.read_bytes():
            continue
        copy_file(s, d)
        changed += 1
    return changed


def make_bundle(pod: Path, tmp: Path) -> None:
    bundle = tmp / "alchemist_repo.bundle"
    git("bundle", "create", str(bundle), "--all")
    copy_file(bundle, pod / "archive" / "alchemist_repo.bundle")
    print(f"[pod_sync] bundle → archive/alchemist_repo.bundle ({bundle.stat().st_size // 1024} КБ)")


def make_update_zip(pod: Path, tmp: Path, since: str, head: str, ver: str, name: str = "") -> None:
    """outbox/alchemist_update_v<ver>.zip — только изменённые и новые файлы с прошлой выдачи.

    Пользователь распаковывает поверх папки проекта (или перетаскивает в GitHub → Add file → Upload files).
    Удалённые файлы перечислены в DELETED.txt внутри архива — их нужно удалить руками.
    """
    changed = git("diff", "--name-only", "--diff-filter=ACMRT", since, head).split("\n")
    changed = [c for c in changed if c]
    deleted = [c for c in git("diff", "--name-only", "--diff-filter=D", since, head).split("\n") if c]
    name = name or f"alchemist_update_v{ver}.zip"
    out = tmp / name
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in changed:
            z.writestr(rel, subprocess.run(["git", "show", f"{head}:{rel}"], cwd=REPO, check=True,
                                           capture_output=True).stdout)
        if deleted:
            z.writestr("DELETED.txt", "\n".join(deleted) + "\n")
    copy_file(out, pod / "outbox" / name)
    print(f"[pod_sync] обновление → outbox/{name} (файлов {len(changed)}, удалить {len(deleted)})")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pod", type=Path, default=POD_DEFAULT)
    ap.add_argument("--quick", action="store_true", help="только bundle")
    ap.add_argument("--id", help="ID подэтапа, например S1.2")
    ap.add_argument("--slug", help="короткое имя снапшота, snake_case")
    ap.add_argument("--allow-dirty", action="store_true", help="не требовать чистое дерево (не рекомендуется)")
    ap.add_argument("--base", help="коммит/тег, на котором стоит GitHub пользователя: дополнительно собрать "
                                   "сводный outbox/alchemist_update_<base-label>_to_v<ver>.zip (прежние сводные удаляются)")
    ap.add_argument("--base-label", help="метка базы в имени сводного архива, например v0.0.1")
    a = ap.parse_args()

    pod: Path = a.pod
    if not pod.exists():
        sys.exit(f"[pod_sync] нет Pod: {pod}")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        if a.quick:
            make_bundle(pod, tmp)
            return

        if not (a.id and a.slug):
            sys.exit("[pod_sync] для полного протокола нужны --id и --slug (или --quick)")
        dirty = git("status", "--porcelain")
        if dirty and not a.allow_dirty:
            sys.exit("[pod_sync] есть незакоммиченные изменения — сначала коммит:\n" + dirty)
        r = subprocess.run([sys.executable, str(REPO / "tools" / "validate_project.py")], cwd=REPO)
        if r.returncode != 0:
            sys.exit("[pod_sync] валидатор нашёл ошибки — выгрузка отменена")

        ver = project_version()
        head = git("rev-parse", "HEAD")
        tags = git("tag", "--points-at", "HEAD").split()
        if f"v{ver}" not in tags:
            print(f"[pod_sync] ВНИМАНИЕ: на HEAD нет тега v{ver} (теги: {tags or '—'})")

        # 2–3. ZIP чистого дерева
        latest = tmp / "alchemist_latest.zip"
        git("archive", "--format=zip", f"--prefix=alchemist/", "-o", str(latest), "HEAD")
        copy_file(latest, pod / "archive" / "alchemist_latest.zip")
        hist_dir = pod / "archive" / "history"
        hist_name = f"alchemist_v{ver}_{a.id}_{a.slug}.zip"
        copy_file(latest, hist_dir / hist_name)
        snaps = sorted(hist_dir.glob("alchemist_v*.zip"), key=lambda p: p.stat().st_mtime)
        for old in snaps[:-HISTORY_KEEP]:
            old.unlink()
            print(f"[pod_sync] удалён старый снапшот {old.name}")
        print(f"[pod_sync] zip → archive/alchemist_latest.zip, archive/history/{hist_name}")

        # 4. bundle
        make_bundle(pod, tmp)

        # 5. патчи с прошлой выдачи
        marker = pod / "outbox" / "patches" / "LAST_PATCHED"
        since = marker.read_text(encoding="utf-8").strip() if marker.exists() else ""
        out = pod / "outbox" / "patches" / f"v{ver}"
        if since == head:
            print("[pod_sync] новых коммитов для патчей нет")
        else:
            pdir = tmp / "patches"
            rng = ["--root", head] if not since else [f"{since}..{head}"]
            git("format-patch", "--binary", "-o", str(pdir), *rng)
            n = mirror_tree(pdir, out)
            marker.parent.mkdir(parents=True, exist_ok=True)
            marker.write_text(head + "\n", encoding="utf-8")
            print(f"[pod_sync] патчи → outbox/patches/v{ver}/ ({len(list(pdir.iterdir()))} шт., изменено файлов {n})")
            if since:
                make_update_zip(pod, tmp, since, head, ver)
        if a.base:
            label = a.base_label or a.base
            for old in (pod / "outbox").glob("alchemist_update_*_to_v*.zip"):
                old.unlink()
            make_update_zip(pod, tmp, git("rev-parse", a.base), head, ver,
                            f"alchemist_update_{label}_to_v{ver}.zip")

        # 6. зеркала
        tree = tmp / "tree"
        with zipfile.ZipFile(latest) as z:
            z.extractall(tree)
        src = tree / "alchemist"
        n = mirror_tree(src, pod / "project")
        for name in MIRROR_TO_ROOT:
            s = src / name
            if s.is_dir():
                n += mirror_tree(s, pod / name)
            elif s.exists():
                copy_file(s, pod / name)
                n += 1
        print(f"[pod_sync] зеркало project/ (+ docs/, tools/, AGENTS.md в корне): изменено {n}")

        # 7. отметка
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        (pod / "archive" / "LAST_SYNC.txt").write_text(
            f"version: v{ver}\nstep: {a.id} {a.slug}\ncommit: {head}\ntags: {' '.join(tags) or '-'}\nsynced: {stamp}\n",
            encoding="utf-8",
        )
        print(f"[pod_sync] готово: v{ver} {a.id} {head[:8]}")


if __name__ == "__main__":
    main()
