# App Store release checklist

Last reviewed against Apple's public requirements: October 2, 2026.

## Current binary

- Product: ScanAnything
- Bundle ID: com.nightvibes33.scananything
- Platform: iPhone only
- Minimum OS: iOS 18
- CI toolchain: Xcode 27 / current iOS SDK
- Camera-only path: ARKit + on-device msplat Gaussian reconstruction
- Enhanced path: Apple Object Capture / photogrammetry on supported LiDAR iPhones
- Data model: local app-container storage; no developer-operated upload service
- Purchases: StoreKit 2

## Blocking before App Store submission

- Move this staging branch into the standalone NightVibes33/ScanAnything repository.
- Publish docs/privacy.html at https://nightvibes33.github.io/ScanAnything/privacy.html.
- Create App Store Connect products com.nightvibes33.scananything.pro.monthly and com.nightvibes33.scananything.pro.yearly in a subscription group.
- Configure Apple Developer signing/team and create the App Store Connect app record.
- Fill App Privacy answers to match the exact submitted binary.
- Re-run required-reason API/privacy-manifest validation against the archived app and bundled third-party code.
- Provide current iPhone screenshots using an accepted App Store Connect size.
- Complete the current age-rating questionnaire.
- Test purchase, pending Ask to Buy, restore, renewal, expiration, and refund/revocation behavior in StoreKit testing/TestFlight.
- Test regular non-LiDAR iPhone and supported Pro/LiDAR iPhone hardware paths in TestFlight.
- Verify every advertised export format actually works for the selected scan type before using it in App Store metadata.

## Product-page positioning

Primary promise:

**Turn real objects into 3D on your iPhone.**

Suggested subtitle:

**3D Scanner for Any iPhone**

Suggested first five screenshot messages:

1. **SCAN ANYTHING INTO 3D** — Point your iPhone, move around the object, and build it on-device.
2. **NO LIDAR REQUIRED** — Camera 3D works on supported regular iPhones.
3. **PRO IPHONES GO FURTHER** — LiDAR devices unlock Apple's guided mesh capture.
4. **YOUR SCANS STAY ON DEVICE** — Capture and reconstruction are local in the current build.
5. **VIEW, SAVE & SHARE** — Explore scans interactively and export the formats supported by each scan type.

Avoid claiming that camera-only Gaussian scans are metrically accurate meshes or directly 3D-printable. Those claims belong only to workflows that actually produce the required geometry.
