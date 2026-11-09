# IPA Decrypter · on-device FairPlay + worse_query

## Actual behavior

The default interface no longer asks for a 16-byte FairPlay account credential. It presents a credential-free **Device-assisted FairPlay** action for a licensed encrypted target that was embedded in the helper bundle at build time, an **Import IPA** button for inspecting an IPA and showing whether it is encrypted, and an actual **worse_query ContainerManager sandbox-extension test**.

**Do not confuse inspection with decryption.** FairPlayed documents that fairplayd cannot read an IPA copied into an ordinary app data container. As a result, imported IPAs cannot be decrypted merely by tapping a button after installation. The imported IPA is inspected only. To decrypt using the device backend, embed that target into a freshly built/signed helper app beforehand, then install that helper on the iPhone signed in to the account holding a license.

The embedded backend calls mremap_encrypted with cryptid model=2 and validates every mapped page before patching any encryption flag. No source claims that GitHub cloud runners can decrypt encrypted FairPlay binaries; only a physical licensed iPhone can run the device path. Re-sign exported IPA outputs.

## Bundled worse_query: actual implementation

The following upstream source from https://github.com/forcequitOS/worse_query is included and compiled, NOT a simulated directory listing:
* Sources/worse_query.h
* Sources/worse_query.m

The bridge to Swift is in Sources/DeviceFairPlay.h. The Xcode target references IPADecrypter.entitlements with App Group **group.com.nightvibes33.ipadecrypter**. The on-device diagnostics call worse_query(target, groupID, alt_flags, false), consume the real returned sandbox extension, check the listing, and call worse_query_release(handle) afterward.

Important: upstream implementation temporarily removes/replaces its *own App Group* Library/Caches directory with a symlink during its ContainerManager query. Do not save valuable files in that directory. An unsigned IPA includes source entitlements but **cannot grant them by itself**. The end user's signing/provisioning profile must authorize group.com.nightvibes33.ipadecrypter. A simple ad hoc or free-signed installation might not have this entitlement. Missing group returns an actionable message.

Upstream reports compatibility with iOS 26.0–26.7.2 and iOS 27.2. It is NOT verified by us on iOS 27.0.1. This is a sandbox-extension/file-container tool, **not** a Keychain/FairPlay-key extractor. It does not directly turn an imported data-container IPA into a decryption source for fairplayd.

LocalDevVPN/RSD and pairing checks remain separate. They do not import Apple ID secrets or change FairPlay license ownership.

## Build

The GitHub Actions workflow at .github/workflows/build-ipa-decrypter.yml builds ARM64 with Xcode 27 and creates an **unsigned IPA artifact** named IPADecrypter-iOS27-unsigned. The GitHub runner validates compilation/archive integrity; physical-iPhone testing is still needed.

Optional embedded payload: on a PRIVATE copy of the repo, provide EMBEDDED_IPA_URL as a private Action secret pointing to the licensed encrypted IPA, then trigger the workflow. The public repo refuses embedding because that would expose account-bound SC_Info records in a public artifact.

## License

GPL-3.0-or-later applies. The included original worse_query source is Copyright (C) 2026 Taj C (forcequit). FairPlayCore.swift is a Swift adaptation of EthanArbuckle/fairplay-decrypt (GPL-3.0); device VM technique is based on public technical research by morzelowski/FairPlayed.

References: 
https://github.com/forcequitOS/worse_query
https://github.com/EthanArbuckle/fairplay-decrypt
https://github.com/morzelowski/FairPlayed
