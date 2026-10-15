"""Community-command dependencies, installed once per package into <pkg>/_deps/plus.

Installs run in a separate sandbox that has the network and can write only _deps. Sources:
the package's own ssc install / net install lines (static), then the names a failed arm A run
reports as missing (command X is unrecognized, unknown egen function, scheme not found, ...),
mapped to their SSC package where the name differs.
"""

from __future__ import annotations

import re
from pathlib import Path

from . import paths, sandbox
from .patching import read_latin1

# command or file name -> SSC packages that provide it (in install order)
KNOWN: dict[str, list[str]] = {
    "reghdfe": ["ftools", "reghdfe"], "ivreghdfe": ["ftools", "reghdfe", "ranktest", "ivreg2", "ivreghdfe"],
    "ppmlhdfe": ["ftools", "reghdfe", "ppmlhdfe"], "ivreg2": ["ranktest", "ivreg2"],
    "xtivreg2": ["ranktest", "ivreg2", "xtivreg2"], "ivreg210": ["ivreg2"], "ivreg2_p": ["ivreg2"],
    "fcollapse": ["ftools"], "fegen": ["ftools"], "fisid": ["ftools"], "join": ["ftools"], "fmerge": ["ftools"],
    "esttab": ["estout"], "eststo": ["estout"], "estadd": ["estout"], "estpost": ["estout"],
    "estout": ["estout"], "estfe": ["estout"],
    "labmask": ["labutil"], "labvarch": ["labutil"],
    "csdid": ["drdid", "csdid"], "drdid": ["drdid"], "eventstudyinteract": ["avar", "eventstudyinteract"],
    "rdplot": ["rdrobust"], "rdbwselect": ["rdrobust"], "rddensity": ["lpdensity", "rddensity"],
    "colorpalette": ["palettes", "colrspace"], "heatplot": ["palettes", "colrspace", "heatplot"],
    "plotplain": ["blindschemes"], "plottig": ["blindschemes"], "plotplainblind": ["blindschemes"],
    "plottigblind": ["blindschemes"], "cleanplots": ["cleanplots"],
    "grc1leg": ["grc1leg"], "binscatter2": ["binscatter2"],
    "mm_quantile": ["moremata"], "mm_median": ["moremata"], "mm_cond": ["moremata"],
}
for _c in ("gcollapse gegen glevelsof gtoplevelsof gunique gdistinct gduplicates gisid greshape gquantiles "
           "gstats gcontract hashsort fasterxtile gtop gpercentile").split():
    KNOWN.setdefault(_c, ["gtools"])
for _f in ("nvals rowmedian rownvals rowsvals rall rany rcount record mixnorm xtile semean "
           "ewma filter").split():
    KNOWN.setdefault(f"egen_{_f}", ["egenmore"])

SSC_RE = re.compile(r"\bssc\s+inst(?:a(?:l(?:l)?)?)?\s+([^\s,`']+)", re.I)
SSC_LOOP_RE = re.compile(r"\bssc\s+inst(?:a(?:l(?:l)?)?)?\s+`(\w+)'", re.I)
NET_RE = re.compile(r"\bnet\s+inst(?:a(?:l(?:l)?)?)?\s+([^\s,`']+)\s*,[^\n]*?\bfrom\(\s*\"?([^\")]+)\"?\s*\)", re.I)
NET_FROM_RE = re.compile(r"\bnet\s+from\s+\"?([^\s\"]+)\"?", re.I)
NET_PLAIN_RE = re.compile(r"\bnet\s+inst(?:a(?:l(?:l)?)?)?\s+([^\s,`']+)", re.I)
FOREACH_RE = re.compile(r"\bforeach\s+(\w+)\s+in\s+([^{]+)\{", re.I)


def static_installs(src: Path) -> list[dict]:
    """[{'ssc': name} | {'net': name, 'from': url}] from the package's install lines."""
    out: list[dict] = []
    seen = set()

    def add(d: dict) -> None:
        name = d.get("ssc") or d.get("net") or ""
        if not NAME_RE.match(name):
            return
        k = tuple(sorted(d.items()))
        if k not in seen:
            seen.add(k)
            out.append(d)

    for p in sorted(src.rglob("*.do")):
        t = read_latin1(p)
        loops = {m.group(1): m.group(2).split() for m in FOREACH_RE.finditer(t)}
        last_from = None
        for line in t.splitlines():
            s = line.strip()
            if s.startswith(("*", "//")):
                continue
            m = NET_FROM_RE.search(s)
            if m:
                last_from = m.group(1)
            for m in SSC_LOOP_RE.finditer(s):
                for name in loops.get(m.group(1), []):
                    add({"ssc": name.strip('"')})
            for m in SSC_RE.finditer(s):
                add({"ssc": m.group(1).strip('"')})
            m = NET_RE.search(s)
            if m:
                add({"net": m.group(1), "from": m.group(2)})
            elif last_from:
                m = NET_PLAIN_RE.search(s)
                if m:
                    add({"net": m.group(1), "from": last_from})
    return out


MISSING = [
    ("command", re.compile(r"^command (\S+) is unrecognized")),
    ("egen", re.compile(r"^unknown egen function (\w+)\(")),
    ("command", re.compile(r"^file (\S+?)\.ado not found")),
    ("command", re.compile(r"scheme-(\S+?)\.scheme not found")),
    ("command", re.compile(r"^scheme (\S+) not found")),
    ("command", re.compile(r"^class (\S+) not found")),
    ("mata", re.compile(r"\b(\w+)\(\) not found")),
    ("command", re.compile(r"[Mm]issing required (?:Stata |user-written |community-contributed )?"
                           r"(?:command|package|program)s?:?\s+(\w+)")),
    ("command", re.compile(r"^(?:error:\s*)?(\w+) (?:is )?not installed")),
    ("command", re.compile(r"[Pp]lease (?:ssc )?install (\w+)")),
]
NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,31}$")


def missing_names(log_text: str) -> list[tuple[str, str]]:
    """(kind, name) for every dependency a Stata log reports as missing."""
    out = []
    for ln in log_text.splitlines():
        for kind, pat in MISSING:
            m = pat.search(ln.strip())
            if m and NAME_RE.match(m.group(1)) and (kind, m.group(1)) not in out:
                out.append((kind, m.group(1)))
    return out


def packages_for(name: str, kind: str = "command") -> list[str]:
    if kind == "egen":
        return KNOWN.get(f"egen_{name}", ["egenmore"])
    if kind == "mata" and name.startswith("mm_"):
        return ["moremata"]
    return KNOWN.get(name, [name])


def install(pkg: str, items: list[dict], log=print) -> tuple[list[str], list[str]]:
    """Installs items into <pkg>/_deps/plus in the network sandbox. Returns (ok, failed) labels."""
    if not items:
        return [], []
    deps = paths.pkg_dir(pkg) / "_deps"
    home = deps / "_home"
    for d in ("plus", "personal"):
        (deps / d).mkdir(parents=True, exist_ok=True)
    home.mkdir(parents=True, exist_ok=True)
    lines = [f'sysdir set PLUS `"{deps}/plus/"\'', f'sysdir set PERSONAL `"{deps}/personal/"\'']
    labels = []
    for it in items:
        if "ssc" in it:
            lab = f"ssc:{it['ssc']}"
            cmd = f"ssc install {it['ssc']}, replace"
        else:
            lab = f"net:{it['net']}"
            cmd = f'net install {it["net"]}, from(`"{it["from"]}"\') replace'
        labels.append(lab)
        lines += [f"capture noisily {cmd}", f'di "FXDEP {lab} " _rc']
    do = home / "install.do"
    do.write_text("\n".join(lines) + "\n")
    sandbox.stata_batch(do, cwd=home, home=home, rw=[deps], network=True, timeout=900)
    text = (home / "install.log").read_text(errors="replace") if (home / "install.log").exists() else ""
    ok, failed = [], []
    for lab in labels:
        m = re.search(r"^FXDEP " + re.escape(lab) + r" (\d+)$", text, re.M)
        (ok if m and m.group(1) == "0" else failed).append(lab)
    log(f"{pkg}: installed {ok or 'nothing'}" + (f"; failed {failed}" if failed else ""))
    return ok, failed
