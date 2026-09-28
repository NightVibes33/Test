#!/usr/bin/env python3
import io, json, os, pathlib, plistlib, re, shutil, sys, urllib.request, zipfile, hashlib

URL = "https://releases.diabrowser.com/release/Dia-1.50.1-87750.zip"
ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT / "out"
OUT.mkdir(parents=True, exist_ok=True)
ZIP = pathlib.Path("/tmp/Dia-1.50.1-87750.zip")

def log(*a):
    print(*a, flush=True)

if not ZIP.exists():
    log("DOWNLOAD", URL)
    req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0 HackerOne/NightVibes33"})
    with urllib.request.urlopen(req, timeout=60) as r, ZIP.open("wb") as f:
        shutil.copyfileobj(r, f, length=1024*1024)

h = hashlib.sha256()
with ZIP.open("rb") as f:
    for chunk in iter(lambda: f.read(1024*1024), b""):
        h.update(chunk)
log("ZIP_BYTES", ZIP.stat().st_size)
log("ZIP_SHA256", h.hexdigest())

report = []
def emit(*a):
    s = " ".join(str(x) for x in a)
    report.append(s)
    log(s)

high_name = re.compile(r"(?i)(Info\.plist|manifest\.json|extension|native.?messag|\.xpc/|\.appex/|helper|ArcCore|sparkle|update|protocol|scheme|webui)")
patterns = {
    "external_connect": re.compile(rb"externally_connectable|onMessageExternal|onConnectExternal", re.I),
    "web_accessible": re.compile(rb"web_accessible_resources", re.I),
    "extension_url": re.compile(rb"chrome-extension://[a-p]{32}", re.I),
    "dia_scheme": re.compile(rb"dia://[A-Za-z0-9_./?=&%#:+~-]{1,200}", re.I),
    "arc_scheme": re.compile(rb"arc://[A-Za-z0-9_./?=&%#:+~-]{1,200}", re.I),
    "native_messaging": re.compile(rb"NativeMessaging|native.?messag", re.I),
    "remote_debug": re.compile(rb"RemoteDebuggingAllowed|DevToolsNeedsConfirmation|remote-debugging", re.I),
    "open_external": re.compile(rb"openExternal|OpenExternal|LaunchServices|NSWorkspace", re.I),
    "profile_sharing": re.compile(rb"profile.?shar|shared.?data|share.?data.?between.?profiles", re.I),
    "activation": re.compile(rb"Web.?Content.?Activation|content.?activation", re.I),
    "dangerous_flags": re.compile(rb"--no-sandbox|--disable-web-security|--allow-file-access-from-files|--disable-site-isolation", re.I),
}

def printable_context(data, start, end, radius=180):
    lo=max(0,start-radius); hi=min(len(data),end+radius)
    chunk=data[lo:hi]
    text=''.join(chr(b) if 32 <= b < 127 else ' ' for b in chunk)
    return re.sub(r"\s+", " ", text).strip()

with zipfile.ZipFile(ZIP) as z:
    names = z.namelist()
    emit("ENTRY_COUNT", len(names))
    emit("=== SECURITY-SENSITIVE PATHS ===")
    for n in names:
        if high_name.search(n):
            emit(n)

    info_names = [n for n in names if n.endswith("Dia.app/Contents/Info.plist") or n.endswith("/Contents/Info.plist") and "/Dia.app/" in n]
    if info_names:
        n=info_names[0]
        p=plistlib.loads(z.read(n))
        emit("=== INFO.PLIST ===")
        for k in [
            "CFBundleIdentifier","CFBundleShortVersionString","CFBundleVersion","CFBundleExecutable",
            "CFBundleURLTypes","CFBundleDocumentTypes","LSApplicationQueriesSchemes",
            "SUFeedURL","SUPublicEDKey","NSAppleEventsUsageDescription",
            "NSDownloadsFolderUsageDescription","NSDesktopFolderUsageDescription",
            "NSDocumentsFolderUsageDescription"
        ]:
            if k in p:
                emit(k, json.dumps(p[k], ensure_ascii=False, default=str))
    else:
        emit("NO_INFO_PLIST_FOUND")

    manifest_names = [n for n in names if n.lower().endswith("manifest.json")]
    emit("=== MANIFESTS ===", len(manifest_names))
    fields = [
        "name","version","manifest_version","permissions","optional_permissions","host_permissions",
        "externally_connectable","web_accessible_resources","background","content_scripts",
        "content_security_policy","update_url"
    ]
    for n in manifest_names:
        try:
            raw=z.read(n)
            obj=json.loads(raw.decode("utf-8","replace"))
        except Exception as e:
            emit("MANIFEST_PARSE_FAIL", n, type(e).__name__)
            continue
        emit("MANIFEST", n)
        for k in fields:
            if k in obj:
                emit(" ", k, json.dumps(obj[k], ensure_ascii=False))

    targets=[]
    for n in names:
        base=n.rstrip("/").split("/")[-1]
        if base in ("Dia","ArcCore") and not n.endswith("/"):
            try:
                info=z.getinfo(n)
                if info.file_size > 1024*1024:
                    targets.append((n,info.file_size))
            except KeyError:
                pass
    targets=sorted(targets,key=lambda x:x[1],reverse=True)[:6]
    emit("=== BINARY TARGETS ===")
    for n,size in targets:
        emit(size,n)

    for n,size in targets:
        emit("=== SCAN", n, size, "===")
        data=z.read(n)
        for label,pat in patterns.items():
            seen=set()
            for m in pat.finditer(data):
                c=printable_context(data,m.start(),m.end())
                if c and c not in seen:
                    seen.add(c)
                    emit(label, c)
                    if len(seen)>=80:
                        emit(label,"[TRUNCATED_AFTER_80_UNIQUE_HITS]")
                        break
        del data

(OUT/"report.txt").write_text("\n".join(report)+"\n", encoding="utf-8")
(OUT/"index.html").write_text(
    "<!doctype html><meta charset=utf-8><title>Dia 1.50.1 audit</title>"
    "<pre style='white-space:pre-wrap'>"+__import__("html").escape("\n".join(report))+"</pre>",
    encoding="utf-8"
)
log("REPORT", OUT/"report.txt")
