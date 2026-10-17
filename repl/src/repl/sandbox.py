"""bwrap sandbox for Stata: read-only root, the user's home and /run hidden, private /tmp, no
network, own PID, IPC, UTS and cgroup namespaces.

Only the listed rw directories are writable; the Stata installation and the ro directories are
visible read-only. HOME is set inside the sandbox (so Stata's PLUS and PERSONAL defaults point
there, never at the user's real ~/ado). The environment is cleared. /run is hidden because a
read-only bind does not stop connections to the sockets there (the user's D-Bus session bus,
whose systemd user manager starts arbitrary commands outside any sandbox; ssh/gpg agents; the
display); a sandbox with the network gets back only what name resolution needs.
"""

from __future__ import annotations

import os
import signal
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from . import paths


def _resolver_binds() -> list[str]:
    """Read-only binds that name resolution needs from /run (systemd-resolved's stub
    resolv.conf and its varlink socket), for a sandbox with the network."""
    out: list[str] = []
    dirs = set()
    rc = Path("/etc/resolv.conf")
    if rc.is_symlink():
        target = rc.resolve()
        if target.is_relative_to("/run") and target.parent.is_dir():
            dirs.add(target.parent)
    if Path("/run/systemd/resolve").is_dir():
        dirs.add(Path("/run/systemd/resolve"))
    for d in sorted(dirs):
        out += ["--ro-bind", str(d), str(d)]
    return out


def bwrap_cmd(argv: list[str], *, cwd: Path, home: Path, rw: list[Path], ro: list[Path] = (),
              env: dict[str, str] | None = None, network: bool = False) -> list[str]:
    real_home = Path.home().resolve()
    stata_dir = paths.stata_binary().parent
    cmd = ["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp",
           "--tmpfs", "/run", "--tmpfs", str(real_home), "--ro-bind", str(stata_dir), str(stata_dir)]
    if network:
        cmd += _resolver_binds()
    for d in ro:
        cmd += ["--ro-bind", str(d), str(d)]
    for d in rw:
        cmd += ["--bind", str(d), str(d)]
    cmd += ["--unshare-pid", "--unshare-ipc", "--unshare-uts", "--unshare-cgroup-try", "--new-session",
            "--die-with-parent"]
    if not network:
        cmd += ["--unshare-net"]
    cmd += ["--clearenv", "--setenv", "PATH", "/usr/local/bin:/usr/bin:/bin",
            "--setenv", "HOME", str(home), "--setenv", "TMPDIR", "/tmp",
            "--setenv", "LANG", os.environ.get("LANG", "C.UTF-8")]
    # An installation whose launcher is a wrapper script (e.g. one adding a libcompat directory)
    # runs with STATA=<real binary> and the wrapper's LD_LIBRARY_PATH, passed through here.
    if os.environ.get("LD_LIBRARY_PATH"):
        cmd += ["--setenv", "LD_LIBRARY_PATH", os.environ["LD_LIBRARY_PATH"]]
    for k, v in (env or {}).items():
        cmd += ["--setenv", k, v]
    cmd += ["--chdir", str(cwd), *argv]
    return cmd


@dataclass
class Result:
    rc: int
    seconds: float
    timed_out: bool


def run(cmd: list[str], timeout: float, stdout_path: Path | None = None) -> Result:
    """Runs cmd in its own process group; kills the group after timeout seconds."""
    t0 = time.monotonic()
    out = open(stdout_path, "wb") if stdout_path else subprocess.DEVNULL
    try:
        p = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                             start_new_session=True)
        try:
            rc = p.wait(timeout=timeout)
            return Result(rc, time.monotonic() - t0, False)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
            return Result(-9, time.monotonic() - t0, True)
    finally:
        if stdout_path:
            out.close()  # type: ignore[union-attr]


def stata_batch(dofile: Path, *, cwd: Path, home: Path, rw: list[Path], ro: list[Path] = (),
                env: dict[str, str] | None = None, network: bool = False, timeout: float = 3600) -> Result:
    """stata-mp -b do <dofile> in the sandbox; the log is <cwd>/<dofile stem>.log."""
    stata = paths.stata_binary()
    # the sandbox shows only the binary's own directory: a launcher script would exec a Stata it
    # cannot see, and every run would fail without a log
    with open(stata, "rb") as f:
        if f.read(2) == b"#!":
            raise SystemExit(f"repl: {stata} is a launcher script; set STATA to the stata-mp binary it "
                             "runs, and LD_LIBRARY_PATH as the script sets it")
    home.mkdir(parents=True, exist_ok=True)
    cmd = bwrap_cmd([str(stata), "-b", "do", str(dofile)], cwd=cwd, home=home, rw=rw,
                    ro=ro, env=env, network=network)
    return run(cmd, timeout, cwd / f"{dofile.stem}.stdout")
