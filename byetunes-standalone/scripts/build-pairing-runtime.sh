#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Vendor/PairingRuntime"
PIN=a8dc7e48b13e130e69c28269a43fc4a8b456952a
SRC="$ROOT/.theos/pairing-source"
TARGET=aarch64-apple-ios

verify_runtime() {
  test -s "$OUT/lib/libairlift_ffi.a"
  test -s "$OUT/include/idevice.h"
  test -s "$OUT/include/AirliftFFI/airlift.h"
  test "$(cat "$OUT/SOURCE_REVISION")" = "$PIN"
  xcrun lipo -verify_arch arm64 "$OUT/lib/libairlift_ffi.a"
  local symbols
  symbols="$(mktemp)"
  xcrun nm -gU "$OUT/lib/libairlift_ffi.a" > "$symbols"
  for symbol in al_pairing_run_host al_pairing_result_free rp_pairing_file_read tunnel_create_rppairing afc_client_connect_rsd notification_proxy_connect_rsd; do
    grep -Eq "[[:space:]]_$symbol$" "$symbols" || { echo "Missing runtime symbol $symbol" >&2; rm -f "$symbols"; return 1; }
  done
  if grep -Eq '[[:space:]]_al_(exploit_|passthm_|zip_extract_|find_app_container|list_app_containers|device_respring|syslog_stream_)' "$symbols"; then
    echo "Unexpected unrelated Airlift API in pairing-only archive" >&2
    rm -f "$symbols"
    return 1
  fi
  rm -f "$symbols"
}
if [ -f "$OUT/SOURCE_REVISION" ] && verify_runtime; then
  echo "Using cached pairing-only runtime"
  exit 0
fi
mkdir -p "$ROOT/.theos"
git clone --filter=blob:none --no-checkout https://github.com/ceoca69/erozzion-mod.git "$SRC"
git -C "$SRC" sparse-checkout set AirCard-iOS-main/rust-core
git -C "$SRC" checkout --detach "$PIN"
test "$(git -C "$SRC" rev-parse HEAD)" = "$PIN"
CORE="$SRC/AirCard-iOS-main/rust-core"
# Keep the exact pairing implementation and vendored idevice from the current
# Filza source. Compile only the pairing and shared utility modules.
python3 - "$CORE" <<'PY'
from pathlib import Path
import sys
r=Path(sys.argv[1])
p=r/"src/lib.rs"
s=p.read_text()
marker="// ---------------------------------------------------------------------------\n// Exploit\n"
assert s.count(marker)==1
s=s.split(marker,1)[0]
for name in ("exploit","grappa"):
    old=f"pub mod {name};\n"
    assert s.count(old)==1
    s=s.replace(old,"",1)
p.write_text(s)
h=r/"include/airlift.h"
s=h.read_text()
assert s.count(marker)==1
s=s.split(marker,1)[0]
# al_string_free is useful elsewhere in the original interface but is not
# part of the standalone pairing contract.
s=s.replace("void al_string_free(char *p);","")
h.write_text(s+"\n#ifdef __cplusplus\n}\n#endif\n#endif\n")
assert "al_pairing_run_host" in p.read_text()
assert "pub mod exploit" not in p.read_text()
PY
export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="$(xcrun --sdk iphoneos --find clang)"
rustup target add "$TARGET"
(cd "$CORE" && cargo build --release --target "$TARGET")
mkdir -p "$OUT/lib" "$OUT/include/AirliftFFI"
cp "$CORE/target/$TARGET/release/libairlift_ffi.a" "$OUT/lib/"
cp "$CORE/vendor/idevice-ffi/idevice.h" "$OUT/include/idevice.h"
cp "$CORE/include/airlift.h" "$OUT/include/AirliftFFI/"
printf 'module AirliftFFI { header "airlift.h" export * }\n' > "$OUT/include/AirliftFFI/module.modulemap"
printf '%s\n' "$PIN" > "$OUT/SOURCE_REVISION"
verify_runtime
echo "PASS: one pairing-only archive, matching idevice header, required transport symbols, no unrelated Airlift exports"
