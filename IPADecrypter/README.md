# IPA Decrypter for iOS 18–27

This project builds a **real iPhone IPA**, not the desktop console. The SwiftUI app includes a native iOS **Go c-archive** built from pinned londek/ipadecrypt core packages.

## iOS engine

The new workflow fetches pinned source commit 9958b9298b62dfef5053d9b6491634c006f3d4e7, compiles a Go C archive using GOOS=ios / GOARCH=arm64, and links it directly into the SwiftUI app. The bridge includes:
- `internal/fairplay` and `internal/pipeline` for complete authorized offline FairPlay decrypt with SINF/SUPF and the matching account credential
- `internal/pipeline.Verify` for source-vs-output cryptid, ciphertext, zero-fill and untouched-byte verification

The **default iOS UI remains credential-free** and uses the device-assisted path on targets embedded at build time. It now invokes upstream Go verification after the device-mapped pages have been written and the IPA rebuilt. The authorized offline method is linked but not exposed as a misleading credential-less button.

The Go upstream CLI's `bootstrap` is a desktop workflow requiring a jailbroken device with root SSH and one installed App Store purchase. It **cannot mint the reusable key through a regular stock iPhone application, device pairing record, worse_query, or LocalDevVPN**. None of those methods is claimed as a substitute.

## worse_query

The original GPL-licensed worse_query.m backend is compiled and the SwiftUI diagnostic invokes it with its required App Group. The IPA must be signed with provisioning that authorizes `group.com.nightvibes33.ipadecrypter`. The upstream project doesn't explicitly list iOS 27.0.1 as supported. This gives data-container sandbox extensions, not access to the FairPlay key or an installed executable's process memory.

## Building and using

The GitHub Actions workflow `.github/workflows/build-ipa-decrypter.yml` builds the native app via Xcode 27 and publishes `IPADecrypter-upstream-Go-iOS-unsigned`, containing `IPADecrypter-iOS-Go-unsigned.ipa` and SHA-256. **This workflow is the iOS deliverable.**

For the device-assisted FairPlayed-style experiment, a licensed target IPA must be embedded before the app is signed and installed. The public repository intentionally does not include owner-bound SINF/SUPF records. A PRIVATE repository and `EMBEDDED_IPA_URL` Actions secret can stage the target. Imported IPAs are currently inspection-only because iOS FairPlay cannot access their ordinary app data-container locations for the device mapping technique.

The device-assisted process has not been validated against iCarCast on a physical iPhone. An unsigned build is not proof of decryption. A valid Apple developer signature is needed to install the helper; a decrypted IPA must also be resigned.

## Licenses / attribution

- `londek/ipadecrypt`: MIT license, pinned upstream core compiled inside the app; no third-party credentials bundled
- `forcequitOS/worse_query`: GPL-3.0-or-later, compiled into app
- Original Swift FairPlay adaptation: GPL-3.0 from `EthanArbuckle/fairplay-decrypt`
- `ZIPFoundation`: MIT

The mistaken desktop-console workflow and wrappers have been removed from this branch. The old GitHub run cannot be retroactively retracted but is not the requested output.
