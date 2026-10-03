#!/usr/bin/env bash
set -euo pipefail

REVISION="cfef6f6f2a70783dedc0bfae40cecbc2052285d3"
MODEL_NAME="DepthAnythingV2SmallF16.mlpackage"
DEST="ScanAnything/Models/${MODEL_NAME}"
BASE="https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/${REVISION}/${MODEL_NAME}"

mkdir -p "${DEST}/Data/com.apple.CoreML/weights"

download() {
  local relative="$1"
  local output="${DEST}/${relative}"
  mkdir -p "$(dirname "${output}")"
  curl -fL --retry 4 --retry-delay 2     "${BASE}/${relative}?download=true"     -o "${output}"
}

download "Manifest.json"
download "Data/com.apple.CoreML/model.mlmodel"
download "Data/com.apple.CoreML/weights/weight.bin"

echo "44ac97a3efcfd52113183fb2862ff59cd0368e9ec2e30a90a54980dd11407042  ${DEST}/Data/com.apple.CoreML/model.mlmodel" | shasum -a 256 -c -
echo "fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed  ${DEST}/Data/com.apple.CoreML/weights/weight.bin" | shasum -a 256 -c -

echo "Depth Anything V2 Small FP16 ready at ${DEST}"
