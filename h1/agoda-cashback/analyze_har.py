#!/usr/bin/env python3
import json, re, sys, urllib.parse
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: analyze_har.py ACCOUNT_A.har ACCOUNT_B.har")

INTEREST = re.compile(
    r"(?i)(cashback|agoda.?cash|wallet|loyalty|reward|promo|credit|balance|redeem|refund|claim|transaction)"
)
IDKEY = re.compile(
    r"(?i)(user.?id|member.?id|account.?id|wallet.?id|reward.?id|promo.?id|transaction.?id|reference.?id|booking.?id|customer.?id|profile.?id)"
)
SENSITIVE_HEADERS = {"cookie","authorization","x-auth-token","x-csrf-token","x-xsrf-token"}

def load(path):
    return json.loads(Path(path).read_text(errors="replace"))

def flatten(obj, prefix=""):
    out = {}
    if isinstance(obj, dict):
        for k,v in obj.items():
            p = f"{prefix}.{k}" if prefix else str(k)
            out.update(flatten(v,p))
    elif isinstance(obj, list):
        for i,v in enumerate(obj):
            out.update(flatten(v,f"{prefix}[{i}]"))
    else:
        out[prefix] = obj
    return out

def body_obj(req):
    pd=req.get("postData") or {}
    text=pd.get("text") or ""
    if not text:
        return {}
    try:
        return json.loads(text)
    except Exception:
        try:
            return dict(urllib.parse.parse_qsl(text, keep_blank_values=True))
        except Exception:
            return {"_raw":text[:1000]}

def normalized_entries(har):
    rows=[]
    for e in har.get("log",{}).get("entries",[]):
        r=e.get("request",{})
        url=r.get("url","")
        body=body_obj(r)
        body_text=json.dumps(body,sort_keys=True,default=str)
        if not (INTEREST.search(url) or INTEREST.search(body_text)):
            continue
        headers={}
        for h in r.get("headers",[]):
            n=h.get("name","").lower()
            if n in SENSITIVE_HEADERS:
                headers[n]="<redacted>"
            elif re.search(r"(?i)(member|user|account|wallet|reward|promo|transaction|reference)",n):
                headers[n]=h.get("value","")
        rows.append({
            "method":r.get("method"),
            "path":urllib.parse.urlsplit(url).path,
            "query":urllib.parse.parse_qs(urllib.parse.urlsplit(url).query),
            "body":body,
            "headers":headers,
        })
    return rows

def signature(row):
    return (row["method"],row["path"])

A=normalized_entries(load(sys.argv[1]))
B=normalized_entries(load(sys.argv[2]))

print(f"interesting requests: A={len(A)} B={len(B)}")
print()

for a in A:
    peers=[b for b in B if signature(b)==signature(a)]
    if not peers:
        print("ONLY_A",a["method"],a["path"])
        continue
    for b in peers:
        fa=flatten({"query":a["query"],"body":a["body"],"headers":a["headers"]})
        fb=flatten({"query":b["query"],"body":b["body"],"headers":b["headers"]})
        diffs=[]
        for k in sorted(set(fa)|set(fb)):
            va,vb=fa.get(k),fb.get(k)
            if va==vb:
                continue
            if IDKEY.search(k) or INTEREST.search(k):
                diffs.append((k,va,vb))
        if diffs:
            print(f"CANDIDATE {a['method']} {a['path']}")
            for k,va,vb in diffs:
                print(" ",k)
                print("   A:",repr(va)[:300])
                print("   B:",repr(vb)[:300])
            print()
