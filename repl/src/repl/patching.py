"""meta.yaml: master do-file and source patches applied to every arm's copy.

Automatic patches
  root paths   global <name> "<absolute path>" and cd "<absolute path>" lines are rewritten to the
               package directory they most likely mean, chosen by which directory of the package
               holds the files the do-files reach through that global (or, for cd, the relative
               paths used in that file). Written with {ARM}, replaced by the arm's directory.
  installs     ssc install / net install / net from / ado update lines get a capture prefix: the
               runs have no network and a read-only PLUS (dependencies are installed beforehand
               into <pkg>/_deps/plus, see deps.py).
Manual patches: repl/patches/<pkg>.yaml, a list of {file: <rel path or omitted for every .do>,
search: <literal>, replace: <literal>}; {ARM} in replace is the arm directory.
Files are handled as latin-1 so that every byte survives.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import yaml

from . import paths

_PFX = r"(?:(?:cap(?:t(?:u(?:r(?:e)?)?)?)?|qui(?:e(?:t(?:l(?:y)?)?)?)?|noi(?:s(?:i(?:l(?:y)?)?)?)?)\s+)*"
GLOBAL_RE = re.compile(r"^(\s*" + _PFX + r"gl(?:o(?:b(?:a(?:l)?)?)?)?\s+([A-Za-z_]\w*)\s*(?:=\s*)?)(.+?)\s*$")
CD_RE = re.compile(r"^(\s*" + _PFX + r"(?:cd|chdir)\s+)(.+?)\s*$")
INSTALL_RE = re.compile(
    r"^(\s*)(" + _PFX + r")((?:ssc\s+inst(?:a(?:l(?:l)?)?)?|net\s+(?:inst(?:a(?:l(?:l)?)?)?|from|get|set)"
    r"|ado\s+(?:update|uninstall)|adoupdate|github\s+install|ssc\s+install)\b.*)$")
ABS_RE = re.compile(r"^(?:[A-Za-z]:[\\/]|\\\\|/|~(?:[\\/]|$))")


def read_latin1(p: Path) -> str:
    return p.read_bytes().decode("latin-1")


def path_value(rest: str) -> tuple[str, int, int] | None:
    """(value, start, end) of the leading path token of rest: "..", `"..."' or a bare word."""
    if rest.startswith('`"'):
        e = rest.find("\"'", 2)
        return (rest[2:e], 2, e) if e > 0 else None
    if rest.startswith('"'):
        e = rest.find('"', 1)
        return (rest[1:e], 1, e) if e > 0 else None
    m = re.match(r"\S+", rest)
    return (m.group(0), 0, m.end()) if m else None


def is_abs(v: str) -> bool:
    return bool(ABS_RE.match(v.strip()))


def _norm(p: str) -> list[str]:
    return [x for x in p.replace("\\", "/").split("/") if x not in ("", ".")]


class Tree:
    """Case-insensitive view of the package's directories and files."""

    def __init__(self, root: Path) -> None:
        self.dirs: set[str] = set()
        self.entries: set[str] = set()
        self.real: dict[str, str] = {}
        for dp, dn, fn in os.walk(root):
            real = os.path.relpath(dp, root).replace(os.sep, "/")
            real = "" if real == "." else real
            rel = real.lower()
            self.real[rel] = real
            self.dirs.add(rel)
            for x in dn + fn:
                self.entries.add(f"{rel}/{x.lower()}" if rel else x.lower())

    def score(self, d: str, refs: list[list[str]]) -> int:
        s = 0
        for parts in refs:
            if not parts or parts[0] == "..":
                continue
            full = "/".join(([d] if d else []) + parts).lower()
            first = "/".join(([d] if d else []) + parts[:1]).lower()
            s += 2 if full in self.entries else 1 if first in self.entries else 0
        return s

    def best(self, refs: list[list[str]], hint: list[str], default: str) -> str:
        """The package directory (real case) that refs most likely start from."""
        d = self._best(refs, hint, default)
        return self.real.get(d.lower(), d)

    def _best(self, refs: list[list[str]], hint: list[str], default: str) -> str:
        tail = hint[-1].lower() if hint else ""
        ranked = sorted(self.dirs, key=lambda d: (-self.score(d, refs),
                                                  0 if d.split("/")[-1] == tail else 1,
                                                  0 if d == default.lower() else 1,
                                                  d.count("/") if d else -1, d))
        top = ranked[0]
        if self.score(top, refs) == 0:
            matches = [d for d in self.dirs if d and d.split("/")[-1] == tail]
            return min(matches, key=lambda d: d.count("/")) if matches else default
        return top


def _global_refs(texts: dict[str, str], name: str) -> list[list[str]]:
    pat = re.compile(r"\$(?:\{" + re.escape(name) + r"\}|" + re.escape(name) + r"(?![A-Za-z0-9_]))[\\/]([^\"'`\s,;()$]+)")
    return [_norm(m.group(1)) for t in texts.values() for m in pat.finditer(t)]


_REL_RE = re.compile(r"(?:\"([^\"$`]+)\"|\b(?:use|using|do|run|save|include)\s+([^\s,\"$`]+))")


def _relative_refs(text: str) -> list[list[str]]:
    out = []
    for m in _REL_RE.finditer(text):
        v = m.group(1) or m.group(2) or ""
        if is_abs(v) or not ("/" in v or "\\" in v or re.search(r"\.\w{2,4}$", v)):
            continue
        out.append(_norm(v))
    return out


def infer_patches(src: Path, master_rel: str) -> list[dict]:
    """Root-path and install-line patches for the package in src."""
    texts = {str(p.relative_to(src)): read_latin1(p) for p in sorted(src.rglob("*.do")) if p.is_file()}
    tree = Tree(src)
    master_dir = "/".join(_norm(str(Path(master_rel).parent)))
    patches = []
    for rel, text in texts.items():
        for line in text.splitlines():
            m = GLOBAL_RE.match(line)
            kind = "root path (global)"
            if not m:
                m2 = CD_RE.match(line)
                if not m2:
                    mi = INSTALL_RE.match(line)
                    if mi:
                        patches.append({"file": rel, "old": line, "new": f"{mi.group(1)}capture {mi.group(2)}{mi.group(3)}",
                                        "why": "install line (no network in the run)"})
                    continue
                head, rest = m2.group(1), m2.group(2)
                kind = "root path (cd)"
                refs = _relative_refs(text)
            else:
                head, rest = m.group(1), m.group(3)
                refs = _global_refs(texts, m.group(2))
            pv = path_value(rest)
            if not pv or not is_abs(pv[0]):
                continue
            value, s, e = pv
            target = tree.best(refs, _norm(value.split("`")[0].split("$")[0]), master_dir)
            newval = "{ARM}" + (f"/{target}" if target else "")
            new_rest = rest[:s] + newval + rest[e:] if s else f'"{newval}"' + rest[e:]
            patches.append({"file": rel, "old": line, "new": head + new_rest, "why": kind})
    return patches


def meta_path(pkg: str) -> Path:
    return paths.pkg_dir(pkg) / "meta.yaml"


def load_meta(pkg: str) -> dict:
    p = meta_path(pkg)
    return yaml.safe_load(p.read_text()) or {} if p.exists() else {}


def save_meta(pkg: str, meta: dict) -> None:
    meta_path(pkg).write_text(yaml.safe_dump(meta, sort_keys=False, allow_unicode=True, width=1000))


def manual_patches(pkg: str) -> list[dict]:
    p = paths.PATCHES / f"{pkg}.yaml"
    return (yaml.safe_load(p.read_text()) or []) if p.exists() else []


def apply_patches(root: Path, meta: dict, pkg: str | None = None) -> list[str]:
    """Applies meta['patches'] and the manual patches to the copy in root; returns patched files."""
    arm = str(root)
    changed: dict[str, str] = {}

    def text(rel: str) -> str | None:
        if rel not in changed:
            p = root / rel
            if not p.is_file():
                return None
            changed[rel] = read_latin1(p)
        return changed[rel]

    for pt in meta.get("patches", []):
        t = text(pt["file"])
        if t is not None:
            changed[pt["file"]] = t.replace(pt["old"], pt["new"].replace("{ARM}", arm))
    for pt in manual_patches(pkg or root.parent.name):
        files = [pt["file"]] if pt.get("file") else [str(p.relative_to(root)) for p in root.rglob("*.do")]
        for rel in files:
            t = text(rel)
            if t is not None:
                changed[rel] = t.replace(pt["search"], pt["replace"].replace("{ARM}", arm))
    out = []
    for rel, t in changed.items():
        p = root / rel
        if read_latin1(p) != t:
            st = p.stat()
            p.write_bytes(t.encode("latin-1"))
            os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))
            out.append(rel)
    return out
