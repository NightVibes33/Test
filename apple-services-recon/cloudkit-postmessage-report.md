# Missing postMessage origin/source validation in CloudKit JS 2.6.4 permits cross-origin CloudKit session injection

## Summary

Apple's currently hosted CloudKit JS SDK accepts the first object-like `window.message` event received during its sign-in popup flow without validating either `event.origin` or `event.source`.

The sign-in flow then reads `event.data.ckSession`, installs that value as the CloudKit session, optionally persists it through the configured `authTokenStore`, and retries the CloudKit identity request. A page on an unrelated origin that holds a Window reference to the CloudKit JS application can therefore inject an attacker-chosen CloudKit web-authentication token during sign-in.

I reproduced this with Apple's current hosted SDK, CloudKit JS **2.6.4**, while intercepting every CloudKit API request locally. No real Apple Account credentials, valid CloudKit API token, real `ckWebAuthToken`, or private CloudKit data were used.

The proof of concept demonstrates both:

1. A cross-origin synthetic `ckSession` is accepted and written to CloudKit's configured auth-token store.
2. The next CloudKit request contains `ckWebAuthToken` with the attacker-supplied value.

This is a login-CSRF / session-fixation primitive for web applications using the affected CloudKit JS sign-in flow.

## Affected component

- Apple-hosted SDK: `https://cdn.apple-cloudkit.com/ck/2/cloudkit.js`
- Observed CloudKit JS version: **2.6.4**
- Authentication path: `CloudKit.Container.setUpAuth()` / sign-in popup
- Affected helper: the SDK's popup-message helper used by `_handleSignInURL`

Apple's CloudKit JS documentation directs web applications to load CloudKit JS from Apple's hosted CDN.

## Vulnerability class

- Missing cross-origin message validation
- Session injection / session fixation
- Login CSRF
- Suggested CWE: **CWE-346 — Origin Validation Error**

## Root cause

The popup helper effectively performs the following sequence:

1. Registers a `window` `message` listener.
2. Resolves the authentication promise when `event.data` is object-like.
3. Opens the sign-in popup.
4. Removes the message listener after the first accepted message.

The listener does **not** verify:

- `event.origin`
- `event.source`
- a per-authentication nonce/state value

The CloudKit auth caller then takes `event.data.ckSession` and passes it to the SDK's session setter.

That means the security boundary is based only on the shape of `event.data`, rather than on who sent the message.

## Security impact

A cross-origin page that has a Window reference to a CloudKit JS application can send a crafted message while the victim starts CloudKit sign-in. If the injected value is a valid attacker-controlled CloudKit web-auth token for the same CloudKit container/API-token context, CloudKit JS can establish the application session as the attacker rather than the victim.

The practical result is **login CSRF / session fixation**: the victim can be placed into the attacker's CloudKit-backed account context. Subsequent actions the victim performs in that application may therefore be performed in the attacker's CloudKit account, potentially exposing information the victim enters or causing confused-account actions.

This report does **not** claim direct access to the victim's Apple Account or general iCloud account data. I also tested several first-party iCloud routes pre-auth and did not find those routes directly activating this popup helper.

## Attack prerequisites

A practical attack requires:

1. A web application using the affected CloudKit JS API-token authentication flow.
2. The attacker to obtain a valid CloudKit web-auth token for the same CloudKit container as the attacker account through the normal sign-in flow.
3. The attacker to retain a cross-origin Window reference to the target application, for example by opening the application from an attacker-controlled page.
4. The victim to initiate the CloudKit sign-in flow.

The attacker does not need same-origin DOM access to the target page because cross-origin windows may send `postMessage`.

## Reproduction

The included PoC is deliberately non-destructive. It loads Apple's real current CloudKit JS SDK but replaces all Apple CloudKit API responses with local synthetic responses. It uses only a synthetic API token and a synthetic `ckSession`.

### Files

- `apple-services-recon/cloudkit_postmessage_poc.py`
- `.github/workflows/cloudkit-postmessage-poc.yml`

### Steps

1. Run the PoC:
   `python3 apple-services-recon/cloudkit_postmessage_poc.py`

2. The PoC starts three local origins:
   - victim CloudKit application: `http://127.0.0.1:18123`
   - attacker page: `http://127.0.0.1:18124`
   - synthetic sign-in popup: `http://127.0.0.1:18125`

3. The victim application loads Apple's real:
   `https://cdn.apple-cloudkit.com/ck/2/cloudkit.js`

4. The PoC intercepts all requests to Apple CloudKit/service hosts and fulfills them locally. The first synthetic response is `AUTHENTICATION_REQUIRED` and supplies the local popup URL.

5. CloudKit JS renders its real sign-in button through `setUpAuth()`.

6. The PoC clicks the CloudKit sign-in button. CloudKit JS installs its popup `message` listener and opens the synthetic popup.

7. The unrelated attacker origin sends:
   `{ ckSession: "OAI_SYNTHETIC_CKSESSION_20260928" }`
   to the victim window with `postMessage`.

8. CloudKit JS accepts the message even though it came from the attacker origin and not from the sign-in popup.

9. The SDK writes the synthetic value through `authTokenStore.putToken(...)`.

10. The SDK retries the current-user CloudKit request. The intercepted request now contains the query key `ckWebAuthToken`, and the value is the attacker-supplied sentinel.

## Observed result

Validated GitHub Actions run:

- Run: **36421475591**
- Job conclusion: **success**
- Artifact: **10969582408**

Relevant output:

- CloudKit version: **2.6.4**
- Sign-in button rendered: **True**
- Synthetic popup opened: **True**
- Cross-origin synthetic `ckSession` accepted into auth token store: **True**
- Injected `ckSession` propagated into a subsequent CloudKit request: **True**

The intercepted request sequence is:

### Request 1 — before injection

- Path: `/database/1/iCloud.com.openai.security.research.synthetic/development/public/users/caller`
- Query keys:
  - `ckAPIToken`
  - `ckjsBuildVersion`
  - `ckjsVersion`
  - `clientId`
- No injected sentinel present.

### Request 2 — after cross-origin injection

- Same current-user path.
- Query keys now include:
  - `ckAPIToken`
  - **`ckWebAuthToken`**
  - `ckjsBuildVersion`
  - `ckjsVersion`
  - `clientId`
- The synthetic attacker-supplied sentinel is present in the request URL.

No request containing this synthetic credential reached Apple's CloudKit backend; the PoC intercepted it locally.

## Expected result

CloudKit JS should accept the authentication result only from the popup/window and origin associated with the authentication attempt.

A `message` event from any unrelated origin or Window should be ignored and must not update `ckSession`, persist an auth token, resolve the sign-in flow, or affect subsequent CloudKit requests.

## Negative controls

### First-party iCloud routes

I checked direct unauthenticated iCloud routes for:

- Drive
- Notes
- Photos
- Mail
- Calendar
- Contacts

None directly activated the vulnerable CloudKit popup helper pre-auth in this test.

Run: **36420841860**

Result: **No current direct iCloud app route activated the vulnerable popup helper pre-auth.**

This is why I am reporting the affected component specifically as the Apple-hosted CloudKit JS authentication SDK rather than claiming a direct iCloud.com account takeover.

### Apple sign-in widget listener

The separate Apple authentication widget listener present on iCloud validates the message origin against its configured service origin. The vulnerable behavior described here is the CloudKit JS popup helper, not that widget listener.

## Why the injected token is security-sensitive

Apple's CloudKit Web Services documentation defines `ckWebAuthToken` as the identifier of an authenticated user. It instructs clients to append that web authentication token to subsequent CloudKit requests, which then act on behalf of that authenticated user.

The current PoC confirms CloudKit JS performs exactly that propagation after accepting the cross-origin message.

## Recommended fix

CloudKit JS should bind each authentication attempt to the popup it created and to the expected callback origin.

At minimum:

1. Save the Window object returned by `window.open`.
2. Require `event.source === popupWindow`.
3. Parse the server-provided sign-in/redirect URL and require `event.origin` to exactly equal its expected origin.
4. Bind the response to a cryptographically random per-authentication nonce/state value.
5. Ignore all unrelated messages rather than resolving on the first object-like `event.data`.
6. Remove the listener on completion, cancellation, and timeout.

A robust check should require all of the expected source, expected origin, and per-attempt state/nonce.

## Evidence integrity / safety

The primary PoC intentionally avoids accessing real user data:

- No Apple Account login.
- No real `ckWebAuthToken`.
- No real CloudKit API token.
- No private CloudKit container.
- All CloudKit API requests are intercepted locally.
- Only Apple's public CDN SDK file is fetched from Apple.
- The injected token is a clearly synthetic sentinel.

Relevant repository object SHAs at validation time:

- `apple-services-recon/cloudkit_postmessage_poc.py`: `e8bdead5945f114e3a9def6ae147316ced8b975d`
- `apple-services-recon/cloudkit_current_static.py`: `c6010f89b41631196b5e8c06f8fea5fe55333709`
- `apple-services-recon/icloud_app_popup_reachability.py`: `c07ed498eaeb7d103ac083bfff9154720cba8ebb`
- `.github/workflows/cloudkit-postmessage-poc.yml`: `353ef7e8f298ebe8df8d01578d8517d1be0289fd`

## Apple documentation references

- CloudKit JS:
  https://developer.apple.com/documentation/cloudkitjs

- `CloudKit.Container.setUpAuth()`:
  https://developer.apple.com/documentation/cloudkitjs/cloudkit.container/setupauth

- CloudKit JS configuration and `authTokenStore`:
  https://developer.apple.com/documentation/cloudkitjs/cloudkit.cloudkitconfig

- CloudKit container config / persistent session token:
  https://developer.apple.com/documentation/cloudkitjs/cloudkit.containerconfig

- CloudKit Web Services authentication / `ckWebAuthToken`:
  https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html

## Disclosure status

I have not intentionally publicly disclosed this vulnerability. The reproduction is kept in a private research repository for submission to Apple.
