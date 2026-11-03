# OTA27 Blocker — unsigned iOS app

An iOS 27 OTA-profile companion and **experimental** AirLift diagnostics app. Lives under `OTA27/` in the Test repository; the existing LiveContainer project is untouched.

## What it does
- Opens the exact profile linked by the user at https://kittymaxine.com/blockota.mobileconfig or shares the checked-in copy.
- Profile uses `com.apple.dnsSettings.managed`, DoH server `https://hi.frcoal`, and `SupplementalMatchDomains = [gdmf.apple.com]`. The DNS resolver is third-party controlled: evaluate its privacy/trust before installation.
- Runs a limited HTTPS connectivity check to the OTA catalog hostname. This is **not** a definitive OTA-blocking test.
- With a pairing file and tunnel, streams AirLift paired-device syslog and filters software-update related messages.
- Optionally invokes AirCard-iOS's AirTraffic **temporary write/read-back canary** in one of two predetermined directories. This stages Books metadata and attempts cleanup; it can fail and leave temporary files. It does **not** modify OTA daemons or update preferences.
- **No Mac required on iOS 27.** Starts its own local RPPairing host and advertises it via Bonjour; enter the displayed PIN under Settings → Privacy & Security → Developer Mode → Pair with OTA27 Blocker.
- Uses LocalDevVPN in local-tunnel mode to reach paired-device services; configure the separate VPN app locally, then select OTA log scan or an optional canary.
- Existing pairing files are still accepted as a fallback.
- Saves only pairing credentials in the app sandbox; exported diagnostics exclude credential files. Syslog can still include sensitive text; inspect before sharing.

## Limits / expectations
- **No silent profile installation.** User completes installation in iOS Settings. The profile does not guarantee a permanent disablement of OTA updates.
- **Not a full filesystem scanner.** AirLift's exposed FFI offers test-file write/read-back but not generic arbitrary directory enumeration.
- **No root/kernel access established.** Merely confirming a canary write is not proof that an OTA preference, softwareupdated, or a boot-time policy can be patched.
- AirCard upstream reports iOS 18–27.0.1 works, but iOS 27.2 beta 3+ patches AirTraffic; no personal device run is claimed.
- Before probing, activate LocalDevVPN and tap **Pair this iPhone** to generate an on-device pairing record. The app shows a PIN that you approve in iOS Developer Mode. LocalDevVPN itself is a separate app and is not silently installed or configured.
- Legacy iOS managed update-deferral profile keys are removed in iOS 27. Supervised DDM deferral is limited to 1–90 days, not permanent.

## Fully on-device setup (iOS 27)
1. Install/sign and open the OTA27 app and a compatible LocalDevVPN app on the iPhone.
2. In LocalDevVPN, enable its local loopback tunnel. Return to OTA27 and tap **Check local tunnel** (the tunnel interface check is advisory, not proof that a VPN/service works).
3. Tap **Pair this iPhone**. In Settings → Privacy & Security → Developer Mode, select **Pair with OTA27 Blocker** and enter the PIN displayed in OTA27.
4. Return to OTA27. Once the pairing record is ready, use **Start OTA log scan**; optionally run a temporary AirLift canary in the predefined locations. No Mac or computer pairing is required for the iOS 27 path.

The on-device pairing procedure is adapted from Mak5er/AirCard-iOS (MIT). This does **not** establish a permanent OTA disable. A DNS profile must still be installed manually in Settings; AirLift only provides diagnostic/test-file access here.

## Build
The workflow `.github/workflows/ota27-unsigned.yml` uses a macOS GitHub-hosted runner, Xcode, and XcodeGen, then downloads the AirCard-iOS `AirliftFFI.xcframework` at pinned commit `40640c4d827aeab8d798285b57d24fcf6be070d0` (third-party binary; audit before using) and builds with code signing disabled.

**Artifact:** `OTA27Blocker-unsigned-ipa`. The IPA must be signed with a provisioning method before it can be installed on stock iOS. No App Store signing entitlements or sideload installer are bundled.

Run locally on macOS:
```bash
brew install xcodegen
# place the pinned AirliftFFI.xcframework under OTA27/Dependencies/
xcodegen generate --spec OTA27/project.yml --project OTA27
xcodebuild -project OTA27/OTA27Blocker.xcodeproj -scheme OTA27Blocker -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Source credits: [AirCard-iOS by Mak5er](https://github.com/Mak5er/AirCard-iOS) and OTA profile by Mineek, linked at kittymaxine.com. Neither project endorses this derivative.

## Exact NFCARD AirLift transport
Pinned NFCARD revision `16f8bfd20a88a474f59c2d6eda291164a1cc015f`, AirCard upstream revision `097a058c984ffc33ccb697b9dfe8058be3e86244`, with NFCARD `scripts/patch-upstream.py` Rust patch. Uses the unchanged NFCARD `RemotePairingPortDiscovery.swift` and its `al_connection_endpoint_set` FFI, instead of OTA27 previous `40640c4` prebuilt FFI. Builds the Rust library from source. Bonjour `_remotepairing._tcp` supplies the live port before the canary or syslog call.

## Cinder27 archive inventory
The app includes **32 directly accessible executable PoC families**: 31 CVE-labelled source folders plus `arc.rr` RockRidge, from the user-supplied Cinder27 v2.0 archive. Tap any family to open its original native Cinder27 runner; choose Run manually to collect local results and a persistent crash journal. The full 51-module Cinder27 lab also exposes additional variants and tools. The original C, Swift, and Python PoC sources can be exported as a bundled ZIP. Tests do **not** prove a vulnerability merely because a module completes; some modules deliberately crash. There is no automatic execution.

### Grappa symbol bridge
The missing `ALGetGrappaToken` callback is supplied by NFCARD's pinned upstream `GrappaHelper.m`/`.h` and explicitly retained by the linker. This fixes the missing-symbol packaging error, not a guarantee of successful device sync.

Build integrity: the main executable explicitly exports `_ALGetGrappaToken` for AirLift’s runtime `dlsym(RTLD_DEFAULT)` lookup; CI checks the symbol with `nm -gU`. A linked callback does not prove that Apple Books will accept the sync token.

Cinder27 source provenance is pinned to `7949c7ce9fab8139e961058d8ddd60b2bae47a09` from the public Cinder27 repository. CI compares SHA-256 fingerprints of the README, core catalog, app views and CVE-2026-112522 C twin to the user-supplied archive and requires 31 C/Swift CVE pairs plus the RockRidge variant. It stages the five original seed files and checks the compiled IPA resource payload. The independent NFCARD/AirLift component is unchanged by PoC execution.
