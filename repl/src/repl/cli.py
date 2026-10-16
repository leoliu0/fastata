"""repl: the fastata replication harness (command line)."""

from __future__ import annotations

import argparse
import json
import sys

from . import compare, discover, fetch, paths, pipeline, prepare, report, runner, scan, state

DEFAULT_SOURCES = "dataverse,zenodo"


def _sources(s: str) -> list[str]:
    out = [x.strip() for x in s.split(",") if x.strip()]
    bad = [x for x in out if x not in ("dataverse", "zenodo", "aea")]
    if bad:
        raise argparse.ArgumentTypeError(f"unknown source(s): {', '.join(bad)}")
    return out


def _arms(s: str) -> tuple[str, ...]:
    out = tuple(x.strip().upper() for x in s.split(",") if x.strip())
    if "A" not in out or not any(x in out for x in ("V", "F")) or any(x not in ("A", "V", "F") for x in out):
        raise argparse.ArgumentTypeError("arms: A plus V and/or F, e.g. A,V")
    return out


def _cand(pkg: str) -> discover.Candidate:
    c = discover.by_pkg().get(pkg)
    if c is None:
        sys.exit(f"repl: {pkg} is not in {paths.candidates_csv()} (run repl discover)")
    return c


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="repl", description=(
        "fastata replication harness: runs published replication packages with the original "
        f"commands and with fastata, in a bwrap sandbox, and compares their outputs. Data root: "
        f"{paths.data_root()}."))
    sub = ap.add_subparsers(dest="cmd", required=True, metavar="<command>")

    p = sub.add_parser("discover", help="list candidate packages -> candidates.csv")
    p.add_argument("--sources", type=_sources, default=_sources(DEFAULT_SOURCES),
                   help=f"comma list of dataverse, zenodo, aea (default {DEFAULT_SOURCES})")
    p.add_argument("--refresh", action="store_true", help="refetch cached Dataverse metadata")
    p.add_argument("--deep", action="store_true",
                   help="check every Dataverse dataset's file list now (slow: rate-limited)")

    p = sub.add_parser("fetch", help="download packages into pkgs/<pkg>/src")
    p.add_argument("pkgs", nargs="+", help="package names (<source>-<id>)")
    p.add_argument("--force", action="store_true")

    p = sub.add_parser("scan", help="count replaced-command calls, find the master do-file")
    p.add_argument("pkgs", nargs="+")
    p.add_argument("--force", action="store_true")

    p = sub.add_parser("prepare", help="meta.yaml, patches, dependencies (runs arm A)")
    p.add_argument("pkgs", nargs="+")
    p.add_argument("--force", action="store_true")

    p = sub.add_parser("run", help="run one arm of a package in the sandbox")
    p.add_argument("pkg")
    p.add_argument("--arm", choices=list(runner.ARMS), required=True)
    p.add_argument("--force", action="store_true", help="rerun even if recorded")

    p = sub.add_parser("compare", help="compare arm V (or F) with arm A")
    p.add_argument("pkgs", nargs="+")
    p.add_argument("--arm", choices=["V", "F"], default="V")
    p.add_argument("--force", action="store_true")

    p = sub.add_parser("report", help="write repl/RESULTS.md")
    p.add_argument("--count-on", choices=["fast", "calls"], default="fast")

    p = sub.add_parser("pipeline", help="discover, fetch, scan, prepare, run, compare until the target")
    p.add_argument("--target", type=int, default=100)
    p.add_argument("--sources", type=_sources, default=_sources(DEFAULT_SOURCES),
                   help=f"comma list of dataverse, zenodo, aea (default {DEFAULT_SOURCES})")
    p.add_argument("--count-on", choices=["fast", "calls"], default="fast",
                   help="a package counts with >=1 fast call (default) or >=1 replaced-command call")
    p.add_argument("--workers", type=int, default=4, help="packages run at a time")
    p.add_argument("--fetchers", type=int, default=6, help="packages fetched at a time (ahead of the runs)")
    p.add_argument("--lookahead", type=int, help="eligible packages fetched ahead (default: --workers)")
    p.add_argument("--fetch-only", action="store_true",
                   help="only fetch and scan, until --target eligible packages are fetched")
    p.add_argument("--max-mb", type=float, default=discover.MAX_BYTES / 2**20, help="largest package (MB)")
    p.add_argument("--only", nargs="*", help="only these packages")
    p.add_argument("--keep-arms", action="store_true", help="keep arm directories after comparing")
    p.add_argument("--keep-src", action="store_true", help="keep sources of ineligible packages")
    p.add_argument("--arms", type=_arms, default=pipeline.DEFAULT_ARMS,
                   help="arms to run: A,V (default; V = fastata in verify mode), A,F (fastata as users "
                        "run it, compared with tolerance and sort-tie arm B), or A,V,F (V decides, F for timing)")
    p.add_argument("--eager-b", action="store_true", help="with F only: run arm B with F instead of only when needed")
    p.add_argument("--rediscover", action="store_true")

    p = sub.add_parser("reset", help="forget recorded stages so that they run again")
    p.add_argument("pkgs", nargs="*")
    p.add_argument("--failed", action="store_true", help="every package that failed at or after --from")
    p.add_argument("--from", dest="start", choices=["fetch", "scan", "prepare", "run", "V", "compare"],
                   default="prepare", help="V: verify again (clears the fastata arms and the comparison, "
                   "keeps prepare and arm A when arm A's outputs are still there)")

    p = sub.add_parser("status", help="stage records of packages")
    p.add_argument("pkgs", nargs="*")

    a = ap.parse_args(argv)
    if a.cmd == "discover":
        discover.discover(a.sources, a.refresh, a.deep)
    elif a.cmd == "fetch":
        for pkg in a.pkgs:
            print(pkg, fetch.fetch(_cand(pkg), a.force))
    elif a.cmd == "scan":
        for pkg in a.pkgs:
            print(pkg, scan.scan(pkg, a.force))
    elif a.cmd == "prepare":
        for pkg in a.pkgs:
            print(pkg, prepare.prepare(pkg, a.force))
    elif a.cmd == "run":
        print(a.pkg, runner.run_arm(a.pkg, a.arm, a.force))
    elif a.cmd == "compare":
        for pkg in a.pkgs:
            print(pkg, compare.compare(pkg, a.force, a.arm))
    elif a.cmd == "report":
        print(report.report(a.count_on))
    elif a.cmd == "pipeline":
        n = pipeline.run(a.target, a.sources, a.count_on, a.workers, a.fetchers, a.lookahead,
                         max_bytes=int(a.max_mb * 2**20), only=a.only, keep_arms=a.keep_arms,
                         keep_src=a.keep_src, eager_b=a.eager_b, rediscover=a.rediscover, arms=a.arms,
                         fetch_only=a.fetch_only)
        return 0 if n >= a.target else 1
    elif a.cmd == "reset":
        order = ["fetch", "scan", "prepare", "run_A", "run_V", "run_F", "run_A2", "run_B", "compare"]
        start = {"run": "run_A", "V": "run_V"}.get(a.start, a.start)
        i0 = order.index(start)
        pkgs = list(a.pkgs)
        if a.failed:
            for st in report.pkg_states():
                e = report.exclusion(st)
                if e is None and st["stages"].get("compare", {}).get("verdict") == "FAIL":
                    e = "compare: FAIL"
                if e and e.split(":", 1)[0] in order and order.index(e.split(":", 1)[0]) >= i0:
                    pkgs.append(st["pkg"])
        nA = 0
        for pkg in pkgs:
            names = order[i0:]
            if i0 <= order.index("scan") and not (paths.pkg_dir(pkg) / "src").exists():
                names = order  # sources were deleted: fetch again
            keep_a = start in ("run_V", "compare") and runner.has_arm(pkg, "A")
            if start in ("run_V", "compare") and not keep_a and state.ok(pkg, "run_A"):
                names = ["run_A", *names]  # arm A's outputs are gone: run it again
                nA += 1
            state.clear(pkg, *names)
            runner.remove_arms(pkg, keep_a=keep_a)
        print(f"reset {len(pkgs)} package(s) from {a.start}" + (f" ({nA} rerun arm A: its outputs were deleted)" if nA else ""))
    elif a.cmd == "status":
        pkgs = a.pkgs or [s["pkg"] for s in report.pkg_states()]
        for pkg in pkgs:
            st = state.load(pkg)["stages"]
            print(pkg, json.dumps({k: (v.get("ok"), v.get("reason") or v.get("verdict") or "") for k, v in st.items()}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
