"""repl prepare <pkg>: meta.yaml (master, patches, dependencies) and the dependency rounds.

Writes meta.yaml, installs the package's own ssc/net install targets into <pkg>/_deps/plus, then
runs arm A; for every missing dependency the log names, installs it and reruns arm A (up to 5
rounds). The last arm A run is the package's arm A result.
"""

from __future__ import annotations

from . import deps, paths, runner, state
from .patching import infer_cwd, infer_patches, load_meta, save_meta

MAX_ROUNDS = 5


def prepare(pkg: str, force: bool = False, log=print) -> dict:
    if not force and state.done(pkg, "prepare"):
        return state.stage(pkg, "prepare") or {}
    sc = state.stage(pkg, "scan") or {}
    if not sc.get("master"):
        return state.record(pkg, "prepare", False, reason="no master do-file")
    src = paths.pkg_dir(pkg) / "src"
    old = load_meta(pkg)
    cwd = infer_cwd(src, sc["master"])
    meta = {
        "master": sc["master"],
        "master_how": sc.get("master_how", ""),
        "cwd": cwd,
        "patches": infer_patches(src, sc["master"], cwd),
        "deps": old.get("deps", []),
    }
    save_meta(pkg, meta)
    tried: set[str] = set(meta["deps"])
    static = [it for it in deps.static_installs(src)
              if (f"ssc:{it['ssc']}" if "ssc" in it else f"net:{it['net']}") not in tried]
    ok, failed = deps.install(pkg, static, log)
    meta["deps"] += ok
    tried |= set(ok) | set(failed)
    save_meta(pkg, meta)
    rounds = 0
    while True:
        rounds += 1
        a = runner.run_arm(pkg, "A", force=True, log=log)
        if a.get("ok") or rounds >= MAX_ROUNDS:
            break
        logp = runner.results_dir(pkg) / "arm_A.log"
        text = logp.read_text(errors="replace") if logp.exists() else ""
        want = []
        for kind, name in deps.missing_names(text):
            for p in deps.packages_for(name, kind):
                if f"ssc:{p}" not in tried and {"ssc": p} not in want:
                    want.append({"ssc": p})
        if not want:
            break
        ok, failed = deps.install(pkg, want, log)
        meta["deps"] += ok
        tried |= set(ok) | set(failed)
        save_meta(pkg, meta)
        if not ok:
            break
    return state.record(pkg, "prepare", True, rounds=rounds, deps=meta["deps"],
                        patches=len(meta["patches"]), arm_A_ok=bool(a.get("ok")))
