"""Host-side access to files that sandboxed package code could write.

A run can leave symbolic links in its arm directory (Stata's shell runs ln). The sandbox cannot
see the user's home, but the harness reads arm outputs on the host, where a link resolves to
whatever it names (~/.ssh, ~/.config). Files of arm directories are therefore only opened when
they are regular files reached through real directories, never through a link.
"""

from __future__ import annotations

import os
import stat
from pathlib import Path, PurePosixPath


def regular_file(root: Path, rel: str | PurePosixPath) -> Path | None:
    """root/rel when every component below root is a real directory (no symbolic link) and the
    last one is a regular file; None otherwise (missing, a link, a directory, a device...).
    Callers read arm directories only after their sandbox has exited, so nothing changes them
    between this check and the read."""
    p = root
    st = None
    for part in PurePosixPath(str(rel).replace("\\", "/")).parts:
        if part in ("", ".", "/", ".."):
            return None
        p = p / part
        try:
            st = os.lstat(p)
        except OSError:
            return None
        if stat.S_ISLNK(st.st_mode):
            return None
    if st is None or not stat.S_ISREG(st.st_mode):
        return None
    return p


def exists_nonregular(root: Path, rel: str | PurePosixPath) -> bool:
    """Something is at root/rel (without following links) that regular_file() refuses."""
    p = root / str(rel).replace("\\", "/")
    try:
        os.lstat(p)
    except OSError:
        return False
    return regular_file(root, rel) is None


def read_text(root: Path, rel: str | PurePosixPath) -> str:
    """The text of regular_file(root, rel) (undecodable bytes replaced), or "" when refused."""
    p = regular_file(root, rel)
    return p.read_text(errors="replace") if p else ""


def contained_dir(root: Path, rel: str) -> Path | None:
    """root/rel for a relative directory path that stays below root lexically ("..", absolute
    paths and empty paths refused)."""
    parts = PurePosixPath(rel.replace("\\", "/")).parts
    if not parts or parts[0] == "/" or any(x in ("..", "") for x in parts):
        return None
    return root.joinpath(*parts)
