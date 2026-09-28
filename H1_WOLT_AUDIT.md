# Wolt HackerOne audit — 2026-09-28

Program: `wolt`
Status: open, paid
Program start: 2026-07-23
Public disclosed reports returned by HackerOne at setup time: 0

## Why this target
- Not present in existing `NightVibes33/Test` H1 branches.
- Critical severity is allowed on the primary auth/API/mobile assets.
- Wolt explicitly highlights cross-role authorization as interesting:
  - regular customer JWTs should have limited access to corporate/drive/merchant surfaces
  - courier accounts are not provided
  - program text specifically calls out interaction with courier APIs without a courier account as interesting
- Use only researcher-owned/test accounts and the program-provided test entities.
- Include `X-HackerOne-Research: <H1 username>` on requests.

## Primary hypothesis
A JWT issued to a normal Wolt customer may be accepted by a courier/partner/admin API without enforcing the expected role or audience boundary.

Potential classes:
- Broken access control / missing function-level authorization
- JWT audience/scope confusion
- Cross-service token acceptance
- IDOR only when demonstrated using researcher-owned/program-provided test entities

## Priority assets
- `authentication.wolt.com`
- `drive.wolt.com`
- `restaurant-api.wolt.com`
- Wolt Courier Partner apps (iOS/Android)
- `*.wolt.com` where explicitly in scope

## Constraints
- No access to other users' data.
- No payment-processor testing.
- No brute force, DoS, mass entity creation, or automated high-volume scanning.
- Keep testing low-volume and stop at minimum proof.
- Public GitHub source references are reconnaissance only; a report needs live impact on an in-scope asset.

## Duplicate-risk note
HackerOne can expose our own private reports and publicly disclosed Hacktivity reports. It cannot expose other researchers' private/undisclosed submissions, so zero public disclosures does not guarantee zero duplicates.
