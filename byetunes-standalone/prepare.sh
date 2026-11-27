#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
UPSTREAM=54491b21c9949fd0410f760cfca9e8cf11f06f1d
if [ -e ByeTunes ]; then echo "Use a fresh checkout for a reproducible build." >&2; exit 1; fi
git clone --filter=blob:none https://github.com/EduAlexxis/ByeTunes.git ByeTunes
git -C ByeTunes checkout --detach "$UPSTREAM"
test "$(git -C ByeTunes rev-parse HEAD)" = "$UPSTREAM"
for patch in upstream-parity-v2 device-library-save public-metadata-stack rppairing-localdevvpn pairing-and-tabs settings-cleanup album-color-save; do
  bash "scripts/patch-byetunes-$patch.sh"
done
bash scripts/patch-byetunes-manage-backups-typecheck.sh
bash scripts/verify-byetunes-lyrics.sh
bash scripts/verify-byetunes-album-color.sh
bash scripts/build-idevice.sh "$ROOT/Vendor/idevice"
bash scripts/stage-nfcard.sh
bash scripts/build-nfcard-ffi.sh "$ROOT/ThirdParty/NFCARD" "$ROOT/ThirdParty/NFCARD/AirliftFFI"
cp ByeTunesMetadataCompat.swift ByeTunesDownloadParityCompat.swift ByeTunesOnDevicePairing.swift StandalonePairingImport.swift ByeTunes/MusicManager/
python3 standalone.py
