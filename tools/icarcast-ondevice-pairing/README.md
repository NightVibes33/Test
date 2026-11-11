# iCarCast built-in iDevicePair / local development VPN

**Target:** original decrypted iCarCast. Preserve the proprietary CarPlay receiver, all original assets and networking code. This module is an additive UI + pairing / developer-service tool, not a CarPlay replacement.

The floating **Pairing** button is injected via a separate framework into the *existing* app window (no duplicate app, no separate installation). It provides a system document picker for genuine RP records, secure protected storage under Library/Application Support (0600, not exposed through Files), generation of new RP host keys through **MIT** idevice, Bonjour `_remotepairing._tcp` port discovery with manual override for iOS 27, a real `tunnel_create_rppairing` handshake over local VPN IP 10.7.0.1, and a built-in Packet Tunnel extension patterned on MIT StosVPN. All network calls run asynchronously and never alter iCarCast's `NEHotspotNetwork.fetchCurrent` behavior.

## Critical requirements

- **Not** classic `idevicepair pair`/Lockdown `HostID` records. Import a modern RP pairing file with `public_key`/`private_key`/`identifier`; a classic record is explicitly rejected.
- The built-in VPN is an **.appex**, not an ordinary library. The SideStore-signed app and extension require valid provisioning profiles authorizing `com.apple.developer.networking.networkextension` containing `packet-tunnel-provider`; otherwise iOS refuses to configure or run it. The side loader must re-sign the extension and framework. No entitlement bypass is claimed.
- VPN starts only after iOS grants the user permission.
- The RP connection verifies access to developer services over RSD, not actual CarPlay. **There is no evidence that this transport substitutes for the original wireless CarPlay data path.** The CarPlay receiver remains unchanged, and Wi-Fi-free CarPlay has not been proven.
- Apple may change service port per device or firmware; discover it from Bonjour or enter the correct port. Never assume 49152.
- No pairing material, certificates, private keys, Wi-Fi passwords or app IPA are committed to GitHub. The CI downloads only public MIT idevice linking material.
- The pairing file stays private (not in user-visible Files). Debug logs are in Files → On My iPhone → iCarCast → CarCastDebug, and redact pairing secrets.

## Open source credits

- `jkcoxson/idevice` MIT (Copyright 2026 Jackson Coxson): https://github.com/jkcoxson/idevice
- `SideStore/StosVPN` MIT (Copyright 2025 SideStore Team): https://github.com/SideStore/StosVPN
- `OpenMinis/iCTRL` Apache 2.0 used as a technical reference only: https://github.com/OpenMinis/iCTRL
- `StikDebug` AGPL is referenced for architecture, **its source is not copied into this module**. An MIT-licensed idevice static build is obtained via its published binary snapshot for CI; verify the library provenance before redistributing.

## Build and test

Run `.github/workflows/build-icarcast-ondevice-pairing.yml` on a hosted macOS runner. It compiles the device framework with the real idevice FFI, compiles the embedded PacketTunnel extension, builds a simulator-only test host (its actual RSD pairing calls are excluded by TARGET_OS_SIMULATOR), and publishes an artifact with executable blobs, plists, signing templates and a repack script. Packaging with your **local** decrypted IPA is performed off GitHub to keep private materials out of the public repository. Simulation is not a genuine CarPlay test.

## Install fix: nonrunnable .appex (November 11, 2026)

The first SideStore IPA accidentally linked `CarCastLocalTunnel.appex/CarCastLocalTunnel` with `clang -bundle`, creating Mach-O `MH_BUNDLE` (filetype 8) rather than an iOS app-extension executable. iOS `installd` rejected it with “does not contain any code that is runnable on this device.” The build now uses `-fapplication-extension -Wl,-e,_NSExtensionMain` without `-bundle`, and fails CI unless the result is arm64 `MH_EXECUTE` with a valid entry point. The IPA repacker also rejects a non-executable .appex. A valid Apple-authorized packet-tunnel provisioning profile is **still required** for SideStore to sign/install/start the VPN extension.
