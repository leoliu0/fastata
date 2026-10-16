"""Which fastata code a fastata arm ran: the repository commit (with -dirty when fastata's
sources differ from it) and a short sha256 of the built plugin, which git ignores.

Recorded in run_V / run_F stage records (key 'fastata') when the arm starts, carried into the
compare record, shown by repl report, and used by repl reset --stale.
"""

from __future__ import annotations

import hashlib
import subprocess

from . import paths

# fastata's sources: a change here (uncommitted) makes the commit -dirty
SOURCES = ("stata", "src", "c", "Cargo.toml", "Cargo.lock", "build.rs")
UNKNOWN = "unknown"


def _git(*args: str) -> str | None:
    try:
        r = subprocess.run(["git", "-C", str(paths.REPO), *args], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


def plugin_hash() -> str:
    p = paths.FASTATA_STATA / "fastata.plugin"
    if not p.is_file():
        return UNKNOWN
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while b := f.read(1 << 20):
            h.update(b)
    return h.hexdigest()[:12]


def fastata_code() -> dict[str, str]:
    """{'commit': '<short sha>[-dirty]', 'plugin': '<sha256[:12]>'} of the fastata this checkout
    installs ('unknown' parts when there is no git repository or no built plugin)."""
    head = _git("rev-parse", "--short", "HEAD")
    if head is None:
        commit = UNKNOWN
    else:
        commit = head.strip()
        status = _git("status", "--porcelain", "--", *SOURCES)
        if status is None or status.strip():
            commit += "-dirty"
    return {"commit": commit, "plugin": plugin_hash()}


def label(code: dict | None) -> str:
    """'<commit> plugin <hash>', or 'unrecorded'."""
    if not code:
        return "unrecorded"
    return f"{code.get('commit', UNKNOWN)} plugin {code.get('plugin', UNKNOWN)}"


def is_stale(code: dict | None, current: dict[str, str]) -> bool:
    """True unless code is fully known and equal to current (commit and plugin hash)."""
    if not code or UNKNOWN in (code.get("commit"), code.get("plugin")):
        return True
    return code.get("commit") != current.get("commit") or code.get("plugin") != current.get("plugin")


def stale_arms(st: dict, current: dict[str, str]) -> list[str]:
    """The fastata arms (run_V, run_F) of package state st that ran with other code than
    current, or with no record of their code."""
    return [n for n in ("run_V", "run_F") if n in st["stages"] and is_stale(st["stages"][n].get("fastata"), current)]
