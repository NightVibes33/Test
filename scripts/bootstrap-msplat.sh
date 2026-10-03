#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor/msplat"
REVISION="e8611098583059b82e0b7d35259fb4e9c42df248"

rm -rf "$VENDOR"
mkdir -p "$ROOT/Vendor"

git clone https://github.com/frs0n/msplat-ios.git "$VENDOR"
git -C "$VENDOR" checkout --detach "$REVISION"

IOS_DEPLOYMENT_TARGET=18.0 "$VENDOR/scripts/build-xcframework.sh"

test -d "$VENDOR/MsplatCore.xcframework"
test -f "$VENDOR/swift/Sources/Msplat/Resources/default-ios.metallib"

echo "msplat ready at $VENDOR"
