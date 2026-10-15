"""repl pipeline: discover -> fetch -> scan -> prepare (arm A) -> run V (and F if asked) -> compare
(-> A2, or B for F, when files differ) -> compare.

Newest candidates first; among fetched eligible packages, those calling a replaced command that
still has fewer than 5 counted packages go first. Up to `workers` packages run at a time. After
each comparison, arm A is pruned to its outputs (so fastata can be verified again without
rerunning it) and the other arm directories are deleted. Every stage is recorded in <pkg>/state.json, so a
stopped pipeline restarts where it was. Stops at `target` counted packages or when the
candidates run out.
"""

from __future__ import annotations

import shutil
import threading
from concurrent.futures import FIRST_COMPLETED, Future, ThreadPoolExecutor, wait
from typing import Iterator

from . import compare, discover, fetch, paths, prepare, report, runner, scan, state
from .discover import Candidate

COVER_MIN = 5


def _log(msg: str) -> None:
    print(msg, flush=True)


DEFAULT_ARMS = ("A", "V")
STAGES = ("fetch", "scan", "prepare", "run_A", "run_V", "run_F", "run_A2", "run_B")


def verification_arm(arms: tuple[str, ...]) -> str:
    return "V" if "V" in arms else "F"


def process(pkg: str, keep_arms: bool = False, eager_b: bool = False, arms: tuple[str, ...] = DEFAULT_ARMS,
            log=_log) -> dict:
    """prepare (with arm A), the fastata arms, compare, the reference arm (A2 for V, B for F) if
    files differ, compare. Returns the compare record."""
    x = verification_arm(arms)
    # arms deleted after an interrupted comparison: rerun them
    if not state.done(pkg, "compare"):
        for arm in runner.ARMS:
            if state.ok(pkg, f"run_{arm}") and not runner.has_arm(pkg, arm):
                state.clear(pkg, f"run_{arm}")
    if not state.done(pkg, "prepare"):
        prepare.prepare(pkg, log=log)
    elif not state.done(pkg, "run_A"):
        runner.run_arm(pkg, "A", log=log)
    if not state.ok(pkg, "run_A"):
        return {"ok": False, "reason": "arm A failed"}
    todo = [a for a in arms if a in runner.FASTATA_ARMS]
    if x == "F" and eager_b:
        todo.append("B")
    with ThreadPoolExecutor(max(1, len(todo))) as ex:
        for f in [ex.submit(runner.run_arm, pkg, arm, False, log) for arm in todo]:
            f.result()
    if not state.ok(pkg, f"run_{x}"):
        return {"ok": False, "reason": f"arm {x} failed: {(state.stage(pkg, f'run_{x}') or {}).get('reason', '')}"}
    r = compare.compare(pkg, arm=x)
    if r.get("needref"):
        ref = r["needref"]
        log(f"{pkg}: {r['pending']} file(s) differ between A and {x}; running arm {ref}")
        runner.run_arm(pkg, ref, force=True, log=log)
        if not state.ok(pkg, f"run_{ref}"):
            r = state.record(pkg, "compare", False, reason=f"arm {ref} failed")
        else:
            r = compare.compare(pkg, arm=x)
    if state.done(pkg, "compare") and not keep_arms:
        runner.remove_arms(pkg)
    return r


def _calls(pkg: str) -> dict:
    return (state.stage(pkg, "scan") or {}).get("calls", {})


def _counted(pkg: str, count_on: str) -> bool:
    return report.is_counted(state.load(pkg), count_on)


def _excluded(pkg: str) -> bool:
    s = state.load(pkg)["stages"]
    return any(name in s and not s[name].get("ok") for name in STAGES)


def fetch_and_scan(c: Candidate, keep_src: bool, log=_log) -> bool:
    """True if c is fetched and eligible."""
    pkg = c.pkg
    f = fetch.fetch(c)
    if not f.get("ok"):
        log(f"{pkg}: fetch failed: {f.get('reason', '')}")
        return False
    s = scan.scan(pkg)
    if not s.get("ok"):
        log(f"{pkg}: not eligible: {s.get('reason', '')}")
        if not keep_src:
            shutil.rmtree(paths.pkg_dir(pkg) / "src", ignore_errors=True)
        return False
    return True


def select_candidates(sources: list[str], max_bytes: int, only: list[str] | None) -> list[Candidate]:
    cands = discover.read_candidates()
    if only:
        want = set(only)
        return [c for c in cands if c.pkg in want or c.id in want]
    out = [c for c in cands if c.source in sources and c.status == "ok" and c.size_bytes <= max_bytes]
    out.sort(key=lambda c: c.date, reverse=True)
    return out


def run(target: int, sources: list[str], count_on: str = "fast", workers: int = 4, lookahead: int = 6,
        max_bytes: int = discover.MAX_BYTES, only: list[str] | None = None, keep_arms: bool = False,
        keep_src: bool = False, eager_b: bool = False, rediscover: bool = False,
        arms: tuple[str, ...] = DEFAULT_ARMS, log=_log) -> int:
    if rediscover or not paths.candidates_csv().exists():
        discover.discover(sources, log=log)
    cands = select_candidates(sources, max_bytes, only)
    log(f"pipeline: {len(cands)} candidates, target {target} counted packages ({count_on})")
    counted = {c.pkg for c in cands if (paths.pkg_dir(c.pkg) / "state.json").exists() and _counted(c.pkg, count_on)}
    cover: dict[str, int] = {}
    for p in counted:
        for cmd, n in _calls(p).items():
            cover[cmd] = cover.get(cmd, 0) + (n > 0)

    it: Iterator[Candidate] = iter(c for c in cands if c.pkg not in counted)
    ready: list[str] = []
    exhausted = False
    lock = threading.Lock()

    def priority(pkg: str) -> tuple[int, int]:
        rare = any(n > 0 and cover.get(cmd, 0) < COVER_MIN for cmd, n in _calls(pkg).items())
        return (0 if rare else 1, 0)

    def fill(n: int) -> None:
        nonlocal exhausted
        while not exhausted and len(ready) < n:
            c = next(it, None)
            if c is None:
                exhausted = True
                return
            if (paths.pkg_dir(c.pkg) / "state.json").exists() and _excluded(c.pkg):
                continue
            if c.source == "dataverse" and not state.done(c.pkg, "fetch"):
                try:
                    _, _, c.size_bytes = discover.dv_judge(discover.dv_dataset_json("doi:" + c.doi))
                except Exception as e:  # noqa: BLE001
                    log(f"{c.pkg}: metadata error: {e}")
                    continue
            if c.size_bytes > max_bytes:
                continue
            try:
                if fetch_and_scan(c, keep_src, log):
                    ready.append(c.pkg)
            except Exception as e:  # noqa: BLE001 - one package must not stop the run
                log(f"{c.pkg}: error before running: {type(e).__name__}: {e}")

    inflight: dict[Future, str] = {}
    with ThreadPoolExecutor(workers) as ex:
        while True:
            while len(inflight) < workers and len(counted) + len(inflight) < target:
                if not ready:
                    fill(1)
                if not ready:
                    break
                ready.sort(key=priority)  # stable: newest first within a class
                pkg = ready.pop(0)
                log(f"{pkg}: start")
                inflight[ex.submit(process, pkg, keep_arms, eager_b, arms, log)] = pkg
            if not inflight:
                break
            if len(ready) < lookahead and not exhausted:
                fill(len(ready) + 1)
                done, _ = wait(inflight, timeout=0, return_when=FIRST_COMPLETED)
                if not done:
                    continue
            else:
                done, _ = wait(inflight, return_when=FIRST_COMPLETED)
            for fu in done:
                pkg = inflight.pop(fu)
                try:
                    r = fu.result()
                except Exception as e:  # noqa: BLE001
                    log(f"{pkg}: error: {type(e).__name__}: {e}")
                    continue
                with lock:
                    if _counted(pkg, count_on):
                        counted.add(pkg)
                        for cmd, n in _calls(pkg).items():
                            cover[cmd] = cover.get(cmd, 0) + (n > 0)
                log(f"{pkg}: {r.get('verdict') or r.get('reason', '')} {r.get('counts', '')} "
                    f"(counted {len(counted)}/{target})")
            report.report(count_on)
    report.report(count_on)
    log(f"pipeline: {len(counted)} counted packages; report {paths.RESULTS_MD}")
    return len(counted)
