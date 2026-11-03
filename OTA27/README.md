# OTA27 Blocker — unsigned iOS app

An iOS 27 OTA-profile companion and **experimental** AirLift diagnostics app. Lives under `OTA27/` in the Test repository; the existing LiveContainer project is untouched.

## What it does
- Opens the exact profile linked by the user at https://kittymaxine.com/blockota.mobileconfig or shares the checked-in copy.
- Profile uses `com.apple.dnsSettings.managed`, DoH server `https://hi.frcoal`, and `SupplementalMatchDomains = [gdmf.apple.com]`. The DNS resolver is third-party controlled: evaluate its privacy/trust before installation.
- Runs a limited HTTPS connectivity check to the OTA catalog hostname. This is **not** a definitive OTA-blocking test.
- With a pairing file and tunnel, streams AirLift paired-device syslog and filters software-update related messages.
- Optionally invokes AirCard-iOS's AirTraffic **temporary write/read-back canary** in one of two predetermined directories. This stages Books metadata and attempts cleanup; it can fail and leave temporary files. It does **not** modify OTA daemons or update preferences.
- Saves only pairing credentials in the app sandbox; exported diagnostics exclude credential files. Syslog can still include sensitive text; inspect before sharing.

## Limits / expectations
- **No silent profile installation.** User completes installation in iOS Settings. The profile does not guarantee a permanent disablement of OTA updates.
- **Not a full filesystem scanner.** AirLift's exposed FFI offers test-file write/read-back but not generic arbitrary directory enumeration.
- **No root/kernel access established.** Merely confirming a canary write is not proof that an OTA preference, softwareupdated, or a boot-time policy can be patched.
- AirCard upstream reports iOS 18–27.0.1 works, but iOS 27.2 beta 3+ patches AirTraffic; no personal device run is claimed.
- Before probing, create/import a local pairing plist (e.g. using the upstream AirCard tool) and start a compatible local VPN/tunnel. These are not configured automatically.
- Legacy iOS managed update-deferral profile keys are removed in iOS 27. Supervised DDM deferral is limited to 1–90 days, not permanent.

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
