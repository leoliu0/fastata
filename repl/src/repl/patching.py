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
ABS_RE = re.compile(r"^(?:[A-Za-z]:(?:[\\/]|$)|\\\\|/|~(?:[\\/]|$))")


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


def _global_refs(texts: dict[str, str], name: str) -> tuple[list[list[str]], bool, bool]:
    """(path parts after $name/..., used as a path at all, used without a separator as in
    ${name}file.dta) over every do-file."""
    n = re.escape(name)
    sep = re.compile(r"\$(?:\{" + n + r"\}|" + n + r"(?![A-Za-z0-9_]))[\\/]([^\"'`,;()$\n]*)")
    glued = re.compile(r"\$\{" + n + r"\}([^\"'`\s,;()$/\\]+\.[A-Za-z]\w{1,3})\b")
    bare = re.compile(r"(?:\b(?:cd|use|using|do|run|save)\s+|\")\$(?:\{" + n + r"\}|" + n + r"(?![A-Za-z0-9_]))\s*(?:\"|,|$)", re.M)
    refs: list[list[str]] = []
    used = glue = False
    for t in texts.values():
        for m in sep.finditer(t):
            refs.append(_norm(m.group(1).strip()))
            used = True
        for m in glued.finditer(t):
            refs.append(_norm(m.group(1)))
            used = glue = True
        if bare.search(t):
            used = True
    return refs, used, glue


_REL_RE = re.compile(r"(?:\"([^\"$`]+)\"|\b(?:use|using|do|run|save|include)\s+([^\s,\"$`]+))")


def _relative_refs(text: str) -> list[list[str]]:
    out = []
    for m in _REL_RE.finditer(text):
        v = m.group(1) or m.group(2) or ""
        if is_abs(v) or not ("/" in v or "\\" in v or re.search(r"\.\w{2,4}$", v)):
            continue
        out.append(_norm(v))
    return out


# net install/from/get with a local source (no URL)
LOCAL_NET_RE = re.compile(r"\bnet\s+(?:(?:inst(?:a(?:l(?:l)?)?)?|get)\b.*\bfrom\(\s*(?!\"?https?:)[^)]*\)|from\s+(?!\"?https?:))", re.I)
USER_IF_RE = re.compile(r"^(\s*)if\s+(?=[^{]*c\((?:username|hostname)\))[^{]*\{(.*)$")
TOOL_RE = re.compile(r"^(\s*)(" + _PFX + r")((?:gtools|ftools|reghdfe)\s*,\s*(?:upgrade|install|compile|reload)\b.*)$")
_PATH_CMD_RE = re.compile(r"\b(do|run|include|use|using|cd|save|saving\()\s*([^\s\"`',]*\\[^\s\"`',]*)")


def _pathlike_backslashes(s: str) -> bool:
    """s uses backslashes as path separators: each follows a path character and precedes one
    (a TeX command such as \\hline or \\\\ does not), and s has no regex characters."""
    if "\\" not in s or re.search(r"[\^*+?|\[\]]", s) or "&" in s:
        return False
    return all(i > 0 and re.match(r"[\w.}:)$'`~-]", s[i - 1]) and i + 1 < len(s) and re.match(r"[\w.$`{ -]", s[i + 1])
               for i, ch in enumerate(s) if ch == "\\")


def fix_backslashes(line: str) -> str:
    """Windows path separators to /, in double-quoted strings and path arguments that are paths."""
    if re.search(r"\b(?:u?regex\w*|u?subinstr|u?strpos|subinword|ustrregex\w*|split|parse)\b", line):
        return line

    def q(m: re.Match) -> str:
        v = m.group(1)
        return '"' + re.sub(r"\\(?![`$])", "/", v) + '"' if _pathlike_backslashes(v) else m.group(0)

    out = re.sub(r'(?<!`)"([^"\n]*)"', q, line)

    def b(m: re.Match) -> str:
        v = m.group(2)
        return m.group(1) + " " + re.sub(r"\\(?![`$])", "/", v) if _pathlike_backslashes(v) else m.group(0)

    return _PATH_CMD_RE.sub(b, out)


def _exists_dir(tree: Tree, base: str, value: str) -> bool:
    """value names a directory of the package, relative to directory base."""
    parts: list[str] = _norm(base)
    for x in _norm(value):
        if x == "..":
            if not parts:
                return False
            parts.pop()
        else:
            parts.append(x)
    return "/".join(parts).lower() in tree.dirs


def infer_cwd(src: Path, master_rel: str) -> str:
    """Directory to run the master from: the master's directory or the ancestor from which the
    relative paths in the master resolve best."""
    tree = Tree(src)
    text = read_latin1(src / master_rel)
    refs = _relative_refs(text)
    parts = _norm(str(Path(master_rel).parent))
    cands = ["/".join(parts[:i]) for i in range(len(parts), -1, -1)]
    best = max(cands, key=lambda d: (tree.score(d.lower(), refs), -cands.index(d)))
    return tree.real.get(best.lower(), best)


def infer_patches(src: Path, master_rel: str, cwd: str | None = None) -> list[dict]:
    """Root-path, user-switch, install-line and path-separator patches for the package in src.

    global <g> "<v>" is rewritten to the package directory g most likely means when g is used
    as a path and v is absolute, or holds no macro and is not a directory of the package (an
    empty value or a placeholder such as "[SET YOUR PATH]"); cd "<v>" likewise when v is
    absolute or empty. if "`c(username)'" == ... { branches (the first per file) become if 1 {.
    """
    texts = {str(p.relative_to(src)): read_latin1(p) for p in sorted(src.rglob("*.do")) if p.is_file()}
    tree = Tree(src)
    cwd = cwd if cwd is not None else infer_cwd(src, master_rel)
    master_dir = "/".join(_norm(str(Path(master_rel).parent)))
    patches = []
    grefs: dict[str, tuple] = {}
    for rel, text in texts.items():
        user_done = False
        in_mata = False
        for line in text.splitlines():
            st = line.strip()
            if re.match(r"mata\s*(?::|\{)?\s*$", st):
                in_mata = True
            elif in_mata and st == "end":
                in_mata = False
            if in_mata:
                continue
            new, whys = line, []
            mu = USER_IF_RE.match(new)
            if mu and not user_done:
                new = f"{mu.group(1)}if 1 {{{mu.group(2)}"
                whys.append("user switch")
                user_done = True
            mi = INSTALL_RE.match(new) or TOOL_RE.match(new)
            if mi and LOCAL_NET_RE.search(new):
                mi = None  # installs from the package's own files work in the run (PLUS is writable)
            if mi:
                new = f"{mi.group(1)}capture {mi.group(2)}{mi.group(3)}"
                whys.append("install line (no network in the run)")
            m = GLOBAL_RE.match(new)
            m2 = None if m else CD_RE.match(new)
            target = None
            if m or m2:
                head, rest = (m.group(1), m.group(3)) if m else (m2.group(1), m2.group(2))
                pv = path_value(rest)
                if pv:
                    value, s, e = pv
                    plain = "$" not in value and "`" not in value
                    if m:
                        name = m.group(2)
                        if name not in grefs:
                            grefs[name] = _global_refs(texts, name)
                        refs, used, glue = grefs[name]
                        if used and (is_abs(value) or (plain and (not value.strip() or not _exists_dir(tree, cwd, value)))):
                            target = tree.best(refs, _norm(re.split(r"[`$]", value)[0]), master_dir)
                            suffix = "/" if glue or value.endswith(("/", "\\")) else ""
                            whys.append("root path (global)")
                    elif is_abs(value) or (plain and value.strip() == ""):
                        target = tree.best(_relative_refs(texts[rel]), _norm(re.split(r"[`$]", value)[0]), cwd)
                        suffix = ""
                        whys.append("root path (cd)")
                    if target is not None:
                        newval = "{ARM}" + (f"/{target}" if target else "") + suffix
                        new = head + (rest[:s] + newval + rest[e:] if s else f'"{newval}"' + rest[e:])
            fixed = fix_backslashes(new)
            if fixed != new:
                new = fixed
                whys.append("path separators")
            if new != line:
                patches.append({"file": rel, "old": line, "new": new, "why": ", ".join(whys)})
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
