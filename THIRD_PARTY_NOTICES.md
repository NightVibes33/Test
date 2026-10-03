# Third-party notices

ScanAnything includes and builds on open-source software.

## ObjectScanner

Original project: `burakSahinkaya/ObjectScanner`.

License: Apache License 2.0.

The upstream `LICENSE` and `NOTICE` files are retained at the repository root. ScanAnything preserves the notices required by the upstream project.

## msplat-ios

Project: `frs0n/msplat-ios`.

Used for on-device 3D Gaussian Splatting training on iOS.

License: Apache License 2.0.

Pinned revision:

`e8611098583059b82e0b7d35259fb4e9c42df248`

The dependency is downloaded and built by `scripts/bootstrap-msplat.sh`; it is not vendored into this repository.

## MetalSplatter

Project: `scier/MetalSplatter`.

Used for rendering Gaussian Splatting models on Apple platforms.

License: MIT.

Swift Package version requirement: 1.0.1 up to the next major version.

## Depth Anything V2 Small — Apple Core ML

Model: `apple/coreml-depth-anything-v2-small`.

Used as an optional learned monocular-depth prior that is calibrated against
ARKit metric feature points before Gaussian Splatting training.

License: Apache License 2.0.

Pinned model revision:

`cfef6f6f2a70783dedc0bfae40cecbc2052285d3`

The FP16 Core ML package is downloaded at build time by
`scripts/bootstrap-depth-anything.sh`; model weights are not committed to this
repository.
