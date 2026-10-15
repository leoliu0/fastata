"""repl compare <pkg>: file verdicts for arm F against arm A (arm B decides tie dependence).

Compared: every file of an arm that the run created or changed (against the arm's pre-run
manifest; the harness's own _fxrepl* files and patched sources excluded), plus the package's
part of the wrapper log (between the FX_REPL_BEGIN and FX_REPL_DONE lines).

Pair comparison (X vs Y) gives SAME, NEAR or DIFF:
  text (.log .smcl .txt .tex .csv .md .html .rtf .xml)  normalised (dates, clock times, r; t=
      lines, timer list lines, the arm directory -> <RUN>, temporary names, banner and licence
      lines, Running ...profile.do), then exact -> SAME; same text apart from numbers that agree
      within reldif 1e-9 -> NEAR;
  .dta   Stata comparator (stata/_fxrepl_cmpdta.ado): strings and integers exact, float within
      1 ulp, double reldif <= 1e-9 is NEAR; data label, characteristics, notes, value labels;
  .xls/.xlsx  cells as text lines, compared as text;
  images, PDF, .gph  skipped and counted;
  anything else  bytes.
File verdict: SAME (F equals A), NEAR (F within tolerance of A and A equals B), TIE (A differs
from B: the file depends on sort tie order, F is not judged), DIFF (A equals B and F differs).
"""

from __future__ import annotations

import csv
import json
import re
import shutil
import tempfile
from pathlib import Path

from . import paths, runner, sandbox, state

TEXT_EXT = {".log", ".smcl", ".txt", ".tex", ".csv", ".md", ".html", ".htm", ".rtf", ".xml", ".out", ".tab"}
SKIP_EXT = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".eps", ".ps", ".svg", ".gph", ".wmf", ".emf", ".tif",
            ".tiff", ".bmp"}
EXCEL_EXT = {".xls", ".xlsx"}
TOL = 1e-9
WRAPPER_ID = "<wrapper log>"

_MONTHS = "jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"
_NORMS = [
    # fastata's runtime directory on the ado-path (adopath listings), and the listing's numbers
    (re.compile(r"^\s*\[\d+\]\s+\"[^\"\n]*/fastata/\"[ \t]*\n", re.M), ""),
    (re.compile(r"^(\s*)\[\d+\](\s+(?:\([A-Z]+\))?\s*\")", re.M), r"\1[#]\2"),
    (re.compile(r"^Running .*profile\.do.*$", re.M), ""),
    (re.compile(r"^.*\br; t=.*$", re.M), "<RTIME>"),
    (re.compile(r"^\s*\d+:\s+[\d.]+\s*/\s+\d+\s*=\s+[\d.]+\s*$", re.M), "<TIMER>"),
    (re.compile(r"^.*(?:Stata license:|Serial number:|Licensed to:|StataCorp LLC|StataNow \d|Copyright 1985-).*$", re.M), "<BANNER>"),
    (re.compile(r"\b\d{1,2}\s+(?:" + _MONTHS + r")[a-z]*\.?,?\s+\d{4}\b", re.I), "<DATE>"),
    (re.compile(r"\b(?:" + _MONTHS + r")[a-z]*\.?\s+\d{1,2},?\s+\d{4}\b", re.I), "<DATE>"),
    (re.compile(r"\b\d{1,2}(?:" + _MONTHS + r")\d{4}\b", re.I), "<DATE>"),
    (re.compile(r"\b\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?\b"), "<DATE>"),
    (re.compile(r"\b\d{1,2}/\d{1,2}/\d{2,4}\b"), "<DATE>"),
    (re.compile(r"\b(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\b", re.I), "<DAY>"),
    (re.compile(r"\b\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:\s?[AaPp][Mm])?\b"), "<TIME>"),
    (re.compile(r"\bSt\d+\.\d+\b"), "<TMPFILE>"),
    (re.compile(r"\b__[0-9A-Z]{6}\b"), "<TMPNAME>"),
]
NUM_RE = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def normalize(text: str, run_root: str) -> str:
    text = text.replace("\r\n", "\n")
    text = re.sub(r"\n> ", "", text)  # Stata's continuation of long command lines
    if run_root:
        text = text.replace(run_root, "<RUN>")
    text = re.sub(r"arm_[ABF]\b", "arm_X", text)
    for pat, rep in _NORMS:
        text = pat.sub(rep, text)
    return text


def reldif(a: float, b: float) -> float:
    return abs(a - b) / (abs(b) + 1)


def cmp_text(x: str, y: str, root_x: str, root_y: str) -> tuple[str, str]:
    nx, ny = normalize(x, root_x), normalize(y, root_y)
    if nx == ny:
        return "SAME", ""
    px, py = NUM_RE.split(nx), NUM_RE.split(ny)
    if px != py:
        for i, (a, b) in enumerate(zip(nx.splitlines(), ny.splitlines())):
            if a != b:
                return "DIFF", f"line {i + 1}: {a.strip()[:80]!r} vs {b.strip()[:80]!r}"
        return "DIFF", "lengths differ"
    worst = 0.0
    for a, b in zip(NUM_RE.findall(nx), NUM_RE.findall(ny)):
        if a != b:
            try:
                worst = max(worst, reldif(float(a), float(b)))
            except ValueError:
                return "DIFF", f"token {a} vs {b}"
    if worst <= TOL:
        return "NEAR", f"numbers within reldif {worst:.2g}"
    return "DIFF", f"numbers differ (max reldif {worst:.2g})"


def excel_text(p: Path) -> str:
    lines = []
    if p.suffix.lower() == ".xlsx":
        import openpyxl

        wb = openpyxl.load_workbook(p, read_only=True, data_only=True)
        for ws in wb.worksheets:
            for row in ws.iter_rows():
                for c in row:
                    if c.value is not None:
                        lines.append(f"{ws.title}!{c.coordinate}\t{c.value!r}")
        wb.close()
    else:
        import xlrd

        wb = xlrd.open_workbook(str(p))
        for ws in wb.sheets():
            for r in range(ws.nrows):
                for c in range(ws.ncols):
                    v = ws.cell_value(r, c)
                    if v not in ("", None):
                        lines.append(f"{ws.name}!R{r + 1}C{c + 1}\t{v!r}")
    return "\n".join(lines) + "\n"


def kind_of(rel: str) -> str:
    """text, dta, excel (cells; text when the file is not a workbook), skip or bytes."""
    if rel == WRAPPER_ID:
        return "text"
    suf = Path(rel).suffix.lower()
    if suf in SKIP_EXT:
        return "skip"
    if suf == ".dta":
        return "dta"
    if suf in EXCEL_EXT:
        return "excel"
    if suf in TEXT_EXT:
        return "text"
    return "bytes"


def changed_files(pkg: str, arm: str) -> set[str]:
    man = json.loads((runner.results_dir(pkg) / f"arm_{arm}_manifest.json").read_text())
    pre, patched = man["files"], set(man.get("patched", []))
    post = runner.manifest(runner.arm_dir(pkg, arm))
    out = {k for k, v in post.items() if pre.get(k) != v}
    out |= {k for k in pre if k not in post}  # deleted by the run
    return out - patched


def _read_side(pkg: str, arm: str, rel: str) -> tuple[Path | None, str]:
    root = runner.arm_dir(pkg, arm)
    if rel == WRAPPER_ID:
        return root / runner.WRAPPER_LOG, str(root)
    p = root / rel
    return (p if p.exists() else None), str(root)


def cmp_dta_batch(pkg: str, pairs: list[tuple[str, Path, Path]]) -> dict[str, tuple[str, str]]:
    """Runs the Stata comparator on (id, fileX, fileY) pairs in the sandbox."""
    if not pairs:
        return {}
    work = Path(tempfile.mkdtemp(prefix="cmp_", dir=runner.results_dir(pkg)))
    try:
        (work / "pairs.txt").write_text("".join(f"{i}|{a}|{b}\n" for i, (_, a, b) in enumerate(pairs)))
        (work / "cmp.do").write_text(
            f'adopath + `"{paths.STATA_HELPERS}"\'\n'
            f'_fxrepl_cmpdta `"{work}/pairs.txt"\' `"{work}/out.csv"\'\n')
        sandbox.stata_batch(work / "cmp.do", cwd=work, home=work, rw=[work],
                            ro=[paths.pkg_dir(pkg), paths.STATA_HELPERS], timeout=3600)
        out: dict[str, tuple[str, str]] = {}
        if (work / "out.csv").exists():
            with open(work / "out.csv", newline="") as f:
                for row in csv.DictReader(f):
                    out[pairs[int(row["id"])][0]] = (row["verdict"], row["detail"])
        log = (work / "cmp.log").read_text(errors="replace") if (work / "cmp.log").exists() else ""
        for rel, _, _ in pairs:
            out.setdefault(rel, ("ERR", "comparator failed: " + runner.run_failure(log)))
        return out
    finally:
        shutil.rmtree(work, ignore_errors=True)


def compare_pairs(pkg: str, x: str, y: str, files: list[str]) -> dict[str, tuple[str, str]]:
    """Verdict SAME/NEAR/DIFF (or SKIP/ERR) per file for arm x against arm y."""
    out: dict[str, tuple[str, str]] = {}
    dta: list[tuple[str, Path, Path]] = []
    for rel in files:
        k = kind_of(rel)
        px, rx = _read_side(pkg, x, rel)
        py, ry = _read_side(pkg, y, rel)
        if k == "skip":
            out[rel] = ("SKIP", "")
            continue
        if px is None or py is None:
            out[rel] = ("SAME", "absent in both") if px is None and py is None else (
                "DIFF", f"only in arm {x if px else y}")
            continue
        try:
            if k == "dta":
                if px.read_bytes() == py.read_bytes():
                    out[rel] = ("SAME", "")
                else:
                    dta.append((rel, px, py))
            elif k == "text":
                tx = px.read_text(errors="replace")
                ty = py.read_text(errors="replace")
                if rel == WRAPPER_ID:
                    tx, ty = runner.log_region(tx) or "", runner.log_region(ty) or ""
                out[rel] = cmp_text(tx, ty, rx, ry)
            elif k == "excel":
                try:
                    tx, ty = excel_text(px), excel_text(py)
                except Exception:  # noqa: BLE001 - outreg2 and others write text or XML as .xls
                    tx, ty = px.read_text(errors="replace"), py.read_text(errors="replace")
                out[rel] = cmp_text(tx, ty, rx, ry)
            else:
                out[rel] = ("SAME", "") if px.read_bytes() == py.read_bytes() else ("DIFF", "bytes differ")
        except Exception as e:  # noqa: BLE001 - unreadable file
            out[rel] = ("ERR", f"{type(e).__name__}: {e}"[:200])
    out.update(cmp_dta_batch(pkg, dta))
    return out


def units(text: str, logish: bool) -> list[str]:
    """A normalised text split into command blocks (log output: each starts at a ". " command
    echo) or lines."""
    if not logish:
        return text.splitlines()
    out: list[str] = []
    for ln in text.splitlines():
        if ln.startswith(". ") or not out:
            out.append(ln)
        else:
            out[-1] += "\n" + ln
    return out


def three_way(rel: str, texts: dict[str, str], roots: dict[str, str]) -> tuple[str, str] | None:
    """File verdict from a unit-by-unit comparison of arms A, F and B, when all three have the
    same number of units: a unit that differs between A and B is a tie unit; F is judged on the
    other units. None when the units do not line up."""
    logish = rel == WRAPPER_ID or Path(rel).suffix.lower() in (".log", ".smcl")
    u = {k: units(normalize(t, roots[k]), logish) for k, t in texts.items()}
    if not (len(u["A"]) == len(u["F"]) == len(u["B"])):
        return None
    ties = near = 0
    for i, (a, f, b) in enumerate(zip(u["A"], u["F"], u["B"])):
        if a == f:
            continue
        if a != b:
            ties += 1
            continue
        v, why = cmp_text(a + "\n", f + "\n", "", "")
        if v == "DIFF":
            return "DIFF", f"unit {i + 1} of {len(u['A'])} ({a.splitlines()[0][:60]!r}): {why}"
        near += v == "NEAR"
    if near:
        return "NEAR", f"{near} unit(s) within tolerance, {ties} tie unit(s)"
    return ("TIE", f"{ties} of {len(u['A'])} units differ between A and B; F equals A elsewhere") if ties else ("SAME", "")


def file_verdict(af: tuple[str, str], ab: tuple[str, str] | None) -> str:
    """Combines A-vs-F and A-vs-B pair verdicts into SAME, NEAR, TIE, DIFF, SKIP or NEEDB."""
    v = af[0]
    if v in ("SAME", "SKIP"):
        return v
    if ab is None:
        return "NEEDB"
    if ab[0] != "SAME":
        return "TIE"
    return "NEAR" if v == "NEAR" else "DIFF"


def compare(pkg: str, force: bool = False) -> dict:
    """Compares arms A and F (B when present). Returns the stage record; NEEDB if B is needed."""
    if not force and state.done(pkg, "compare"):
        return state.stage(pkg, "compare") or {}
    if not (state.ok(pkg, "run_A") and state.ok(pkg, "run_F")):
        return {"ok": False, "reason": "arms A and F have not both finished"}
    if not (runner.arm_dir(pkg, "A").exists() and runner.arm_dir(pkg, "F").exists()):
        return {"ok": False, "reason": "arm directories are gone (deleted after comparing); "
                "rerun with repl reset <pkg> --from run, then repl pipeline --only <pkg>"}
    have_b = state.ok(pkg, "run_B") and runner.arm_dir(pkg, "B").exists()
    files = changed_files(pkg, "A") | changed_files(pkg, "F") | {WRAPPER_ID}
    if have_b:
        files |= changed_files(pkg, "B")
    files_l = sorted(files)
    af = compare_pairs(pkg, "A", "F", files_l)
    pending = [f for f in files_l if af[f][0] not in ("SAME", "SKIP")]
    if pending and not have_b:
        return {"ok": False, "needb": True, "pending": len(pending)}
    ab = compare_pairs(pkg, "A", "B", pending) if pending else {}
    refined: dict[str, tuple[str, str]] = {}
    for f in pending:
        if kind_of(f) == "text" and ab[f][0] not in ("SAME", "ERR") and af[f][0] != "ERR":
            texts, roots = {}, {}
            for arm in "AFB":
                p, roots[arm] = _read_side(pkg, arm, f)
                texts[arm] = p.read_text(errors="replace") if p else ""
                if f == WRAPPER_ID:
                    texts[arm] = runner.log_region(texts[arm]) or ""
            r = three_way(f, texts, roots)
            if r:
                refined[f] = r
    rows = []
    counts = {k: 0 for k in ("SAME", "NEAR", "TIE", "DIFF", "SKIP", "ERR")}
    for f in files_l:
        v = refined[f][0] if f in refined else "ERR" if af[f][0] == "ERR" else file_verdict(af[f], ab.get(f))
        counts[v] += 1
        rows.append({"file": f, "verdict": v, "af": list(af[f]), "ab": list(ab[f]) if f in ab else None,
                     "units": refined[f][1] if f in refined else None})
    (runner.results_dir(pkg) / "compare.json").write_text(json.dumps(rows, indent=1))
    verdict = "PASS" if counts["DIFF"] == 0 and counts["ERR"] == 0 else "FAIL"
    return state.record(pkg, "compare", True, verdict=verdict, counts=counts,
                        notes=[r for r in rows if r["verdict"] in ("NEAR", "TIE", "DIFF", "ERR")][:50])
