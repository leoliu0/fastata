"""repl fetch: download a package into ~/fastata-repl/pkgs/<source>-<id>/src/ and unpack archives.

Dataverse: files up to 16 MB in zips of many files (/api/access/datafiles/<ids>?format=original:
original formats of ingested tabular files), larger ones one by one; under directoryLabel, named
originalFileName, md5-checked; files a zip leaves out are fetched one by one. Zenodo: per file,
md5-checked. Large files come in parallel byte ranges (net.download). AEA (only when the aea
source is requested): ICPSR login and project zip, else a zip the user put in
inbox/aea/<projectid>.zip. Nested archives are unpacked in place (zip, tar), up to depth 3.

prescan() fetches only what scan reads (do-files, other-language code, READMEs), reading large
zips remotely through byte ranges, so that packages scan rejects are never downloaded.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import shutil
import tarfile
import threading
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

import requests

from . import icpsr, net, paths, scan, state
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


def is_archive_name(name: str) -> bool:
    return name.lower().endswith((".zip", ".tar", ".tar.gz", ".tgz"))


def unpack_tree(root: Path, depth: int = 3) -> int:
    """Unpacks every archive below root next to itself, then deletes it; repeats for nested ones."""
    n = 0
    for _ in range(depth):
        arcs = [p for p in root.rglob("*") if p.is_file() and is_archive_name(p.name)]
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


@dataclass
class Remote:
    """One file of a package as its repository lists it."""

    rel: PurePosixPath  # path under src
    size: int
    md5: str | None
    url: str
    dv_id: int | None = None  # Dataverse file id (bulk downloads)


def dv_files(c: Candidate) -> list[Remote]:
    d = dv_dataset_json("doi:" + c.doi)
    status, why, _ = dv_judge(d)
    if status != "ok":
        raise FetchError(why)
    out = []
    for f in d["latestVersion"]["files"]:
        df = f["dataFile"]
        name = df.get("originalFileName") or df.get("filename")
        rel = _safe_rel(f"{f.get('directoryLabel', '')}/{name}")
        if rel is None:
            continue
        url = f"{DATAVERSE}/api/access/datafile/{df['id']}"
        if df.get("tabularData"):
            url += "?format=original"
        ck = df.get("checksum", {})
        md5 = ck.get("value") if ck.get("type") == "MD5" else df.get("md5")
        out.append(Remote(rel, dv_file_size(f), md5, url, int(df["id"])))
    return out


def zn_record(rec_id: str) -> dict:
    """The Zenodo record (with its file list), cached under cache/zenodo."""
    cache = paths.cache_dir() / "zenodo" / f"{rec_id}.json"
    if cache.exists():
        return json.loads(cache.read_text())
    rec = net.get_json(f"{ZENODO}/api/records/{rec_id}")
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(rec))
    return rec


def zn_files(c: Candidate) -> list[Remote]:
    out = []
    for f in zn_record(c.id).get("files", []):
        rel = _safe_rel(f["key"])
        if rel is None:
            continue
        ck = f.get("checksum", "")
        md5 = ck.split(":", 1)[1] if ck.startswith("md5:") else None
        url = f.get("links", {}).get("self") or f"{ZENODO}/api/records/{c.id}/files/{f['key']}/content"
        out.append(Remote(rel, int(f.get("size", -1)), md5, url))
    return out


LISTERS = {"dataverse": dv_files, "zenodo": zn_files}


def _present(src: Path, f: Remote) -> bool:
    p = src / f.rel
    return p.is_file() and p.stat().st_size == f.size


def _bulk_chunks(files: list[Remote], max_n: int = 300, max_bytes: int = 1 << 30) -> list[list[Remote]]:
    out: list[list[Remote]] = []
    n = 0
    for f in files:
        if not out or len(out[-1]) >= max_n or n + f.size > max_bytes:
            out.append([])
            n = 0
        out[-1].append(f)
        n += f.size
    return out


def dv_bulk(files: list[Remote], src: Path) -> list[Remote]:
    """Downloads Dataverse files a zip at a time (/api/access/datafiles/<ids>, original formats).
    Returns the files the zips did not deliver intact (left out for the zip size limit, which
    MANIFEST.TXT lists, or failed): they are fetched one by one."""
    left: list[Remote] = []
    for chunk in _bulk_chunks(files):
        if len(chunk) == 1:
            left += chunk
            continue
        tmp = src.parent / f"_bulk{threading.get_ident()}.zip"
        got: set[PurePosixPath] = set()
        try:
            net.download(f"{DATAVERSE}/api/access/datafiles/{','.join(str(f.dv_id) for f in chunk)}"
                         "?format=original", tmp)
            want = {f.rel: f for f in chunk}
            with zipfile.ZipFile(tmp) as z:
                for info in z.infolist():
                    rel = _safe_rel(info.filename)
                    f = want.get(rel) if rel is not None else None
                    if f is None or rel in got or info.file_size != f.size:
                        continue
                    if _extract(z, info, src / rel, f.md5):
                        got.add(rel)
        except (zipfile.BadZipFile, OSError, RuntimeError, requests.RequestException):
            pass  # whatever is missing is fetched one by one
        finally:
            tmp.unlink(missing_ok=True)
            tmp.with_name(tmp.name + ".part").unlink(missing_ok=True)
        left += [f for f in chunk if f.rel not in got]
    return left


def _extract(z: zipfile.ZipFile, info: zipfile.ZipInfo, dest: Path, md5: str | None = None) -> bool:
    """Writes member info to dest; False (and nothing written) when md5 is given and differs."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    h = hashlib.md5()
    with z.open(info) as s, open(part, "wb") as d:
        while b := s.read(1 << 20):
            d.write(b)
            h.update(b)
    if md5 and h.hexdigest() != md5.lower():
        part.unlink()
        return False
    part.replace(dest)
    return True


BULK_MAX_FILE = net.SEGMENT  # larger Dataverse files come one by one, in parallel byte ranges


def download_files(files: list[Remote], src: Path) -> int:
    """Downloads the files not yet in src (small Dataverse ones in bulk zips); returns the total
    size of files."""
    todo = [f for f in files if not _present(src, f)]
    small = [f.dv_id is not None and f.size <= BULK_MAX_FILE for f in todo]
    bulk = [f for f, s in zip(todo, small) if s]
    one = [f for f, s in zip(todo, small) if not s]
    if bulk:
        one += dv_bulk(bulk, src)
    for f in one:
        net.download(f.url, src / f.rel, md5=f.md5, size=f.size)
    return sum(f.size for f in files)


def fetch_listed(c: Candidate, src: Path) -> int:
    return download_files(LISTERS[c.source](c), src)


# ------------------------------------------------------------------------------- prescan

SMALL_ARCHIVE = 32 << 20  # archives up to this size are downloaded whole for the prescan
NESTED_MAX = 64 << 20  # nested archives up to this (compressed) size are read into memory


class Undecided(Exception):
    """The prescan cannot get every file scan reads without downloading the package."""


def _zip_regions(z: zipfile.ZipFile, infos: list[zipfile.ZipInfo]) -> list[tuple[int, int]]:
    """Byte regions holding members infos (local header estimated from the central one)."""
    return [(i.header_offset, i.header_offset + 30 + len(i.orig_filename.encode()) + len(i.extra) + 64
             + i.compress_size) for i in infos]


def _prescan_archive(fobj, base: Path, depth: int) -> None:
    """Writes the scan-relevant members of archive fobj (and of archives nested in it, down to
    unpack_tree's depth) under base, where unpack_tree would put them."""
    try:
        z = zipfile.ZipFile(fobj)
    except zipfile.BadZipFile:
        if isinstance(fobj, net.RemoteFile):
            raise Undecided("remote archive is not a zip")
        try:
            fobj.seek(0)
            t = tarfile.open(fileobj=fobj)
        except tarfile.TarError:
            return  # unpack_tree leaves a broken archive as it is
        with t:
            for m in t.getmembers():
                rel = _safe_rel(m.name)
                if rel is None or not m.isfile():
                    continue
                if scan.relevant(rel.name) or (is_archive_name(rel.name) and depth < 3):
                    data = t.extractfile(m).read()  # type: ignore[union-attr]
                    if scan.relevant(rel.name):
                        (base / rel).parent.mkdir(parents=True, exist_ok=True)
                        (base / rel).write_bytes(data)
                    else:
                        _prescan_archive(io.BytesIO(data), (base / rel).parent, depth + 1)
        return
    with z:
        members = [(i, _safe_rel(i.filename)) for i in z.infolist() if not i.is_dir()]
        need = [(i, r) for i, r in members if r is not None and scan.relevant(r.name)]
        nested = [(i, r) for i, r in members if r is not None and depth < 3 and is_archive_name(r.name)]
        if any(i.compress_size > NESTED_MAX for i, _ in nested):
            raise Undecided("large nested archive")
        if isinstance(fobj, net.RemoteFile):
            fobj.prefetch(_zip_regions(z, [i for i, _ in need + nested]))
        for i, r in need:
            _extract(z, i, base / r)
        for i, r in nested:
            _prescan_archive(io.BytesIO(z.read(i)), (base / r).parent, depth + 1)


def prescan(c: Candidate) -> bool:
    """Puts into src only the files scan reads: from the file list, plus the matching members of
    archives (small ones downloaded, larger zips read remotely through byte ranges). True when
    src then gives the same scan verdict as the full package; False (undecided) when it cannot
    (no file list for the source, a tar or a large nested archive that would need downloading)."""
    lister = LISTERS.get(c.source)
    if lister is None:
        return False
    src = paths.pkg_dir(c.pkg) / "src"
    files = lister(c)
    arcs = [f for f in files if is_archive_name(f.rel.name)]
    small = [f for f in arcs if f.size <= SMALL_ARCHIVE]
    download_files([f for f in files if scan.relevant(f.rel.name)] + small, src)
    try:
        for f in arcs:
            base = (src / f.rel).parent
            if f in small:
                with open(src / f.rel, "rb") as fh:
                    _prescan_archive(fh, base, 1)
            elif f.rel.name.lower().endswith(".zip"):
                with net.RemoteFile(f.url) as rf:
                    _prescan_archive(rf, base, 1)
            else:
                raise Undecided("large tar archive")
    except (Undecided, net.RangeError):
        return False
    return True


_icpsr: icpsr.Client | None = None
_icpsr_failed: str | None = None
_icpsr_lock = threading.Lock()


def fetch_aea(c: Candidate, src: Path) -> int:
    """Inbox zip first; otherwise ICPSR login (once per process); failure -> shortlist + error."""
    global _icpsr, _icpsr_failed
    zipf = paths.inbox_aea() / f"{c.id}.zip"
    from_inbox = zipf.exists()
    if not from_inbox:
        with _icpsr_lock:
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


FETCHERS = {"dataverse": fetch_listed, "zenodo": fetch_listed, "aea": fetch_aea}


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
