"""Community-command dependencies, installed once per package into <pkg>/_deps/plus.

Installs run in a separate sandbox that has the network and can write only _deps. Sources:
the package's own ssc install / net install lines (static), then the names a failed arm A run
reports as missing (command X is unrecognized, unknown egen function, scheme not found, ...),
mapped to their SSC package where the name differs.
"""

from __future__ import annotations

import re
from pathlib import Path

import requests

from . import paths, sandbox
from .patching import read_latin1

# command or file name -> SSC packages that provide it (in install order)
KNOWN: dict[str, list[str]] = {
    "reghdfe": ["ftools", "require", "reghdfe"],
    "ivreghdfe": ["ftools", "require", "reghdfe", "ranktest", "ivreg2", "ivreghdfe"],
    "ppmlhdfe": ["ftools", "require", "reghdfe", "ppmlhdfe"], "ivreg2": ["ranktest", "ivreg2"],
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
FOREACH_LOCAL_RE = re.compile(r"\bforeach\s+(\w+)\s+of\s+(?:local|global)\s+(\w+)\s*\{", re.I)
LOCAL_LIST_RE = re.compile(r"^\s*(?:loc(?:al)?|gl(?:obal)?)\s+(\w+)\s+\"?([A-Za-z0-9_ ]+?)\"?\s*(?://.*)?$", re.I | re.M)

# commands that are not on SSC: (package, net site) to install them from
NET_HOMES: dict[str, list[tuple[str, str]]] = {
    "grc1leg": [("grc1leg", "http://www.stata.com/users/vwiggins")],
    "binscatter2": [("binscatter2", "https://raw.githubusercontent.com/mdroste/stata-binscatter2/master/")],
    "require": [("require", "https://raw.githubusercontent.com/sergiocorreia/stata-require/master/src/")],
    "reghdfe": [("reghdfe", "https://raw.githubusercontent.com/sergiocorreia/reghdfe/master/src/")],
    "ftools": [("ftools", "https://raw.githubusercontent.com/sergiocorreia/ftools/master/src/")],
    "multe": [("multe", "https://raw.githubusercontent.com/gphk-metrics/stata-multe/main/")],
}
WEBSEE = "https://www.stata.com/websee.cgi"


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
        lists = {m.group(1): m.group(2).split() for m in LOCAL_LIST_RE.finditer(t)}
        for m in FOREACH_LOCAL_RE.finditer(t):
            loops.setdefault(m.group(1), lists.get(m.group(2), []))
        last_from = None
        for line in t.splitlines():
            s = line.strip()
            if s.startswith(("*", "//")):
                continue
            m = NET_FROM_RE.search(s)
            if m:
                last_from = m.group(1) if m.group(1).lower().startswith(("http://", "https://")) else None
            for m in SSC_LOOP_RE.finditer(s):
                for name in loops.get(m.group(1), []):
                    add({"ssc": name.strip('"')})
            for m in SSC_RE.finditer(s):
                add({"ssc": m.group(1).strip('"')})
            m = NET_RE.search(s)
            if m:
                if m.group(2).strip().lower().startswith(("http://", "https://")):
                    add({"net": m.group(1), "from": m.group(2).strip()})
            elif last_from:
                m = NET_PLAIN_RE.search(s)
                if m:
                    add({"net": m.group(1), "from": last_from})
    return out


MISSING = [
    ("command", re.compile(r"^command (\S+) is unrecognized")),
    ("egen", re.compile(r"^unknown egen function (\w+)\(")),
    ("command", re.compile(r"^file (\S+?)\.ado not found")),
    ("scheme", re.compile(r"scheme-(\S+?)\.scheme not found")),
    ("scheme", re.compile(r"^scheme (\S+) not found")),
    ("command", re.compile(r"^class (\S+) not found")),
    ("mata", re.compile(r"\b(\w+)\(\) not found")),
    ("command", re.compile(r"[Mm]issing required (?:Stata |user-written |community-contributed )?"
                           r"(?:command|package|program)s?:?\s+(\w+)")),
    ("command", re.compile(r"^(?:error:\s*)?(\w+) (?:is )?not installed")),
    ("command", re.compile(r"[Pp]lease (?:ssc )?install (\w+)")),
    ("command", re.compile(r"\buses the (\w+) package\b")),
    ("command", re.compile(r"\brequires the (\w+) package\b")),
    ("command", re.compile(r"\bmust have (\w+) version\b")),
    ("command", re.compile(r"\b(?:type|run)\s*:?\s*`?ssc inst(?:all)? (\w+)")),
    ("command", re.compile(r"[Rr]equired (?:command|package|program) '?(\w+)'? (?:not found|is not installed|missing)")),
]
NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,31}$")


def missing_names(log_text: str) -> list[tuple[str, str]]:
    """(kind, name) for every dependency a Stata log reports as missing; kind is command, egen,
    scheme or mata."""
    out = []
    for ln in log_text.splitlines():
        for kind, pat in MISSING:
            m = pat.search(ln.strip())
            if m and NAME_RE.match(m.group(1)) and (kind, m.group(1)) not in out:
                out.append((kind, m.group(1)))
    return out


def packages_for(name: str, kind: str = "command") -> list[str]:
    """SSC packages to install, in order, for a missing name (a best first guess)."""
    if kind == "egen":
        return KNOWN.get(f"egen_{name}", ["egenmore"])
    if kind == "mata" and name.startswith("mm_"):
        return ["moremata"]
    return KNOWN.get(name, [name])


def websee(name: str) -> list[tuple[str, str]]:
    """(package, site) pairs Stata's own search (search <name>, net) lists, Stata Journal first;
    cached under cache/websee. Empty when the search fails."""
    cache = paths.cache_dir() / "websee" / f"{name}.txt"
    if cache.exists():
        text = cache.read_text()
    else:
        try:
            r = requests.get(WEBSEE, params={"r": 2, "s": "bds", "o": "w", "j": "a", "k": name}, timeout=30)
            r.raise_for_status()
            text = r.text
        except requests.RequestException:
            return []
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(text)
    return re.findall(r"@net:describe (\S+), from\(([^)]+)\)", text)


def check_cmd(kind: str, name: str) -> str:
    """A Stata command that succeeds once name is available."""
    if kind == "egen":
        return f"capture findfile _g{name}.ado"
    if kind == "scheme":
        return f"capture findfile scheme-{name}.scheme"
    if kind == "mata":
        return f"capture mata: mata which {name}()"
    return f"capture which {name}"


def ssc(name: str) -> dict:
    return {"ssc": name}


def resolution(kind: str, name: str, search: bool = True) -> dict:
    """{'label', 'check', 'alts'}: alternative install lists for a missing name, tried in order
    until the check succeeds: the known SSC packages, the name on SSC, known net sites, scheme
    package names, then what Stata's net search lists for the name."""
    alts: list[list[dict]] = []

    def add(items: list[dict]) -> None:
        if items and items not in alts:
            alts.append(items)

    add([ssc(p) for p in packages_for(name, kind)])
    if kind in ("command", "egen", "scheme"):
        add([ssc(name)])
    for pkg, site in NET_HOMES.get(name, []):
        pre = [ssc(p) for p in packages_for(name, kind)[:-1]]
        add(pre + [{"net": pkg, "from": site}])
    if kind == "scheme":
        for p in (f"scheme_{name}", f"scheme-{name}", "schemepack", "blindschemes"):
            add([ssc(p)])
    if search:
        for pkg, site in websee(name)[:6]:
            if not NAME_RE.match(pkg):
                continue
            item = ssc(pkg) if "fmwww.bc.edu/repec/bocode" in site.lower() else {"net": pkg, "from": site}
            add([item])
    return {"label": f"{kind}:{name}", "check": check_cmd(kind, name), "alts": alts}


def item_label(it: dict) -> str:
    return f"ssc:{it['ssc']}" if "ssc" in it else f"net:{it['net']}"


def item_cmd(it: dict) -> str:
    if "ssc" in it:
        return f"ssc install {it['ssc']}, replace"
    return f'net install {it["net"]}, from(`"{it["from"]}"\') replace'


def install_text(groups: list[dict], deps: Path) -> str:
    """Do-file that installs every group: alternatives in order until the group's check passes
    (no check: the last install's return code). Prints FXDEP <label> <alternative number|0>."""
    lines = [f'sysdir set PLUS `"{deps}/plus/"\'', f'sysdir set PERSONAL `"{deps}/personal/"\'',
             "set timeout1 120", "set timeout2 900"]
    for g in groups:
        lines.append('local fxok 0')
        for k, alt in enumerate(g["alts"], 1):
            lines.append("if !`fxok' {")
            lines += [f"\tcapture noisily {item_cmd(it)}" for it in alt]
            if g.get("check"):
                lines += ["\tcapture mata: mata mlib index", f"\t{g['check']}"]
            lines += [f"\tif !_rc local fxok {k}", "}"]
        lines.append(f'di "FXDEP {g["label"]} `fxok\'"')
    return "\n".join(lines) + "\n"


def install_groups(pkg: str, groups: list[dict], log=print) -> tuple[list[str], list[str]]:
    """Installs groups into <pkg>/_deps/plus in the network sandbox. Returns (installed item
    labels, labels of groups that failed)."""
    groups = [g for g in groups if g["alts"]]
    if not groups:
        return [], []
    deps = paths.pkg_dir(pkg) / "_deps"
    home = deps / "_home"
    for d in ("plus", "personal"):
        (deps / d).mkdir(parents=True, exist_ok=True)
    home.mkdir(parents=True, exist_ok=True)
    do = home / "install.do"
    do.write_text(install_text(groups, deps))
    sandbox.stata_batch(do, cwd=home, home=home, rw=[deps], network=True, timeout=1800)
    text = (home / "install.log").read_text(errors="replace") if (home / "install.log").exists() else ""
    ok, failed = [], []
    for g in groups:
        m = re.search(r"^FXDEP " + re.escape(g["label"]) + r" (\d+)$", text, re.M)
        k = int(m.group(1)) if m else 0
        if k:
            ok += [item_label(it) for it in g["alts"][k - 1]]
        else:
            failed.append(g["label"])
    log(f"{pkg}: installed {ok or 'nothing'}" + (f"; failed {failed}" if failed else ""))
    return ok, failed


def install(pkg: str, items: list[dict], log=print) -> tuple[list[str], list[str]]:
    """Installs items (each on its own, success = its return code)."""
    return install_groups(pkg, [{"label": item_label(it), "check": "", "alts": [[it]]} for it in items], log)
