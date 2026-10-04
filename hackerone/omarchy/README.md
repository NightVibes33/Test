# Omarchy HackerOne Hunt — 2026-10-04

## Target
- HackerOne program: `omarchy`
- In-scope source: https://github.com/omacom/omarchy
- Required target branch: `quattro`
- HackerOne structured scope ID: `1041203`
- Maximum in-scope severity: Critical
- Public bounty opened: 2026-10-01
- Disclosed reports observed at hunt start: 0

## Current target commit
- `2f7302a777dc3b8d2416a94eec22dd606bc33b80`

## Reverse-skill tracks used
- code-audit
- supply-chain-security
- api-security / boundary review
- attack-chain triage

## Validated dead ends
1. Update post-update hooks share the update sudo authorization, but the current source and tests explicitly define this as intentional behavior.
2. Third-party plugin `omarchy.clonedFrom` can inherit a first-party capability profile, but no credential read or other security-boundary impact has been demonstrated yet.
3. The shipped `NOPASSWD` DNS and browser-policy helpers pin root PATH and constrain arguments.
4. The timezone `NOPASSWD` rule was tested locally against a user-writable secure-path shadow. The shadowed command did not match the passwordless rule; sudo required authentication.

## Active hunt
Prioritize:
- package/update signature and channel trust;
- root systemd/udev/PAM references into user-controlled paths;
- plugin authentication-service boundary;
- privileged file publication / symlink / ownership races.

Do not submit until a working local/source PoC demonstrates security impact.
