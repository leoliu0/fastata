"""HTTP with retries, back-off on 429/5xx and per-host request rate limits."""

from __future__ import annotations

import hashlib
import re
import threading
import time
from collections import Counter, deque
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator
from urllib.parse import urljoin, urlparse

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
_counts: Counter[str] = Counter()
_counts_lock = threading.Lock()


def _count(host: str) -> None:
    with _counts_lock:
        _counts[host] += 1
    t = getattr(_local, "track", None)
    if t is not None:
        t[host] += 1


def counts() -> dict[str, int]:
    """Requests sent so far by this process, per host (redirect targets included)."""
    with _counts_lock:
        return dict(_counts)


@contextmanager
def track() -> Iterator[Counter[str]]:
    """Counts the requests this thread sends inside the block, per host."""
    prev = getattr(_local, "track", None)
    c: Counter[str] = Counter()
    _local.track = c
    try:
        yield c
    finally:
        _local.track = prev
        if prev is not None:
            prev.update(c)


def session() -> requests.Session:
    s = getattr(_local, "s", None)
    if s is None:
        s = requests.Session()
        s.headers["User-Agent"] = USER_AGENT
        _local.s = s
    return s


def get(url: str, *, params=None, stream=False, tries=6, timeout=120, sess=None, headers=None,
        allow_redirects=True) -> requests.Response:
    """GET with back-off. Returns the final response (raises after the last try on errors)."""
    s = sess or session()
    host = urlparse(url).hostname or ""
    delay = 2.0
    last: Exception | None = None
    for attempt in range(tries):
        _limiter.wait(host)
        _count(host)
        try:
            r = s.get(url, params=params, stream=stream, timeout=timeout, headers=headers,
                      allow_redirects=allow_redirects)
        except requests.RequestException as e:
            last = e
            time.sleep(delay)
            delay *= 2
            continue
        if getattr(r, "history", None):  # the redirect target (storage), not rate-limited here
            _count(urlparse(r.url).hostname or "")
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


SEGMENT = 16 << 20  # files of at least two segments are downloaded in parallel byte ranges
MAX_SEGMENTS = 16
# Range connections in flight (all downloads): Zenodo serves ~0.25 MB/s per connection and
# scales with connections (16 gave 3.7 MB/s).
_segment_slots = threading.BoundedSemaphore(48)


def download(url: str, dest: Path, *, md5: str | None = None, sess=None, tries: int = 4,
             size: int | None = None) -> int:
    """Streams url to dest (through dest.part); checks md5 when given. Returns the byte count.
    With size given and large, the file comes in parallel byte ranges when the server allows."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    if size is not None and size >= 2 * SEGMENT and sess is None:
        try:
            return _download_segments(url, dest, part, size, md5)
        except (RangeError, requests.RequestException, OSError, RuntimeError):
            part.unlink(missing_ok=True)  # one stream instead
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


def _download_segments(url: str, dest: Path, part: Path, size: int, md5: str | None) -> int:
    r = get(url, stream=True, allow_redirects=False, headers={"Range": "bytes=0-0"})
    final = url
    if r.is_redirect or r.status_code in (301, 302, 303, 307, 308):
        final = urljoin(url, r.headers["Location"])  # storage (Dataverse): resolved once
    elif r.status_code != 206:
        r.close()
        raise RangeError(f"{r.status_code} for a range request to {url}")
    r.close()
    n = min(MAX_SEGMENTS, -(-size // SEGMENT))
    cuts = [size * i // n for i in range(n + 1)]
    with open(part, "wb") as f:
        f.truncate(size)

    def one(a: int, b: int) -> None:
        with _segment_slots:
            for _ in range(4):
                try:
                    r = get(final, stream=True, timeout=600, headers={"Range": f"bytes={a}-{b - 1}"})
                    try:
                        m = _CRANGE.match(r.headers.get("Content-Range", ""))
                        if r.status_code != 206 or not m or int(m.group(1)) != a:
                            raise RangeError(f"no range support at {final}")
                        with open(part, "r+b") as f:
                            f.seek(a)
                            for chunk in r.iter_content(1 << 20):
                                f.write(chunk[:b - a])
                                a += min(len(chunk), b - a)
                    finally:
                        r.close()
                except requests.RequestException:
                    pass  # resume the segment where it stopped
                if a >= b:
                    return
        raise RuntimeError(f"segment of {url} incomplete")

    with ThreadPoolExecutor(n) as ex:
        for fu in [ex.submit(one, cuts[i], cuts[i + 1]) for i in range(n)]:
            fu.result()
    if md5:
        h = hashlib.md5()
        with open(part, "rb") as f:
            while b := f.read(1 << 20):
                h.update(b)
        if h.hexdigest() != md5.lower():
            raise RuntimeError(f"md5 mismatch for {url}")
    part.replace(dest)
    return size


MAX_PUBLIC_BYTES = 2 << 30


def public_url(url: str) -> bool:
    """An http(s) URL without credentials whose host resolves only to public addresses (not
    localhost, private, shared, link-local or reserved ones)."""
    import ipaddress
    import socket

    u = urlparse(url)
    if u.scheme not in ("http", "https") or not u.hostname or u.username or u.password:
        return False
    try:
        infos = socket.getaddrinfo(u.hostname, u.port or (443 if u.scheme == "https" else 80),
                                   proto=socket.IPPROTO_TCP)
    except (OSError, UnicodeError, ValueError):
        return False
    try:
        return bool(infos) and all(ipaddress.ip_address(sa[0].split("%")[0]).is_global for *_, sa in infos)
    except ValueError:
        return False


def download_public(url: str, dest: Path, *, max_bytes: int = MAX_PUBLIC_BYTES, redirects: int = 5) -> int:
    """download() for a URL that package code names (a do-file reading a file from the web):
    every hop, redirects included, must pass public_url(), so the host never fetches from its
    own network for a package. Raises RuntimeError otherwise. Returns the byte count."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    for _ in range(redirects + 1):
        if not public_url(url):
            raise RuntimeError(f"not a public http(s) URL: {url}")
        r = get(url, stream=True, timeout=600, allow_redirects=False)
        if r.is_redirect or r.status_code in (301, 302, 303, 307, 308):
            r.close()
            url = urljoin(url, r.headers.get("Location", ""))
            continue
        r.raise_for_status()
        n = 0
        try:
            with open(part, "wb") as f:
                for chunk in r.iter_content(1 << 20):
                    n += len(chunk)
                    if n > max_bytes:
                        raise RuntimeError(f"more than {max_bytes} bytes at {url}")
                    f.write(chunk)
        except BaseException:
            part.unlink(missing_ok=True)
            raise
        finally:
            r.close()
        part.replace(dest)
        return n
    raise RuntimeError(f"more than {redirects} redirects from {url}")


class RangeError(RuntimeError):
    """The server does not answer byte-range requests."""


_CRANGE = re.compile(r"bytes (\d+)-(\d+)/(\d+)")


class RemoteFile:
    """Seekable read-only file over HTTP range requests, enough for zipfile to list an archive
    and read some members without downloading it. A redirect (Dataverse -> storage) is resolved
    once. Fetched byte spans are kept; prefetch() loads several regions in merged requests."""

    TAIL = 1 << 18  # the first request reads the end: the zip directory usually fits
    MIN_READ = 1 << 16

    def __init__(self, url: str):
        self.url = url
        self.spans: list[tuple[int, bytes]] = []
        self.pos = 0
        r = get(url, stream=True, allow_redirects=False, headers={"Range": f"bytes=-{self.TAIL}"})
        if r.is_redirect or r.status_code in (301, 302, 303, 307, 308):
            self.url = urljoin(url, r.headers["Location"])
            r.close()
            r = get(self.url, stream=True, headers={"Range": f"bytes=-{self.TAIL}"})
        start, body, total = self._body(r)
        self.size = total
        self._add(start, body)

    def _body(self, r: requests.Response) -> tuple[int, bytes, int]:
        try:
            if r.status_code == 200:  # ranges ignored: accept only a small whole file
                if int(r.headers.get("Content-Length") or 1 << 62) > self.TAIL:
                    raise RangeError(f"no range support at {self.url}")
                body = r.content
                return 0, body, len(body)
            if r.status_code != 206:
                raise RangeError(f"{r.status_code} for a range request to {self.url}")
            m = _CRANGE.match(r.headers.get("Content-Range", ""))
            if not m:
                raise RangeError(f"no Content-Range from {self.url}")
            return int(m.group(1)), r.content, int(m.group(3))
        finally:
            r.close()

    def _add(self, start: int, body: bytes) -> None:
        self.spans.append((start, body))

    def _fetch(self, start: int, end: int) -> None:
        """Loads bytes [start, end)."""
        r = get(self.url, stream=True, headers={"Range": f"bytes={start}-{end - 1}"})
        s, body, _ = self._body(r)
        if s != start or not body:
            raise RangeError(f"unexpected range answer from {self.url}")
        self._add(s, body)

    def _cached(self, start: int, n: int) -> bytes | None:
        for s, b in self.spans:
            if s <= start and start + n <= s + len(b):
                return b[start - s:start - s + n]
        return None

    def prefetch(self, regions: list[tuple[int, int]], gap: int = 1 << 20) -> None:
        """Loads regions [start, end) in as few requests as possible: regions closer than gap
        bytes are read together."""
        merged: list[list[int]] = []
        for s, e in sorted((max(0, s), min(self.size, e)) for s, e in regions):
            if e <= s or self._cached(s, e - s) is not None:
                continue
            if merged and s - merged[-1][1] <= gap:
                merged[-1][1] = max(merged[-1][1], e)
            else:
                merged.append([s, e])
        for s, e in merged:
            self._fetch(s, e)

    def read(self, n: int = -1) -> bytes:
        n = self.size - self.pos if n is None or n < 0 else min(n, self.size - self.pos)
        if n <= 0:
            return b""
        b = self._cached(self.pos, n)
        if b is None:
            self._fetch(self.pos, min(self.size, self.pos + max(n, self.MIN_READ)))
            b = self._cached(self.pos, n)
            if b is None:  # a short answer: return what it covers
                s, body = self.spans[-1]
                b = body[self.pos - s:self.pos - s + n]
        self.pos += len(b)
        return b

    def seek(self, off: int, whence: int = 0) -> int:
        self.pos = off if whence == 0 else self.pos + off if whence == 1 else self.size + off
        return self.pos

    def tell(self) -> int:
        return self.pos

    def seekable(self) -> bool:
        return True

    def close(self) -> None:
        self.spans = []

    def __enter__(self) -> "RemoteFile":
        return self

    def __exit__(self, *a) -> None:
        self.close()
