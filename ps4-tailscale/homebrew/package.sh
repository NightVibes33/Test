#!/usr/bin/env bash
# Runtime mode requires the entire original Go relay inside the daemon SELF.
set -euo pipefail
tool=$(realpath "$1")
eboot=$(realpath "$2")
out=$(realpath -m "$3")
mode=${4:-frontend}
here=$(cd "$(dirname "$0")" && pwd)
test -s "$eboot"
mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stage="$work/project"
mkdir -p "$stage/sce_sys" "$work/extracted"
cp "$eboot" "$stage/eboot.bin"
title_id=BREW00127
content_id=IV0000-BREW00127_00-PS4TAILSCALE0000
title='PS4 Tailscale Frontend'
filename=PS4-Tailscale-Frontend-TEST.pkg
if [[ "$mode" == native ]]; then
  payload=$(realpath "${5:?background payload required}")
  relay=$(realpath "${6:?original Go relay required}")
  title_id=BREW00128
  content_id=IV0000-BREW00128_00-PS4TAILSCALE0000
  title=TailScale
  filename=TailScale.pkg
  mkdir -p "$stage/assets"
  cp "$payload" "$stage/assets/TailScale.elf"
  /usr/bin/python3 "$here/verify-embedded-runtime.py" "$payload" "$relay"
elif [[ "$mode" == runtime ]]; then
  relay=$(realpath "${5:?original Go relay image required}")
  title_id=BREW00128
  content_id=IV0000-BREW00128_00-PS4TAILSCALE0000
  title='TailScale'
  filename=TailScale.pkg
  /usr/bin/python3 "$here/verify-embedded-runtime.py" "$eboot" "$relay"
elif [[ "$mode" != frontend ]]; then
  exit 2
fi
pkgtool(){ dotnet "$tool" "$@"; }
sfo="$stage/sce_sys/param.sfo"
pkgtool sfo_new "$sfo"
int(){ pkgtool sfo_setentry "$sfo" "$1" --type Integer --maxsize 4 --value "$2"; }
str(){ pkgtool sfo_setentry "$sfo" "$1" --type Utf8 --maxsize "$2" --value "$3"; }
int APP_TYPE 1
int ATTRIBUTE 0
int SYSTEM_VER 0
str APP_VER 8 '1.00'
str VERSION 8 '1.00'
str CATEGORY 4 gd
str CONTENT_ID 48 "$content_id"
str TITLE 128 "$title"
str TITLE_ID 12 "$title_id"
pkgtool sfo_listentries "$sfo" | tee "$out/param-sfo.txt"
grep -F "$content_id" "$out/param-sfo.txt"
grep -F "$title" "$out/param-sfo.txt"
/usr/bin/python3 "$here/package-assets.py" "$stage" "$content_id" "$mode"
pkgtool pkg_build "$stage/project.gp4" "$work"
pkg="$work/$content_id.pkg"
test -s "$pkg"
# Verify actual PKG magic, then independently read it with LibOrbisPkg.
test "$(od -An -tx1 -N4 "$pkg" | tr -d ' \n')" = 7f434e54
pkgtool pkg_listentries "$pkg" | tee "$out/pkg-entries.txt"
pkgtool pkg_extract --passcode 00000000000000000000000000000000 "$pkg" "$work/extracted"
# Round trip the executable, then check the actual embedded runtime again.
found=$(find "$work/extracted" -type f -name eboot.bin -print -quit)
test -n "$found"
cmp "$eboot" "$found"
if [[ "$mode" == native ]]; then
  extracted_payload=$(find "$work/extracted" -type f -name TailScale.elf -print -quit)
  test -n "$extracted_payload"
  cmp "$payload" "$extracted_payload"
  /usr/bin/python3 "$here/verify-embedded-runtime.py" "$extracted_payload" "$relay" | tee "$out/embedded-runtime.txt"
  printf "%s\n" "Native UI and independent payload verified in PKG." "Firmware 14.02 execution and background persistence unverified. AutoRun enable is locked pending hardware validation." >"$out/BUILD-STATUS.txt"
elif [[ "$mode" == runtime ]]; then
  /usr/bin/python3 "$here/verify-embedded-runtime.py" "$found" "$relay" | tee "$out/embedded-runtime.txt"
  printf '%s\n' 'PKG contains the real Go Tailscale daemon and native launcher.' 'Runtime startup, authentication, background operation and hardware 14.02 compatibility remain unverified. Experimental only; do not install on production console.' >"$out/BUILD-STATUS.txt"
else
printf '%s\n' 'PKG container verified; extracted eboot matches live frontend.' 'Native Tailscale daemon not included; hardware 14.02 installation untested.' >"$out/BUILD-STATUS.txt"
fi
cp "$pkg" "$out/$filename"
(cd "$out" && sha256sum "$filename" > SHA256SUMS)
cat "$out/BUILD-STATUS.txt"
