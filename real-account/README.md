# Real-account CloudKit validation

This validates the CloudKit JS cross-origin postMessage candidate using only the researcher's Apple Account and a researcher-owned CloudKit container.

## What this proves

The test is successful only if all of these occur:

1. Apple authentication succeeds with the researcher's real Apple Account.
2. CloudKit JS accepts the synthetic cross-origin `ckSession`.
3. The victim page prints `✅ SYNTHETIC SESSION ACCEPTED`.
4. The next CloudKit request carries that injected value and the page prints `✅ SYNTHETIC SESSION PROPAGATED INTO CLOUDKIT REQUEST`.

No private records are needed.

## Apple-side setup

Use a fresh Development container if possible.

1. Open CloudKit Console.
2. Select a researcher-owned container, or create a dedicated research container.
3. Stay in the Development environment.
4. Open API Access and create a Web API Token.
5. For an isolated empty research container, use an origin configuration that permits the localhost victim page.
6. Do not create, query, modify, or delete any user records for this test.
7. Delete/revoke the Web API Token after validation.

The Apple Account password is never stored by these files. Authentication happens only on Apple's sign-in page.

## iPhone / iSH setup

This path does **not** require your Apple ID password in iSH, GitHub, or the PoC files. iSH only hosts two localhost pages. Apple Account authentication, if Apple requires it, happens in Safari on Apple's own sign-in flow. If Safari already has a usable CloudKit session, Apple may reuse it without asking for the password again.

The only CloudKit credential entered into the PoC is a temporary **Development Web API Token** for the researcher-owned container. That token is entered into the victim page in Safari and is not committed to the repository.

Container used by this PoC:

- Name: `Chattest`
- Identifier: `iCloud.com.nightvibes.prism`

Clone or fetch this private branch into iSH, then run:

```sh
cd real-account
sh serve-ish.sh
```

The local pages are:

- Victim: `http://127.0.0.1:8000/victim.html`
- Attacker: `http://127.0.0.1:8001/attacker.html`

Different ports are different browser origins.

The `mo1` App Store Connect signing secrets are not required for this browser/iSH validation. App Store Connect API keys and CloudKit Web API tokens are separate credential systems.

## Real-account sequence

1. Open the attacker URL in Safari first.
2. Tap **Open victim** so the attacker retains a Window reference.
3. In the victim tab:
   - verify the pinned container is `iCloud.com.nightvibes.prism`;
   - enter the temporary Development Web API Token;
   - leave the environment set to Development.
4. Tap **Configure CloudKit**.
5. Use Apple's generated **Sign In** button.
6. Authenticate the researcher's Apple Account on Apple's page and complete 2FA if requested.
7. Confirm the victim reports the researcher's CloudKit identity.
8. Sign out / restart the auth flow so CloudKit JS is waiting for the popup authentication message.
9. Return to the attacker tab and tap **Send synthetic ckSession**.
10. Return to the victim and tap **Check auth state**.

Record only the boolean/metadata output. Never copy a real `ckSession`, `ckWebAuthToken`, cookie, or private record into the report.

## Expected vulnerable result

```text
✅ SYNTHETIC SESSION ACCEPTED
✅ SYNTHETIC SESSION PROPAGATED INTO CLOUDKIT REQUEST
```

If the first appears but the second does not, the message primitive exists but the real authenticated request path did not consume the injected session.

## Cleanup

- Delete/revoke the temporary CloudKit Web API Token.
- Remove any dedicated research container if it is no longer needed.
- Clear Safari data for the localhost origins if desired.
