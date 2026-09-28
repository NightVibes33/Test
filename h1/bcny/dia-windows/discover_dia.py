import re
import urllib.request
from urllib.parse import urljoin, urlparse

BASE = "https://www.diabrowser.com/windows"
HEADERS = {"User-Agent": "Mozilla/5.0 HackerOne/NightVibes33"}


def get(url: str) -> str:
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


html = get(BASE)
print("PAGE_BYTES", len(html))

candidate_words = re.compile(
    r"windows|win32|win64|x64|msix|msixbundle|msi|exe|appinstaller|download|installer|update|release",
    re.I,
)
url_re = re.compile(r"https?://[^\"'<>\s]+", re.I)

print("=== DIRECT CANDIDATES ===")
for url in sorted(set(url_re.findall(html))):
    if candidate_words.search(url):
        print(url)

src_re = re.compile(r"<script[^>]+src=[\"']([^\"']+)[\"']", re.I)
scripts = []
for src in src_re.findall(html):
    url = urljoin(BASE, src)
    host = urlparse(url).hostname or ""
    if host.endswith("diabrowser.com"):
        scripts.append(url)
scripts = sorted(set(scripts))

print("=== FIRST PARTY SCRIPTS ===")
for url in scripts:
    print(url)

patterns = [
    re.compile(r"https?://[^\"'\s<>]+\.(?:exe|msix|msixbundle|msi|appinstaller)(?:\?[^\"'\s<>]*)?", re.I),
    re.compile(r"https?://[^\"'\s<>]*(?:download|installer|update|release)[^\"'\s<>]*", re.I),
    re.compile(r"[^\"'\s<>]{0,120}(?:windows|win32|win64|x64)[^\"'\s<>]{0,180}", re.I),
]

seen = set()
for script in scripts:
    try:
        body = get(script)
    except Exception as exc:
        print("SCRIPT_FETCH_FAILED", script, type(exc).__name__, exc)
        continue
    for pattern in patterns:
        for match in pattern.finditer(body):
            value = match.group(0).replace("\\u0026", "&").replace("\\/", "/")
            if value not in seen:
                seen.add(value)
                print("CANDIDATE", value)

print("CANDIDATE_COUNT", len(seen))
