# HubSpot CTF research — portal 46962361

Authorized HackerOne target only.

## Scope
- Target: https://app.hubspot.com
- Portal: 46962361
- Objective: read the CTF contact properties `firstname` and optionally `super_secret`
- No brute force, social engineering, victim interaction, DoS, or testing against any other portal.

## Method
This branch contains only low-rate, deterministic probes that can be replayed in GitHub Actions. Any request that accepts a portal identifier must use `46962361` only.

Initial observations:
- `GET https://app.hubspot.com/contacts/46962361/` returns the current CRM frontend shell.
- Public CRM v3 object endpoints correctly return HTTP 401 without authentication.
- Current CRM frontend routes relative API requests through `https://app.hubspot.com/api/...`.
