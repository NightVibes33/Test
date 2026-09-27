import { chromium } from 'playwright';
import fs from 'node:fs';

const TARGET = 'https://app.hubspot.com/contacts/46962361/';
const rows = [];

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();
const page = await context.newPage();

page.on('response', async (res) => {
  const url = res.url();
  if (!url.includes('hubspot.com')) return;
  if (!(url.includes('/api/') || url.includes('46962361'))) return;

  const req = res.request();
  const headers = await res.allHeaders();
  let body = '';
  const ct = headers['content-type'] || '';
  if (/json|text/.test(ct)) {
    try { body = (await res.text()).slice(0, 2000); } catch {}
  }

  rows.push({
    status: res.status(),
    method: req.method(),
    url,
    contentType: ct,
    body,
  });
});

await page.goto(TARGET, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(10000);

const result = {
  target: TARGET,
  finalUrl: page.url(),
  title: await page.title(),
  bodyText: (await page.locator('body').innerText()).slice(0, 3000),
  responses: rows,
};

fs.mkdirSync('artifacts', { recursive: true });
fs.writeFileSync('artifacts/browser-network.json', JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));

await browser.close();
