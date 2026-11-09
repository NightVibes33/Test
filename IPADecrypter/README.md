# Native IPA Decrypter for iOS 18–27

An unsigned SwiftUI iOS app with two real FairPlay decryption paths. Neither path simply clears cryptid without decrypting the encrypted Mach-O pages.

## Path A: offline license-authorized decryption

Import an encrypted IPA through Files. Import a separately obtained 16-byte FairPlay credential for the Apple account that licensed the IPA. The Swift implementation parses Mach-O arm64 encryption commands, FairPlay SINF and SUPF v3/v5 records, derives per-page AES keys, replaces the ciphertext with plaintext, clears the encryption command only afterwards, removes account-bound SC_Info files, and rebuilds a Payload/*.app IPA in Documents/Decrypted. Share the file with the app UI and sign with your own valid signing certificate before installation.

The account credential is held only in memory and not included in exported IPAs. No pairing file or developer certificate can substitute for a FairPlay account credential.

## Path B: licensed device-assisted decryption

The app includes an independent native implementation of the public FairPlayed research method (mremap_encrypted with model cryptid 2), plus arm64 page verification and repackage. It does not need an exported account credential. A licensed encrypted app must have been embedded as resources in the installed helper app at BUILD time. FairPlayed's research shows fairplayd cannot access normal iOS app data-container copies, so an IPA imported after installation cannot be decrypted by this mode. The iPhone must be signed in to an Apple account holding a valid license for that app. This method is only reported tested by its author on iOS 27.0.1, and this implementation itself needs physical-device verification.

To create an embedded-target IPA build, use a PRIVATE repository and set the secret EMBEDDED_IPA_URL to a short-lived URL for the licensed IPA, then rerun the build workflow. The build refuses to embed account-licensed contents while the repository is public. Normal public builds produce the working tool without a bundled target, with both backends present.

## Build

Push the temporary branch to trigger .github/workflows/build-ipa-decrypter.yml, which runs on GitHub-hosted Xcode 27 (Apple Silicon). After success, retrieve IPADecrypter-iOS27-unsigned from the Actions run. The archive is unsigned and must be signed before sideloading to a real device. Xcode runner validation is compilation and archive integrity, not proof that any device has successfully decrypted an IPA.

## worse_query, LocalDevVPN and pairing files

These grant different filesystem or device-service capabilities and are NOT FairPlay account credentials. The published worse_query PoC documents supported system/app containers, not access to reusable FairPlay account keys. The app does not harvest or upload secrets and does not claim unsupported Keychain access. Pairing may help device connectivity for development workflows but cannot replace either valid authorization path above.

## Sources and licenses

Offline FairPlay key derivation is adapted from the GPL-3.0 project EthanArbuckle/fairplay-decrypt. GPL-3.0 full license text is included at IPADecrypter/LICENSE. Device-assisted mapping code is an independent implementation informed by the documented approach at morzelowski/FairPlayed, without redistributing its source. ZIPFoundation is MIT-licensed.

References:
https://github.com/EthanArbuckle/fairplay-decrypt
https://github.com/morzelowski/FairPlayed
https://github.com/forcequitOS/worse_query
