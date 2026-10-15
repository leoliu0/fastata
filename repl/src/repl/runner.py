"""repl run <pkg> --arm A|B|F: one run of the package's master do-file in the sandbox.

Arms
  A  the original commands: a fresh sandbox HOME, no fastata.
  B  as A with set sortseed 20261015: files that differ between A and B depend on sort tie order.
  F  fastata: net install from this repository's stata/ into the sandbox HOME's PLUS, fastata
     enable (writes the sandbox PERSONAL profile.do), off, on and status in a setup session; the
     package run is a new session, so fastata starts through profile.do as it would for a user.
     Every replaced-command call is recorded through FASTATA_COUNTS.

Each arm runs on its own copy of src (<pkg>/arm_<X>/) with meta.yaml's patches applied; the
harness's own files in the copy start with _fxrepl. Results go to <pkg>/results/.
"""

from __future__ import annotations

import csv
import json
import os
import re
import shutil
import subprocess
from collections import Counter
from pathlib import Path

from . import paths, sandbox, state
from .patching import apply_patches, load_meta
from .stataparse import REPLACED

HARNESS_PREFIX = "_fxrepl"
WRAPPER = "_fxrepl_wrapper.do"
WRAPPER_LOG = "_fxrepl_wrapper.log"
HOME = "_fxrepl_home"
CALLS = "_fxrepl_calls.csv"
PERSONAL = "_fxrepl_personal"
PLUS = "_fxrepl_plus"
TIMEOUT_MIN = {"A": 60, "B": 90, "F": 90}
SORTSEED = 20261015
PROCESSORS = 8
BEGIN, DONE = "FX_REPL_BEGIN", "FX_REPL_DONE"


def arm_dir(pkg: str, arm: str) -> Path:
    return paths.pkg_dir(pkg) / f"arm_{arm}"


def results_dir(pkg: str) -> Path:
    d = paths.pkg_dir(pkg) / "results"
    d.mkdir(parents=True, exist_ok=True)
    return d


def deps_dir(pkg: str) -> Path:
    return paths.pkg_dir(pkg) / "_deps"


def sq(s: str | Path) -> str:
    """A Stata compound-quoted string."""
    return f'`"{s}"\''


def manifest(root: Path) -> dict[str, list[int]]:
    """rel path -> [size, mtime_ns] for every file outside the harness's own entries."""
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        if rel_dir == ".":
            dirnames[:] = [d for d in dirnames if not d.startswith(HARNESS_PREFIX)]
        for f in filenames:
            if rel_dir == "." and f.startswith(HARNESS_PREFIX):
                continue
            p = Path(dirpath) / f
            try:
                st = p.lstat()
            except OSError:
                continue
            rel = f if rel_dir == "." else f"{rel_dir}/{f}"
            out[rel] = [st.st_size, st.st_mtime_ns]
    return out


def wrapper_text(pkg: str, arm: str, master: Path, cwd: Path | None = None) -> str:
    """The do-file each arm runs: PLUS is the arm's copy of the package's dependencies (packages
    install their own bundled ado-files there), PERSONAL a writable directory of the arm."""
    plus = arm_dir(pkg, arm) / PLUS
    personal = arm_dir(pkg, arm) / PERSONAL
    lines = [
        f"* fastata replication harness: arm {arm} of {pkg}",
        "clear all",
        "set more off",
        f"set processors {PROCESSORS}",
        f"sysdir set PLUS {sq(str(plus) + '/')}",
        f"sysdir set PERSONAL {sq(str(personal) + '/')}",
        "mata: mata mlib index",
    ]
    if arm == "B":
        lines.append(f"set sortseed {SORTSEED}")
    if arm == "F":
        lines += [
            "quietly findfile egen.ado",
            'if strpos(`"`r(fn)\'"\', "/fastata/") == 0 {',
            '\tdi as err "FX_REPL_NOT_ACTIVE: fastata did not start through profile.do"',
            "\texit 9",
            "}",
        ]
    lines += [
        f"cd {sq(cwd or master.parent)}",
        f'di "{BEGIN}"',
        f"do {sq(master)}",
        f'di "{DONE}"',
        "",
    ]
    return "\n".join(lines)


def setup_text() -> str:
    return "\n".join([
        f"net install fastata, from({sq(paths.FASTATA_STATA)}) replace",
        "fastata enable",
        "fastata off",
        "fastata on",
        "fastata status",
        "",
    ])


def log_region(text: str) -> str | None:
    """The package's part of a wrapper log: between the BEGIN and DONE output lines."""
    lines = text.splitlines()
    try:
        b = lines.index(BEGIN)
    except ValueError:
        return None
    try:
        e = len(lines) - 1 - lines[::-1].index(DONE)
    except ValueError:
        e = len(lines)
    return "\n".join(lines[b + 1:e]) + "\n"


def run_failure(text: str) -> str:
    """Why a wrapper log did not reach DONE: the first r(#); and the message line before it."""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    for i, ln in enumerate(lines):
        if re.fullmatch(r"r\(\d+\);", ln):
            return f"{lines[i - 1] if i else ''} {ln}".strip()[:300]
    return f"no {DONE} in the log"


def aggregate_calls(path: Path) -> dict[str, dict]:
    out: dict[str, dict] = {c: {"fast": 0, "fallback": 0, "last_reason": "", "reasons": Counter()} for c in REPLACED}
    if not path.exists():
        return out
    with open(path, newline="", errors="replace") as f:
        for row in csv.reader(f):
            if len(row) < 2:
                continue
            cmd, kind = row[0], row[1]
            why = ",".join(row[2:])
            d = out.setdefault(cmd, {"fast": 0, "fallback": 0, "last_reason": "", "reasons": Counter()})
            if kind == "fast":
                d["fast"] += 1
            else:
                d["fallback"] += 1
                d["last_reason"] = why
                d["reasons"][why] += 1
    return out


def write_counts_csv(agg: dict[str, dict], path: Path) -> None:
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["cmd", "fast", "fallback", "last_reason"])
        for cmd, d in agg.items():
            w.writerow([cmd, d["fast"], d["fallback"], d["last_reason"]])


def fresh_copy(pkg: str, arm: str) -> Path:
    src = paths.pkg_dir(pkg) / "src"
    dst = arm_dir(pkg, arm)
    if dst.exists():
        shutil.rmtree(dst)
    subprocess.run(["cp", "-a", str(src), str(dst)], check=True)
    return dst


def run_arm(pkg: str, arm: str, force: bool = False, log=print) -> dict:
    stage_name = f"run_{arm}"
    if not force and state.done(pkg, stage_name):
        return state.stage(pkg, stage_name) or {}
    meta = load_meta(pkg)
    if not meta.get("master"):
        return state.record(pkg, stage_name, False, reason="no master do-file")
    root = fresh_copy(pkg, arm)
    patched = apply_patches(root, meta)
    for d in meta.get("mkdirs", []):
        (root / d).mkdir(parents=True, exist_ok=True)
    (root / PERSONAL).mkdir()
    deps = deps_dir(pkg)
    (deps / "plus").mkdir(parents=True, exist_ok=True)
    subprocess.run(["cp", "-a", str(deps / "plus"), str(root / PLUS)], check=True)
    pre = manifest(root)
    res = results_dir(pkg)
    (res / f"arm_{arm}_manifest.json").write_text(json.dumps({"files": pre, "patched": patched}))
    home = root / HOME
    home.mkdir()
    ro = [paths.pkg_dir(pkg)]
    env: dict[str, str] = {}
    if arm == "F":
        if not (paths.FASTATA_STATA / "fastata.linux64.plugin").exists():
            return state.record(pkg, stage_name, False, reason="plugin not built (bash scripts/build_plugin.sh)")
        ro.append(paths.FASTATA_STATA)
        (home / "_fxrepl_setup.do").write_text(setup_text())
        r = sandbox.stata_batch(home / "_fxrepl_setup.do", cwd=home, home=home, rw=[root], ro=ro, timeout=600)
        slog = (home / "_fxrepl_setup.log").read_text(errors="replace") if (home / "_fxrepl_setup.log").exists() else ""
        if slog:
            shutil.copy2(home / "_fxrepl_setup.log", res / "arm_F_setup.log")
        if "fastata: enabled; Stata loads it at startup through" not in slog or "on now:      yes" not in slog:
            return state.record(pkg, stage_name, False, reason="fastata setup failed (see results/arm_F_setup.log)")
        env["FASTATA_COUNTS"] = str(root / CALLS)
    master = root / meta["master"]
    cwd = root / meta["cwd"] if meta.get("cwd") else master.parent
    (root / WRAPPER).write_text(wrapper_text(pkg, arm, master, cwd))
    log(f"{pkg}: arm {arm} running")
    r = sandbox.stata_batch(root / WRAPPER, cwd=root, home=home, rw=[root], ro=ro, env=env,
                            timeout=TIMEOUT_MIN[arm] * 60)
    wlog = root / WRAPPER_LOG
    text = wlog.read_text(errors="replace") if wlog.exists() else ""
    if wlog.exists():
        shutil.copy2(wlog, res / f"arm_{arm}.log")
    info: dict = {"seconds": round(r.seconds, 1)}
    if arm == "F":
        agg = aggregate_calls(root / CALLS)
        write_counts_csv(agg, res / "fastata_counts.csv")
        info["counts"] = {c: {"fast": d["fast"], "fallback": d["fallback"],
                              "reasons": dict(d["reasons"])} for c, d in agg.items() if d["fast"] or d["fallback"]}
    if r.timed_out:
        return state.record(pkg, stage_name, False, reason=f"timeout after {TIMEOUT_MIN[arm]} min", **info)
    if not any(ln == DONE for ln in text.splitlines()):
        return state.record(pkg, stage_name, False, reason=run_failure(text), **info)
    return state.record(pkg, stage_name, True, **info)


def remove_arms(pkg: str) -> None:
    for arm in "ABF":
        d = arm_dir(pkg, arm)
        if d.exists():
            shutil.rmtree(d, ignore_errors=True)
