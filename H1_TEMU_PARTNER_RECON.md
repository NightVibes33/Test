# HackerOne — Temu Partner Platform (2026-10-05)

Program: `temu`

Target: `https://partner.temu.com`

Structured scope ID: `1041457`

Scope added: 2026-09-28

Maximum severity: **Critical**

## Why this target

- New to the Temu HackerOne scope (added 2026-09-28).
- Bounty-eligible and submission-eligible.
- No prior Temu reports on the connected HackerOne account.
- No public HackerOne hacktivity found for `partner.temu.com` during the initial duplicate check.
- Recent independent HackerOne directory research reports Temu's `signal_requirements_setting.target_signal = -10`, meaning Signal Requirements are disabled.

## Program constraints

- Use only accounts owned by the researcher or accounts with explicit permission.
- Use the HackerOne alias when creating test accounts.
- Add `X-HackerOne-Research: zyn33` to research traffic where possible.
- No social engineering, DoS, or privacy violations.
- Automated-tool output must be manually verified.
- Stop after demonstrating the minimum security impact.

## Current architecture notes

Partner Platform exposes app registration and Temu Open API integrations.

Documented authorization flow:
1. Seller authorizes an application.
2. Temu redirects to the application's callback URL with an authorization code.
3. The code is exchanged using `bg.open.accesstoken.create`.
4. The returned token carries API scopes and mall/store identity.
5. Requests are signed using the application's `app_secret`.

Documented regional Open API hosts:
- US: `https://openapi-b-us.temu.com/openapi/router`
- EU: `https://openapi-b-eu.temu.com/openapi/router`
- Global: `https://openapi-b-global.temu.com/openapi/router`

## Medium / High / Critical hypotheses

### 1. Authorization-code binding

Verify that an authorization code is cryptographically/logically bound to:
- the exact `app_key` that initiated authorization;
- the registered callback/redirect URI;
- the expected region;
- the authorizing mall/store;
- one single token exchange.

Control: code A must fail when exchanged by app B, another region, or after first use.

### 2. Redirect URI binding

The current seller authorization documentation accepts a `redirect_uri` parameter in the authorization URL. Verify that Temu requires an exact authorized callback for the application rather than accepting an arbitrary caller-provided URI.

Do not involve third-party apps or users. Test only between two researcher-owned apps/callback endpoints.

### 3. Token-to-mall authorization

Using two researcher-owned seller/test stores, verify that a token associated with Mall A cannot:
- query orders belonging to Mall B;
- modify Mall B products, inventory, prices, shipment state, returns, or promotions;
- substitute Mall B identifiers in otherwise valid requests.

### 4. API scope enforcement

Create/authorize tokens with deliberately reduced permission packages and verify that endpoints outside the returned `apiScopeList` are rejected server-side.

Priority write surfaces:
- product update / stock update;
- pricing;
- shipping/fulfillment;
- after-sales/refunds;
- promotions;
- advertising.

### 5. Regional authorization separation

Verify that US/EU/Global credentials, codes, tokens, and mall identifiers cannot be replayed across the other regional API hosts unless explicitly intended.

### 6. Webhook/event subscription ownership

Verify that event-subscription configuration is bound to the correct application and mall, and that one app cannot alter another app's event/callback configuration.

## Severity gate

Continue only with candidates demonstrating at least **Medium** impact.

Priority:
1. Cross-mall unauthorized read/write — High/Critical candidate.
2. Cross-app authorization/token compromise — High/Critical candidate.
3. Scope bypass enabling sensitive writes — High candidate.
4. Sensitive order/customer disclosure — Medium/High depending data and scale.

No report should be drafted from documentation alone. A candidate must be manually reproduced with controlled accounts and a working PoC.
