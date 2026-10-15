from pathlib import Path

from repl.deps import missing_names, packages_for, static_installs
from repl.patching import apply_patches, infer_patches, is_abs


def _tree(tmp: Path, files: dict[str, str]) -> Path:
    for rel, text in files.items():
        p = tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    return tmp


def test_is_abs():
    for v in ("C:/Users/x", "D:\\proj", "/Users/me/p", "~/Dropbox/x", "\\\\server\\share"):
        assert is_abs(v)
    for v in ("data/x", "$root/x", "..", "`c(pwd)'"):
        assert not is_abs(v)


def test_infer_root_global(tmp_path):
    src = _tree(tmp_path, {
        "Replication/code/master.do": (
            'global root "C:/Users/me/Dropbox/Replication"\n'
            'gl  out   D:\\results\n'
            'global n = 5\n'
            'use "$root/data/raw.dta"\n'
            'do "${root}/code/clean.do"\n'),
        "Replication/data/raw.dta": "", "Replication/code/clean.do": "save $out/x.dta\n"})
    pts = infer_patches(src, "Replication/code/master.do")
    by_old = {p["old"]: p for p in pts}
    assert by_old['global root "C:/Users/me/Dropbox/Replication"']["new"] == 'global root "{ARM}/Replication"'
    # $out has no resolvable references: the master's directory
    assert by_old["gl  out   D:\\results"]["new"] == 'gl  out   "{ARM}/Replication/code"'
    assert len(pts) == 2


def test_infer_cd_and_installs(tmp_path):
    src = _tree(tmp_path, {
        "pkg/run.do": ('cd "/Users/me/project/pkg"\ndo "code/a.do"\nuse data/x.dta\n'
                       'cap ssc install reghdfe, replace\nnet install grc1leg, from("http://x.org/s")\n'
                       'foreach p in estout ftools {\n ssc install `p\'\n}\n'),
        "pkg/code/a.do": "", "pkg/data/x.dta": ""})
    pts = infer_patches(src, "pkg/run.do")
    olds = {p["old"]: p["new"] for p in pts}
    assert olds['cd "/Users/me/project/pkg"'] == 'cd "{ARM}/pkg"'
    assert olds["cap ssc install reghdfe, replace"] == "capture cap ssc install reghdfe, replace"
    assert olds['net install grc1leg, from("http://x.org/s")'].startswith("capture net install")
    st = static_installs(src)
    assert {"ssc": "reghdfe"} in st and {"ssc": "estout"} in st and {"ssc": "ftools"} in st
    assert {"net": "grc1leg", "from": "http://x.org/s"} in st


def test_apply_patches(tmp_path):
    arm = _tree(tmp_path / "pkgX" / "arm_A", {"m.do": 'global root "C:/x"\nuse "$root/d.dta"\n'})
    meta = {"patches": [{"file": "m.do", "old": 'global root "C:/x"', "new": 'global root "{ARM}"'}]}
    changed = apply_patches(arm, meta, pkg="pkgX")
    assert changed == ["m.do"]
    assert (arm / "m.do").read_text().startswith(f'global root "{arm}"')


def test_missing_names():
    log = ("command reghdfe is unrecognized\nr(199);\nunknown egen function nvals()\n"
           "(file scheme-plotplain.scheme not found)\n         mm_quantile():  3499  mm_quantile() not found\n")
    got = missing_names(log)
    assert ("command", "reghdfe") in got and ("egen", "nvals") in got
    assert ("command", "plotplain") in got and ("mata", "mm_quantile") in got
    assert packages_for("reghdfe") == ["ftools", "reghdfe"]
    assert packages_for("nvals", "egen") == ["egenmore"]
    assert packages_for("plotplain") == ["blindschemes"]
    assert packages_for("mm_quantile", "mata") == ["moremata"]
    assert packages_for("winsor2") == ["winsor2"]


def test_placeholder_and_empty_globals(tmp_path):
    from repl.patching import infer_cwd

    src = _tree(tmp_path, {
        "Replication Package/00_master.do": (
            'global root "[SET_YOUR_PATH]/Replication Package"\n'
            'global DAT "$root/outputs/datasets"\n'
            'do "$root/scripts/clean.do"\n'),
        "Replication Package/scripts/clean.do": "",
        "Replication Package/outputs/datasets/x.dta": "",
        "code/config.do": 'global data_final ""\nglobal stem "data/raw"\nglobal up ".."\n',
        "code/fig1.do": 'use "${data_final}pastfuture.dta"\nuse "$stem/a.dta"\ndo "$up/x.do"\n',
        "data/final/pastfuture.dta": "", "data/raw/a.dta": ""})
    pts = {p["old"]: p for p in infer_patches(src, "Replication Package/00_master.do")}
    assert pts['global root "[SET_YOUR_PATH]/Replication Package"']["new"] == 'global root "{ARM}/Replication Package"'
    assert pts['global data_final ""']["new"] == 'global data_final "{ARM}/data/final/"'
    # $DAT holds a macro; stem exists relative to the package root; .. from code/ is the root
    assert 'global DAT "$root/outputs/datasets"' not in pts
    assert infer_cwd(src, "Replication Package/00_master.do") == "Replication Package"


def test_relative_global_kept_from_cwd(tmp_path):
    src = _tree(tmp_path, {"code/master.do": 'global up ".."\ndo "$up/code/a.do"\n', "code/a.do": ""})
    assert infer_patches(src, "code/master.do", cwd="code") == []


def test_user_switch_and_tools(tmp_path):
    src = _tree(tmp_path, {"m.do": (
        'if "`c(username)\'" == "jdoe" {\n  global root "C:/x"\n}\n'
        'else if c(username) == "bob" {\n  global root "/y"\n}\n'
        'else {\n  di as err "Username not recognized"\n  exit 1\n}\n'
        'use "$root/d.dta"\ngtools, upgrade\n'), "d.dta": ""})
    olds = {p["old"]: p for p in infer_patches(src, "m.do")}
    assert olds['if "`c(username)\'" == "jdoe" {']["new"] == "if 1 {"
    assert 'else if c(username) == "bob" {' not in olds
    assert olds["gtools, upgrade"]["new"] == "capture gtools, upgrade"


def test_backslashes(tmp_path):
    from repl.patching import fix_backslashes

    assert fix_backslashes('use "$root\\data\\x.dta", clear') == 'use "$root/data/x.dta", clear'
    assert fix_backslashes("do code\\1_prep.do") == "do code/1_prep.do"
    assert fix_backslashes('cd "..\\out"') == 'cd "../out"'
    assert fix_backslashes('local s "\\hline"') == 'local s "\\hline"'
    assert fix_backslashes('esttab using x.tex, prehead("\\begin{table}" "a \\\\")') == \
        'esttab using x.tex, prehead("\\begin{table}" "a \\\\")'
    assert fix_backslashes('replace x = subinstr(x, "a\\b", "", .)') == 'replace x = subinstr(x, "a\\b", "", .)'
    assert fix_backslashes('save "$out\\`f\'.dta"') == 'save "$out\\`f\'.dta"'
    src = _tree(tmp_path, {"m.do": 'mata:\nx = (1 \\ 2)\nend\nuse "data\\x.dta"\n', "data/x.dta": ""})
    pts = infer_patches(src, "m.do")
    assert [p["new"] for p in pts] == ['use "data/x.dta"']


def test_more_missing_names():
    got = missing_names("Missing required Stata command: reghdfe. Install it.\nftools not installed\n"
                        "please install `x'\n")
    assert ("command", "reghdfe") in got and ("command", "ftools") in got
    assert all(n != "`x'" for _, n in got)


def test_local_net_install_kept(tmp_path):
    src = _tree(tmp_path, {"m.do": ('net install mytool, from("$root/ado") replace\n'
                                    'net from "ado"\nnet install x, from(https://a.org/s)\n')})
    olds = {p["old"]: p["new"] for p in infer_patches(src, "m.do")}
    assert list(olds) == ["net install x, from(https://a.org/s)"]
    assert static_installs(src) == [{"net": "x", "from": "https://a.org/s"}]
