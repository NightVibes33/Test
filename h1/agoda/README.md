# HackerOne Agoda Public — fresh Critical scope

Program: `agoda-public`

Fresh Critical-capable assets added 2026-09-01:

- Scope ID `1036250` — `https://www.agoda.com/account/cashback`
- Scope ID `1036251` — `https://www.agoda.com/account/agodacash`

Anti-duplicate checks performed through HackerOne:

- Public disclosed reports for `agoda-public`: 0
- Reports from connected HackerOne account for `agoda-public`: 0
- Program is open and bounty-paying.

Program constraints that matter:

- No automated security testing or scanning.
- Use only self-provisioned test accounts.
- Requests used for testing must identify the researcher, preferably with
  `User-Agent: hackerone-<username>`.
- Do not access, modify, or retain another user's sensitive data.
- Demonstrated impact controls bounty severity.

Highest-value manual hypotheses for these fresh account-value surfaces:

1. Cross-account IDOR / broken object-level authorization affecting cashback or AgodaCash balances.
2. Broken function-level authorization allowing a normal account to invoke privileged redemption/transfer functions.
3. Authentication/session confusion between two self-owned accounts.
4. Server-side amount/currency/trust-boundary errors that change value without authorization.
5. State-changing request replay or ownership binding failures that can be demonstrated only between self-owned test accounts.

This branch intentionally contains offline analysis tooling only. It does not
send automated requests to Agoda because the program prohibits automated
security testing.
