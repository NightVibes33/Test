# Twilio PKCV canonicalization collision — candidate

Program: `twilio`
Target: official `twilio/twilio-node` SDK / PKCV client validation
HackerOne max severity for Twilio SDK/API scope: Critical

## Candidate

`src/jwt/validation/RequestCanonicalizer.ts` converts each query entry to
`key=value`, then later does:

```ts
const [key, value] = param.split("=");
```

Any additional `=` characters in the value are discarded before the
canonical request hash is generated.

Therefore these distinct parameter values collide:

- `token=abc=ONE`
- `token=abc=TWO`
- `token=abc=`
- `token=abc`

All canonicalize to:

```
token=abc
```

## Security hypothesis

PKCV is intended to cryptographically bind a client-validation JWT to the
HTTP request. If Twilio's live PKCV verification accepts the Node-generated
canonical form, an intercepted/replayed valid PKCV token may fail to bind the
suffix of a query parameter after the first `=`, allowing request mutation
without invalidating client authentication.

This is potentially high/critical impact only if live verification accepts an
altered request and the affected parameter can control a security-sensitive API
operation.

## Current status

- Local canonicalization collision: CONFIRMED.
- Matching public GitHub issue/PR found: NONE in the searches performed.
- HackerOne public Twilio disclosures returned: 0.
- Live Twilio verifier acceptance: NOT YET PROVEN.
- Do not submit as Critical until live verifier behavior and concrete API impact
  are demonstrated on a researcher-owned Twilio account.
