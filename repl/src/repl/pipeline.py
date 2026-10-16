"""repl pipeline: discover -> fetch -> scan -> prepare (arm A) -> run V (and F if asked) -> compare
(-> A2, or B for F, when files differ) -> compare.

Newest candidates first; among fetched eligible packages, those calling a replaced command that
still has fewer than 5 counted packages go first. Up to `workers` packages run at a time, while
`fetchers` threads fetch ahead (up to `lookahead` eligible packages waiting). A package is
prescanned first (only the files scan reads), and downloaded in full only when it is eligible.
After each comparison, arm A is pruned to its outputs (so fastata can be verified again without
rerunning it) and the other arm directories are deleted. Every stage is recorded in <pkg>/state.json, so a
stopped pipeline restarts where it was. Stops at `target` counted packages or when the
candidates run out.
"""

from __future__ import annotations

import shutil
import time
from concurrent.futures import FIRST_COMPLETED, Future, ThreadPoolExecutor, wait
from typing import Iterator

from . import compare, discover, fetch, net, paths, prepare, report, runner, scan, state
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
    """True if c is fetched and eligible. Unless already fetched, c is prescanned first: a package
    whose prescan is ineligible is never downloaded in full. The time and the requests it took
    are recorded in the package's info (fetch_seconds, fetch_requests)."""
    fetched = state.done(c.pkg, "fetch")
    t0 = time.monotonic()
    with net.track() as req:
        ok = _fetch_and_scan(c, keep_src, log)
    if not fetched:
        state.set_info(c.pkg, fetch_seconds=round(time.monotonic() - t0, 1), fetch_requests=dict(req))
    return ok


def _fetch_and_scan(c: Candidate, keep_src: bool, log) -> bool:
    pkg = c.pkg
    src = paths.pkg_dir(pkg) / "src"

    def reject(reason: str) -> bool:
        log(f"{pkg}: not eligible: {reason}")
        if not keep_src:
            shutil.rmtree(src, ignore_errors=True)
        return False

    if not state.done(pkg, "fetch"):
        state.set_info(pkg, source=c.source, id=c.id, doi=c.doi, journal=c.journal, year=c.year,
                       title=c.title, date=c.date, url=c.url)
        try:
            decided = fetch.prescan(c)
        except fetch.FetchError as e:
            log(f"{pkg}: fetch failed: {e}")
            state.record(pkg, "fetch", False, reason=str(e))
            return False
        except Exception as e:  # noqa: BLE001 - the full fetch decides
            log(f"{pkg}: prescan failed ({type(e).__name__}: {e}); fetching in full")
            decided = False
        if decided:
            r = scan.scan_tree(src)
            if not r.pop("eligible"):
                state.record(pkg, "scan", False, prescan=True, **r)
                return reject(r["reason"])
    f = fetch.fetch(c)
    if not f.get("ok"):
        log(f"{pkg}: fetch failed: {f.get('reason', '')}")
        return False
    s = scan.scan(pkg)
    if not s.get("ok"):
        return reject(s.get("reason", ""))
    return True


def select_candidates(sources: list[str], max_bytes: int, only: list[str] | None) -> list[Candidate]:
    cands = discover.read_candidates()
    if only:
        want = set(only)
        return [c for c in cands if c.pkg in want or c.id in want]
    out = [c for c in cands if c.source in sources and c.status == "ok" and c.size_bytes <= max_bytes]
    out.sort(key=lambda c: c.date, reverse=True)
    return out


def run(target: int, sources: list[str], count_on: str = "fast", workers: int = 4, fetchers: int = 6,
        lookahead: int | None = None, max_bytes: int = discover.MAX_BYTES, only: list[str] | None = None,
        keep_arms: bool = False, keep_src: bool = False, eager_b: bool = False, rediscover: bool = False,
        arms: tuple[str, ...] = DEFAULT_ARMS, fetch_only: bool = False, log=_log) -> int:
    """Returns the number of counted packages (with fetch_only: of eligible fetched packages,
    target being how many to fetch)."""
    if rediscover or not paths.candidates_csv().exists():
        discover.discover(sources, log=log)
    cands = select_candidates(sources, max_bytes, only)
    lookahead = max(1, workers if lookahead is None else lookahead)
    log(f"pipeline: {len(cands)} candidates, target {target} "
        + ("eligible packages (fetch only)" if fetch_only else f"counted packages ({count_on})"))
    counted = {c.pkg for c in cands if (paths.pkg_dir(c.pkg) / "state.json").exists() and _counted(c.pkg, count_on)}
    cover: dict[str, int] = {}
    for p in counted:
        for cmd, n in _calls(p).items():
            cover[cmd] = cover.get(cmd, 0) + (n > 0)

    it: Iterator[Candidate] = iter(c for c in cands if c.pkg not in counted)
    ready: list[str] = []
    fetching: dict[Future, Candidate] = {}
    inflight: dict[Future, str] = {}
    exhausted = False
    judged = eligible = 0
    t0 = time.monotonic()
    req0 = net.counts()

    def priority(pkg: str) -> tuple[int, int]:
        rare = any(n > 0 and cover.get(cmd, 0) < COVER_MIN for cmd, n in _calls(pkg).items())
        return (0 if rare else 1, 0)

    def fetch_job(c: Candidate) -> bool:
        if c.source == "dataverse" and not state.done(c.pkg, "fetch"):
            try:
                _, _, c.size_bytes = discover.dv_judge(discover.dv_dataset_json("doi:" + c.doi))
            except Exception as e:  # noqa: BLE001
                log(f"{c.pkg}: metadata error: {e}")
                return False
            if c.size_bytes > max_bytes:
                return False
        return fetch_and_scan(c, keep_src, log)

    def want_more() -> bool:
        if fetch_only:
            return eligible + len(fetching) < target
        return len(ready) + len(fetching) < lookahead and len(counted) < target

    def fetch_rate() -> str:
        mins = (time.monotonic() - t0) / 60
        req = {h: n - req0.get(h, 0) for h, n in net.counts().items() if n > req0.get(h, 0)}
        return (f"fetch: {judged} judged ({eligible} eligible) in {mins:.1f} min "
                f"({judged / max(mins, 1e-9) * 60:.0f}/hour); requests {req}")

    with ThreadPoolExecutor(workers) as ex, ThreadPoolExecutor(fetchers) as fx:
        while True:
            while not exhausted and len(fetching) < fetchers and want_more():
                c = next(it, None)
                if c is None:
                    exhausted = True
                elif not ((paths.pkg_dir(c.pkg) / "state.json").exists() and _excluded(c.pkg)) \
                        and c.size_bytes <= max_bytes:
                    fetching[fx.submit(fetch_job, c)] = c
            while (not fetch_only and ready and len(inflight) < workers
                   and len(counted) + len(inflight) < target):
                ready.sort(key=priority)  # stable: newest first within a class
                pkg = ready.pop(0)
                log(f"{pkg}: start")
                inflight[ex.submit(process, pkg, keep_arms, eager_b, arms, log)] = pkg
            if not inflight and not fetching:
                break
            done, _ = wait([*inflight, *fetching], return_when=FIRST_COMPLETED)
            for fu in done:
                if fu in fetching:
                    c = fetching.pop(fu)
                    judged += 1
                    try:
                        ok = fu.result()
                    except Exception as e:  # noqa: BLE001 - one package must not stop the run
                        log(f"{c.pkg}: error before running: {type(e).__name__}: {e}")
                        ok = False
                    if ok:
                        eligible += 1
                        ready.append(c.pkg)
                    if judged % 10 == 0:
                        log(fetch_rate())
                    continue
                pkg = inflight.pop(fu)
                try:
                    r = fu.result()
                except Exception as e:  # noqa: BLE001
                    log(f"{pkg}: error: {type(e).__name__}: {e}")
                    continue
                if _counted(pkg, count_on):
                    counted.add(pkg)
                    for cmd, n in _calls(pkg).items():
                        cover[cmd] = cover.get(cmd, 0) + (n > 0)
                log(f"{pkg}: {r.get('verdict') or r.get('reason', '')} {r.get('counts', '')} "
                    f"(counted {len(counted)}/{target})")
                report.report(count_on)
    log(fetch_rate())
    if fetch_only:
        return eligible
    report.report(count_on)
    log(f"pipeline: {len(counted)} counted packages; report {paths.results_md()}")
    return len(counted)
