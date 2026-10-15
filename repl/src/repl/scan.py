"""repl scan: replaced-command call counts, master do-file, eligibility."""

from __future__ import annotations

from collections import Counter
from pathlib import Path

from . import paths, state
from .stataparse import REPLACED, code_line_count, count_calls, find_master, logical_lines, read_text

OTHER_LANGS = (".r", ".m", ".py", ".jl")


def scan_tree(src: Path) -> dict:
    calls: Counter[str] = Counter()
    do_lines = 0
    other_lines = 0
    dofiles = []
    for p in sorted(src.rglob("*")):
        if not p.is_file():
            continue
        suf = p.suffix.lower()
        if suf in (".do", ".ado"):
            t = read_text(p)
            calls.update(count_calls(t))
            do_lines += len(logical_lines(t))
            if suf == ".do":
                dofiles.append(p)
        elif suf in OTHER_LANGS:
            try:
                other_lines += code_line_count(read_text(p))
            except OSError:
                pass
    master, how = find_master(src, dofiles)
    score = sum(calls.values())
    reasons = []
    if score < 1:
        reasons.append("no replaced-command call")
    if other_lines >= do_lines:
        reasons.append(f"dominated by other languages ({other_lines} vs {do_lines} lines)")
    if master is None:
        reasons.append(how)
    return {
        "calls": {c: calls.get(c, 0) for c in REPLACED},
        "score": score,
        "do_lines": do_lines,
        "other_lines": other_lines,
        "ndo": len(dofiles),
        "master": str(master.relative_to(src)) if master else "",
        "master_how": how,
        "eligible": not reasons,
        "reason": "; ".join(reasons),
    }


def scan(pkg: str, force: bool = False) -> dict:
    if not force and state.done(pkg, "scan"):
        return state.stage(pkg, "scan") or {}
    src = paths.pkg_dir(pkg) / "src"
    r = scan_tree(src)
    ok = r.pop("eligible")
    return state.record(pkg, "scan", ok, **r)
