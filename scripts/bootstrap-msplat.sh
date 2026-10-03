#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor/msplat"
REVISION="e8611098583059b82e0b7d35259fb4e9c42df248"
JOBS="${BUILD_JOBS:-$(sysctl -n hw.ncpu)}"

rm -rf "$VENDOR"
mkdir -p "$ROOT/Vendor"
git clone --filter=blob:none https://github.com/frs0n/msplat-ios.git "$VENDOR"
git -C "$VENDOR" checkout --detach "$REVISION"

cd "$VENDOR"

SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
cmake   -B build/ios-device   -DCMAKE_BUILD_TYPE=Release   -DMSPLAT_METAL_SDK=iphoneos   -DCMAKE_SYSTEM_NAME=iOS   -DCMAKE_OSX_ARCHITECTURES=arm64   -DCMAKE_OSX_SYSROOT="$SDKROOT"   -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0   -DMSPLAT_METAL_IOS_DEPLOYMENT_TARGET=18.0

cmake --build build/ios-device --config Release --target msplat_core metallib -j "$JOBS"

test -f build/ios-device/libmsplat_core.a
test -f build/ios-device/default.metallib

HEADERS=build/xcf-headers
rm -rf "$HEADERS" MsplatCore.xcframework
mkdir -p "$HEADERS"
cp core/include/msplat_c_api.h "$HEADERS/"
cat > "$HEADERS/module.modulemap" <<'MAP'
module MsplatCore {
    header "msplat_c_api.h"
    export *
}
MAP

xcodebuild -create-xcframework   -library build/ios-device/libmsplat_core.a   -headers "$HEADERS"   -output MsplatCore.xcframework

RESOURCES=swift/Sources/Msplat/Resources
mkdir -p "$RESOURCES"
cp build/ios-device/default.metallib "$RESOURCES/default-ios.metallib"
# Package.swift lists all platform resources. The app target consumes only the iOS
# resource, but the other named files must exist for SwiftPM to resolve the package.
cp build/ios-device/default.metallib "$RESOURCES/default-macos.metallib"
cp build/ios-device/default.metallib "$RESOURCES/default-iossimulator.metallib"

echo "msplat iOS device package ready"
