"""Fetching against a local HTTP server (byte ranges, redirects, Dataverse bulk zips): remote zip
listings, the prescan (same scan verdict as the full package, without downloading it), bulk
downloads with per-file fallback, and the fetch-only pipeline."""

import hashlib
import io
import os
import re
import tarfile
import threading
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from repl import fetch, net, paths, pipeline, scan, state
from repl.discover import Candidate, write_candidates


class Server:
    """Serves files[path] at /files/<path> with byte ranges and at /plain/<path> without;
    /redir/<p> answers 303 to /files/<p>; /api/access/datafiles/<ids> zips the files
    dv[id] = (name, bytes), leaving out skip_ids and corrupting bad_ids; /api/access/datafile/<id>
    serves one. log holds the paths asked for, ranges the Range headers."""

    def __init__(self):
        self.files: dict[str, bytes] = {}
        self.dv: dict[int, tuple[str, bytes]] = {}
        self.skip_ids: set[int] = set()
        self.bad_ids: set[int] = set()
        self.log: list[str] = []
        self.ranges: list[str] = []
        srv = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                path = self.path.split("?")[0]
                srv.log.append(path)
                if path.startswith("/redir/"):
                    self.send_response(303)
                    self.send_header("Location", "/files/" + path[len("/redir/"):])
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                if path.startswith("/api/access/datafiles/"):
                    ids = [int(x) for x in path.rsplit("/", 1)[1].split(",")]
                    buf = io.BytesIO()
                    with zipfile.ZipFile(buf, "w") as z:
                        for i in ids:
                            name, data = srv.dv[i]
                            if i in srv.skip_ids:
                                continue
                            z.writestr(name, data[:-1] + b"#" if i in srv.bad_ids else data)
                        if srv.skip_ids & set(ids):
                            z.writestr("MANIFEST.TXT", "some files were left out")
                    return self._send(buf.getvalue())
                if path.startswith("/api/access/datafile/"):
                    return self._send(srv.dv[int(path.rsplit("/", 1)[1])][1])
                plain = path.startswith("/plain/")
                body = srv.files.get(path.removeprefix("/plain" if plain else "/files"))
                if body is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                self._send(body, ranges=not plain)

            def _send(self, body: bytes, ranges: bool = True):
                rng = self.headers.get("Range") if ranges else None
                if rng:
                    srv.ranges.append(rng)
                if not rng:
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                m = re.match(r"bytes=(\d*)-(\d*)", rng)
                a, b = m.group(1), m.group(2)
                if a == "":
                    start, end = max(0, len(body) - int(b)), len(body) - 1
                else:
                    start, end = int(a), min(len(body) - 1, int(b) if b else len(body) - 1)
                part = body[start:end + 1]
                self.send_response(206)
                self.send_header("Content-Range", f"bytes {start}-{end}/{len(body)}")
                self.send_header("Content-Length", str(len(part)))
                self.end_headers()
                self.wfile.write(part)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()


@pytest.fixture
def srv():
    s = Server()
    yield s
    s.close()


@pytest.fixture
def root(tmp_path, monkeypatch):
    monkeypatch.setenv("FASTATA_REPL_ROOT", str(tmp_path / "root"))
    return tmp_path / "root"


def _zip(members: dict[str, bytes]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for k, v in members.items():
            z.writestr(k, v)
    return buf.getvalue()


def _tgz(members: dict[str, bytes]) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        for k, v in members.items():
            ti = tarfile.TarInfo(k)
            ti.size = len(v)
            t.addfile(ti, io.BytesIO(v))
    return buf.getvalue()


BIG = os.urandom(3 << 20)  # incompressible data between the code files


def _package() -> bytes:
    inner = _zip({"code/helper.do": b"isid id\n", "code/plot.R": b"plot(x)\n", "data/x.csv": BIG[:100000]})
    deep = _tgz({"t/tools.ado": b"program tools\n xtile q = x, nq(4)\nend\n", "t/d.dta": BIG[:5000]})
    return _zip({
        "pkg/README.md": b"Instructions to replicators: run main.do\n",
        "pkg/data/big1.dta": BIG,
        "pkg/code/main.do": b"do sub\ndo helper\n",
        "pkg/data/big2.dta": BIG[::-1],
        "pkg/code/sub.do": b"egen a = mean(b), by(g)\nduplicates drop\n",
        "pkg/code/inner.zip": inner,
        "pkg/code/deep.tar.gz": deep,
        "pkg/code/analysis.py": b"print(1)\n",
        "__MACOSX/pkg/._main.do": b"junk",
    })


def _zenodo(srv, monkeypatch, rec_id: str, files: dict[str, bytes]) -> Candidate:
    recs = {}
    for k, v in files.items():
        srv.files[f"/{rec_id}/{k}"] = v
    recs[rec_id] = {"files": [{"key": k, "size": len(v), "checksum": "md5:" + hashlib.md5(v).hexdigest(),
                               "links": {"self": f"{srv.base}/files/{rec_id}/{k}"}} for k, v in files.items()]}
    old = getattr(fetch.zn_record, "recs", None)
    if old is None:
        table: dict = {}
        fake = lambda rid: table[rid]  # noqa: E731
        fake.recs = table
        monkeypatch.setattr(fetch, "zn_record", fake)
        old = table
    old.update(recs)
    return Candidate("zenodo", rec_id, "10.5281/x", "EJ", "2026", rec_id, sum(map(len, files.values())), "ok", "")


def _tree(d):
    return sorted(str(p.relative_to(d)) for p in d.rglob("*") if p.is_file())


def test_remote_file_lists_zip_with_few_requests(srv):
    data = _package()
    srv.files["/p.zip"] = data
    n0 = net.counts().get("127.0.0.1", 0)
    with net.RemoteFile(f"{srv.base}/redir/p.zip") as rf:
        assert rf.size == len(data)
        z = zipfile.ZipFile(rf)
        assert z.read("pkg/code/sub.do").startswith(b"egen")
        names = z.namelist()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        assert names == z.namelist()
    # redirect, tail (directory), one member
    assert net.counts()["127.0.0.1"] - n0 <= 4


@pytest.mark.parametrize("small", [False, True])
def test_prescan_matches_full_scan(srv, root, monkeypatch, small):
    if not small:
        monkeypatch.setattr(fetch, "SMALL_ARCHIVE", 1000)  # read the zip remotely
    pkgzip = _package()
    c = _zenodo(srv, monkeypatch, "101", {"replication.zip": pkgzip, "README.txt": b"see pkg\n",
                                          "results.xlsx": BIG[:2000]})
    src = paths.pkg_dir(c.pkg) / "src"
    srv.log.clear()
    assert fetch.prescan(c)
    partial = scan.scan_tree(src)
    got = _tree(src)
    assert "results.xlsx" not in got and not any(g.endswith(".dta") for g in got)
    assert "pkg/code/sub.do" in got and "pkg/code/code/helper.do" in got and "pkg/code/code/plot.R" in got
    assert "pkg/code/t/tools.ado" in got and "pkg/README.md" in got and "README.txt" in got
    # full fetch on top of the prescan, and a full fetch from scratch, give the same verdict
    assert fetch.fetch(c)["ok"]
    full = scan.scan_tree(src)
    assert partial == full and full["eligible"] and full["calls"]["egen"] == 1 and full["calls"]["xtile"] == 1
    assert full["master"] == "pkg/code/main.do"


def test_prescan_reads_few_bytes_of_large_zip(srv, root, monkeypatch):
    monkeypatch.setattr(fetch, "SMALL_ARCHIVE", 1000)
    pkgzip = _package()
    c = _zenodo(srv, monkeypatch, "102", {"replication.zip": pkgzip})
    sent: list[int] = []
    real = net.RemoteFile._fetch

    def counting(self, s, e):
        sent.append(e - s)
        return real(self, s, e)

    monkeypatch.setattr(net.RemoteFile, "_fetch", counting)
    assert fetch.prescan(c)
    assert sum(sent) + net.RemoteFile.TAIL < len(pkgzip) / 4


def test_prescan_undecided_for_large_tar(srv, root, monkeypatch):
    monkeypatch.setattr(fetch, "SMALL_ARCHIVE", 10)
    c = _zenodo(srv, monkeypatch, "103", {"replication.tar.gz": _tgz({"a/m.do": b"egen x = sum(y)\n"})})
    assert fetch.prescan(c) is False


def _dataverse(srv, monkeypatch, files: dict[str, bytes], tabular: set[str] = frozenset()):
    monkeypatch.setattr(fetch, "DATAVERSE", srv.base)
    entries = []
    for i, (name, data) in enumerate(files.items(), start=1):
        d, _, base = name.rpartition("/")
        srv.dv[i] = (name, data)
        df = {"id": i, "filename": base, "filesize": len(data), "md5": hashlib.md5(data).hexdigest(),
              "contentType": "application/x-stata-syntax" if base.endswith(".do") else "x"}
        if name in tabular:
            df.update(tabularData=True, originalFileName=base, originalFileSize=len(data), filename=base + ".tab")
        entries.append({"restricted": False, "directoryLabel": d, "dataFile": df} if d else
                       {"restricted": False, "dataFile": df})
    ds = {"latestVersion": {"files": entries}}
    monkeypatch.setattr(fetch, "dv_dataset_json", lambda gid: ds)
    return Candidate("dataverse", "ABC123", "10.7910/DVN/ABC123", "QJE", "2026", "t", 0, "ok", "")


def test_dataverse_bulk_with_per_file_fallback(srv, root, monkeypatch):
    files = {"code/main.do": b"egen a = group(b)\n", "code/b.do": b"isid id\n", "data/a.dta": BIG[:50000],
             "data/b.csv": b"x,y\n1,2\n", "README.md": b"readme\n", "data/c.dta": BIG[:7000]}
    c = _dataverse(srv, monkeypatch, files, tabular={"data/b.csv"})
    srv.skip_ids = {3}  # left out of the zip (size limit): MANIFEST.TXT
    srv.bad_ids = {6}  # damaged in the zip: md5 fails
    assert fetch.fetch(c)["ok"]
    src = paths.pkg_dir(c.pkg) / "src"
    for name, data in files.items():
        assert (src / name).read_bytes() == data
    assert not (src / "MANIFEST.TXT").exists()
    bulk = [p for p in srv.log if p.startswith("/api/access/datafiles/")]
    one = sorted(p for p in srv.log if p.startswith("/api/access/datafile/"))
    assert len(bulk) == 1 and one == ["/api/access/datafile/3", "/api/access/datafile/6"]
    assert not list(src.parent.glob("_bulk*"))


def test_dataverse_prescan_fetches_code_only(srv, root, monkeypatch):
    files = {"code/main.do": b"egen a = group(b)\n", "data/a.dta": BIG[:50000], "README.md": b"r\n"}
    c = _dataverse(srv, monkeypatch, files)
    assert fetch.prescan(c)
    assert _tree(paths.pkg_dir(c.pkg) / "src") == ["README.md", "code/main.do"]
    assert [p for p in srv.log if "datafile" in p] == ["/api/access/datafiles/1,3"]


def test_fetch_only_pipeline_skips_ineligible_downloads(srv, root, monkeypatch):
    monkeypatch.setattr(fetch, "SMALL_ARCHIVE", 1000)
    good = _zenodo(srv, monkeypatch, "201", {"replication.zip": _package()})
    bad = _zenodo(srv, monkeypatch, "202", {"code.zip": _zip({"a.py": b"x = 1\ny = 2\n"}), "data.dta": BIG})
    write_candidates([good, bad])
    srv.log.clear()
    n = pipeline.run(5, ["zenodo"], fetch_only=True, fetchers=2, log=lambda m: None)
    assert n == 1
    assert state.ok(good.pkg, "fetch") and state.ok(good.pkg, "scan")
    st = state.stage(bad.pkg, "scan")
    assert st and not st["ok"] and st["prescan"] and "no replaced-command call" in st["reason"]
    assert not state.done(bad.pkg, "fetch") and not (paths.pkg_dir(bad.pkg) / "src").exists()
    assert "/files/202/data.dta" not in srv.log
    assert state.info(good.pkg)["fetch_requests"]["127.0.0.1"] >= 2
    # a rerun skips both
    srv.log.clear()
    assert pipeline.run(5, ["zenodo"], fetch_only=True, fetchers=2, log=lambda m: None) == 1
    assert srv.log == []


@pytest.mark.parametrize("prefix,segmented", [("/redir/", True), ("/files/", True), ("/plain/", False)])
def test_segmented_download(srv, tmp_path, monkeypatch, prefix, segmented):
    monkeypatch.setattr(net, "SEGMENT", 1 << 20)
    data = os.urandom((5 << 20) + 123)
    srv.files["/big.bin"] = data
    dest = tmp_path / "out" / "big.bin"
    md5 = hashlib.md5(data).hexdigest()
    assert net.download(srv.base + prefix + "big.bin", dest, md5=md5, size=len(data)) == len(data)
    assert dest.read_bytes() == data and not dest.with_name("big.bin.part").exists()
    parts = [r for r in srv.ranges if r != "bytes=0-0"]
    assert len(parts) == (6 if segmented else 0)  # 5 MB + 123 bytes in 1 MB segments
