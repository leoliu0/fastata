"""repl prepare <pkg>: meta.yaml (master, run directory, patches, dependencies, directories).

Writes meta.yaml, installs the package's own ssc/net install targets into <pkg>/_deps/plus, then
runs arm A and repairs what its log reports, rerunning arm A after each repair (up to
MAX_ROUNDS runs):
  - a missing community command, egen function, scheme or Mata function: installed from SSC;
  - a directory the package writes into but does not ship (Dataverse and zip files drop empty
    directories): created in every arm's copy (meta.yaml mkdirs).
The last arm A run is the package's arm A result.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

from . import deps, paths, runner, state
from .patching import infer_cwd, infer_patches, load_meta, save_meta

MAX_ROUNDS = 8

_WRITE_FAIL = [
    re.compile(r"\bfile (.+?) could not be opened\b"),
    re.compile(r"\bfile (.+?) cannot be modified or erased\b"),
]
_DIR_FAIL = [
    re.compile(r"\bdirectory (.+?) not found\b"),
    re.compile(r"\bunable to change to (.+?)$"),
    re.compile(r"\bfolder (.+?) (?:does not exist|not found)\b"),
]


def unwrap(lines: list[str]) -> str:
    """Joins Stata's wrapped message lines: '> ' continues a token, an indent continues a line."""
    out = ""
    for ln in lines:
        s = ln.strip()
        if s.startswith("> "):
            out += s[2:]
        elif out:
            out += " " + s
        else:
            out = s
    return out


def failure_message(text: str) -> tuple[str, list[str]]:
    """(the message before the first r(#); unwrapped, the log lines before it). The message is
    the last line starting in column 0 with its indented continuation lines."""
    lines = text.splitlines()
    for i, ln in enumerate(lines):
        if re.fullmatch(r"r\(\d+\);.*", ln.strip()):
            j = i
            while j > 0 and lines[j - 1][:1].isspace():
                j -= 1
            if j > 0 and lines[j - 1].strip() and not lines[j - 1].startswith((". ", "> ")):
                j -= 1
            return unwrap(lines[j:i]), lines[:j]
    return "", lines


def current_dir(before: list[str], arm_root: Path, default: Path) -> Path:
    """The working directory at the failure: the last directory Stata printed after a cd."""
    root = str(arm_root)
    for k in range(len(before) - 1, -1, -1):
        s = before[k].strip()
        if s.startswith(root) and Path(s).is_dir():
            return Path(s)
    return default


def missing_dir(text: str, arm_root: Path, cwd: Path) -> str | None:
    """The package-relative directory a write failed for, if it does not exist."""
    msg, before = failure_message(text)
    if not msg:
        return None
    target = None
    for pat in _WRITE_FAIL:
        m = pat.search(msg)
        if m:
            target = m.group(1).strip().strip('"')
            target = os.path.dirname(target.replace("\\", "/").rstrip("/")) or "."
            break
    else:
        for pat in _DIR_FAIL:
            m = pat.search(msg)
            if m:
                target = m.group(1).strip().strip('"').replace("\\", "/")
                break
    if target is None:
        return None
    here = current_dir(before, arm_root, cwd)
    p = Path(os.path.normpath(target if os.path.isabs(target) else here / target))
    try:
        rel = p.relative_to(arm_root)
    except ValueError:
        return None
    if p.exists() or str(rel) == "." or rel.parts[0].startswith(runner.HARNESS_PREFIX):
        return None
    return str(rel)


def prepare(pkg: str, force: bool = False, log=print) -> dict:
    if not force and state.done(pkg, "prepare"):
        return state.stage(pkg, "prepare") or {}
    sc = state.stage(pkg, "scan") or {}
    if not sc.get("master"):
        return state.record(pkg, "prepare", False, reason="no master do-file")
    src = paths.pkg_dir(pkg) / "src"
    old = load_meta(pkg)
    cwd = infer_cwd(src, sc["master"])
    meta = {
        "master": sc["master"],
        "master_how": sc.get("master_how", ""),
        "cwd": cwd,
        "patches": infer_patches(src, sc["master"], cwd),
        "deps": old.get("deps", []),
        "mkdirs": [],
    }
    save_meta(pkg, meta)
    tried: set[str] = set(meta["deps"])
    static = [it for it in deps.static_installs(src)
              if (f"ssc:{it['ssc']}" if "ssc" in it else f"net:{it['net']}") not in tried]
    ok, failed = deps.install(pkg, static, log)
    meta["deps"] += ok
    tried |= set(ok) | set(failed)
    save_meta(pkg, meta)
    rounds = 0
    while True:
        rounds += 1
        a = runner.run_arm(pkg, "A", force=True, log=log)
        if a.get("ok") or rounds >= MAX_ROUNDS:
            break
        logp = runner.results_dir(pkg) / "arm_A.log"
        text = logp.read_text(errors="replace") if logp.exists() else ""
        arm = runner.arm_dir(pkg, "A")
        d = missing_dir(text, arm, arm / cwd)
        if d and d not in meta["mkdirs"]:
            log(f"{pkg}: creating missing directory {d}")
            meta["mkdirs"].append(d)
            save_meta(pkg, meta)
            continue
        want = []
        for kind, name in deps.missing_names(text):
            for p in deps.packages_for(name, kind):
                if f"ssc:{p}" not in tried and {"ssc": p} not in want:
                    want.append({"ssc": p})
        if not want:
            break
        ok, failed = deps.install(pkg, want, log)
        meta["deps"] += ok
        tried |= set(ok) | set(failed)
        save_meta(pkg, meta)
        if not ok:
            break
    return state.record(pkg, "prepare", True, rounds=rounds, deps=meta["deps"], mkdirs=meta["mkdirs"],
                        patches=len(meta["patches"]), arm_A_ok=bool(a.get("ok")))
