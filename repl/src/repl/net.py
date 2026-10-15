"""HTTP with retries, back-off on 429/5xx and per-host request rate limits."""

from __future__ import annotations

import hashlib
import threading
import time
from collections import deque
from pathlib import Path
from urllib.parse import urlparse

import requests

USER_AGENT = "fastata-repl/0.1 (+https://github.com/leoliu0/fastata)"

# Requests per minute per host (Zenodo's anonymous limit is 60/min, searches 30/min).
# Harvard Dataverse's load balancer answers 403 for a while after bursts (seen at ~1500/min).
RATE = {"zenodo.org": 50, "api.datacite.org": 100, "dataverse.harvard.edu": 40}


def _throttled(r: requests.Response) -> bool:
    """429, or the HTML 403 an AWS load balancer sends while it throttles a client."""
    if r.status_code == 429:
        return True
    return (r.status_code == 403 and "awselb" in r.headers.get("Server", "")
            and "text/html" in r.headers.get("Content-Type", ""))


class _Limiter:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.hits: dict[str, deque[float]] = {}

    def wait(self, host: str) -> None:
        per_min = RATE.get(host)
        if not per_min:
            return
        while True:
            with self.lock:
                q = self.hits.setdefault(host, deque())
                now = time.monotonic()
                while q and now - q[0] > 60:
                    q.popleft()
                if len(q) < per_min:
                    q.append(now)
                    return
                delay = 60 - (now - q[0]) + 0.05
            time.sleep(delay)


_limiter = _Limiter()
_local = threading.local()


def session() -> requests.Session:
    s = getattr(_local, "s", None)
    if s is None:
        s = requests.Session()
        s.headers["User-Agent"] = USER_AGENT
        _local.s = s
    return s


def get(url: str, *, params=None, stream=False, tries=6, timeout=120, sess=None) -> requests.Response:
    """GET with back-off. Returns the final response (raises after the last try on errors)."""
    s = sess or session()
    host = urlparse(url).hostname or ""
    delay = 2.0
    last: Exception | None = None
    for attempt in range(tries):
        _limiter.wait(host)
        try:
            r = s.get(url, params=params, stream=stream, timeout=timeout)
        except requests.RequestException as e:
            last = e
            time.sleep(delay)
            delay *= 2
            continue
        if _throttled(r) or r.status_code >= 500:
            ra = r.headers.get("Retry-After")
            wait = float(ra) if ra and ra.isdigit() else max(delay, 60.0 if r.status_code == 403 else 0.0)
            r.close()
            last = requests.HTTPError(f"{r.status_code} for {url}")
            time.sleep(min(wait, 120))
            delay *= 2
            continue
        return r
    raise last or RuntimeError(f"GET {url} failed")


def get_json(url: str, params=None):
    r = get(url, params=params)
    r.raise_for_status()
    return r.json()


def download(url: str, dest: Path, *, md5: str | None = None, sess=None, tries: int = 4) -> int:
    """Streams url to dest (through dest.part); checks md5 when given. Returns the byte count."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    for attempt in range(tries):
        r = get(url, stream=True, sess=sess, timeout=600)
        r.raise_for_status()
        h = hashlib.md5()
        n = 0
        with open(part, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)
                h.update(chunk)
                n += len(chunk)
        if md5 and h.hexdigest() != md5.lower():
            part.unlink(missing_ok=True)
            if attempt + 1 == tries:
                raise RuntimeError(f"md5 mismatch for {url}")
            continue
        part.replace(dest)
        return n
    raise RuntimeError(f"download failed: {url}")
