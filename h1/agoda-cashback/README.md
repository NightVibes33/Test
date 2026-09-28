# HackerOne — Agoda fresh Critical-scope hunt

Program: `agoda-public`

Fresh Critical-capable scope added 2026-09-01:

- Scope `1036250`: `https://www.agoda.com/account/cashback`
- Scope `1036251`: `https://www.agoda.com/account/agodacash`

## Why this branch

Agoda's policy says IDOR can range up to Critical depending on demonstrated impact.
These account-money surfaces were added to bounty scope on 2026-09-01.

A fresh public Agoda research capture from 2026-08-26 observed authenticated state keys:

- `promoWalletResult`
- `loyaltyProfileInfo`
- `rewardsMember`
- `vipProgress`
- `isLoyaltyCashEnabled`

It also observed Agoda using GraphQL plus REST/BFF endpoints.

## Test strategy

Use only two accounts owned by the researcher: Account A and Account B.

1. Open `/account/cashback` and `/account/agodacash` on Account A and export a HAR.
2. Repeat with Account B.
3. Run `analyze_har.py A.har B.har`.
4. Inspect requests that differ by account-bound identifiers.
5. For a single candidate request, replay only against the researcher's own second account.
6. Stop after proving unauthorized read/write impact; do not access another customer's data.

Agoda requires a research identifier on requests. Use a User-Agent containing
`hackerone-<H1 username>` during live testing.

No automated scanning is used by this harness. It performs offline HAR analysis only.
