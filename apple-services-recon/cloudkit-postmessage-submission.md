# CloudKit JS 2.6.4 accepts cross-origin postMessage as authentication result

## Summary

Apple's hosted CloudKit JS SDK does not validate `event.origin` or `event.source` when receiving the authentication result from its sign-in popup.

During `CloudKit.Container.setUpAuth()`, the SDK opens the Apple sign-in popup and installs a `window.message` listener. The listener resolves on any object-like `event.data`. The auth handler then reads `event.data.ckSession`, stores it as the CloudKit session, and retries the current-user request with that value as `ckWebAuthToken`.

A different origin that has a Window reference to the CloudKit application can therefore inject an attacker-controlled CloudKit session during sign-in.

I reproduced this against Apple's currently hosted `https://cdn.apple-cloudkit.com/ck/2/cloudkit.js`, version **2.6.4**.

## Security impact

This creates a **login-CSRF / session-fixation** primitive for sites using CloudKit JS API-token authentication.

A practical attacker can:

1. Authenticate normally to the same CloudKit-backed application as the attacker.
2. Retain a Window reference to the victim's application, for example by opening it from an attacker-controlled page.
3. While the victim initiates CloudKit sign-in, send the attacker's valid CloudKit web-auth token to the victim window with `postMessage`.
4. CloudKit JS accepts the unrelated-origin message as the authentication result and uses the injected session on its next CloudKit request.

The victim application can therefore become authenticated to the attacker's CloudKit account context. Actions or data the victim subsequently enters into that application may be associated with the attacker account.

I am **not** claiming general victim Apple Account/iCloud takeover. I also tested direct unauthenticated iCloud Drive, Notes, Photos, Mail, Calendar, and Contacts routes and did not find them directly activating this popup helper pre-auth.

## Root cause

The SDK's popup-message helper:

- installs a `window` `message` listener;
- accepts the first event whose `event.data` is object-like;
- does not check `event.origin`;
- does not check `event.source`;
- does not bind the response to a per-authentication nonce/state.

The CloudKit auth caller then takes `event.data.ckSession` and installs it as the session.

## Reproduction

Attached PoC: `cloudkit_postmessage_poc.py`

The PoC is non-destructive:

- Loads Apple's real current CloudKit JS CDN file.
- Uses three localhost origins for victim, attacker, and synthetic popup.
- Uses a synthetic container identifier, API token, and `ckSession`.
- Intercepts every request to CloudKit API/service hosts and fulfills it locally.
- No Apple Account login or private CloudKit data is used.

Run:

```
python3 cloudkit_postmessage_poc.py
```

Expected output from my validated run:

```
CloudKit version: 2.6.4
Sign-in button rendered: True
Synthetic popup opened: True
Cross-origin synthetic ckSession accepted into auth token store: True
Injected ckSession propagated into a subsequent CloudKit request: True
```

The intercepted request sequence is decisive:

1. Before injection, the current-user request contains `ckAPIToken` but **not** `ckWebAuthToken`.
2. After the unrelated-origin `postMessage`, the next current-user request contains `ckWebAuthToken`, and its value is the synthetic attacker-supplied sentinel.

Validated GitHub Actions run: **36421475591** (artifact **10969582408**).

### Apple-owned live validation

I also reproduced the same receiver-side flaw on Apple's public CloudKit Catalog:

`https://cdn.apple-cloudkit.com/cloudkit-catalog/`

The safe live PoC:

1. opens the Catalog from a separate research origin and retains the returned `WindowProxy`;
2. opens **Authentication** and executes the Catalog's `setUpAuth()` example with **Run Code**;
3. clicks the Catalog's Apple Sign In control;
4. waits for the Apple authentication popup to open;
5. sends `{ckSession: <synthetic sentinel>}` from the unrelated opener to the exact target origin `https://cdn.apple-cloudkit.com`;
6. intercepts and aborts every outgoing request containing the synthetic sentinel before network transmission.

Observed on the Apple-owned Catalog:

- Authentication sample executed: **True**
- Apple sign-in popup opened: **True**
- Cross-origin synthetic `ckSession` accepted: **True**
- Sentinel persisted in a Catalog cookie: **True**
- Subsequent sentinel-bearing CloudKit requests attempted: **2**
- Sentinel-bearing requests allowed to reach Apple: **0**

Exact-target-origin validation:

- GitHub Actions run: **36421483045**
- Job: **108925016350**
- Artifact: **10969377753**

This demonstrates that the issue is not limited to a synthetic local application: Apple's own CloudKit Catalog accepts, persists, and attempts to use a session value supplied by an unrelated origin.

## Expected behavior

CloudKit JS should accept an authentication result only from the specific popup/window and exact expected origin associated with the active authentication attempt.

Messages from unrelated origins or unrelated Window objects should be ignored and must not modify the CloudKit session.

## Suggested fix

For each sign-in attempt:

1. Keep the Window object returned by `window.open`.
2. Require `event.source === popupWindow`.
3. Require `event.origin` to exactly match the expected authentication callback origin derived from the server-provided redirect URL.
4. Require an unguessable per-attempt nonce/state in the message.
5. Ignore unrelated messages instead of resolving on the first object-like payload.

## Affected Apple component

- Apple-hosted CloudKit JS
- URL: `https://cdn.apple-cloudkit.com/ck/2/cloudkit.js`
- Observed version: **2.6.4**
- Suggested CWE: **CWE-346: Origin Validation Error**

## Apple documentation

Apple documents `ckWebAuthToken` as the identifier of an authenticated CloudKit user and instructs clients to append it to subsequent requests:

https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html

CloudKit JS:

https://developer.apple.com/documentation/cloudkitjs

`setUpAuth()`:

https://developer.apple.com/documentation/cloudkitjs/cloudkit.container/setupauth

I have not intentionally publicly disclosed this vulnerability.
