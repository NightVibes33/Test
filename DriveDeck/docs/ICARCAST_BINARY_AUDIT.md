# iCarCast 1.0 (17) IPA: static protocol audit (2026-11-09)

## Provenance & scope

Analyzed the IPA supplied for the project; no binary, bundled framework, signing identity, certificate, private keys, or copied proprietary JavaScript is committed. The analysis is static only. A decrypted executable can still contain copyrighted proprietary implementation, and code-signing or MFi entitlements are not automatically transferable.

- IPA SHA-256: `825ce152dd879681edcca1ea853830fb718598b09fd8e7acb97d1ff07a7dec06`
- Main binary SHA-256: `103a2bf185b705cb573279426623c45063ba4a7b514f1e4df70ab8690a3b4437`
- AirPlay framework SHA-256: `520024f36b1052a87dbb90d5aa7d3e3a24111645fdab3787280deb6ea46967c6`
- Original bundle ID: `ai.rplay.carcast.ios`; display name `iCarCast`; minimum iOS 18.0; iOS 27.0 SDK; app version 1.0 build 17.
- Arm64 Mach-O main executable 8,681,872 bytes; bundled `CarCastAirPlay.framework` 1,334,944 bytes.
- Mach-O `LC_ENCRYPTION_INFO_64` `cryptid = 0` in both binaries: distributed files are decrypted.
- Info.plist declares local network, Bluetooth, location, microphone permissions; background audio; Bonjour services `_airplay._tcp`, `_raop._tcp`, `_carplay-ctrl._tcp` and `_carcast-hu._tcp`.
- Linked Apple frameworks include CoreBluetooth, Network, AVFoundation, VideoToolbox, AudioToolbox, Security, NetworkExtension, CoreLocation and UIKit. Linking alone is not proof of individual feature operation.

## Native receiver protocol clues

The main binary contains symbols/strings consistent with:
- A `CarPlayReceiver` and `CarPlayBonjourService`, including Bluetooth pairing and accessory-authentication components.
- A native `gal` messaging namespace and `wifi_projection_protocol` protobuf-like types, plus audio/video sources, sinks and input feedback. These are strong indicators of Android Auto and car-projection protocol machinery.
- Optional cluster and CarPlay Ultra feature flags; their exact behavior is not established from strings alone.
- The bundled AirPlay framework contains receiver/audio and ScreenStream code, RAOP and AirPlay Bonjour, pairing, video decode and RTP/RTSP strings. Static evidence suggests a substantial AirPlay implementation, not just a UI switch.
- Some visible MFi terminology and an authentication handshake. No authorization, MFi credential or reusable private signing identity was established by this audit.

## Browser viewer wire map (based on non-executable static analysis)

The IPA includes a local browser viewer under `Payload/CarCast.app/web`. The following high-level behavior was observed:

1. The browser requests `GET /getsocketport?w=<viewportWidth>&h=<viewportHeight>&webcodec=true` over HTTPS.
2. The JSON response includes at least a WebSocket `port` and video geometry such as `video_width` and `video_height` or `width` / `height`.
3. A browser worker connects to `wss://<receiver-host>:<port>`.
4. On connection the client sends JSON control messages with `START` and dark-theme preference `NIGHT`; periodic `PING` maintains liveness.
5. Video arrives in H.264 Annex-B NAL units. SPS/PPS configure an AVC decoder; IDR NALs begin a key frame and other slices provide delta frames. Browser implementation uses WebCodecs and an offscreen WebGL canvas.
6. Browser input is scaled to the decoded video size. User down/drag/up events are forwarded as corresponding `DOWN`, `DRAG`, `UP` messages with integer X/Y coordinates; drags are throttled.
7. Browser may send GPS data as a JSON action after browser geolocation permission.

Unknowns requiring packet-level and device validation: auth state, TLS certificate chain, media encryption, audio routes, CarPlay advertisement data, Bluetooth/iAP2 pairing order, channel mapping, input-to-iAP2 translation, full instrument cluster transport, same-iPhone CarPlay launch, and Android Auto handshake.

**Do not** infer that opening `_carplay-ctrl._tcp` or receiving JPEG frames equals a genuine Apple CarPlay session.

## Independent DriveDeck implementations from the audit

- Browser viewer: host an explicitly authorized HTTPS CarPlay receiver webpage in WKWebView; same-origin navigation checks and normal TLS validation; saved receiver URL stored in iOS Keychain, not logged. Compatible only when a receiver offers a usable web view.
- Native local viewer & receiver: secure device discovery and pairing over MultipeerConnectivity (`_ddcast._tcp`); on-device ReplayKit frames sent over a bounded application protocol, displayed as real video on a second device; a small allowlist of DriveDeck UI controls can be forwarded. Consent is required. Audio is **not** yet sent.
- Existing DriveDeck screen, custom car logo, browser dashboard, radio and cluster are kept.

This is a concrete bidirectional transport, but it is **not** a CarPlay/iAP2/CarPlay Ultra, Android Auto or AirPlay protocol implementation. Those require independently authored and tested protocol state machines or an appropriately licensed SDK. No unsupported CarPlay-success state should be shown.

## Receiver engineering checkpoints for future compatible CarPlay implementation

1. Isolate head-unit state machine from UI: advertisement, request/response, pairing, authentication, encrypted transport, teardown.
2. Verify exact Bonjour TXT attributes and Bluetooth advertisement service records via *authorized own-device* captures.
3. Establish iAP2 or equivalent protocol session with a permitted accessory identity; validate over real iOS 27 devices and check for authorization constraints.
4. Negotiate H.264 session, decode VideoToolbox frames; implement timestamped audio playback and microphone routes.
5. Map authenticated input/touch controls and phone callbacks; add active CarPlay session tests against reference hardware.
6. Implement second-display cluster and Ultra only after first screen is verified.
7. Run a separate interop suite for Android Auto and an independent AirPlay stack; do not equate AirPlay browser status with AirPlay receiver compatibility.

## Reproducible local verification

The auditing process used `zipfile`, `plistlib`, arm64 Mach-O load-command parsing for `LC_ENCRYPTION_INFO_64` and bounded ASCII string extraction. There was no runtime device session, disassembly-based source reconstruction, license transfer, or code copying in the Git repository.

This report does not establish a fully working CarPlay clone. It documents what can be established from the uploaded IPA.
