"""What package code (untrusted) can make the harness do on the host: read through links it
leaves in arm directories, get text into the published report, or reach other processes from
the sandbox. Also: a sandbox that could not start Stata at all."""

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from repl import compare, deps, net, report, runner, safefs, sandbox, state

SECRET = "SECRET-7f3a"
HAVE_SANDBOX = bool(shutil.which("bwrap") and (os.environ.get("STATA") or shutil.which("stata-mp")))


@pytest.fixture
def root(tmp_path, monkeypatch):
    monkeypatch.setenv("FASTATA_REPL_ROOT", str(tmp_path / "root"))
    return tmp_path / "root"


def test_regular_file_refuses_links(tmp_path):
    secret = tmp_path / "secret.txt"
    secret.write_text(SECRET)
    (tmp_path / "outside").mkdir()
    (tmp_path / "outside" / "s.txt").write_text(SECRET)
    r = tmp_path / "arm"
    (r / "out").mkdir(parents=True)
    (r / "out" / "a.txt").write_text("ok")
    (r / "out" / "link.txt").symlink_to(secret)
    (r / "ldir").symlink_to(tmp_path / "outside")
    assert safefs.regular_file(r, "out/a.txt") == r / "out" / "a.txt"
    assert safefs.regular_file(r, "out/link.txt") is None and safefs.exists_nonregular(r, "out/link.txt")
    assert safefs.regular_file(r, "ldir/s.txt") is None  # a link on the way
    assert safefs.regular_file(r, "out") is None  # a directory
    assert safefs.regular_file(r, "../secret.txt") is None
    assert safefs.regular_file(r, "out/none.txt") is None and not safefs.exists_nonregular(r, "out/none.txt")
    assert safefs.read_text(r, "out/link.txt") == ""
    assert safefs.contained_dir(r, "a/b") == r / "a" / "b"
    assert safefs.contained_dir(r, "../a") is None and safefs.contained_dir(r, "/etc") is None


def test_compare_and_counts_never_read_through_links(root, tmp_path):
    secret = tmp_path / "secret.txt"
    secret.write_text(f"{SECRET}\n")
    pkg = "dataverse-LNK"
    for arm in ("A", "V"):
        d = runner.arm_dir(pkg, arm) / "out"
        d.mkdir(parents=True)
    (runner.arm_dir(pkg, "A") / "out" / "r.txt").write_text("result 1\n")
    (runner.arm_dir(pkg, "V") / "out" / "r.txt").symlink_to(secret)
    (runner.arm_dir(pkg, "A") / runner.WRAPPER_LOG).write_text(f"{runner.BEGIN}\n{runner.DONE}\n")
    (runner.arm_dir(pkg, "V") / runner.WRAPPER_LOG).symlink_to(secret)
    (runner.arm_dir(pkg, "V") / runner.CALLS).symlink_to(secret)
    got = compare.compare_pairs(pkg, "A", "V", ["out/r.txt", compare.WRAPPER_ID])
    assert got == {"out/r.txt": ("SKIP", compare.NONREG), compare.WRAPPER_ID: ("SKIP", compare.NONREG)}
    calls = runner.aggregate_calls(safefs.regular_file(runner.arm_dir(pkg, "V"), runner.CALLS))
    assert all(sum(v[k] for k in runner.KINDS) == 0 for v in calls.values())
    assert SECRET not in json.dumps(got) + json.dumps(calls, default=str)


def test_net_sites_validated(tmp_path, monkeypatch):
    src = tmp_path / "src"
    src.mkdir()
    (src / "i.do").write_text(
        'net install a, from(https://a.org/s`=fileread("/etc/hostname")\')\n'
        'net install b, from("http://b.org/$HOME/x")\n'
        "net install c, from(https://c.org/stata/)\n")
    assert deps.static_installs(src) == [{"net": "c", "from": "https://c.org/stata/"}]
    monkeypatch.setattr(deps, "websee", lambda name: [("ok1", "http://www.stata-journal.com/software/sj5-4"),
                                                     ("bad", "http://x.org/`a'")])
    g = deps.resolution("command", "zzz")
    assert [{"net": "ok1", "from": "http://www.stata-journal.com/software/sj5-4"}] in g["alts"]
    assert all(it.get("net") != "bad" for alt in g["alts"] for it in alt)
    with pytest.raises(ValueError):
        deps.item_cmd({"net": "x", "from": "http://x.org/$y"})
    with pytest.raises(ValueError):
        deps.item_cmd({"ssc": "a b"})


@pytest.mark.parametrize("url", ["http://localhost/x", "http://127.0.0.1:8080/", "http://10.1.2.3/a",
                                 "http://169.254.169.254/latest/meta-data", "http://[::1]/", "file:///etc/passwd",
                                 "ftp://example.com/x", "http://user:pw@example.com/x", "http://100.100.1.1/x"])
def test_public_url_refuses_local_and_odd(url):
    assert not net.public_url(url)


def test_download_public_refuses_before_connecting(tmp_path):
    with pytest.raises(RuntimeError, match="not a public"):
        net.download_public("http://127.0.0.1:9/x", tmp_path / "x")
    assert not (tmp_path / "x").exists()


def test_report_has_no_package_text(root):
    pkg = "dataverse-TXT"
    state.set_info(pkg, journal="QJE", year="2026", doi="10.1/x", title=f"A <img src=x> [link](y) | {'t' * 200}")
    for st in ("fetch", "scan", "prepare"):
        state.record(pkg, st, True)
    state.record(pkg, "run_A", True, seconds=1.0)
    state.record(pkg, "run_V", True, seconds=1.0, counts={"egen": {"fast": 1, "fallback": 0, "verify_mismatch": 1}})
    note = {"file": "out/r`x|y.txt", "verdict": "DIFF", "af": ["DIFF", f"line 3: '{SECRET}' vs 'b'"],
            "ab": ["SAME", ""], "units": None}
    state.record(pkg, "compare", True, arm="V", verdict="FAIL", counts={"DIFF": 1}, verify={},
                 mismatches=[f"egen: m differs in obs 1: {SECRET}"], notes=[note])
    state.record("dataverse-FAILED", "run_A", False, reason=f"{SECRET} not found r(601);")
    md = report.render("fast")
    assert SECRET not in md
    assert "<img" not in md and "[link]" not in md
    assert "|dataverse-TXT|egen|1|" in md
    assert "DIFF line 3|" in md
    assert "|run_A: r(601)|1|" in md


@pytest.mark.skipif(not HAVE_SANDBOX, reason="needs bwrap and Stata")
def test_sandbox_hides_run_and_session_sockets(tmp_path):
    uid = os.getuid()
    probe = (f"test -e /run/user/{uid} && echo RUNUSER; test -e /run/dbus/system_bus_socket && echo SYSBUS; "
             "ls -A /run | wc -l")
    cmd = sandbox.bwrap_cmd(["/bin/sh", "-c", probe], cwd=tmp_path, home=tmp_path, rw=[tmp_path])
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    assert "RUNUSER" not in out.stdout and "SYSBUS" not in out.stdout
    assert out.stdout.split()[-1] == "0"


@pytest.mark.skipif(not HAVE_SANDBOX or not shutil.which("getent"), reason="needs bwrap, Stata and getent")
def test_network_sandbox_still_resolves_names(tmp_path):
    host = "www.stata.com"
    if subprocess.run(["getent", "hosts", host], capture_output=True).returncode != 0:
        pytest.skip("no name resolution on this host")
    cmd = sandbox.bwrap_cmd(["getent", "hosts", host], cwd=tmp_path, home=tmp_path, rw=[tmp_path], network=True)
    assert subprocess.run(cmd, capture_output=True, timeout=60).returncode == 0


def test_stata_batch_refuses_a_launcher_script(tmp_path, monkeypatch):
    # the sandbox shows the launcher's directory only, so the Stata it execs would be missing
    launcher = tmp_path / "bin" / "stata-mp"
    launcher.parent.mkdir()
    launcher.write_text('#!/bin/sh\nexec /opt/stata19/stata-mp "$@"\n')
    launcher.chmod(0o755)
    monkeypatch.setenv("STATA", str(launcher))
    with pytest.raises(SystemExit, match="launcher script"):
        sandbox.stata_batch(tmp_path / "x.do", cwd=tmp_path, home=tmp_path / "h", rw=[tmp_path])
