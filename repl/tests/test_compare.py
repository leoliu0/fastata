from repl.compare import cmp_text, file_verdict, kind_of, normalize, WRAPPER_ID
from repl.runner import log_region, run_failure, wrapper_text, aggregate_calls


def test_normalize():
    a = """      name:  <unnamed>
       log:  /data/pkgs/p/arm_A/out/x.log
 opened on:  15 Oct 2026, 22:41:07
r; t=0.52 22:41:08
   1:      3.21 /        1 =       3.2100
file /tmp/St12345.000001 saved
__000ABC
Running /x/_fxrepl_home/ado/personal/profile.do ...
"""
    b = a.replace("arm_A", "arm_F").replace("22:41:07", "09:01:02").replace("3.21", "4.50").replace(
        "St12345.000001", "St999.000002").replace("__000ABC", "__000XYZ").replace("15 Oct 2026", "16 Oct 2026")
    assert normalize(a, "/data/pkgs/p/arm_A") == normalize(b, "/data/pkgs/p/arm_F")
    assert "<RUN>/out/x.log" in normalize(a, "/data/pkgs/p/arm_A")


def test_cmp_text_numbers():
    assert cmp_text("b = 1.5\n", "b = 1.5\n", "", "")[0] == "SAME"
    assert cmp_text("b = 1.0000000000001\n", "b = 1.0000000000002\n", "", "")[0] == "NEAR"
    v, why = cmp_text("b = 1.0001\n", "b = 1.0002\n", "", "")
    assert v == "DIFF" and "reldif" in why
    assert cmp_text("b = 1\n", "c = 1\n", "", "")[0] == "DIFF"
    assert cmp_text("a\nb\n", "a\n", "", "")[0] == "DIFF"


def test_file_verdict():
    assert file_verdict(("SAME", ""), None) == "SAME"
    assert file_verdict(("NEAR", ""), None) == "NEEDB"
    assert file_verdict(("NEAR", ""), ("SAME", "")) == "NEAR"
    assert file_verdict(("DIFF", ""), ("SAME", "")) == "DIFF"
    assert file_verdict(("DIFF", ""), ("DIFF", "")) == "TIE"
    assert file_verdict(("DIFF", ""), ("NEAR", "")) == "TIE"
    assert file_verdict(("SKIP", ""), None) == "SKIP"


def test_kind_of():
    assert kind_of("a/b.DTA") == "dta"
    assert kind_of("x.png") == "skip"
    assert kind_of("t.tex") == "text"
    assert kind_of("t.xlsx") == "excel"
    assert kind_of("e.ster") == "bytes"
    assert kind_of(WRAPPER_ID) == "text"


def test_log_region_and_failure():
    log = ". di \"FX_REPL_BEGIN\"\nFX_REPL_BEGIN\n. do x.do\n. egen a = sum(b)\n. di \"FX_REPL_DONE\"\nFX_REPL_DONE\n"
    assert log_region(log) == ". do x.do\n. egen a = sum(b)\n. di \"FX_REPL_DONE\"\n"
    bad = ". use x\nfile x.dta not found\nr(601);\n\nend of do-file\nr(601);\n"
    assert run_failure(bad) == "file x.dta not found r(601);"


def test_wrapper_text(tmp_path, monkeypatch):
    monkeypatch.setenv("FASTATA_REPL_ROOT", str(tmp_path))
    from pathlib import Path
    w = wrapper_text("dataverse-X", "F", Path("/r/arm_F/code/master.do"))
    assert 'cd `"/r/arm_F/code"\'' in w and "FX_REPL_NOT_ACTIVE" in w and "sortseed" not in w
    assert f'sysdir set PLUS `"{tmp_path}/pkgs/dataverse-X/_deps/plus/"\'' in w
    b = wrapper_text("dataverse-X", "B", Path("/r/arm_B/m.do"))
    assert "set sortseed 20261015" in b and "FX_REPL_NOT_ACTIVE" not in b


def test_aggregate_calls(tmp_path):
    p = tmp_path / "calls.csv"
    p.write_text("egen,fallback,not implemented\negen,fast,\nisid,fallback,string blanks, x\n")
    a = aggregate_calls(p)
    assert a["egen"]["fast"] == 1 and a["egen"]["fallback"] == 1
    assert a["isid"]["last_reason"] == "string blanks, x"
    assert a["xtile"]["fast"] == 0
