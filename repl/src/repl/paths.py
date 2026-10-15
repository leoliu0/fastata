"""Locations: the data root (outside the repository), the repository, Stata."""

from __future__ import annotations

import os
import shutil
from pathlib import Path

# The fastata repository this harness belongs to (repl/ is a direct child of it).
REPO = Path(__file__).resolve().parents[3]
REPL_DIR = REPO / "repl"
FASTATA_STATA = REPO / "stata"
PATCHES = REPL_DIR / "patches"
RESULTS_MD = REPL_DIR / "RESULTS.md"
STATA_HELPERS = Path(__file__).resolve().parent / "stata"


def data_root() -> Path:
    """~/fastata-repl, or $FASTATA_REPL_ROOT (tests)."""
    return Path(os.environ.get("FASTATA_REPL_ROOT", Path.home() / "fastata-repl")).resolve()


def candidates_csv() -> Path:
    return data_root() / "candidates.csv"


def pkgs_dir() -> Path:
    return data_root() / "pkgs"


def pkg_dir(pkg: str) -> Path:
    return pkgs_dir() / pkg


def cache_dir() -> Path:
    return data_root() / "cache"


def inbox_aea() -> Path:
    return data_root() / "inbox" / "aea"


def icpsr_env() -> Path:
    return Path.home() / ".config" / "fastata-repl" / "icpsr.env"


def stata_binary() -> Path:
    """The real stata-mp binary ($STATA overrides)."""
    s = os.environ.get("STATA") or shutil.which("stata-mp")
    if not s:
        raise SystemExit("repl: stata-mp not found on PATH (set STATA=<binary>)")
    return Path(s).resolve()
