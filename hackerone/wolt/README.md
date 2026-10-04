# Wolt HackerOne Hunt — 2026-10-04

## Program
- HackerOne handle: `wolt`
- Public bounty opened: 2026-07-23
- Hacker identity: `zyn33`
- Required live-test header: `X-HackerOne-Research: zyn33`
- Disclosed HackerOne reports observed at hunt start: 0

## Critical-capable priority scope
- `authentication.wolt.com` — OAuth2 / OIDC / JWT
- `corporate.wolt.com`
- `drive.wolt.com`
- `merchant.wolt.com`
- `ops.wolt.com`
- `restaurant-api.wolt.com`
- `wolt.com`

## Hunt priorities
1. OAuth/OIDC trust boundaries: redirect URI, PKCE, state/nonce, audience/client confusion, issuer validation.
2. Cross-role authorization using a normal Wolt user identity.
3. BOLA/IDOR only against researcher-owned data or program-designated test entities.
4. JWT scope/role/tenant confusion across corporate, drive, merchant, ops, and restaurant-api.

## Rules followed
- Low-volume targeted requests only.
- Include the required HackerOne research header on live requests.
- Do not access or modify unrelated customer, merchant, courier, employee, or venue data.
- Do not submit until a reproducible Medium/High/Critical security impact is demonstrated.

## PoC policy for this branch
Once a finding is verified, commit the complete reproduction here: prerequisites, exact requests/scripts, trigger, expected/actual results, impact proof, and cleanup.
