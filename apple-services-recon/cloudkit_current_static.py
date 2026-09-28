#!/usr/bin/env python3
"""Static trace of the current Apple-hosted CloudKit JS CDN bundle."""
from __future__ import annotations
import json,re,ssl
from urllib.request import Request,build_opener,HTTPSHandler,HTTPRedirectHandler
from urllib.error import HTTPError,URLError

URL="https://cdn.apple-cloudkit.com/ck/2/cloudkit.js"
UA="AppleSecurityBounty-Research/1.0 (+cloudkit-current-static)"
MAX=20*1024*1024
NEEDLES=[
 "getAsyncMessageFromPopup",
 "AUTHENTICATION_REQUIRED",
 "_handleSignInURL",
 "ckSession",
 "redirectURL",
 "whenUserSignsIn",
 "setUpAuth",
 "authTokenStore",
 "responseHandler",
 "serverErrorCode",
]

def get():
    req=Request(URL,headers={"User-Agent":UA,"Accept":"application/javascript,*/*;q=.1"},method="GET")
    op=build_opener(HTTPSHandler(context=ssl.create_default_context()),HTTPRedirectHandler())
    try:
        with op.open(req,timeout=25) as r:return r.getcode(),r.geturl(),dict(r.headers.items()),r.read(MAX),None
    except HTTPError as e:
        try:b=e.read(MAX)
        except Exception:b=b""
        return e.code,e.geturl(),dict(e.headers.items()),b,None
    except (URLError,TimeoutError,OSError,ssl.SSLError) as e:return None,URL,{},b"",type(e).__name__+": "+str(e)[:180]

def main():
    st,final,h,b,err=get();t=b.decode("utf-8","replace")
    hits=[]
    for n in NEEDLES:
        start=0;c=0
        while True:
            i=t.find(n,start)
            if i<0 or c>=20:break
            hits.append({"needle":n,"offset":i,"context":t[max(0,i-4200):min(len(t),i+len(n)+7600)].replace("\n"," ").replace("\r"," ")[:13000]})
            start=i+len(n);c+=1
    out={"safety":"GET-only static fetch of Apple's public CloudKit JS CDN bundle.","status":st,"final":final,"bytes":len(b),"content_type":h.get("Content-Type") or h.get("content-type"),"error":err,"hits":hits}
    with open("apple-services-recon/cloudkit-current-static.json","w") as f:json.dump(out,f,indent=2)
    lines=["# Current CloudKit JS static trace","",f"- HTTP: **{st}**",f"- Bytes: **{len(b)}**",f"- Content-Type: **{out['content_type']}**",""]
    for n in NEEDLES:lines.append(f"- {n}: {sum(1 for x in hits if x['needle']==n)}")
    lines+=["","## Security-relevant call sites",""]
    for x in hits:
        if x["needle"] in ("getAsyncMessageFromPopup","_handleSignInURL","AUTHENTICATION_REQUIRED"):
            lines += [f"### {x['needle']} @ {x['offset']}","",x["context"],""]
    with open("apple-services-recon/cloudkit-current-static.md","w") as f:f.write("\n".join(lines)+"\n")
    print("\n".join(lines[:180]),flush=True)

if __name__=="__main__":main()
