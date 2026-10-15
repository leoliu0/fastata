"""Light Stata do-file parsing: comments, continuation lines, command calls, master detection."""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

REPLACED = ("egen", "isid", "duplicates", "xtile", "pctile", "destring", "tostring")

_PREFIX = (r"(?:(?:cap(?:t(?:u(?:r(?:e)?)?)?)?|qui(?:e(?:t(?:l(?:y)?)?)?)?|noi(?:s(?:i(?:l(?:y)?)?)?)?)\s+"
           r"|(?:by|bys(?:o(?:r(?:t)?)?)?)\s+[^:]*:\s*)")
# A call of a replaced command at the start of a logical line, after capture/quietly/noisily and
# by/bysort prefixes in any order (ado-commands cannot be abbreviated).
CALL_RE = re.compile(r"^\s*(?:" + _PREFIX + r")*(" + "|".join(REPLACED) + r")(?![A-Za-z0-9_])")
# do/run of another file
DO_RE = re.compile(r"^\s*(?:" + _PREFIX + r")*(?:do|ru(?:n)?|include)\s+(\"[^\"]+\"|`\"[^\"]+\"'|\S+)", re.I)


def read_text(p: Path) -> str:
    b = p.read_bytes()
    try:
        return b.decode("utf-8")
    except UnicodeDecodeError:
        return b.decode("latin-1")


def strip_block_comments(text: str) -> str:
    """Removes /* */ comments (nested, as Stata does), keeping newlines for line numbers."""
    out = []
    depth = 0
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("/*", i):
            depth += 1
            i += 2
            continue
        if depth and text.startswith("*/", i):
            depth -= 1
            i += 2
            continue
        ch = text[i]
        if depth == 0 or ch == "\n":
            out.append(ch)
        i += 1
    return "".join(out)


_LINE_COMMENT = re.compile(r"(^|\s)//.*$")


def logical_lines(text: str) -> list[str]:
    """Code lines: block comments removed, /// continuations joined, * and // comments dropped."""
    text = strip_block_comments(text.replace("\r\n", "\n").replace("\r", "\n"))
    out: list[str] = []
    buf = ""
    for raw in text.split("\n"):
        m = re.search(r"(^|\s)///.*$", raw)
        if m:
            buf += raw[: m.start()] + " "
            continue
        line = buf + raw
        buf = ""
        if line.lstrip().startswith("*"):
            continue
        line = _LINE_COMMENT.sub("", line)
        if line.strip():
            out.append(line)
    if buf.strip():
        out.append(buf)
    return out


def count_calls(text: str) -> Counter[str]:
    c: Counter[str] = Counter()
    for line in logical_lines(text):
        # a line can hold several commands inside braces: { egen ... }
        for part in re.split(r"[{}]", line):
            m = CALL_RE.match(part)
            if m:
                c[m.group(1)] += 1
    return c


def code_line_count(text: str) -> int:
    return sum(1 for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith(("#", "%", "*", "//")))


def do_targets(text: str) -> list[str]:
    """Arguments of do/run/include lines, unquoted, without .do."""
    out = []
    for line in logical_lines(text):
        m = DO_RE.match(line)
        if m:
            t = m.group(1).strip().strip("`'").strip('"')
            out.append(t)
    return out


MASTER_NAME = re.compile(r"^(main|master|run_?all|0+_?master|00_?run)\.do$", re.I)


def _readme_text(root: Path) -> str:
    texts = []
    for p in sorted(root.rglob("*")):
        if p.is_file() and re.match(r"read_?me", p.name, re.I) and p.suffix.lower() in (".md", ".txt", ".rtf", ""):
            texts.append(read_text(p))
    return "\n".join(texts)


def find_master(root: Path, dofiles: list[Path] | None = None) -> tuple[Path | None, str]:
    """(master do-file, how it was found)."""
    dofiles = dofiles if dofiles is not None else sorted(p for p in root.rglob("*.do") if p.is_file())
    if not dofiles:
        return None, "no do-files"
    by_name: dict[str, list[Path]] = {}
    for p in dofiles:
        by_name.setdefault(p.name.lower(), []).append(p)
    # 1. README: the section with instructions to replicators names the file to run
    readme = _readme_text(root)
    m = re.search(r"instructions\s+(?:to|for)\s+replicators(.*)", readme, re.I | re.S)
    if m:
        sect = m.group(1)[:6000]
        for name in re.findall(r"([A-Za-z0-9_\-. ]+?\.do)\b", sect):
            cands = by_name.get(Path(name.strip()).name.lower())
            if cands:
                return min(cands, key=lambda p: len(p.parts)), "README instructions"
    # 2. conventional names (shallowest first)
    named = [p for p in dofiles if MASTER_NAME.match(p.name)]
    if named:
        return min(named, key=lambda p: (len(p.parts), p.name.lower())), "file name"
    # 3. the do-file that runs the most other do-files
    stems = {p.stem.lower() for p in dofiles}
    best, nbest = None, 0
    for p in dofiles:
        n = sum(1 for t in do_targets(read_text(p)) if Path(t.replace("\\", "/")).stem.lower() in stems)
        if n > nbest or (n == nbest and n and best is not None and len(p.parts) < len(best.parts)):
            best, nbest = p, n
    if best is not None:
        return best, f"runs {nbest} do-files"
    if len(dofiles) == 1:
        return dofiles[0], "only do-file"
    return None, "no master found"
