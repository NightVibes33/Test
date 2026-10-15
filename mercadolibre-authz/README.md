# Mercado Libre — owned-account order authorization probe

**Status:** No vulnerability has been discovered or reproduced by this branch. It contains a real-HTTP test harness, not a finding.

## Scope and source

- HackerOne: https://hackerone.com/mercadolibre
- Explicit in-scope Tier 1 target: `api.mercadolibre.com` (structured scope ID `73176`)
- Program explicitly prohibits mass scanning, brute force, third-party account compromise, account abuse, and misuse of test users.
- Official [Start testing](https://developers.mercadolibre.com.ar/en_us/net/start-testing) guide: Mercado Libre provides test users on production (not a separate sandbox). Generate users through the authorized developer API, maximum 10 per account; use test users only for test transactions.
- Official [Sales/Orders API](https://developers.mercadolibre.com.ar/en_us/about-our-api/manage-sales) documents `GET https://api.mercadolibre.com/orders/{ORDER_ID}` with bearer authentication.

## Objective

Determine whether the Orders API properly denies a third, unrelated **developer-created test user** access to an order intentionally generated only between a separate buyer test user and seller test user. The outsider and anonymous response bodies are not saved; only HTTP statuses and response SHA-256 hashes are recorded.

### Setup

1. Register your own Mercado Libre developer app and obtain its permitted access token using the official authentication flow.
2. Create **three separate test users** using the documented `POST /users/test_user` flow. The endpoint requires a developer token, accepts `{"site_id":"MLA"}`, and returns one-time test credentials. Don't paste credentials in the repository, ChatGPT, Actions inputs, or logs.
3. Make a controlled `Item de Prueba - Por favor, NO OFERTAR` listing using the seller test user, and create exactly one test order using the buyer test user (documented test-user flows only). **Do not use a real customer or real payment.**
4. Securely obtain valid access tokens for all three developer test users, through the documented OAuth flow; the three tokens must resolve to distinct `test_user` users via `GET /users/me`.
5. Use the seller/buyer order ID **only if you created that order yourself**.

### Local execution (including iSH)

```sh
export ML_TEST_SELLER_TOKEN='[seller test-user token]'
export ML_TEST_BUYER_TOKEN='[buyer test-user token]'
export ML_TEST_OUTSIDER_TOKEN='[third unrelated test-user token]'
export ML_OWN_TEST_ORDER_ID='[your own test order id]'
python3 mercadolibre-authz/owned_order_probe.py
```

For GitHub Actions, use **repository Actions secrets** named `ML_TEST_SELLER_TOKEN`, `ML_TEST_BUYER_TOKEN`, `ML_TEST_OUTSIDER_TOKEN`, then invoke the workflow manually with only your controlled test order ID.

### Security checks enforced in code

1. Only HTTPS to `api.mercadolibre.com`.
2. Only 7 fixed GET requests; no discovery, ID iteration, mutations, brute force, or redirects.
3. Fail closed if any of the three credentials does not belong to an official `test_user` or two roles share an identity.
4. Refuse the outsider test unless the target order is readable to both intended buyer and seller and its `seller.id` and `buyer.id` match the test user IDs.
5. Compare outsider and anonymous responses, recording only HTTP statuses and digests. If unrelated access returns 2xx and a matching order ID, classify as **candidate only**, not an established bug.
6. Evidence never includes authentication tokens or unredacted order bodies.

**Verdict semantics:** A green CI run only proves the verifier ran and did *not* observe a suspicious outsider read. It does not establish a security finding. A candidate result also requires manual validation of sensitive fields, expected permissions, and repeatability before reporting.

### Program nuances

- The stated reward examples are **not payout guarantees**. High/Critical findings are assessed using CVSS v3.1 and the program's tier formula.
- Explicit exclusions include KYC-only non-monetary actions, the Collaborators feature, GraphQL DoS, and Melidolar.
- The site accepts reports, but your personal HackerOne account's submission eligibility is **not yet confirmed**; a previous WordPress draft returned HTTP 403 at submit time.
