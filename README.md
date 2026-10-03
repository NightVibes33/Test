# ScanAnything

Turn real objects into 3D on an iPhone.

ScanAnything has one consumer-facing scan flow and chooses the best reconstruction pipeline available on the device.

## Device paths

### Regular iPhone — no LiDAR required

1. ARKit captures tracked RGB camera frames.
2. Camera intrinsics and camera-to-world poses are stored with each accepted frame.
3. ARKit raw feature points seed the reconstruction.
4. The capture is written as a Nerfstudio-compatible dataset.
5. msplat trains a 3D Gaussian Splat locally with Metal.
6. The result is stored as a compact SPZ model.
7. MetalSplatter renders the result directly in the library.

No server upload is required.

### Pro / LiDAR iPhone

Supported devices automatically use Apple's guided Object Capture flow and on-device photogrammetry from the upstream ObjectScanner foundation.

This path produces a metrically scaled USDZ mesh and supports the upstream mesh export tools.

### Additional modes

The advanced modes screen keeps the upstream:

- RoomPlan room capture
- TrueDepth point-cloud capture
- turntable photogrammetry

Availability is determined at runtime by Apple's framework capability checks rather than hard-coded device names.

## Build

Requirements:

- iOS 18+
- Xcode 16+
- CMake
- macOS for the build toolchain

Prepare the on-device Gaussian trainer:

```bash
bash scripts/bootstrap-msplat.sh
```

Then build:

```bash
xcodebuild \
  -project ScanAnything.xcodeproj \
  -scheme ScanAnything \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The GitHub Actions workflow performs the same bootstrap and unsigned build automatically.

## App Store configuration

Current bundle identifier:

`com.nightvibes33.scananything`

Before App Store submission, configure the Apple Developer team/signing identity for the target. The source tree intentionally does not contain another developer's Team ID.

## Storage

Each scan is stored under the app's Documents directory in:

`Scans/<UUID>/`

Camera-only scans retain:

- accepted source JPEGs
- `transforms.json`
- ARKit feature-point seed PLY
- final `model.spz`

LiDAR/Object Capture scans retain the upstream source images/checkpoints and final USDZ.

## Open source

The scanner foundation comes from ObjectScanner under Apache-2.0. Camera-only training uses msplat-ios under Apache-2.0. Gaussian rendering uses MetalSplatter under MIT.

See `LICENSE`, `NOTICE`, and `THIRD_PARTY_NOTICES.md`.
