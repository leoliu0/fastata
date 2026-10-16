from repl.compare import cmp_text, file_verdict, kind_of, normalize, three_way, WRAPPER_ID
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
    assert file_verdict(("NEAR", ""), None) == "NEEDREF"
    assert file_verdict(("NEAR", ""), ("SAME", ""), "NONDET", False) == "DIFF"
    assert file_verdict(("DIFF", ""), ("DIFF", ""), "NONDET", False) == "NONDET"
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
    assert f'sysdir set PLUS `"{tmp_path}/pkgs/dataverse-X/arm_F/_fxrepl_plus/"\'' in w
    assert "mata: mata mlib index" in w
    b = wrapper_text("dataverse-X", "B", Path("/r/arm_B/m.do"))
    assert "set sortseed 20261015" in b and "FX_REPL_NOT_ACTIVE" not in b


def test_aggregate_calls(tmp_path):
    p = tmp_path / "calls.csv"
    p.write_text("egen,fallback,not implemented\negen,fast,\nisid,fallback,string blanks, x\n")
    a = aggregate_calls(p)
    assert a["egen"]["fast"] == 1 and a["egen"]["fallback"] == 1
    p.write_text("egen,fast,\negen,verify_ok,\negen,verify_mismatch,m differs in 3 obs\n"
                 "isid,verify_skipped,too large\n")
    b = aggregate_calls(p)
    assert b["egen"]["verify_ok"] == 1 and b["egen"]["mismatches"] == ["m differs in 3 obs"]
    assert b["isid"]["skipped"] == {"too large": 1} and b["isid"]["fallback"] == 0
    assert a["isid"]["last_reason"] == "string blanks, x"
    assert a["xtile"]["fast"] == 0


def test_three_way():
    from repl.compare import three_way

    base = ". sum x\n  mean 1.5\n. sort g\n. list in 1\n  tie 7\n"
    t = {"A": base, "B": base.replace("tie 7", "tie 8"), "F": base}
    r = {"A": "", "B": "", "F": ""}
    assert three_way("x.log", t, r)[0] == "SAME"
    assert three_way("x.log", {**t, "F": base.replace("tie 7", "tie 9")}, r)[0] == "TIE"
    v, why = three_way("x.log", {**t, "F": base.replace("1.5", "1.6")}, r)
    assert v == "DIFF" and "sum x" in why
    assert three_way("x.log", {**t, "F": base.replace("1.5", "1.5000000000001")}, r)[0] == "NEAR"
    assert three_way("x.log", {**t, "F": base + ". extra\n"}, r) is None
    assert three_way("t.csv", {"A": "a,1\nb,2\n", "B": "a,1\nb,3\n", "F": "a,2\nb,2\n"}, r)[0] == "DIFF"
    # strict (arm V against A2): numbers within tolerance are a difference; A2 variation is NONDET
    tv = {"A": t["A"], "A2": t["B"], "V": base.replace("1.5", "1.5000000000001")}
    rv = {"A": "", "A2": "", "V": ""}
    assert three_way("x.log", tv, rv, "V", "A2", "NONDET", False)[0] == "DIFF"
    assert three_way("x.log", {**tv, "V": base.replace("tie 7", "tie 9")}, rv, "V", "A2", "NONDET", False)[0] == "NONDET"


def test_adopath_listing_normalised():
    """fastata's runtime directory is dropped from ado-path listings of fastata arms only, and
    the entries after it are renumbered, so the rest must match arm A exactly."""
    a = '. adopath\n  [1]  (BASE)      "/s/ado/base/"\n  [2]  (SITE)      "/s/site/"\n  [3]              "."\n'
    f = ('. adopath\n  [1]              "/r/arm_V/_fxrepl_home/ado/plus/fastata/"\n'
         '  [2]  (BASE)      "/s/ado/base/"\n  [3]  (SITE)      "/s/site/"\n  [4]              "."\n')
    assert normalize(f, "/r/arm_V", fastata=True) == normalize(a, "/r/arm_A")
    assert cmp_text(a, f, "/r/arm_A", "/r/arm_V", False, True)[0] == "SAME"
    # only in the fastata arm: arm A keeps such a line (and its numbering)
    assert normalize(f, "/r/arm_A") != normalize(a, "/r/arm_A")
    assert cmp_text(a, f, "/r/arm_A", "/r/arm_V")[0] == "DIFF"
    # the rest of the listing still has to match
    f2 = f.replace('"/s/site/"', '"/s/other/"')
    assert cmp_text(a, f2, "/r/arm_A", "/r/arm_V", False, True)[0] == "DIFF"
    f3 = f.replace("[4]", "[3]")  # numbering after the dropped entry is checked too
    assert cmp_text(a, f3, "/r/arm_A", "/r/arm_V", False, True)[0] == "DIFF"


def test_adopath_listing_wrapped_middle_and_repeated():
    """Text logs wrap the long runtime path with "> "; after adopath ++ the runtime directory
    is not first; a log can hold several listings."""
    a = ('. adopath ++ PLUS\n  [1]  (PLUS)      "/r/arm_A/ado/"\n  [2]  (BASE)      "/b/"\n'
         '  [3]              "."\n\n. adopath\n  [1]  (BASE)      "/b/"\n  [2]              "."\n')
    f = ('. adopath ++ PLUS\n  [1]  (PLUS)      "/r/arm_F/ado/"\n  [2]              "/r/arm_F/_fxrepl_\n'
         '> home/ado/plus/fastata/"\n  [3]  (BASE)      "/b/"\n  [4]              "."\n\n. adopath\n'
         '  [1]              "/r/arm_F/_fxrepl_home/ado/plus/fastata/"\n  [2]  (BASE)      "/b/"\n'
         '  [3]              "."\n')
    assert normalize(f, "/r/arm_F", fastata=True) == normalize(a, "/r/arm_A")


def test_adopath_listing_smcl():
    """zenodo-19562339: an SMCL log (line 833 of master_replication_log.smcl)."""
    a = ('{com}. adopath\n{txt}  [1]  (BASE)      "{res}/s/ado/base/{txt}"\n'
         '{txt}  [2]  (SITE)      "{res}/s/site/{txt}"\n{txt}  [3]              "{res}.{txt}"\n')
    # as Stata writes it: only the first entry carries {txt}
    a = ('{com}. adopath\n{txt}  [1]  (BASE)      "{res}/s/ado/base/{txt}"\n'
         '  [2]  (SITE)      "{res}/s/site/{txt}"\n  [3]              "{res}.{txt}"\n')
    f = ('{com}. adopath\n{txt}  [1]              "{res}/r/arm_V/_fxrepl_home/ado/plus/fastata/{txt}"\n'
         '  [2]  (BASE)      "{res}/s/ado/base/{txt}"\n  [3]  (SITE)      "{res}/s/site/{txt}"\n'
         '  [4]              "{res}.{txt}"\n')
    assert normalize(f, "/r/arm_V", fastata=True) == normalize(a, "/r/arm_A")
    assert normalize(f.replace("[3]  (SITE)", "[3]  (PLUS)"), "/r/arm_V", fastata=True) != normalize(a, "/r/arm_A")
    assert three_way("x.smcl", {"A": a, "A2": a, "V": f}, {"A": "/r/arm_A", "A2": "/r/arm_A2", "V": "/r/arm_V"},
                     "V", "A2", "NONDET", False)[0] == "SAME"



# macro list output from dataverse-6KG67M (arms A and V; Stata wraps the value at column 80)
SADO_A = (
    "eststo:         est1\n"
    "S_ADO:          `\"PLUS\"';`\"BASE\"';`\"SITE\"';`\".\"';`\"/home/leo/fastata-repl/pkgs/\n"
    "                > dataverse-6KG67M/arm_A/_fxrepl_plus/\"'\n"
    "adodir:         /home/leo/fastata-repl/pkgs/dataverse-6KG67M/arm_A/ado\n")
SADO_V = (
    "eststo:         est1\n"
    "S_ADO:          `\"PLUS\"';`\"/home/leo/fastata-repl/pkgs/dataverse-6KG67M/arm_V/_\n"
    "                > fxrepl_home/ado/plus/fastata/\"';`\"BASE\"';`\"SITE\"';`\".\"';`\"/ho\n"
    "                > me/leo/fastata-repl/pkgs/dataverse-6KG67M/arm_V/_fxrepl_plus/\n"
    "                > \"'\n"
    "adodir:         /home/leo/fastata-repl/pkgs/dataverse-6KG67M/arm_V/ado\n")
RA, RV = "/home/leo/fastata-repl/pkgs/dataverse-6KG67M/arm_A", "/home/leo/fastata-repl/pkgs/dataverse-6KG67M/arm_V"


def test_macro_list_joined_in_all_arms():
    """Continuation lines of a macro list value are joined (mid-word after "> ", at a dropped
    space without it), so values wrapped at different points compare; entries stay apart."""
    a = "zz:             a b c d e f g h i j k l m n o p q r s t u v w x y z aa bb cc dd\n                ee ff\n" \
        "verylongmacronamehere:\n                short\nS_ADO:          x;`\"/r/arm_A/lo\n                > ng/\"'\n"
    b = "zz:             a b c d e f g h i j k l m n o p q r s t u v w x y z aa bb cc dd ee\n                ff\n" \
        "verylongmacronamehere:\n                short\nS_ADO:          x;`\"/r/arm_A2/l\n                > ong/\"'\n"
    assert normalize(a, "/r/arm_A") == normalize(b, "/r/arm_A2")
    assert "dd ee ff" in normalize(a, "/r/arm_A") and "verylongmacronamehere:short" in normalize(a, "")
    assert cmp_text(a, b.replace("ff", "gg"), "/r/arm_A", "/r/arm_A2")[0] == "DIFF"
    # indented lines that do not follow a macro entry are left alone
    t = "Variable:  x\n                > y\n"
    assert normalize(t, "") == t


def test_sado_runtime_entry_dropped():
    assert normalize(SADO_V, RV, fastata=True) == normalize(SADO_A, RA)
    assert cmp_text(SADO_A, SADO_V, RA, RV, False, True)[0] == "SAME"
    assert cmp_text(SADO_A, SADO_V, RA, RV)[0] == "DIFF"  # only fastata arms lose the entry
    # the rest of the value still has to match
    assert cmp_text(SADO_A, SADO_V.replace('`"SITE"\';', ""), RA, RV, False, True)[0] == "DIFF"
    # first and last entry, bare form, and the SMCL layout (one line)
    for a, f in [("S_ADO:          BASE;SITE;.\n", "S_ADO:          /r/arm_V/_fxrepl_home/ado/plus/fastata/;BASE;SITE;.\n"),
                 ("S_ADO:          BASE;SITE\n", "S_ADO:          BASE;SITE;`\"/r/arm_V/_fxrepl_home/ado/plus/fastata/\"'\n"),
                 ("S_ADO:{space 10}{res}{res}`\"PLUS\"';`\"BASE\"'\n{p_end}\n",
                  "S_ADO:{space 10}{res}{res}`\"PLUS\"';`\"/r/arm_V/_fxrepl_home/ado/plus/fastata/\"';`\"BASE\"'\n{p_end}\n"),
                 ("S_ADO:{space 10}{res}{res}`\"BASE\"'\n{p_end}\n",
                  "S_ADO:{space 10}{res}{res}`\"/r/arm_V/_fxrepl_home/ado/plus/fastata/\"';`\"BASE\"'\n{p_end}\n")]:
        assert normalize(f, "/r/arm_V", fastata=True) == normalize(a, "/r/arm_A"), f


def test_creturn_adopath_masked():
    """creturn list cuts c(adopath) to a few characters (fastata's directory can be in them)."""
    a = '             c(adopath) = "BASE;SITE;.;P.."      (adopath)\n                 c(pwd) = "/r/arm_A"                (cd)\n'
    f = '             c(adopath) = "`"/r/arm_V/_fx.."      (adopath)\n                 c(pwd) = "/r/arm_V"                (cd)\n'
    assert cmp_text(a, f, "/r/arm_A", "/r/arm_V", False, True)[0] == "SAME"
    s = '             c(adopath) = "{res}PLUS"\';`"/home/le..{txt}"{col 54}({help adopath})\n'
    assert "<ADOPATH>" in normalize(s, "") and "/home/le" not in normalize(s, "")
    assert cmp_text(a, f.replace("(cd)", "(xx)"), "/r/arm_A", "/r/arm_V", False, True)[0] == "DIFF"
