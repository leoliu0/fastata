"""Which fastata ran each arm: the code record (commit, -dirty, plugin hash), its way into the
compare record and the report, and repl reset --stale."""

import hashlib
import json
import subprocess

import pytest

from repl import cli, compare, paths, provenance, report, runner, state


def _git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


@pytest.fixture
def repo(tmp_path, monkeypatch):
    """A fastata checkout: committed sources, a git-ignored built plugin."""
    r = tmp_path / "fastata"
    (r / "stata").mkdir(parents=True)
    (r / "src").mkdir()
    (r / "stata" / "_fx.ado").write_text("program _fx\nend\n")
    (r / "src" / "lib.rs").write_text("fn main() {}\n")
    (r / "README.md").write_text("readme\n")
    (r / ".gitignore").write_text("stata/*.plugin\n")
    (r / "stata" / "fastata.plugin").write_bytes(b"plugin v1")
    _git(r, "init", "-q")
    _git(r, "add", ".")
    _git(r, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
    monkeypatch.setattr(paths, "REPO", r)
    monkeypatch.setattr(paths, "FASTATA_STATA", r / "stata")
    return r


def _head(r):
    return subprocess.run(["git", "-C", str(r), "rev-parse", "--short", "HEAD"], capture_output=True,
                          text=True, check=True).stdout.strip()


def test_fastata_code_commit_dirty_and_plugin(repo):
    head = _head(repo)
    c = provenance.fastata_code()
    assert c == {"commit": head, "plugin": hashlib.sha256(b"plugin v1").hexdigest()[:12]}
    # a rebuilt plugin is git-ignored: same commit, other hash
    (repo / "stata" / "fastata.plugin").write_bytes(b"plugin v2")
    c2 = provenance.fastata_code()
    assert c2["commit"] == head and c2["plugin"] != c["plugin"]
    # files outside fastata's sources do not make it dirty
    (repo / "README.md").write_text("changed\n")
    assert provenance.fastata_code()["commit"] == head
    # a changed ado-file, or a new Rust source, does
    (repo / "stata" / "_fx.ado").write_text("program _fx\n di 1\nend\n")
    assert provenance.fastata_code()["commit"] == head + "-dirty"
    _git(repo, "checkout", "--", "stata/_fx.ado")
    assert provenance.fastata_code()["commit"] == head
    (repo / "src" / "new.rs").write_text("\n")
    assert provenance.fastata_code()["commit"] == head + "-dirty"


def test_fastata_code_unknown(tmp_path, monkeypatch):
    monkeypatch.setattr(paths, "REPO", tmp_path)  # no git repository, no plugin
    monkeypatch.setattr(paths, "FASTATA_STATA", tmp_path / "stata")
    c = provenance.fastata_code()
    assert c == {"commit": "unknown", "plugin": "unknown"}
    assert provenance.is_stale(c, c)  # unknown code never counts as current


def test_is_stale():
    cur = {"commit": "abc1234", "plugin": "0123456789ab"}
    assert not provenance.is_stale(dict(cur), cur)
    assert provenance.is_stale(None, cur)  # no record (arms run before records existed)
    assert provenance.is_stale({}, cur)
    assert provenance.is_stale({**cur, "commit": "def5678"}, cur)
    assert provenance.is_stale({**cur, "plugin": "ffffffffffff"}, cur)
    assert provenance.is_stale({**cur, "commit": "abc1234-dirty"}, cur)
    assert provenance.label(None) == "unrecorded"
    assert provenance.label(cur) == "abc1234 plugin 0123456789ab"


@pytest.fixture
def root(tmp_path, monkeypatch):
    monkeypatch.setenv("FASTATA_REPL_ROOT", str(tmp_path / "root"))
    return tmp_path / "root"


def _compared(pkg, code, arm="V", counts=None):
    """A package whose arms A and <arm> wrote the same out.txt (a fake run: no Stata)."""
    for a in ("A", arm):
        d = runner.arm_dir(pkg, a)
        d.mkdir(parents=True)
        (d / "out.txt").write_text("result 1.5\n")
        (runner.results_dir(pkg) / f"arm_{a}_manifest.json").write_text(json.dumps({"files": {}, "patched": []}))
        (d / runner.WRAPPER_LOG).write_text(f"{runner.BEGIN}\n. display 1\n1\n{runner.DONE}\n")
    state.set_info(pkg, journal="QJE", year="2026", doi="10.1/x", title=pkg)
    state.record(pkg, "fetch", True)
    state.record(pkg, "scan", True, calls={"egen": 1})
    state.record(pkg, "prepare", True)
    state.record(pkg, "run_A", True, seconds=10.0)
    rec = {"seconds": 12.0, "counts": counts or {"egen": {"fast": 2, "fallback": 0, "verify_ok": 2}}}
    if code is not None:
        rec["fastata"] = code
    state.record(pkg, f"run_{arm}", True, **rec)
    return compare.compare(pkg, arm=arm)


def test_compare_carries_code_and_report_shows_it(root, repo):
    cur = provenance.fastata_code()
    old = {"commit": "0000000", "plugin": "aaaaaaaaaaaa"}
    r = _compared("dataverse-P1", cur)
    assert r["verdict"] == "PASS" and r["fastata"] == cur
    assert _compared("dataverse-P2", cur)["fastata"] == cur
    assert _compared("dataverse-P3", old)["fastata"] == old
    assert _compared("dataverse-P4", None)["fastata"] is None
    md = report.render("fast")
    lab = provenance.label(cur)
    assert (f"- fastata the counted packages were verified with: `{lab}`: 2 (current); "
            "`0000000 plugin aaaaaaaaaaaa`: 1; `unrecorded`: 1 **(mixed)**") in md
    row = next(ln for ln in md.splitlines() if ln.startswith("|dataverse-P3|"))
    assert "|V|0000000 plugin aaaaaaaaaaaa|10|12|" in row
    assert "|V|unrecorded|" in next(ln for ln in md.splitlines() if ln.startswith("|dataverse-P4|"))


def test_report_single_code_not_mixed(root, repo):
    _compared("dataverse-P1", provenance.fastata_code())
    md = report.render("fast")
    assert "(current)" in md and "(mixed)" not in md


def test_reset_stale(root, repo, capsys):
    cur = provenance.fastata_code()
    _compared("dataverse-CUR", cur)
    _compared("dataverse-OLD", {**cur, "plugin": "bbbbbbbbbbbb"})
    _compared("dataverse-NOREC", None)
    _compared("dataverse-DIRTY", {**cur, "commit": cur["commit"] + "-dirty"})
    _compared("dataverse-F", {"commit": "1111111", "plugin": cur["plugin"]}, arm="F")
    state.record("dataverse-AONLY", "run_A", False, reason="r(601)")  # never reached a fastata arm
    before = {p: state.load(p) for p in ("dataverse-CUR", "dataverse-OLD")}

    cli.main(["reset", "--stale", "--dry-run"])
    out = capsys.readouterr().out
    assert f"current fastata: {provenance.label(cur)}" in out
    assert "would reset 4 package(s) from V" in out
    for p in ("dataverse-OLD", "dataverse-NOREC", "dataverse-DIRTY", "dataverse-F"):
        assert f"\n{p} run_V" in out
    assert "dataverse-CUR " not in out and "dataverse-AONLY" not in out
    assert "[run_V: unrecorded]" in out and "[run_F: 1111111 plugin" in out
    assert state.load("dataverse-OLD") == before["dataverse-OLD"]  # dry run: nothing changed

    cli.main(["reset", "--stale"])  # --from V by default
    assert "reset 4 package(s) from V" in capsys.readouterr().out
    for p in ("dataverse-OLD", "dataverse-NOREC", "dataverse-DIRTY", "dataverse-F"):
        s = state.load(p)["stages"]
        assert "run_V" not in s and "run_F" not in s and "compare" not in s and s["run_A"]["ok"], p
        assert runner.has_arm(p, "A") and not runner.arm_dir(p, "V").exists()
    assert state.load("dataverse-CUR") == before["dataverse-CUR"]
    # a package whose arm A outputs are gone reruns arm A as well
    _compared("dataverse-GONE", None)
    import shutil
    shutil.rmtree(runner.arm_dir("dataverse-GONE", "A"))
    cli.main(["reset", "--stale", "--dry-run"])
    assert "dataverse-GONE run_A run_V" in capsys.readouterr().out
