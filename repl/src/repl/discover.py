"""repl discover: candidate replication packages -> ~/fastata-repl/candidates.csv.

Sources: Harvard Dataverse collections (no login), Zenodo communities (no login), and AEA
packages on ICPSR listed through DataCite (fetching those needs a login, see icpsr.py).
"""

from __future__ import annotations

import csv
import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass, fields
from pathlib import Path
from typing import Any, Iterable

from . import net, paths

MAX_BYTES = 3 * 1024**3
DATAVERSE = "https://dataverse.harvard.edu"
DV_ALIASES = {
    "qje": "QJE",
    "restat": "REStat",
    "JPE": "JPE",
    "JPE_Microeconomics": "JPE Micro",
    "JPE_Macroeconomics": "JPE Macro",
    "rfs": "RFS",
}
ZENODO = "https://zenodo.org"
ZN_COMMUNITIES = {"restud-replication": "REStud", "ej-replication-repository": "EJ"}
DATACITE = "https://api.datacite.org/dois"
AEA_JOURNALS = {"aer": "AER", "app": "AEJ:Applied", "pol": "AEJ:Policy", "mac": "AEJ:Macro",
                "mic": "AEJ:Micro", "aeri": "AER:Insights"}
AEA_YEARS = (2019, 2026)
STATA_SYNTAX = "application/x-stata-syntax"


@dataclass
class Candidate:
    source: str  # dataverse | zenodo | aea
    id: str  # package id: <source>-<id> is the package directory name
    doi: str
    journal: str
    year: str
    title: str
    size_bytes: int
    status: str  # ok | skip
    reason: str
    date: str = ""  # publication date (ISO), for newest-first ordering
    url: str = ""  # landing page

    @property
    def pkg(self) -> str:
        return f"{self.source}-{self.id}"


COLUMNS = [f.name for f in fields(Candidate)]


def write_candidates(cands: Iterable[Candidate], path: Path | None = None) -> Path:
    path = path or paths.candidates_csv()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", newline="") as f:
        w = csv.DictWriter(f, COLUMNS)
        w.writeheader()
        for c in cands:
            w.writerow(asdict(c))
    tmp.replace(path)
    return path


def read_candidates(path: Path | None = None) -> list[Candidate]:
    path = path or paths.candidates_csv()
    if not path.exists():
        return []
    out = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            row["size_bytes"] = int(row.get("size_bytes") or 0)
            out.append(Candidate(**{k: row.get(k, "") for k in COLUMNS} | {"size_bytes": row["size_bytes"]}))
    return out


def by_pkg() -> dict[str, Candidate]:
    return {c.pkg: c for c in read_candidates()}


# ------------------------------------------------------------------------------- Dataverse


def dv_short(global_id: str) -> str:
    """doi:10.7910/DVN/O5ICCH -> O5ICCH."""
    return global_id.rsplit("/", 1)[-1]


def dv_search(alias: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    start = 0
    while True:
        d = net.get_json(f"{DATAVERSE}/api/search", params={
            "q": "*", "subtree": alias, "type": "dataset", "per_page": 1000, "start": start,
            "sort": "date", "order": "desc"})["data"]
        items.extend(d["items"])
        start += len(d["items"])
        if not d["items"] or start >= d["total_count"]:
            return items


def dv_dataset_json(global_id: str, refresh: bool = False) -> dict[str, Any]:
    """The dataset's JSON (latest version, with its file list), cached under cache/dataverse."""
    cache = paths.cache_dir() / "dataverse" / f"{dv_short(global_id)}.json"
    if cache.exists() and not refresh:
        return json.loads(cache.read_text())
    d = net.get_json(f"{DATAVERSE}/api/datasets/:persistentId/", params={"persistentId": global_id})["data"]
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(d))
    return d


def dv_file_size(f: dict[str, Any]) -> int:
    df = f.get("dataFile", {})
    return int(df.get("originalFileSize") or df.get("filesize") or 0)


def dv_judge(d: dict[str, Any]) -> tuple[str, str, int]:
    """(status, reason, size) for a dataset JSON."""
    files = d.get("latestVersion", {}).get("files", [])
    size = sum(dv_file_size(f) for f in files)
    if "guestbookId" in d or "guestbookId" in d.get("latestVersion", {}):
        return "skip", "guestbook", size
    if any(f.get("restricted") for f in files):
        return "skip", "restricted files", size
    if size > MAX_BYTES:
        return "skip", "larger than 3 GB", size
    names = [(f.get("dataFile", {}).get("originalFileName") or f.get("dataFile", {}).get("filename") or "").lower()
             for f in files]
    ctypes = [f.get("dataFile", {}).get("contentType", "") for f in files]
    if any(ct == STATA_SYNTAX for ct in ctypes) or any(n.endswith((".do", ".ado")) for n in names):
        return "ok", "", size
    if any(n.endswith(".zip") for n in names):
        return "ok", "zip only (scan decides)", size
    return "skip", "no Stata do-file", size


def discover_dataverse(refresh: bool = False, workers: int = 8, log=print) -> list[Candidate]:
    hits: list[tuple[str, dict[str, Any]]] = []
    for alias, journal in DV_ALIASES.items():
        items = dv_search(alias)
        log(f"dataverse {alias}: {len(items)} datasets")
        hits.extend((journal, it) for it in items)

    def one(arg: tuple[str, dict[str, Any]]) -> Candidate:
        journal, it = arg
        gid = it["global_id"]
        date = it.get("published_at", "")
        c = Candidate("dataverse", dv_short(gid), gid.removeprefix("doi:"), journal, date[:4],
                      it.get("name", ""), 0, "skip", "", date, it.get("url", ""))
        try:
            st, why, size = dv_judge(dv_dataset_json(gid, refresh))
            c.status, c.reason, c.size_bytes = st, why, size
        except Exception as e:  # noqa: BLE001 - recorded per candidate
            c.reason = f"metadata error: {e}"
        return c

    with ThreadPoolExecutor(workers) as ex:
        out = list(ex.map(one, hits))
    seen: set[str] = set()
    uniq = []
    for c in out:  # a dataset can sit in two collections
        if c.id not in seen:
            seen.add(c.id)
            uniq.append(c)
    return uniq


# ------------------------------------------------------------------------------- Zenodo


def zn_judge(rec: dict[str, Any]) -> tuple[str, str, int]:
    files = rec.get("files") or []
    size = sum(int(f.get("size", 0)) for f in files)
    access = rec.get("metadata", {}).get("access_right", "open")
    if access != "open":
        return "skip", f"access {access}", size
    if not files:
        return "skip", "no files", size
    if size > MAX_BYTES:
        return "skip", "larger than 3 GB", size
    names = [f.get("key", "").lower() for f in files]
    if any(n.endswith((".do", ".ado")) for n in names):
        return "ok", "", size
    if any(n.endswith((".zip", ".tar.gz", ".tgz", ".7z")) for n in names):
        return "ok", "archive (scan decides)", size
    return "skip", "no Stata do-file", size


def discover_zenodo(log=print) -> list[Candidate]:
    out = []
    for comm, journal in ZN_COMMUNITIES.items():
        page, n = 1, 0
        while True:
            d = net.get_json(f"{ZENODO}/api/records", params={
                "communities": comm, "size": 25, "page": page, "sort": "newest"})
            hits = d["hits"]["hits"]
            for rec in hits:
                st, why, size = zn_judge(rec)
                md = rec.get("metadata", {})
                date = md.get("publication_date") or rec.get("created", "")
                out.append(Candidate("zenodo", str(rec["id"]), rec.get("doi", ""), journal, date[:4],
                                     md.get("title", ""), size, st, why, date,
                                     rec.get("links", {}).get("self_html", "")))
            n += len(hits)
            if not hits or n >= d["hits"]["total"]:
                break
            page += 1
        log(f"zenodo {comm}: {n} records")
    return out


# ------------------------------------------------------------------------------- AEA (DataCite)

AEA_PID = re.compile(r"10\.3886/e(\d+)(?:v(\d+))?$", re.I)


def aea_records(prefix: str) -> Iterable[dict[str, Any]]:
    url: str | None = DATACITE
    params: dict[str, Any] | None = {
        "query": f"relatedIdentifiers.relatedIdentifier:10.1257/{prefix}.* AND relatedIdentifiers.relationType:IsSupplementTo",
        "client-id": "gesis.icpsr", "page[size]": 1000, "page[cursor]": 1}
    while url:
        d = net.get_json(url, params=params)
        yield from d.get("data", [])
        url, params = d.get("links", {}).get("next"), None
        if not d.get("data"):
            break


def aea_fold(records: Iterable[tuple[str, dict[str, Any]]]) -> list[Candidate]:
    """One candidate per ICPSR project: the highest version; years AEA_YEARS."""
    best: dict[str, tuple[int, Candidate]] = {}
    for journal, rec in records:
        m = AEA_PID.search(rec["id"])
        if not m:
            continue
        pid, ver = m.group(1), int(m.group(2) or 0)
        a = rec["attributes"]
        year = str(a.get("publicationYear") or "")
        if not year.isdigit() or not AEA_YEARS[0] <= int(year) <= AEA_YEARS[1]:
            continue
        rel = next((r["relatedIdentifier"] for r in a.get("relatedIdentifiers", [])
                    if r.get("relationType") == "IsSupplementTo"
                    and r.get("relatedIdentifier", "").lower().startswith("10.1257/")), "")
        title = (a.get("titles") or [{}])[0].get("title", "")
        date = a.get("registered") or a.get("created") or ""
        c = Candidate("aea", pid, f"10.3886/E{pid}" + (f"V{ver}" if ver else ""), journal, year, title,
                      0, "ok", "", date, f"https://www.openicpsr.org/openicpsr/project/{pid}" + (
                          f"/version/V{ver}/view" if ver else ""))
        c.reason = f"article {rel}" if rel else ""
        old = best.get(pid)
        if old is None or ver > old[0]:
            best[pid] = (ver, c)
    return [c for _, c in best.values()]


def discover_aea(log=print) -> list[Candidate]:
    recs: list[tuple[str, dict[str, Any]]] = []
    for prefix, journal in AEA_JOURNALS.items():
        n0 = len(recs)
        recs.extend((journal, r) for r in aea_records(prefix))
        log(f"datacite 10.1257/{prefix}: {len(recs) - n0} DOIs")
    return aea_fold(recs)


# ------------------------------------------------------------------------------- command


def discover(sources: list[str], refresh: bool = False, log=print) -> list[Candidate]:
    old = read_candidates()
    keep = [c for c in old if c.source not in sources]
    new: list[Candidate] = []
    for s in sources:
        try:
            if s == "dataverse":
                new += discover_dataverse(refresh, log=log)
            elif s == "zenodo":
                new += discover_zenodo(log=log)
            elif s == "aea":
                new += discover_aea(log=log)
        except Exception as e:  # noqa: BLE001 - keep the other sources
            print(f"repl discover: {s} failed: {e}", file=sys.stderr)
            keep += [c for c in old if c.source == s]
    allc = keep + new
    allc.sort(key=lambda c: c.date, reverse=True)
    write_candidates(allc)
    nok = sum(c.status == "ok" for c in allc)
    log(f"candidates: {len(allc)} ({nok} ok) -> {paths.candidates_csv()}")
    return allc
