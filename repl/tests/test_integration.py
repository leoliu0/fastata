"""End to end through Stata and bwrap on two tiny packages (skipped without stata-mp or bwrap).

pkg PASS: replaced commands, a .dta, a csv and a log; one .dta holds the arm directory (differs
between A and B, so TIE). pkg FAIL: one variable is 1 only in arm F, so DIFF.
"""

import shutil
from pathlib import Path

import pytest

from repl import paths, pipeline, report, scan, state

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

    r = pipeline.process(ok, log=lambda m: None)
    assert r["verdict"] == "PASS", r
    assert r["counts"]["TIE"] == 1 and r["counts"]["DIFF"] == 0 and r["counts"]["SAME"] >= 4
    assert state.ok(ok, "run_B")  # needed for where.dta
    assert not (Path.home() / "fxrepl_probe.txt").exists()
    calls = state.stage(ok, "run_F")["counts"]
    assert calls["egen"]["fallback"] == 2 and calls["isid"]["fallback"] == 1
    assert calls["destring"]["fallback"] == 1 and calls["tostring"]["fallback"] == 1
    # the global root was patched to the arm
    meta = (root / "pkgs" / ok / "meta.yaml").read_text()
    assert "{ARM}" in meta
    assert not (root / "pkgs" / ok / "arm_A").exists()  # arms removed after compare

    r2 = pipeline.process(bad, log=lambda m: None)
    assert r2["verdict"] == "FAIL" and r2["counts"]["DIFF"] == 1
    note = next(n for n in r2["notes"] if n["verdict"] == "DIFF")
    assert note["file"] == "out/where.dta" and "isF" in note["af"][1]

    # rerun: everything recorded, nothing runs again
    before = state.load(ok)
    pipeline.process(ok, log=lambda m: None)
    assert state.load(ok) == before

    md = report.render("calls")
    assert "counted packages: **2**" in md and "dataverse-FAIL" in md
