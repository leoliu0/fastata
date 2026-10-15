"""repl report: repl/RESULTS.md from every package's state (no data or log content)."""

from __future__ import annotations

import re
import time
from collections import Counter
from pathlib import Path

from . import paths, state
from .stataparse import REPLACED


def pkg_states() -> list[dict]:
    d = paths.pkgs_dir()
    if not d.exists():
        return []
    out = []
    for p in sorted(d.iterdir()):
        if (p / "state.json").exists():
            out.append(state.load(p.name))
    return out


def calls_of(st: dict) -> dict[str, dict]:
    return (st["stages"].get("run_F") or {}).get("counts", {})


def is_counted(st: dict, count_on: str) -> bool:
    """Compared, and arm F made at least one fast call (count_on='fast') or any replaced call."""
    if not st["stages"].get("compare", {}).get("ok"):
        return False
    c = calls_of(st)
    if count_on == "fast":
        return any(v.get("fast", 0) > 0 for v in c.values())
    return any(v.get("fast", 0) + v.get("fallback", 0) > 0 for v in c.values())


def exclusion(st: dict) -> str | None:
    """Why a package dropped out ('' while unfinished), None if it was compared."""
    s = st["stages"]
    if s.get("compare", {}).get("ok"):
        return None
    for name in ("fetch", "scan", "prepare", "run_A", "run_F", "run_B"):
        r = s.get(name)
        if r is not None and not r.get("ok"):
            return f"{name}: {r.get('reason', '')}"
    return ""


def _fmt_s(x) -> str:
    return f"{x:.0f}" if isinstance(x, (int, float)) else ""


def render(count_on: str = "fast") -> str:
    sts = pkg_states()
    done = [s for s in sts if s["stages"].get("compare", {}).get("ok")]
    counted = [s for s in done if is_counted(s, count_on)]
    crit = "at least one fast call" if count_on == "fast" else "at least one replaced-command call (fast or fallback)"
    L = ["# fastata replication results", "",
         f"Generated {time.strftime('%Y-%m-%d %H:%M')} by `repl report`. Arms: A original commands, "
         "B original with `set sortseed 20261015`, F fastata (installed and enabled in the sandbox).",
         f"A package counts when it was compared and arm F made {crit}.", ""]
    vt = Counter()
    for s in done:
        vt.update(s["stages"]["compare"].get("counts", {}))
    ndiff = sum(s["stages"]["compare"].get("counts", {}).get("DIFF", 0) for s in counted)
    npass = sum(s["stages"]["compare"].get("verdict") == "PASS" for s in counted)
    L += ["## Totals", "",
          f"- counted packages: **{len(counted)}** (PASS {npass}, files with DIFF: {ndiff})",
          f"- compared packages: {len(done)}; packages tried: {len(sts)}",
          "- file verdicts (all compared packages): " + ", ".join(f"{k} {vt.get(k, 0)}" for k in
                                                                  ("SAME", "NEAR", "TIE", "DIFF", "SKIP", "ERR")),
          ""]
    cov = Counter()
    calls_tot: dict[str, list[int]] = {c: [0, 0] for c in REPLACED}
    static_tot = Counter()
    for s in counted:
        for c, v in calls_of(s).items():
            if v.get("fast", 0) + v.get("fallback", 0):
                cov[c] += 1
            calls_tot.setdefault(c, [0, 0])
            calls_tot[c][0] += v.get("fast", 0)
            calls_tot[c][1] += v.get("fallback", 0)
        static_tot.update((s["stages"].get("scan") or {}).get("calls", {}))
    L += ["## Replaced commands (counted packages)", "",
          "|command|packages|fast calls|fallback calls|call lines in source|", "|---|---:|---:|---:|---:|"]
    for c in REPLACED:
        L.append(f"|`{c}`|{cov[c]}|{calls_tot[c][0]}|{calls_tot[c][1]}|{static_tot[c]}|")
    L += ["", "## Packages", "",
          "|package|journal|year|DOI|title|A s|F s|F/A|calls (fast/fallback)|SAME|NEAR|TIE|DIFF|SKIP|verdict|",
          "|---|---|---|---|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---|"]
    for s in sorted(done, key=lambda s: s["pkg"]):
        i = s.get("info", {})
        a = (s["stages"].get("run_A") or {}).get("seconds")
        f = (s["stages"].get("run_F") or {}).get("seconds")
        ratio = f"{f / a:.2f}" if a and f else ""
        calls = ", ".join(f"{c} {v.get('fast', 0)}/{v.get('fallback', 0)}" for c, v in sorted(calls_of(s).items()))
        cm = s["stages"]["compare"]
        k = cm.get("counts", {})
        title = (i.get("title") or "").replace("|", "/")[:90]
        doi = i.get("doi", "")
        mark = "" if is_counted(s, count_on) else " (not counted)"
        L.append(f"|{s['pkg']}|{i.get('journal', '')}|{i.get('year', '')}|[{doi}](https://doi.org/{doi})|{title}|"
                 f"{_fmt_s(a)}|{_fmt_s(f)}|{ratio}|{calls}|{k.get('SAME', 0)}|{k.get('NEAR', 0)}|"
                 f"{k.get('TIE', 0)}|{k.get('DIFF', 0)}|{k.get('SKIP', 0)}|{cm.get('verdict', '')}{mark}|")
    notes = [(s["pkg"], n) for s in done for n in s["stages"]["compare"].get("notes", [])]
    L += ["", "## NEAR, TIE and DIFF files", ""]
    if not notes:
        L.append("None.")
    else:
        L += ["|package|file|verdict|A vs F|A vs B|", "|---|---|---|---|---|"]
        for pkg, n in notes:
            ab = n.get("ab") or ["", ""]
            L.append(f"|{pkg}|`{n['file']}`|{n['verdict']}|{n['af'][0]} {n['af'][1]}|{ab[0]} {ab[1]}|".replace("\n", " "))
    excl = Counter()
    for s in sts:
        e = exclusion(s)
        if e:
            stage_name, _, why = e.partition(": ")
            why = re.sub(r"\S*[/\\]\S*", "<path>", why)
            excl[f"{stage_name}: {why[:70]}"] += 1
    L += ["", "## Packages that dropped out", "", "|stage: reason|packages|", "|---|---:|"]
    for k, n in excl.most_common():
        L.append(f"|{k.replace('|', '/')}|{n}|")
    return "\n".join(L) + "\n"


def report(count_on: str = "fast", out: Path | None = None) -> Path:
    out = out or paths.RESULTS_MD
    out.write_text(render(count_on))
    return out
