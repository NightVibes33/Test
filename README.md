# ScanAnything

## Platform scope

ScanAnything v1 is iPhone-only and targets iOS 18+. Regular iPhones use the camera-only Gaussian pipeline; supported Pro/LiDAR iPhones automatically gain Apple Object Capture and LiDAR modes.

Turn real objects into 3D on an iPhone.

ScanAnything has one consumer-facing scan flow and chooses the best reconstruction pipeline available on the device.

## Device paths

### Regular iPhone — no LiDAR required

1. ARKit captures tracked RGB camera frames at the best available format, preferring its 4K recommendation.
2. Soft frames are rejected before they can contaminate the multi-view solve.
3. Camera intrinsics and camera-to-world poses are stored with each accepted frame.
4. Capture coverage is measured across azimuth and elevation bands rather than by frame count alone.
5. ARKit raw feature points seed the reconstruction.
6. The capture is written as a Nerfstudio-compatible dataset.
7. msplat trains a 3D Gaussian Splat locally with Metal using a 30,000-step progressive-resolution quality profile.
8. The master result is stored as float32 Gaussian PLY so training detail is not quantized away.
9. MetalSplatter renders the PLY result directly in the library.

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
- final full-precision `model.ply`

LiDAR/Object Capture scans retain the upstream source images/checkpoints and final USDZ.

## Open source

The scanner foundation comes from ObjectScanner under Apache-2.0. Camera-only training uses msplat-ios under Apache-2.0. Gaussian rendering uses MetalSplatter under MIT.

See `LICENSE`, `NOTICE`, and `THIRD_PARTY_NOTICES.md`.
