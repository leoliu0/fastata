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
