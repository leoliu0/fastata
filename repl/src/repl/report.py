"""repl report: repl/RESULTS.md from every package's state.

The report is published, and package code (untrusted, and able to read any file the sandbox
shows it) decides what its outputs, logs and counts files contain. So the report carries no text
a package wrote: comparison details say what differs and where, not the differing lines; verify
mismatches are counted, not described; a failed run shows its return code, not the message
before it. The full details stay in each package's results/ and state.json. Repository metadata
(titles) and file names are reduced to one plain line.
"""

from __future__ import annotations

import re
import time
from collections import Counter
from pathlib import Path

from . import paths, provenance, state
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


def varm(st: dict) -> str:
    """The package's verification arm: the one its comparison used, else V when it ran."""
    a = (st["stages"].get("compare") or {}).get("arm")
    if a:
        return a
    return "V" if "run_V" in st["stages"] else "F"


def calls_of(st: dict) -> dict[str, dict]:
    return (st["stages"].get(f"run_{varm(st)}") or {}).get("counts", {})


def fastata_of(st: dict) -> dict | None:
    """The fastata code the package was verified with (compare record, else its arm's record)."""
    cm = st["stages"].get("compare") or {}
    return cm.get("fastata") or (st["stages"].get(f"run_{varm(st)}") or {}).get("fastata")


def is_counted(st: dict, count_on: str) -> bool:
    """Compared, and the verification arm made at least one fast call (count_on='fast') or any
    replaced-command call."""
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
    for name in ("fetch", "scan", "prepare", "run_A", "run_V", "run_F", "run_A2", "run_B", "compare"):
        r = s.get(name)
        if r is not None and not r.get("ok"):
            return f"{name}: {r.get('reason', '')}"
    return ""


def _fmt_s(x) -> str:
    return f"{x:.0f}" if isinstance(x, (int, float)) else ""


def _cell(s: str, n: int = 90) -> str:
    """Text for a table cell: one line, no Markdown or HTML markup characters, at most n chars."""
    s = re.sub(r"[\x00-\x1f\x7f]", " ", str(s))
    s = re.sub(r"[|`<>\[\]]", "/", s)
    return re.sub(r"\s+", " ", s).strip()[:n]


def _public_detail(s: str) -> str:
    """A comparison detail without the compared text: what differs and where (the lines
    themselves are in the package's results/compare.json)."""
    return _cell(re.split(r"['\"]", str(s), maxsplit=1)[0].rstrip(" :("), 120)


_RC_RE = re.compile(r"\br\((\d+)\);?$")


def _public_reason(stage: str, why: str) -> str:
    """A drop-out reason without text the package printed: a failed run shows its return code
    (the message line before it stays in state.json); the harness's own reasons stay."""
    if stage.startswith("run_"):
        m = _RC_RE.search(why.strip())
        if m:
            return f"r({m.group(1)})"
    return why


VKINDS = ("verify_ok", "verify_mismatch", "verify_skipped")
FILE_VERDICTS = ("SAME", "NEAR", "TIE", "NONDET", "DIFF", "SKIP", "ERR")


def render(count_on: str = "fast") -> str:
    sts = pkg_states()
    done = [s for s in sts if s["stages"].get("compare", {}).get("ok")]
    counted = [s for s in done if is_counted(s, count_on)]
    crit = "at least one fast call" if count_on == "fast" else "at least one replaced-command call (fast or fallback)"
    L = ["# fastata replication results", "",
         f"Generated {time.strftime('%Y-%m-%d %H:%M')} by `repl report`. Arms: A original commands; "
         "V fastata in verify mode (every fast call is checked against the original, which also decides "
         "the session state), compared strictly with A; A2 a second A run, for packages that are "
         "nondeterministic themselves (NONDET files). Packages compared with arm F (fastata as users "
         "run it, with tolerance; B = A with `set sortseed 20261015` for TIE files) are marked F.",
         f"A package counts when it was compared and its fastata arm made {crit}. A package fails on "
         "any DIFF or ERR file or any verify mismatch.", ""]
    vt = Counter()
    vv = Counter()
    for s in done:
        vt.update(s["stages"]["compare"].get("counts", {}))
    for s in counted:
        for v in calls_of(s).values():
            vv.update({k: v.get(k, 0) for k in VKINDS})
    ndiff = sum(s["stages"]["compare"].get("counts", {}).get("DIFF", 0) for s in counted)
    npass = sum(s["stages"]["compare"].get("verdict") == "PASS" for s in counted)
    L += ["## Totals", "",
          f"- counted packages: **{len(counted)}** (PASS {npass}, files with DIFF: {ndiff}, "
          f"verify mismatches: {vv['verify_mismatch']})",
          f"- verified calls (counted packages): ok {vv['verify_ok']}, mismatch {vv['verify_mismatch']}, "
          f"skipped {vv['verify_skipped']}",
          f"- compared packages: {len(done)}; packages tried: {len(sts)}",
          "- file verdicts (all compared packages): " + ", ".join(f"{k} {vt.get(k, 0)}" for k in FILE_VERDICTS)]
    cur = provenance.label(provenance.fastata_code())
    used = Counter(provenance.label(fastata_of(s)) for s in counted)
    L.append("- fastata the counted packages were verified with: "
             + ("; ".join(f"`{k}`: {n}" + (" (current)" if k == cur else "")
                          for k, n in sorted(used.items(), key=lambda kv: -kv[1])) or "none")
             + (" **(mixed)**" if len(used) > 1 else ""))
    L.append("")
    cov = Counter()
    tot: dict[str, Counter] = {c: Counter() for c in REPLACED}
    static_tot = Counter()
    for s in counted:
        for c, v in calls_of(s).items():
            if v.get("fast", 0) + v.get("fallback", 0):
                cov[c] += 1
            tot.setdefault(c, Counter()).update({k: v.get(k, 0) for k in ("fast", "fallback", *VKINDS)})
        static_tot.update((s["stages"].get("scan") or {}).get("calls", {}))
    L += ["## Replaced commands (counted packages)", "",
          "|command|packages|fast calls|fallback calls|verify ok|verify mismatch|verify skipped|call lines in source|",
          "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for c in REPLACED:
        t = tot[c]
        L.append(f"|`{c}`|{cov[c]}|{t['fast']}|{t['fallback']}|{t['verify_ok']}|{t['verify_mismatch']}|"
                 f"{t['verify_skipped']}|{static_tot[c]}|")
    L += ["", "## Packages", "",
          "|package|journal|year|DOI|title|arm|fastata|A s|arm s|arm/A|calls (fast/fallback)|verify ok/mismatch/skipped|"
          "SAME|NEAR|TIE|NONDET|DIFF|SKIP|verdict|",
          "|---|---|---|---|---|---|---|---:|---:|---:|---|---|---:|---:|---:|---:|---:|---:|---|"]
    for s in sorted(done, key=lambda s: s["pkg"]):
        i = s.get("info", {})
        arm = varm(s)
        a = (s["stages"].get("run_A") or {}).get("seconds")
        f = (s["stages"].get(f"run_{arm}") or {}).get("seconds")
        ratio = f"{f / a:.2f}" if a and f else ""
        cs = calls_of(s)
        calls = ", ".join(f"{c} {v.get('fast', 0)}/{v.get('fallback', 0)}" for c, v in sorted(cs.items()))
        ver = "/".join(str(sum(v.get(k, 0) for v in cs.values())) for k in VKINDS) if arm == "V" else ""
        cm = s["stages"]["compare"]
        k = cm.get("counts", {})
        title = _cell(i.get("title") or "")
        doi = i.get("doi", "")
        mark = "" if is_counted(s, count_on) else " (not counted)"
        L.append(f"|{s['pkg']}|{i.get('journal', '')}|{i.get('year', '')}|[{doi}](https://doi.org/{doi})|{title}|{arm}|"
                 f"{provenance.label(fastata_of(s))}|"
                 f"{_fmt_s(a)}|{_fmt_s(f)}|{ratio}|{calls}|{ver}|" + "|".join(str(k.get(x, 0)) for x in
                 ("SAME", "NEAR", "TIE", "NONDET", "DIFF", "SKIP")) + f"|{cm.get('verdict', '')}{mark}|")
    mism = Counter()
    for s in done:
        for m in s["stages"]["compare"].get("mismatches", []):
            mism[(s["pkg"], _cell(m.partition(":")[0], 20))] += 1
    L += ["", "## Verify mismatches", ""]
    if not mism:
        L.append("None.")
    else:
        L += ["|package|command|mismatches (details in the package's state.json)|", "|---|---|---:|"]
        L += [f"|{p}|{c}|{n}|" for (p, c), n in sorted(mism.items())]
    notes = [(s["pkg"], n) for s in done for n in s["stages"]["compare"].get("notes", [])]
    L += ["", "## NEAR, TIE, NONDET and DIFF files", ""]
    if not notes:
        L.append("None.")
    else:
        L += ["|package|file|verdict|A vs fastata arm|A vs A2 or B|", "|---|---|---|---|---|"]
        for pkg, n in notes:
            ab = n.get("ab") or ["", ""]
            L.append(f"|{pkg}|`{_cell(n['file'], 120)}`|{n['verdict']}|{n['af'][0]} {_public_detail(n['af'][1])}|"
                     f"{ab[0]} {_public_detail(ab[1])}|")
    excl = Counter()
    for s in sts:
        e = exclusion(s)
        if e:
            stage_name, _, why = e.partition(": ")
            why = _public_reason(stage_name, why)
            why = re.sub(r"\S*[/\\]\S*", "<path>", why)
            why = re.sub(r"\(\d+ vs \d+ lines\)", "", why)
            for part in why.split("; "):
                excl[f"{stage_name}: {_cell(part, 70)}"] += 1
    L += ["", "## Packages that dropped out", "", "|stage: reason|packages|", "|---|---:|"]
    for k, n in excl.most_common():
        L.append(f"|{k.replace('|', '/')}|{n}|")
    return "\n".join(L) + "\n"


def report(count_on: str = "fast", out: Path | None = None) -> Path:
    out = out or paths.results_md()
    out.write_text(render(count_on))
    return out
