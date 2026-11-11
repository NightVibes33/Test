# iCarCast original-behavior diagnostic-only build

The user's original decrypted iCarCast keeps its CarPlay implementation and resources. This build adds only a logging framework and the minimum Mach-O header record required to load it. No Wi-Fi method swizzling, no fabricated hotspot identity, no Keychain credentials, and no CarPlay implementation replacement.

## Verified upstream research

- [iCarCast user guide](https://github.com/rPlayAI/carcast-public/blob/main/docs/icarcast-user-guide.md): the iPhone must actually join Wi-Fi for This iPhone; a self-hosted hotspot is not enough. The proprietary iCarCast implementation is not publicly available.
- [SideSign](https://github.com/SideStore/SideSign): the signer embeds new provisioning profiles and signs nested frameworks. Source-code or old-signature entitlement text does not grant capabilities.
- [LiveContainer](https://github.com/LiveContainer/LiveContainer): guest app entitlements do not automatically apply to the host.
- [react-native-netinfo](https://github.com/react-native-netinfo/react-native-netinfo/blob/master/CHANGELOG.md) and [NetScope](https://github.com/HrantZak/NetScope): NEHotspotNetwork.fetchCurrent may return nil without an authorized Wi-Fi Information entitlement. NWPath saying wifi=1 does not mean SSID is accessible.

## Usage

Build the framework using .github/workflows/build-icarcast-diagnostics-only.yml (Xcode 27). After downloading its zip, run:

```sh
python3 patch_diagnostics.py --input iCarCast-Original-Decrypted-Minimal.ipa \
  --framework CarCastDiagnosticsOnly.framework/CarCastDiagnosticsOnly \
  --output iCarCast-Original-DiagnosticsOnly-unsigned.ipa --manifest diagnostics-audit.json
```

The output is unsigned; SideStore must sign the main executable and nested framework. On device, the app writes session logs under Files > On My iPhone > iCarCast > CarCastDebug. Logs include original app stdout/stderr, lifecycle, independent read-only Wi-Fi probe, network path, and Objective-C uncaught exceptions. They do **not** include all native crashes or system daemon logs. Review for sensitive information before sharing.

Neither a successful CI build nor an independently loaded framework proves CarPlay will start. The final SideStore-signed app must have a provisioning profile granting the capabilities that its original TestFlight distribution had, including com.apple.developer.networking.wifi-info.

## November 2026: on-device-only feasibility and simulator validation

The iCarCast public source code is unavailable. The proprietary original IPA is a physical-device iOS ARM64 Mach-O (LC_BUILD_VERSION platform=2), not an iOS Simulator binary (platform=7). The developer's This iPhone guide explicitly says the iPhone must join a Wi-Fi network even when the screen is local. Do not claim that Bonjour, localhost, synthetic NEHotspotNetwork, or removing hotspot permissions eliminates that wireless CarPlay dependency.

This build preserves the real proprietary This iPhone implementation and receiver. A new read-only runtime check attempts to query the installed signature's three networking entitlements by dynamically resolving SecTask* functions. If unavailable or blocked, it logs NOT_QUERYABLE / NOT_REPORTED and instructs comparing the final SideStore signature and embedded.mobileprovision. No values/secrets are logged.

GitHub's Xcode runner also compiles the same diagnostics framework for the iOS simulator and boots a SIMULATOR DIAGNOSTIC HOST to verify the framework emits session logs. This host is explicitly NOT iCarCast or a CarPlay simulator. On-device iCarCast CarPlay functionality is still unverified and cannot be proven in the iOS Simulator without a simulator-buildable original receiver.
