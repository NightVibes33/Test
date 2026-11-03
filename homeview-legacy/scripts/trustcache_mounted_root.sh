#!/bin/bash
# Hash a mounted system volume into a v1 trustcache. The caller supplies the deadline.
set +e
MOUNT="$1"
DEST="$2"
TCBIN="$3"
OUT="${4:-out}"
LOG="$OUT/cryptex-walk.log"
mkdir -p "$OUT"
if [[ ! -d "$MOUNT" ]]; then
  echo "MOUNT_MISSING" >> "$LOG"
  exit 2
fi
if ! find "$MOUNT" -name BreadBoard -type f | grep -q .; then
  echo "BREADBOARD_ABSENT" >> "$LOG"
  exit 3
fi
FILE_COUNT="$(find "$MOUNT" -type f | wc -l | tr -d ' ')"
LINK_COUNT="$(find "$MOUNT" -type l | wc -l | tr -d ' ')"
echo "CRYPTEX_FILE_COUNT=$FILE_COUNT CRYPTEX_LINK_COUNT=$LINK_COUNT" | tee -a "$LOG"
if [[ -x "$TCBIN" ]]; then
  python3 homeview-legacy/scripts/static_trustcache.py \
    --build-root "$MOUNT" --tool "$TCBIN" \
    --trustcache "$DEST/system-volume.tc" \
    --output "$OUT/homeview-static-trustcache.json" \
    >> "$OUT/trustcache-build.log" 2>&1 || true
fi
if [[ -s "$DEST/cryptex-system.dmg" ]]; then
  cp "$DEST/cryptex-system.dmg" "$DEST/system-volume.dmg"
fi
python3 homeview-legacy/scripts/static_trustcache.py \
  --trustcache "$DEST/system-volume.tc" \
  --image "$DEST/system-volume.dmg" \
  --firmware-dir "$DEST" \
  --extracted-files "${FILE_COUNT:-0}" \
  --output "$OUT/homeview-static-trustcache.json" || true
