#!/bin/bash
# Index the OTA and stage a payload root. The workflow kills this whole
# process group at its deadline so the evidence upload still runs.
set +e
set +x
KEY="${KEY:-}"
AEA="$RUNNER_TEMP/HomeView.aea"
LIST="$RUNNER_TEMP/ota-payload-index.txt"
DEST="$RUNNER_TEMP/hv-firmware"
: > "$LIST"
if [[ -s "$AEA" && -n "$KEY" ]]; then
  ipsw ota ls --key-val "$KEY" "$AEA" > "$LIST" 2>out/ota-payload-index.err
  ipsw ota ls --payload --pattern 'SpringBoard|BreadBoard|AppleFirmwareKit|sbin/launchd|usr/lib/dyld' \
    --key-val "$KEY" "$AEA" >> "$LIST" 2>>out/ota-payload-index.err || true
else
  echo "OTA_OR_KEY_MISSING" > "$LIST"
fi
python3 homeview-legacy/scripts/summarize_ota_payload_index.py \
  --listing "$LIST" --output out/homeview-payloadv2-index.json
head -100 "$LIST" > out/ota-payload-index-head.txt
tail -80 "$LIST" > out/ota-payload-index-tail.txt
python3 - <<'PY'
import json, os, pathlib
index = json.loads(pathlib.Path("out/homeview-payloadv2-index.json").read_text())
dest = pathlib.Path(os.environ["RUNNER_TEMP"]) / "hv-firmware"
dmgs = [path for path in index.get("candidate_system_dmgs") or [] if path.endswith(".dmg")]
(dest / "system-volume-decision.txt").write_text((dmgs[0] if dmgs else "") + "\n")
print("SYSTEM_DMG_CANDIDATE", dmgs[:4], "payload_lines", index.get("payload_line_count"))
PY
# 141-21962-183.dmg is not a file in the OTA. Do not scan the archive for it.
echo "FULL_PAYLOAD_EXTRACT_OMITTED unbounded_extract_exceeded_job_timeout" > out/system-root-extract.log
echo "PHANTOM_DMG_SCAN_OMITTED 141-21962-183.dmg is not an OTA member" >> out/system-root-extract.log
git clone --depth 1 https://github.com/CRKatri/trustcache.git "$RUNNER_TEMP/trustcache-src" \
  > out/trustcache-build.log 2>&1 || true
make -C "$RUNNER_TEMP/trustcache-src" >> out/trustcache-build.log 2>&1 || true
TCBIN="$RUNNER_TEMP/trustcache-src/trustcache"
for CRYPTEX_NAME in system app; do
  CRYPTEX="$RUNNER_TEMP/cryptex-$CRYPTEX_NAME"
  rm -rf "$CRYPTEX"
  mkdir -p "$CRYPTEX"
  if [[ -s "$AEA" && -n "$KEY" ]]; then
    python3 homeview-legacy/scripts/run_bounded.py --timeout 600 --log "out/cryptex-${CRYPTEX_NAME}-extract.log" -- \
      ipsw ota extract --cryptex "$CRYPTEX_NAME" -o "$CRYPTEX" --key-val "$KEY" "$AEA" || true
  fi
  python3 homeview-legacy/scripts/record_volume_image.py \
    --dir "$CRYPTEX" --label "${CRYPTEX_NAME}-cryptex" \
    --output "out/homeview-cryptex-${CRYPTEX_NAME}.json" || true
  python3 homeview-legacy/scripts/stage_fitting_image.py \
    --dir "$CRYPTEX" --dest "$DEST/cryptex-${CRYPTEX_NAME}.dmg" \
    --max-bytes 6442450944 --output "out/homeview-cryptex-${CRYPTEX_NAME}-stage.json" || true
  rm -rf "$CRYPTEX"
  if [[ -s "$DEST/cryptex-${CRYPTEX_NAME}.dmg" && ! -s "$DEST/cryptex-system.dmg" ]]; then
    cp "$DEST/cryptex-${CRYPTEX_NAME}.dmg" "$DEST/cryptex-system.dmg"
  fi
done
if [[ -s "$DEST/cryptex-system.dmg" ]]; then
  python3 homeview-legacy/scripts/run_bounded.py --timeout 180 --log out/cryptex-attach.txt -- \
    hdiutil attach -readonly -nobrowse "$DEST/cryptex-system.dmg" || true
  MOUNT="$(awk '/\/Volumes\// { print $NF; exit }' out/cryptex-attach.txt)"
  if [[ -n "$MOUNT" && -d "$MOUNT" ]]; then
    python3 homeview-legacy/scripts/run_bounded.py --timeout 480 --log out/cryptex-walk.log -- \
      bash homeview-legacy/scripts/trustcache_mounted_root.sh "$MOUNT" "$DEST" "$TCBIN" out || true
    python3 homeview-legacy/scripts/run_bounded.py --timeout 60 --log out/cryptex-detach.log -- \
      hdiutil detach "$MOUNT" || true
  fi
  rm -f "$DEST/cryptex-system.dmg" "$DEST/cryptex-app.dmg"
fi
DYLD="$RUNNER_TEMP/dyld-cache"
rm -rf "$DYLD"
mkdir -p "$DYLD"
if [[ -s "$AEA" && -n "$KEY" ]]; then
  python3 homeview-legacy/scripts/run_bounded.py --timeout 600 --log out/dyld-cache-extract.log -- \
    ipsw ota extract --dyld --dyld-arch arm64e --json -o "$DYLD" --key-val "$KEY" "$AEA" \
    || echo "DYLD_EXTRACT_FAILED" >> out/dyld-cache-extract.log
fi
python3 homeview-legacy/scripts/record_volume_image.py \
  --dir "$DYLD" --label dyld-shared-cache \
  --output out/homeview-dyld-cache-volume.json || true
rm -rf "$DYLD"
EXTRACT="$RUNNER_TEMP/system-root"
if [[ -f out/homeview-system-volume-manifest.json ]] && grep -q '"boot_payload_root": true' out/homeview-system-volume-manifest.json; then
  echo "PATTERN_EXTRACT_SKIPPED payload_root_already_staged" >> out/system-root-extract.log
elif [[ -s "$AEA" && -n "$KEY" ]]; then
  mkdir -p "$EXTRACT"
  python3 homeview-legacy/scripts/run_bounded.py --timeout 600 --log out/system-root-extract.log -- \
    ipsw ota extract -y -p 'CoreServices/BreadBoard.app/|PrivateFrameworks/BreadBoard|sbin/launchd$|usr/lib/dyld$' \
    -o "$EXTRACT" --key-val "$KEY" "$AEA" || true
  echo "BREADBOARD_PATTERN_EXTRACT" >> out/system-root-extract.log
fi
if [[ -d "$EXTRACT" ]] && find "$EXTRACT" -name BreadBoard -type f | grep -q .; then
  find "$EXTRACT" -print | sed "s#^$EXTRACT/##" > "$RUNNER_TEMP/payload-files.txt"
  FILE_COUNT="$(find "$EXTRACT" -type f | wc -l | tr -d ' ')"
  LINK_COUNT="$(find "$EXTRACT" -type l | wc -l | tr -d ' ')"
  echo "PAYLOAD_FILE_COUNT=$FILE_COUNT PAYLOAD_LINK_COUNT=$LINK_COUNT"
  MTREE="$RUNNER_TEMP/hv-extracted/AssetData/boot/Firmware/141-21962-183.dmg.mtree"
  python3 homeview-legacy/scripts/compare_payload_mtree.py \
    --mtree "$MTREE" --files "$RUNNER_TEMP/payload-files.txt" \
    --symlink-count "$LINK_COUNT" \
    --output out/homeview-payload-mtree.json || true
  if [[ -x "$TCBIN" ]]; then
    python3 homeview-legacy/scripts/static_trustcache.py \
      --build-root "$EXTRACT" --tool "$TCBIN" \
      --trustcache "$DEST/system-volume.tc" \
      --output out/homeview-static-trustcache.json \
      >> out/trustcache-build.log 2>&1 || true
  fi
  python3 homeview-legacy/scripts/static_trustcache.py \
    --trustcache "$DEST/system-volume.tc" --output out/homeview-static-trustcache.json || true
  sudo chown -R root:wheel "$EXTRACT" >/dev/null 2>&1 || true
  python3 homeview-legacy/scripts/run_bounded.py --timeout 180 --log out/system-volume-create.log -- \
    hdiutil create -fs APFS -srcfolder "$EXTRACT" -volname System "$DEST/system-volume.dmg" || true
  python3 homeview-legacy/scripts/static_trustcache.py \
    --trustcache "$DEST/system-volume.tc" \
    --image "$DEST/system-volume.dmg" \
    --firmware-dir "$DEST" \
    --extracted-files "${FILE_COUNT:-0}" \
    --output out/homeview-static-trustcache.json || true
  rm -rf "$EXTRACT"
fi
rm -f "$LIST" "$DEST/system-volume-decision.txt"
echo "PAYLOAD_STEP_SCRIPT_FINISHED"
