#!/usr/bin/env python3
from __future__ import annotations
import asyncio,json,os
from playwright.async_api import async_playwright

ROUTES=[
 ("drive","https://www.icloud.com/iclouddrive/"),
 ("notes","https://www.icloud.com/notes/"),
 ("photos","https://www.icloud.com/photos/"),
 ("mail","https://www.icloud.com/mail/"),
 ("calendar","https://www.icloud.com/calendar/"),
 ("contacts","https://www.icloud.com/contacts/"),
]
UA="AppleSecurityBounty-Research/1.0 (+app-route-popup-auth)"

INIT=r"""
(() => {
 window.__oai={listeners:[],opens:[]};
 const a=EventTarget.prototype.addEventListener;
 EventTarget.prototype.addEventListener=function(type,listener,options){
   if(this===window && type==="message"){
     let src="",stack="";
     try{src=String(listener).slice(0,3500)}catch(e){}
     try{stack=(new Error()).stack.slice(0,5000)}catch(e){}
     window.__oai.listeners.push({src,stack});
   }
   return a.call(this,type,listener,options);
 };
 const o=window.open;
 window.open=function(...args){
   window.__oai.opens.push({args:args.map(x=>String(x).slice(0,1200))});
   return o.apply(this,args);
 };
})();
"""

async def inspect(browser,name,url):
    ctx=await browser.new_context(user_agent=UA)
    page=await ctx.new_page()
    await page.add_init_script(INIT)
    try:
        resp=await page.goto(url,wait_until="domcontentloaded",timeout=60000)
        await page.wait_for_timeout(7000)
        before=await page.evaluate("window.__oai")
        controls=[]
        for el in (await page.locator("button,a,[role=button]").all())[:120]:
            try:
                if not await el.is_visible():continue
                txt=(await el.inner_text()).strip()
                aria=await el.get_attribute("aria-label")
                if "sign" in (txt+" "+(aria or "")).lower():
                    controls.append({"text":txt[:120],"aria":(aria or "")[:120]})
            except:pass
        clicked=False
        for sel in ["text=Sign In","text=Sign in","button:has-text('Sign In')","button:has-text('Sign in')"]:
            try:
                loc=page.locator(sel).first
                if await loc.count() and await loc.is_visible():
                    await loc.click(timeout=3000);clicked=True;await page.wait_for_timeout(5000);break
            except:pass
        after=await page.evaluate("window.__oai")
        # Persist all message listener source snippets because this is local JS metadata only.
        def compact(st):
            return {
              "count":len(st.get("listeners",[])),
              "listeners":[{"src":x.get("src","")[:2200],"stack":x.get("stack","")[:2400]} for x in st.get("listeners",[])[:30]],
              "opens":st.get("opens",[])[:10],
            }
        return {"route":name,"status":resp.status if resp else None,"final_url":page.url,
                "controls":controls[:20],"clicked":clicked,"before":compact(before),"after":compact(after)}
    except Exception as e:
        return {"route":name,"error":type(e).__name__+": "+str(e)[:300]}
    finally:
        await ctx.close()

async def main():
    async with async_playwright() as p:
        chrome="/usr/bin/google-chrome" if os.path.exists("/usr/bin/google-chrome") else None
        browser=await p.chromium.launch(headless=True,executable_path=chrome,args=["--no-sandbox","--disable-dev-shm-usage"])
        rows=[]
        for name,url in ROUTES:
            print("route",name,flush=True)
            rows.append(await inspect(browser,name,url))
        await browser.close()
    signals=[]
    for r in rows:
        if "error" in r:continue
        new=r["after"]["listeners"][r["before"]["count"]:]
        for i,x in enumerate(new):
            src=x["src"]
            # exact signature of the vulnerable helper: object-valued e.data then resolve(e)
            if "data" in src and ("resolve" in src or ".resolve" in src) and "origin" not in src and "source" not in src:
                signals.append({"route":r["route"],"listener_index":r["before"]["count"]+i,"signal":"new message listener accepts data without visible origin/source validation","src":src[:1200]})
    out={"safety":"Unauthenticated direct iCloud app routes; sign-in UI click only; no credentials or forged messages.","rows":rows,"signals":signals}
    with open("apple-services-recon/icloud-app-popup-reachability.json","w") as f:json.dump(out,f,indent=2,sort_keys=True)
    lines=["# iCloud app-route popup-auth reachability","",
      "| Route | Status | Before listeners | After listeners | Popup opens | Signals |",
      "|---|---:|---:|---:|---:|---:|"]
    for r in rows:
        if "error" in r:
            lines.append(f"| {r['route']} | error | - | - | - | - |")
        else:
            n=sum(1 for s in signals if s["route"]==r["route"])
            lines.append(f"| {r['route']} | {r['status']} | {r['before']['count']} | {r['after']['count']} | {len(r['after']['opens'])} | {n} |")
    lines+=["","## Signals",""]
    lines += [f"- {s['route']}: {s['signal']}" for s in signals] if signals else ["No current direct iCloud app route activated the vulnerable popup helper pre-auth."]
    with open("apple-services-recon/icloud-app-popup-reachability.md","w") as f:f.write("\n".join(lines)+"\n")
    print("\n".join(lines),flush=True)
if __name__=="__main__":asyncio.run(main())
