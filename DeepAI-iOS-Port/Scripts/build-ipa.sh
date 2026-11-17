#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'macOS Xcode is required to compile the iOS target.' >&2; exit 1; }
command -v xcodegen >/dev/null || { echo 'Install XcodeGen first: brew install xcodegen' >&2; exit 1; }
test -f OriginalWebClient/index.html || { echo 'Missing original DeepAI client assets. Run extract_deepai_dmg.py first.' >&2; exit 1; }
xcodegen generate --spec project.yml
mkdir -p build
xcodebuild -project DeepAICodeIOS.xcodeproj -scheme DeepAICodeIOS -configuration Release \
  -destination 'generic/platform=iOS' -sdk iphoneos \
  -derivedDataPath build/Derived CODE_SIGNING_ALLOWED=NO build
APP='build/Derived/Build/Products/Release-iphoneos/DeepAICodeIOS.app'
test -d "$APP" || { echo 'No .app produced' >&2; exit 1; }
mkdir -p build/package/Payload
rm -rf build/package/Payload/DeepAICodeIOS.app
cp -R "$APP" build/package/Payload/
(cd build/package && zip -qry ../DeepAI-Code-iOS-0.3.40-unsigned.ipa Payload)
echo "Built unsigned IPA: $(pwd)/build/DeepAI-Code-iOS-0.3.40-unsigned.ipa"
