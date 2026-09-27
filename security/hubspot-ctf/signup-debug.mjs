import { chromium } from 'playwright';

const URL='https://app.hubspot.com/signup-hubspot/trial?intent=trial&trialId=4&dtt_source=free-trial-landing-page';
const browser=await chromium.launch({headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1000}});
const page=await context.newPage();

page.on('console', m => console.log('CONSOLE',m.type(),m.text()));
page.on('pageerror', e => console.log('PAGEERROR',e.message));
page.on('requestfailed', r => console.log('REQFAIL',r.failure()?.errorText,r.url()));
page.on('response', async r => {
  const u=r.url();
  if (u.includes('hubspot.com') && (r.status()>=400 || /signup|talon|verify|captcha/i.test(u))) {
    console.log('RESP',r.status(),r.request().method(),u);
    const ct=(await r.allHeaders())['content-type']||'';
    if (/json|text/.test(ct)) {
      try { console.log('RESPBODY',(await r.text()).slice(0,1000).replace(/\s+/g,' ')); } catch {}
    }
  }
});

await page.goto(URL,{waitUntil:'domcontentloaded',timeout:60000});
await page.waitForTimeout(3000);
for(const sel of ['#hs-eu-decline-button','#hs-eu-close-button']){
  const el=page.locator(sel);
  if(await el.count()) { try { await el.click({timeout:3000}); } catch {} }
}
await page.waitForTimeout(10000);
console.log('FINAL',page.url());
console.log('HTML_BYTES',(await page.content()).length);
console.log('BODY',JSON.stringify((await page.locator('body').innerText()).slice(0,5000)));
console.log('TALON',await page.locator('#talon').getAttribute('value').catch(()=>null));
await browser.close();