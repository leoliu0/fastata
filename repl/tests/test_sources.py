"""Discovery filters, archive unpacking and the ICPSR login flow (fake HTTP, no network)."""

import io
import zipfile

import pytest

from repl import icpsr
from repl.discover import aea_fold, dv_judge, zn_judge, Candidate, read_candidates, write_candidates
from repl.fetch import unpack_archive, unpack_tree


def _dv(files, **extra):
    return {"latestVersion": {"files": files}, **extra}


def _f(name, ct="application/x-stata-syntax", size=10, restricted=False, **df):
    return {"restricted": restricted, "dataFile": {"filename": name, "contentType": ct, "filesize": size, **df}}


def test_dv_judge():
    assert dv_judge(_dv([_f("a.do")]))[0] == "ok"
    assert dv_judge(_dv([_f("a.zip", "application/zip")]))[:2] == ("ok", "zip only (scan decides)")
    assert dv_judge(_dv([_f("a.do"), _f("b.dta", "x", restricted=True)]))[1] == "restricted files"
    assert dv_judge(_dv([_f("a.do")], guestbookId=3))[1] == "guestbook"
    big = _f("d.tab", "text/tab-separated-values", size=10, originalFileSize=4 * 1024**3)
    assert dv_judge(_dv([_f("a.do"), big]))[1] == "larger than 3 GB"
    assert dv_judge(_dv([_f("a.R", "type/x-r-syntax")]))[1] == "no Stata do-file"


def test_zn_judge():
    rec = {"files": [{"key": "code.do", "size": 3}], "metadata": {"access_right": "open"}}
    assert zn_judge(rec)[0] == "ok"
    assert zn_judge({**rec, "metadata": {"access_right": "restricted"}})[0] == "skip"
    assert zn_judge({"files": [{"key": "p.zip", "size": 3}], "metadata": {}})[0] == "ok"


def test_aea_fold():
    def rec(doi, year, rel="10.1257/aer.2019"):
        return {"id": doi, "attributes": {"publicationYear": year, "titles": [{"title": "T"}],
                                          "relatedIdentifiers": [{"relationType": "IsSupplementTo",
                                                                  "relatedIdentifier": rel}]}}
    got = aea_fold([("AER", rec("10.3886/e111641v1", 2019)), ("AER", rec("10.3886/e111641v2", 2020)),
                    ("AER", rec("10.3886/e111641", 2020)), ("AER", rec("10.3886/e100", 2017))])
    assert len(got) == 1 and got[0].id == "111641" and got[0].doi == "10.3886/E111641V2"


def test_candidates_roundtrip(tmp_path):
    c = Candidate("dataverse", "ABC", "10.7910/DVN/ABC", "QJE", "2026", "T, with comma", 5, "ok", "", "2026-01-01")
    p = write_candidates([c], tmp_path / "c.csv")
    assert read_candidates(p) == [c] and c.pkg == "dataverse-ABC"


def test_unpack_safety(tmp_path):
    inner = io.BytesIO()
    with zipfile.ZipFile(inner, "w") as z:
        z.writestr("code/m.do", "egen a = sum(b)\n")
    with zipfile.ZipFile(tmp_path / "pkg.zip", "w") as z:
        z.writestr("../evil.txt", "x")
        z.writestr("__MACOSX/._m.do", "x")
        z.writestr("top/data.zip", inner.getvalue())
        z.writestr("top/readme.txt", "r")
    src = tmp_path / "src"
    src.mkdir()
    (tmp_path / "pkg.zip").rename(src / "pkg.zip")
    unpack_tree(src)
    files = sorted(str(p.relative_to(src)) for p in src.rglob("*") if p.is_file())
    assert files == ["top/code/m.do", "top/readme.txt"]
    assert not (tmp_path / "evil.txt").exists()


class FakeResp:
    def __init__(self, url, status=200, text="", headers=None, body=None):
        self.url, self.status_code, self.text = url, status, text
        self.headers = headers or {"Content-Type": "text/html"}
        self._body = body if body is not None else text.encode()

    def iter_content(self, n):
        for i in range(0, len(self._body), n):
            yield self._body[i:i + n]

    def close(self):
        pass


LOGIN_PAGE = ('<html><form id="kc-form-login" action="https://login.icpsr.umich.edu/realms/icpsr/'
              'login-actions/authenticate?session_code=a&amp;tab_id=b" method="post">'
              '<input name="username"><input type="password" name="password"></form></html>')


class FakeSession:
    """Scripted ICPSR: the site, a login page, a POST result and the download."""

    def __init__(self, post_text="<html>welcome</html>", download=None, site_status=200):
        self.headers = {}
        self.posts = []
        self.post_text = post_text
        self.download = download if download is not None else FakeResp("d", body=b"PK\x03\x04zipdata",
                                                                        headers={"Content-Type": "application/zip"})
        self.site_status = site_status
        self.gets = []

    def get(self, url, **kw):
        self.gets.append(url)
        if url == icpsr.AEA_HOME:
            return FakeResp("https://www.openicpsr.org/openicpsr/aea")
        if url.endswith("/openicpsr/"):
            return FakeResp(url, self.site_status)
        if url.endswith("/login"):
            return FakeResp("https://login.icpsr.umich.edu/realms/icpsr/protocol/openid-connect/auth", text=LOGIN_PAGE)
        return self.download

    def post(self, url, data=None, **kw):
        self.posts.append((url, data))
        return FakeResp(url, text=self.post_text)


def test_icpsr_success(tmp_path):
    s = FakeSession()
    c = icpsr.Client("me@x.org", "secret", session=s)
    n = c.download("123456", 2, tmp_path / "p.zip")
    assert n == len(b"PK\x03\x04zipdata") and (tmp_path / "p.zip").read_bytes().startswith(b"PK")
    url, data = s.posts[0]
    assert url.endswith("authenticate?session_code=a&tab_id=b")  # &amp; unescaped
    assert data == {"username": "me@x.org", "password": "secret"}
    assert c.base == "https://www.openicpsr.org/openicpsr/"
    assert any("project/123456/version/V2/download" in g for g in s.gets)


def test_icpsr_login_form_after_post(tmp_path):
    c = icpsr.Client("me@x.org", "bad", session=FakeSession(post_text=LOGIN_PAGE))
    with pytest.raises(icpsr.IcpsrError, match="login form came back"):
        c.download("1", 1, tmp_path / "p.zip")


def test_icpsr_cloudflare_and_status(tmp_path):
    cf = FakeResp("x", 200, text="<html><title>Just a moment...</title></html>")
    c = icpsr.Client("a", "b", session=FakeSession(download=cf))
    with pytest.raises(icpsr.IcpsrError, match="Cloudflare"):
        c.download("1", 1, tmp_path / "p.zip")
    c2 = icpsr.Client("a", "b", session=FakeSession(site_status=403))
    with pytest.raises(icpsr.IcpsrError, match="HTTP 403"):
        c2.login()


def test_icpsr_no_credentials(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    with pytest.raises(icpsr.IcpsrError, match="no ICPSR credentials"):
        icpsr.Client.from_env(session=FakeSession())


def test_read_env(tmp_path):
    p = tmp_path / "icpsr.env"
    p.write_text('# c\nexport ICPSR_EMAIL="a@b.c"\nICPSR_PASS=\'p=w\'\n')
    assert icpsr.read_env(p) == {"ICPSR_EMAIL": "a@b.c", "ICPSR_PASS": "p=w"}


def test_throttled():
    from repl.net import _throttled

    class R:
        def __init__(self, status, headers):
            self.status_code, self.headers = status, headers

    assert _throttled(R(429, {}))
    assert _throttled(R(403, {"Server": "awselb/2.0", "Content-Type": "text/html"}))
    assert not _throttled(R(403, {"Content-Type": "application/json"}))
