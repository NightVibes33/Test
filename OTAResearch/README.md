# OTA Research — AirLift diagnostics (iOS 27)

Experimental iOS app to **investigate** update service behavior without overwriting OTA settings. Stored on a temporary branch of NightVibes33/Test; it does not change the original LiveContainer project.

## Research modes
- Live **read-only syslog filter**, via AirCard's \`al_syslog_stream_start\`, watching for \`softwareupdated\`, \`mobileassetd\`, \`MobileSoftwareUpdate\`, \`gdmf.apple.com\`, and related update-service messages. Trigger **Settings → General → Software Update** while scanning, then export a JSON log.
- Optional **AirLift /var/tmp canary probe**, via \`al_exploit_run\`. This is a temporary canary write/read-back/cleanup test, **not a read-only operation** and **not an OTA modification**.
- Open the user-provided \`https://kittymaxine.com/blockota.mobileconfig\` profile for manual approval in Settings. This profile routes **gdmf.apple.com** to a third-party DoH endpoint and is not guaranteed to block all update mechanisms.

## Important limitations
- No demonstrated permanent OTA disable technique; no write to \`softwareupdated\`, \`mobileassetd\`, \`/System/Library/LaunchDaemons\`, preference domains or update assets.
- AirLift's support for iOS 27.0.1 is stated by AirCard upstream, not verified by this project on real hardware.
- Pairing/LocalDevVPN are prerequisites for diagnostic operations; syslog may omit or redact lines.
- Never point the canary at any system/persistent directory.
- An unsigned IPA must be **signed** by a sideloading tool before installing. The user controls manual profile installation and removal.

## Build
GitHub Actions \`OTA Research unsigned IPA\` uses Xcode 26.2 and a pinned AirCard-iOS revision \`40640c4d827aeab8d798285b57d24fcf6be070d0\`. It copies the upstream \`AirliftFFI.xcframework\` plus pairing/network support classes into a dedicated XcodeGen project, compiles without signing, and uploads an IPA artifact. GitHub Actions success alone is **not** device validation.

## Next experiment
1. Establish on-device pairing / LocalDevVPN.
2. Start OTA log scan and trigger an update check.
3. Save JSON and identify observed services and paths.
4. Only then evaluate persistent candidate configuration; no blind writes or launch daemon tampering.
