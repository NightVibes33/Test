# Real-account validation harness

This harness validates the CloudKit JS postMessage candidate using only a researcher-owned Apple account and CloudKit container.

## Safety

- Use only a CloudKit container owned by the researcher.
- Do not commit the CloudKit Web API token.
- The victim page accepts the token at runtime and keeps the resulting session in sessionStorage only.
- No private records need to be created, read, modified, or deleted.
- The attacker page sends only the synthetic marker `OAI_REAL_ACCOUNT_TEST_CKSESSION_20260928`.

## Required Apple setup

CloudKit JS requires an existing CloudKit container with Web Services enabled and a Web API Token authorized for the exact victim-page origin.

## Validation

1. Serve `victim.html` and `attacker.html` from two different HTTPS origins.
2. Enter the researcher-owned container ID and Web API Token in the victim page.
3. Click Configure CloudKit, then use Apple’s generated Sign In button.
4. Authenticate only the researcher’s Apple account.
5. Confirm the victim reports an authenticated CloudKit identity.
6. Start a fresh auth flow, then from the different-origin attacker page send the synthetic ckSession marker while CloudKit JS is awaiting the popup response.
7. Observe whether the victim token store accepts the cross-origin value.
8. Capture only metadata proving the injected value reached the subsequent CloudKit request; do not access records belonging to anyone else.
