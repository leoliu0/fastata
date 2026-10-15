"""ICPSR (openICPSR) login and project download for AEA packages.

Follows AEADataEditor/replication-template tools/download_openicpsr-private.py: an authenticated
requests session (GET the site for cookies, GET <base>login which redirects to the identity
provider's form, POST username and password to the form's action), then the project zip.
openICPSR merged into ICPSR in August 2026, so the base URL is found by following redirects from
the AEA home page, and several download URL patterns are tried in order (ICPSR_DOWNLOAD_URL in
icpsr.env, with {pid} and {ver}, overrides them).

Failure (status other than 200, a Cloudflare challenge page, a login form after posting, or a
download that is not a zip) raises IcpsrError; the caller then falls back to the manual inbox.
Credentials are never printed or logged.
"""

from __future__ import annotations

import html
import re
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests

from . import paths

AEA_HOME = "https://www.icpsr.umich.edu/sites/aea/home"
DEFAULT_BASE = "https://www.openicpsr.org/openicpsr/"
DOWNLOAD_PATTERNS = [
    "{base}project/{pid}/version/V{ver}/download/project?dirPath=/openicpsr/{pid}/fcr:versions/V{ver}",
    "https://deposit.icpsr.umich.edu/deposit/downloadZip?dirPath=/openicpsr/{pid}/fcr:versions/V{ver}",
    "https://deposit.icpsr.umich.edu/deposit/downloadZip?dirPath=/openicpsr/{pid}",
]
HEADERS = {
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
}


class IcpsrError(RuntimeError):
    pass


def read_env(path: Path | None = None) -> dict[str, str]:
    """KEY=VALUE lines (quotes and `export ` allowed). Empty dict if the file is missing."""
    path = path or paths.icpsr_env()
    if not path.exists():
        return {}
    out = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.removeprefix("export ").split("=", 1)
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
            v = v[1:-1]
        out[k.strip()] = v
    return out


def is_cloudflare(r: requests.Response) -> bool:
    t = r.text[:20000] if "html" in r.headers.get("Content-Type", "html") else ""
    return (r.headers.get("cf-mitigated") == "challenge" or "challenge-platform" in t
            or "Just a moment..." in t or "cf-chl-" in t)


def has_login_form(text: str) -> bool:
    return bool(re.search(r"<input[^>]+type=[\"']password[\"']", text, re.I))


def form_action(text: str, page_url: str) -> str | None:
    """Action of the form holding the password field (else the first form), absolute."""
    forms = re.findall(r"<form\b[^>]*>.*?</form>", text, re.I | re.S)
    pick = next((f for f in forms if has_login_form(f)), forms[0] if forms else None)
    src = pick if pick else text
    m = re.search(r"action=[\"']([^\"']*)[\"']", src, re.I)
    if not m:
        return None
    return urljoin(page_url, html.unescape(m.group(1)))


def _check(r: requests.Response, what: str) -> None:
    if r.status_code != 200:
        raise IcpsrError(f"{what}: HTTP {r.status_code}")
    if is_cloudflare(r):
        raise IcpsrError(f"{what}: Cloudflare challenge")


class Client:
    def __init__(self, email: str, password: str, session: requests.Session | None = None,
                 base: str | None = None, download_url: str | None = None) -> None:
        if not email or not password:
            raise IcpsrError("no ICPSR credentials (ICPSR_EMAIL, ICPSR_PASS in icpsr.env)")
        self._email, self._password = email, password
        self.s = session or requests.Session()
        self.s.headers.update(HEADERS)
        self.base = base
        self.download_url = download_url
        self.logged_in = False

    @classmethod
    def from_env(cls, session: requests.Session | None = None) -> "Client":
        env = read_env()
        return cls(env.get("ICPSR_EMAIL", ""), env.get("ICPSR_PASS", ""), session,
                   env.get("ICPSR_BASE") or None, env.get("ICPSR_DOWNLOAD_URL") or None)

    def find_base(self) -> str:
        """The site base after redirects from the AEA home page (DEFAULT_BASE if unclear)."""
        if self.base:
            return self.base
        try:
            r = self.s.get(AEA_HOME, allow_redirects=True, timeout=60)
            u = urlparse(r.url)
            if r.status_code == 200 and "/openicpsr/" in u.path:
                self.base = f"{u.scheme}://{u.netloc}{u.path.split('/openicpsr/')[0]}/openicpsr/"
        except requests.RequestException:
            pass
        self.base = self.base or DEFAULT_BASE
        return self.base

    def login(self) -> None:
        base = self.find_base()
        r = self.s.get(base, timeout=60)
        _check(r, "site")
        r = self.s.get(urljoin(base, "login"), headers={"Referer": base}, allow_redirects=True, timeout=60)
        _check(r, "login page")
        action = form_action(r.text, r.url)
        if not action:
            raise IcpsrError("login page: no form")
        r = self.s.post(action, data={"username": self._email, "password": self._password},
                        headers={"Content-Type": "application/x-www-form-urlencoded", "Referer": r.url},
                        allow_redirects=True, timeout=60)
        _check(r, "login")
        if has_login_form(r.text):
            raise IcpsrError("login: the login form came back (wrong credentials or a changed flow)")
        self.logged_in = True

    def download(self, pid: str, ver: int, dest: Path) -> int:
        """Downloads project pid (version ver, 1 if unknown) as a zip to dest; returns bytes."""
        if not self.logged_in:
            self.login()
        pats = [self.download_url] if self.download_url else DOWNLOAD_PATTERNS
        errors = []
        for pat in pats:
            url = pat.format(base=self.base, pid=pid, ver=ver or 1)
            r = self.s.get(url, allow_redirects=True, stream=True, timeout=600)
            if r.status_code != 200:
                errors.append(f"HTTP {r.status_code}")
                r.close()
                continue
            it = r.iter_content(1 << 20)
            first = next(it, b"")
            if not first.startswith(b"PK"):
                text = first.decode("utf-8", "replace")
                errors.append("Cloudflare challenge" if ("challenge-platform" in text or "Just a moment" in text)
                              else "login form" if has_login_form(text) else "not a zip")
                r.close()
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            part = dest.with_name(dest.name + ".part")
            n = len(first)
            with open(part, "wb") as f:
                f.write(first)
                for chunk in it:
                    f.write(chunk)
                    n += len(chunk)
            part.replace(dest)
            return n
        raise IcpsrError(f"download of project {pid}: " + "; ".join(errors))
