# iCarCast: SideStore network identity fallback

This is an **iOS arm64 framework that gets embedded in an already-decrypted iCarCast IPA**, together with a deterministic, non-destructive Mach-O load-command patcher. It is not a desktop application or a rewritten CarPlay receiver. The patch specifically addresses the case where the original TestFlight build can read its Wi-Fi network but a SideStore-signed copy receives `nil` from `NEHotspotNetwork.fetchCurrentWithCompletionHandler:`.

## What changes

1. Calls Apple's real `NEHotspotNetwork.fetchCurrentWithCompletionHandler:` first. If the system returns a real network, the original result is passed through **unchanged**.
2. If it returns `nil`, checks a locally stored manual SSID/password, or shows a **Wi-Fi for CarPlay** prompt so the user can supply them. The password is stored exclusively in this installation's device-only Keychain record, never embedded in the IPA or sent over the network.
3. Creates a typed `NEHotspotNetwork` fallback object backed by the user-provided SSID (and open/personal security). This lets the *original* iCarCast preflight path try the user-selected SSID rather than stopping at “No Wi-Fi to read”.
4. The original **This iPhone**, **Connect**, AirPlay, CarCastAirPlay framework, UI, assets, and existing Wi-Fi password features are preserved. No original code instructions are rewritten. Only a new Mach-O `LC_LOAD_DYLIB` record is appended to header padding.
5. No cryptid-only fake decrypt: the patcher requires the source executable to have already been legitimately decrypted (cryptid = 0). It won't accept an encrypted IPA.

**This is an experimental runtime fallback, not a guaranteed CarPlay fix.** A user-entered SSID **cannot prove the phone is actually joined to that network**. The prompt explicitly asks for the actual currently joined SSID and password. A SideStore provisioning profile must still authorize any protected networking functionality that iCarCast later uses. This shim cannot make Apple grant unavailable entitlements, and it cannot make an iPhone's own hotspot function as a connected Wi-Fi network. On-device CarPlay startup and SideStore signing have not been verified in CI.

## Build

The workflow `build-icarcast-sidestore-fallback.yml` compiles `src/CarCastWiFiFallback.m` with the iOS SDK from Xcode 27, checks it is an ARM64 `MH_DYLIB`, runs tests, and uploads a small framework/patcher artifact. It does **not** upload third-party proprietary binaries or your original App Store IPA to GitHub.

## Use with your own decrypted iCarCast IPA

After downloading the workflow artifact and extracting `CarCastWiFiFallback-iOS27.zip`:

```bash
python3 patch_icarcast.py \
  --input /path/to/your/decrypted-iCarCast.ipa \
  --framework CarCastWiFiFallback.framework/CarCastWiFiFallback \
  --output /path/to/your/iCarCast-wifi-fallback-unsigned.ipa \
  --manifest /path/to/your/iCarCast-wifi-fallback-manifest.json
```

The resulting IPA is **unsigned**. SideStore must sign both the newly added framework and main executable and install with an appropriate provisioning profile. The patch preserves the original app bundle identifier and avoids embedding stale code signatures. The resulting app cannot inherit permissions or Keychain items from the original developer's TestFlight installation automatically.

### Limitations and how to verify

1. Install through SideStore and confirm the library is signed and loaded. If you see the old “No Wi-Fi to read” dialogue without the new **Wi-Fi for CarPlay** prompt, this shim did not load or the method was not reached.
2. With an active external Wi-Fi connection, enter its **exact SSID** and genuine password. This is needed because the OS refuses to expose the SSID on a signature without the authorized entitlement. Never enter your Apple ID or FairPlay `.bin` as Wi-Fi credentials.
3. Tap **This iPhone**. The original iCarCast logic should now advance past the empty-name check. Whether CarPlay actually starts depends on iOS services and the SideStore provisioning profile; test on physical hardware and capture the displayed error.
4. Don't use your own iPhone's Personal Hotspot as the “connected network”; that's not a substitute for joining Wi-Fi. Do not use the fallback to spoof a different network: mismatched SSIDs may make an Apple Wi-Fi configuration fail.

## Privacy / integrity

- No private Apple FairPlay credential, signing keys, pairing files, or account-bound IPA are checked in.
- The manual network SSID/password is stored in the *device-only Keychain* with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- If Apple supplies real network information, the runtime passes it through untouched.
- IPA patcher rejects still-encrypted binaries, duplicate ZIP entries, non-empty header padding, and overwriting existing output.
- Original app binaries/resources remain byte-for-byte preserved except for the added Mach-O load command and new framework; all files keep original ZIP metadata and executable permissions.