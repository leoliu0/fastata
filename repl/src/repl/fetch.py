"""repl fetch: download a package into ~/fastata-repl/pkgs/<source>-<id>/src/ and unpack archives.

Dataverse: per file (?format=original for ingested tabular files), under directoryLabel, named
originalFileName, md5-checked. Zenodo: per file, md5-checked. AEA (only when the aea source is
requested): ICPSR login and project zip, else a zip the user put in inbox/aea/<projectid>.zip.
Nested archives are unpacked in place (zip, tar), up to depth 3.
"""

from __future__ import annotations

import csv
import re
import shutil
import tarfile
import zipfile
from pathlib import Path, PurePosixPath

from . import icpsr, net, paths, state
from .discover import DATAVERSE, ZENODO, Candidate, dv_dataset_json, dv_file_size, dv_judge

MAX_UNPACKED = 12 * 1024**3


class FetchError(RuntimeError):
    pass


def _safe_rel(name: str) -> PurePosixPath | None:
    p = PurePosixPath(name.replace("\\", "/"))
    parts = [x for x in p.parts if x not in ("", ".", "/")]
    if not parts or any(x == ".." for x in parts) or parts[0] == "__MACOSX" or p.name == ".DS_Store":
        return None
    return PurePosixPath(*parts)


def unpack_archive(arc: Path, into: Path) -> int:
    """Unpacks zip/tar archive arc into directory into (no path escapes); returns file count."""
    n = 0
    total = 0
    if zipfile.is_zipfile(arc):
        with zipfile.ZipFile(arc) as z:
            for info in z.infolist():
                rel = _safe_rel(info.filename)
                if rel is None or info.is_dir():
                    continue
                total += info.file_size
                if total > MAX_UNPACKED:
                    raise FetchError(f"{arc.name}: unpacks to more than {MAX_UNPACKED >> 30} GB")
                out = into / rel
                out.parent.mkdir(parents=True, exist_ok=True)
                with z.open(info) as src, open(out, "wb") as dst:
                    shutil.copyfileobj(src, dst, 1 << 20)
                n += 1
        return n
    with tarfile.open(arc) as t:
        for m in t.getmembers():
            rel = _safe_rel(m.name)
            if rel is None or not m.isfile():
                continue
            total += m.size
            if total > MAX_UNPACKED:
                raise FetchError(f"{arc.name}: unpacks to more than {MAX_UNPACKED >> 30} GB")
            out = into / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            with t.extractfile(m) as src, open(out, "wb") as dst:  # type: ignore[union-attr]
                shutil.copyfileobj(src, dst, 1 << 20)
            n += 1
    return n


def is_archive(p: Path) -> bool:
    n = p.name.lower()
    return n.endswith((".zip", ".tar", ".tar.gz", ".tgz"))


def unpack_tree(root: Path, depth: int = 3) -> int:
    """Unpacks every archive below root next to itself, then deletes it; repeats for nested ones."""
    n = 0
    for _ in range(depth):
        arcs = [p for p in root.rglob("*") if p.is_file() and is_archive(p)]
        if not arcs:
            break
        for a in arcs:
            try:
                n += unpack_archive(a, a.parent)
            except (zipfile.BadZipFile, tarfile.TarError, EOFError, OSError):
                continue  # leave a broken archive as it is
            a.unlink()
    return n


# ------------------------------------------------------------------------------- sources


def fetch_dataverse(c: Candidate, src: Path) -> int:
    d = dv_dataset_json("doi:" + c.doi)
    status, why, _ = dv_judge(d)
    if status != "ok":
        raise FetchError(why)
    total = 0
    for f in d["latestVersion"]["files"]:
        df = f["dataFile"]
        name = df.get("originalFileName") or df.get("filename")
        rel = _safe_rel(f"{f.get('directoryLabel', '')}/{name}")
        if rel is None:
            continue
        dest = src / rel
        size = dv_file_size(f)
        if dest.exists() and dest.stat().st_size == size:
            total += size
            continue
        url = f"{DATAVERSE}/api/access/datafile/{df['id']}"
        if df.get("tabularData"):
            url += "?format=original"
        ck = df.get("checksum", {})
        md5 = ck.get("value") if ck.get("type") == "MD5" else df.get("md5")
        total += net.download(url, dest, md5=md5)
    return total


def fetch_zenodo(c: Candidate, src: Path) -> int:
    rec = net.get_json(f"{ZENODO}/api/records/{c.id}")
    total = 0
    for f in rec.get("files", []):
        rel = _safe_rel(f["key"])
        if rel is None:
            continue
        dest = src / rel
        if dest.exists() and dest.stat().st_size == int(f.get("size", -1)):
            total += dest.stat().st_size
            continue
        ck = f.get("checksum", "")
        md5 = ck.split(":", 1)[1] if ck.startswith("md5:") else None
        url = f.get("links", {}).get("self") or f"{ZENODO}/api/records/{c.id}/files/{f['key']}/content"
        total += net.download(url, dest, md5=md5)
    return total


_icpsr: icpsr.Client | None = None
_icpsr_failed: str | None = None


def fetch_aea(c: Candidate, src: Path) -> int:
    """Inbox zip first; otherwise ICPSR login (once per process); failure -> shortlist + error."""
    global _icpsr, _icpsr_failed
    zipf = paths.inbox_aea() / f"{c.id}.zip"
    from_inbox = zipf.exists()
    if not from_inbox:
        if _icpsr_failed is None:
            try:
                if _icpsr is None:
                    _icpsr = icpsr.Client.from_env()
                m = re.search(r"V(\d+)$", c.doi, re.I)
                zipf = paths.pkg_dir(c.pkg) / "download.zip"
                _icpsr.download(c.id, int(m.group(1)) if m else 1, zipf)
            except icpsr.IcpsrError as e:
                _icpsr_failed = str(e)
                write_aea_shortlist()
        if _icpsr_failed is not None:
            raise FetchError(f"ICPSR: {_icpsr_failed}; put the zip in {paths.inbox_aea()}/{c.id}.zip "
                             "(list: aea_shortlist.csv)")
    src.mkdir(parents=True, exist_ok=True)
    n = unpack_archive(zipf, src)
    if not from_inbox:
        zipf.unlink()
    return n


def write_aea_shortlist(n: int = 80) -> Path:
    """The n most recent AER, AEJ:Applied and AEJ:Policy packages, for manual download."""
    from .discover import read_candidates

    aea = [c for c in read_candidates() if c.source == "aea" and c.journal in ("AER", "AEJ:Applied", "AEJ:Policy")]
    aea.sort(key=lambda c: c.date, reverse=True)
    out = paths.data_root() / "aea_shortlist.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["projectid", "doi", "journal", "year", "title", "landing_url", "save_as"])
        for c in aea[:n]:
            w.writerow([c.id, c.doi, c.journal, c.year, c.title, c.url,
                        str(paths.inbox_aea() / f"{c.id}.zip")])
    paths.inbox_aea().mkdir(parents=True, exist_ok=True)
    return out


FETCHERS = {"dataverse": fetch_dataverse, "zenodo": fetch_zenodo, "aea": fetch_aea}


def fetch(c: Candidate, force: bool = False) -> dict:
    """Fetches candidate c (skipped when already fetched). Returns the stage record."""
    pkg = c.pkg
    if not force and state.done(pkg, "fetch"):
        return state.stage(pkg, "fetch") or {}
    state.set_info(pkg, source=c.source, id=c.id, doi=c.doi, journal=c.journal, year=c.year,
                   title=c.title, date=c.date, url=c.url)
    src = paths.pkg_dir(pkg) / "src"
    try:
        nbytes = FETCHERS[c.source](c, src)
        nun = unpack_tree(src)
    except (FetchError, icpsr.IcpsrError) as e:
        if c.source == "aea":  # may arrive in the inbox later: do not record
            return {"ok": False, "reason": str(e)}
        return state.record(pkg, "fetch", False, reason=str(e))
    except Exception as e:  # noqa: BLE001 - network errors are per package
        return state.record(pkg, "fetch", False, reason=f"{type(e).__name__}: {e}")
    nfiles = sum(1 for p in src.rglob("*") if p.is_file())
    return state.record(pkg, "fetch", True, bytes=nbytes, unpacked=nun, files=nfiles)
