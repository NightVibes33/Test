import { chromium } from 'playwright';
import fs from 'node:fs';

const URL = 'https://app.hubspot.com/signup-hubspot/trial?intent=trial&trialId=4&dtt_source=free-trial-landing-page';
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();
const page = await context.newPage();

await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(7000);

const interactive = await page.locator('input, button, select, textarea, a').evaluateAll((els) =>
  els.map((el) => ({
    tag: el.tagName,
    type: el.getAttribute('type'),
    name: el.getAttribute('name'),
    id: el.id || null,
    placeholder: el.getAttribute('placeholder'),
    autocomplete: el.getAttribute('autocomplete'),
    text: (el.textContent || '').trim().slice(0, 200),
    href: el.getAttribute('href'),
    disabled: 'disabled' in el ? el.disabled : undefined,
    ariaLabel: el.getAttribute('aria-label'),
  })).filter((x) => x.name || x.id || x.placeholder || x.text || x.href || x.ariaLabel)
);

const result = {
  finalUrl: page.url(),
  title: await page.title(),
  bodyText: (await page.locator('body').innerText()).slice(0, 5000),
  interactive,
};

fs.mkdirSync('security/hubspot-ctf/artifacts', { recursive: true });
fs.writeFileSync('security/hubspot-ctf/artifacts/signup-dom.json', JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
await browser.close();
