#!/usr/bin/env python3
"""
Offline two-account HTTP capture comparator for Agoda bounty research.

Input files are sanitized request/response exports captured manually from two
self-owned test accounts. This script never sends network traffic.

Usage:
    python compare_captures.py account_a.json account_b.json

Expected JSON shape:
{
  "request": {
    "method": "GET",
    "url": "...",
    "headers": {...},
    "body": "..."
  },
  "response": {
    "status": 200,
    "headers": {...},
    "body": "..."
  }
}
"""
import json, sys, re
from pathlib import Path

SENSITIVE = re.compile(r"(cookie|authorization|token|secret|session|password)", re.I)

def load(path):
    return json.loads(Path(path).read_text())

def redact_headers(h):
    out={}
    for k,v in (h or {}).items():
        out[k] = "<redacted>" if SENSITIVE.search(k) else v
    return out

def normalize_url(u):
    return re.sub(r"([?&](?:token|session|bookingId|auth|code)=)[^&]+", r"\1<redacted>", u or "", flags=re.I)

def summarize(label, x):
    req=x.get("request",{})
    res=x.get("response",{})
    print(f"=== {label} ===")
    print("method:", req.get("method"))
    print("url:", normalize_url(req.get("url","")))
    print("request_headers:", json.dumps(redact_headers(req.get("headers")), indent=2, sort_keys=True))
    print("request_body:", req.get("body",""))
    print("status:", res.get("status"))
    print("response_headers:", json.dumps(redact_headers(res.get("headers")), indent=2, sort_keys=True))
    body=res.get("body","")
    print("response_body_length:", len(body) if isinstance(body,str) else "non-string")

def main():
    if len(sys.argv)!=3:
        raise SystemExit("usage: compare_captures.py account_a.json account_b.json")
    a,b=map(load,sys.argv[1:])
    summarize("ACCOUNT_A",a)
    summarize("ACCOUNT_B",b)

    ar=a.get("request",{})
    br=b.get("request",{})
    print("=== DIFFERENCES WORTH MANUAL REVIEW ===")
    if ar.get("url") != br.get("url"):
        print("request URL differs")
    if ar.get("body") != br.get("body"):
        print("request body differs")
    ah=redact_headers(ar.get("headers"))
    bh=redact_headers(br.get("headers"))
    for k in sorted(set(ah)|set(bh)):
        if ah.get(k)!=bh.get(k):
            print("request header differs:",k)

    ares=a.get("response",{})
    bres=b.get("response",{})
    if ares.get("status")!=bres.get("status"):
        print("response status differs")
    if ares.get("body")!=bres.get("body"):
        print("response body differs")

if __name__=="__main__":
    main()
