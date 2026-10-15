from pathlib import Path

from repl.scan import scan_tree
from repl.stataparse import count_calls, do_targets, find_master, logical_lines


def test_comments_and_continuations():
    t = """* egen in a comment
egen a = mean(x) // egen trailing
/* egen
   isid id */ isid id
gen y = 1 ///
    + 2
// duplicates drop
local u "http://x.org" // fine
"""
    lines = logical_lines(t)
    assert lines[0].strip() == "egen a = mean(x)"
    assert lines[1].strip() == "isid id"
    assert "gen y = 1" in lines[2] and "+ 2" in lines[2]
    assert any("http://x.org" in ln for ln in lines)
    assert count_calls(t) == {"egen": 1, "isid": 1}


def test_prefixes():
    t = """bysort g (t): egen m = max(x)
cap noi duplicates drop id, force
qui by g: egen n = count(x)
quietly { 
  xtile q = x, nq(10)
}
foreach v of varlist a b { destring `v', replace }
cap tostring z, replace
egenx = 1
gen pctile = 1
by g: replace isid = 1
"""
    c = count_calls(t)
    assert c == {"egen": 2, "duplicates": 1, "xtile": 1, "destring": 1, "tostring": 1}


def test_nested_block_comments():
    assert count_calls("/* a /* b */ egen x = sum(y) */\nisid a\n") == {"isid": 1}


def test_do_targets():
    t = 'do "code/01 clean.do"\nrun code/02_est\nqui do `"x.do"\'\n'
    assert do_targets(t) == ["code/01 clean.do", "code/02_est", "x.do"]


def _tree(tmp: Path, files: dict[str, str]) -> Path:
    for rel, text in files.items():
        p = tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    return tmp


def test_master_by_readme(tmp_path):
    root = _tree(tmp_path, {
        "README.md": "## Instructions to Replicators\nRun `code/runme.do` in Stata.\n",
        "code/runme.do": "do a.do\n", "code/master.do": "", "code/a.do": "egen x = sum(y)\n"})
    m, how = find_master(root)
    assert m == root / "code/runme.do" and how == "README instructions"


def test_master_by_name_and_by_calls(tmp_path):
    root = _tree(tmp_path, {"x/0_master.do": "", "x/deep/main.do": "", "a.do": ""})
    assert find_master(root)[0] == root / "x/0_master.do"
    root2 = _tree(tmp_path / "two", {"run.do": 'do "s1.do"\ndo s2\n', "s1.do": "do s2\n", "s2.do": ""})
    m, how = find_master(root2)
    assert m == root2 / "run.do" and how == "runs 2 do-files"


def test_scan_tree(tmp_path):
    root = _tree(tmp_path, {"main.do": "egen a = group(b)\nisid a\n", "x.R": "a <- 1\n",
                            "helpers/my.ado": "program my\n duplicates report\nend\n"})
    r = scan_tree(root)
    assert r["eligible"] and r["score"] == 3 and r["master"] == "main.do"
    assert r["calls"]["duplicates"] == 1
    root2 = _tree(tmp_path / "r", {"main.do": "egen a = group(b)\n", "a.R": "x\ny\nz\n"})
    r2 = scan_tree(root2)
    assert not r2["eligible"] and "dominated" in r2["reason"]
