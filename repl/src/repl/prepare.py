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
    re.compile(r"\bfolder path \[(.+?)\]"),
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
            while j > 0 and (lines[j - 1][:1].isspace() or lines[j - 1].startswith("> ")) \
                    and not _ECHO_RE.match(lines[j - 1]):
                j -= 1
            if j > 0 and lines[j - 1].strip() and not _ECHO_RE.match(lines[j - 1]) \
                    and not lines[j - 1].startswith("> "):
                j -= 1
            elif j < i and lines[j].startswith("> "):
                # only an echoed command's continuation lines: no message
                while j < i and lines[j].startswith("> "):
                    j += 1
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


_ECHO_RE = re.compile(r"^(?:\. |\s*\d+\.\s)")
_SAVE_FAIL = re.compile(r"unable to save|could not be saved|cannot be saved|unable to (?:open|create) file")
_TARGET_RE = re.compile(r"\b(?:export|saving\(|save|using)\s*(?:`\"|\")?([^\",)]+?)(?:\"'|\"|,|\)|$)")
_GLOBAL_ECHO_RE = re.compile(r"^\s*(?:\.|\d+\.)\s+gl(?:o(?:b(?:a(?:l)?)?)?)?\s+(\w+)\s+(?:=\s*)?(.*)$")


def echoed_commands(lines: list[str]) -> list[str]:
    """The commands echoed in log lines (". cmd" or "  N. cmd" in loops), continuations joined."""
    out: list[str] = []
    for ln in lines:
        if _ECHO_RE.match(ln):
            out.append(ln)
        elif ln.startswith("> ") and out:
            out[-1] += ln[2:]
    return out


def expand_globals(s: str, cmds: list[str]) -> str | None:
    """s with $name and ${name} replaced by the last values the echoed global commands gave;
    None if a macro is left."""
    vals: dict[str, str] = {}
    for c in cmds:
        m = _GLOBAL_ECHO_RE.match(c)
        if m:
            v = m.group(2).strip()
            if v.startswith('`"') and v.endswith("\"'"):
                v = v[2:-2]
            elif len(v) >= 2 and v[0] == v[-1] == '"':
                v = v[1:-1]
            vals[m.group(1)] = v
    for _ in range(6):
        new = re.sub(r"\$\{(\w+)\}|\$([A-Za-z_]\w*)", lambda m: vals.get(m.group(1) or m.group(2), m.group(0)), s)
        if new == s:
            break
        s = new
    return None if ("$" in s or "`" in s) else s


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
        else:
            if _SAVE_FAIL.search(msg):
                cmds = echoed_commands(before)
                mt = _TARGET_RE.search(re.sub(_ECHO_RE, "", cmds[-1], count=1)) if cmds else None
                path = expand_globals(mt.group(1).strip(), cmds) if mt else None
                if path:
                    target = os.path.dirname(path.replace("\\", "/").rstrip("/")) or "."
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


def fetch_urls(pkg: str, patches: list[dict], log=print) -> list[dict]:
    """Downloads the files patches read from the web into <pkg>/_deps/urls (the runs have no
    network); drops a patch whose download fails, so the line stays as the package wrote it."""
    from . import net
    from .patching import url_dest

    keep = []
    deps = paths.pkg_dir(pkg) / "_deps"
    for pt in patches:
        ok = True
        for url in pt.get("urls", []):
            dest = Path(url_dest(url).replace("{DEPS}", str(deps)))
            if dest.exists():
                continue
            try:
                net.download(url, dest)
            except Exception as e:  # noqa: BLE001 - the run then fails as it would have
                log(f"{pkg}: could not download {url}: {e}")
                ok = False
        if ok:
            keep.append(pt)
    return keep


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
    meta["patches"] = fetch_urls(pkg, meta["patches"], log)
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
        groups = []
        for kind, name in deps.missing_names(text):
            g = deps.resolution(kind, name)
            if g["label"] not in tried:
                groups.append(g)
                tried.add(g["label"])
        if not groups:
            break
        ok, failed = deps.install_groups(pkg, groups, log)
        meta["deps"] += [x for x in ok if x not in meta["deps"]]
        save_meta(pkg, meta)
        if not ok:
            break
    return state.record(pkg, "prepare", True, rounds=rounds, deps=meta["deps"], mkdirs=meta["mkdirs"],
                        patches=len(meta["patches"]), arm_A_ok=bool(a.get("ok")))
