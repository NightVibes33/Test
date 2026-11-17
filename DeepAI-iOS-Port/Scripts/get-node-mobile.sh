#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
URL='https://github.com/fogtape/nodejs-mobile/releases/download/v24.22.1-0/nodejs-mobile-ios-24.22.1-0.zip'
SHA='3fa1b8fb0720768b01c2e0dae3a17e788476e8c1613a1d9a54e206793b45326e'
mkdir -p build node-mobile-download Frameworks
curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 "$URL" -o build/node-mobile.zip
echo "$SHA  build/node-mobile.zip" | shasum -a 256 -c -
unzip -q -o build/node-mobile.zip -d node-mobile-download
SRC="$(find node-mobile-download -type d -name 'NodeMobile.xcframework' -print -quit)"
test -n "$SRC" || { echo 'NodeMobile XCFramework missing from verified release'; exit 1; }
rm -rf Frameworks/NodeMobile.xcframework
cp -R "$SRC" Frameworks/NodeMobile.xcframework
find Frameworks/NodeMobile.xcframework -maxdepth 2 -type f | head -25
