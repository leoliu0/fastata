"""End to end through Stata and bwrap on tiny packages (skipped without stata-mp or bwrap).

pkg PASS: replaced commands, a .dta, a csv and a log; one .dta holds the arm directory (differs
between A and B, so TIE with arm F; between A and A2, so NONDET with arm V). pkg FAIL: one
variable is 1 only in the fastata arm, so DIFF. Arm V runs this repository's fastata in verify
mode; one package adds a verify mismatch line of its own, which must fail it.
"""

import shutil
from pathlib import Path

import pytest

from repl import paths, pipeline, provenance, report, scan, state

pytestmark = pytest.mark.skipif(not (shutil.which("stata-mp") and shutil.which("bwrap")),
                                reason="needs stata-mp and bwrap")

MASTER = r"""
global root "C:/Users/someone/Dropbox/proj"
sysuse auto, clear
egen double m = mean(price), by(foreign)
egen g = group(rep78)
isid make
duplicates report foreign
xtile q = price, nq(4)
tostring rep78, gen(rs)
destring rs, gen(rn)
save "$root/out/auto2.dta", replace
export delimited using "$root/out/auto2.csv", replace
log using "$root/out/log.txt", text replace
tab foreign q
log close
capture noisily file open fh using "{realhome}/fxrepl_probe.txt", write replace
clear
set obs 3
gen str200 where = c(pwd)
{extra}
save "$root/out/where.dta", replace
"""


def _pkg(root: Path, name: str, extra: str) -> str:
    src = root / "pkgs" / name / "src"
    (src / "code").mkdir(parents=True)
    (src / "out").mkdir()
    (src / "code" / "master.do").write_text(MASTER.format(realhome=Path.home(), extra=extra))
    state.set_info(name, source="dataverse", doi="10.0/x", journal="T", year="2026", title=name)
    state.record(name, "fetch", True)
    scan.scan(name)
    return name


@pytest.fixture
def root(tmp_path, monkeypatch):
    monkeypatch.setenv("FASTATA_REPL_ROOT", str(tmp_path))
    if not (paths.FASTATA_STATA / "fastata.linux64.plugin").exists():
        pytest.skip("plugin not built (bash scripts/build_plugin.sh)")
    return tmp_path


def test_two_packages(root, tmp_path):
    ok = _pkg(root, "dataverse-PASS", "")
    bad = _pkg(root, "dataverse-FAIL", 'gen isF = strpos(c(pwd), "arm_F") > 0\ndrop where')
    assert state.stage(ok, "scan")["calls"]["egen"] == 2

    r = pipeline.process(ok, arms=("A", "F"), log=lambda m: None)
    assert r["verdict"] == "PASS", r
    assert r["counts"]["TIE"] == 1 and r["counts"]["DIFF"] == 0 and r["counts"]["SAME"] >= 4, r["notes"]
    assert state.ok(ok, "run_B")  # needed for where.dta
    assert not (Path.home() / "fxrepl_probe.txt").exists()
    calls = state.stage(ok, "run_F")["counts"]
    n = {c: v["fast"] + v["fallback"] for c, v in calls.items()}
    assert n["egen"] == 2 and n["isid"] == 1 and n["destring"] == 1 and n["tostring"] == 1
    # the global root was patched to the arm
    meta = (root / "pkgs" / ok / "meta.yaml").read_text()
    assert "{ARM}" in meta
    assert not (root / "pkgs" / ok / "arm_F").exists()  # arms removed after compare, A pruned
    assert sorted(p.name for p in (root / "pkgs" / ok / "arm_A").rglob("*") if p.is_file()) == \
        ["_fxrepl_wrapper.log", "auto2.csv", "auto2.dta", "log.txt", "where.dta"]

    r2 = pipeline.process(bad, arms=("A", "F"), log=lambda m: None)
    assert r2["verdict"] == "FAIL" and r2["counts"]["DIFF"] == 1
    note = next(n for n in r2["notes"] if n["verdict"] == "DIFF")
    assert note["file"] == "out/where.dta" and "isF" in note["af"][1]

    # rerun: everything recorded, nothing runs again
    before = state.load(ok)
    pipeline.process(ok, arms=("A", "F"), log=lambda m: None)
    assert state.load(ok) == before

    md = report.render("calls")
    assert "counted packages: **2**" in md and "dataverse-FAIL" in md


MISMATCH_LINE = """
local f : env FASTATA_COUNTS
if `"`f'"' != "" {
    file open fhv using `"`f'"', write text append
    file write fhv "egen,verify_mismatch,injected: m differs" _n
    file close fhv
}
"""


@pytest.fixture
def no_verify(tmp_path, monkeypatch):
    """A copy of fastata's stata/ whose _fx mode rejects verify (an older fastata)."""
    d = tmp_path / "old_stata"
    shutil.copytree(paths.FASTATA_STATA, d)
    fx = (d / "_fx.ado").read_text()
    old = 'if !inlist("`mode\'", "auto", "original", "verify") {'
    if old not in fx:
        pytest.skip("unexpected _fx mode code")
    (d / "_fx.ado").write_text(fx.replace(old, 'if !inlist("`mode\'", "auto", "original") {'))
    monkeypatch.setattr(paths, "FASTATA_STATA", d)
    return d


def test_verify_arm(root):
    from repl import cli, runner

    ok = _pkg(root, "dataverse-VOK", "")
    bad = _pkg(root, "dataverse-VBAD", MISMATCH_LINE)
    r = pipeline.process(ok, log=lambda m: None)
    assert r.get("arm") == "V" and r["verdict"] == "PASS", (r, state.load(ok))
    assert r["counts"]["NONDET"] == 1 and r["counts"]["DIFF"] == 0, r["notes"]
    assert r["verify"]["verify_mismatch"] == 0 and r["verify"]["verify_ok"] >= 1, r["verify"]
    assert r["fastata"] == state.stage(ok, "run_V")["fastata"] == provenance.fastata_code()
    assert state.ok(ok, "run_A2") and not state.done(ok, "run_B")
    calls = state.stage(ok, "run_V")["counts"]
    assert calls["egen"]["fast"] + calls["egen"]["fallback"] == 2

    r2 = pipeline.process(bad, log=lambda m: None)
    assert r2["verdict"] == "FAIL" and r2["counts"]["DIFF"] == 0, r2
    assert r2["mismatches"] == ["egen: injected: m differs"]
    md = report.render("calls")
    assert "verify mismatches: 1" in md and "|dataverse-VBAD|egen: injected: m differs|" in md

    # verify again without rerunning arm A
    a_before = state.stage(ok, "run_A")
    cli.main(["reset", ok, "--from", "V"])
    assert state.stage(ok, "run_A") == a_before and not state.done(ok, "run_V") and not state.done(ok, "compare")
    r3 = pipeline.process(ok, log=lambda m: None)
    assert r3["verdict"] == "PASS" and state.stage(ok, "run_A") == a_before
    assert runner.has_arm(ok, "A")


def test_no_verify_mode(root, no_verify):
    """A fastata without verify mode: arm V fails and says so."""
    pkg = _pkg(root, "dataverse-NOV", "")
    r = pipeline.process(pkg, log=lambda m: None)
    assert r["reason"].startswith("arm V failed: fastata has no verify mode"), r
