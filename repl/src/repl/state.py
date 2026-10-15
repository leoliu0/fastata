"""Per-package state (<pkg>/state.json), so every stage can be stopped and restarted.

Stages: fetch, scan, prepare, run_A, run_F, run_B, compare. Each stage records
{"ok": bool, ...details}. A stage that finished (ok or not) is skipped on reruns unless forced.
"""

from __future__ import annotations

import json
import os
import threading
import time
from pathlib import Path
from typing import Any

from . import paths

_lock = threading.Lock()


def state_path(pkg: str) -> Path:
    return paths.pkg_dir(pkg) / "state.json"


def load(pkg: str) -> dict[str, Any]:
    p = state_path(pkg)
    if not p.exists():
        return {"pkg": pkg, "stages": {}}
    with open(p) as f:
        return json.load(f)


def save(st: dict[str, Any]) -> None:
    p = state_path(st["pkg"])
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(f".tmp{os.getpid()}.{threading.get_ident()}")
    with open(tmp, "w") as f:
        json.dump(st, f, indent=1, sort_keys=True)
    os.replace(tmp, p)


def stage(pkg: str, name: str) -> dict[str, Any] | None:
    return load(pkg)["stages"].get(name)


def done(pkg: str, name: str) -> bool:
    return stage(pkg, name) is not None


def ok(pkg: str, name: str) -> bool:
    s = stage(pkg, name)
    return bool(s and s.get("ok"))


def record(pkg: str, name: str, ok: bool, **info: Any) -> dict[str, Any]:
    with _lock:
        st = load(pkg)
        rec = {"ok": ok, "at": time.strftime("%Y-%m-%dT%H:%M:%S"), **info}
        st["stages"][name] = rec
        save(st)
    return rec


def clear(pkg: str, *names: str) -> None:
    with _lock:
        st = load(pkg)
        for n in names:
            st["stages"].pop(n, None)
        save(st)


def set_info(pkg: str, **info: Any) -> None:
    with _lock:
        st = load(pkg)
        st.setdefault("info", {}).update(info)
        save(st)


def info(pkg: str) -> dict[str, Any]:
    return load(pkg).get("info", {})
