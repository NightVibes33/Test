#!/usr/bin/env bash
# Packages only the live OpenOrbis frontend, not the fixture or research ELF.
set -euo pipefail
tool=$(realpath "$1")
eboot=$(realpath "$2")
out=$(realpath -m "$3")
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
/usr/bin/python3 "$here/package-assets.py" "$stage" "$content_id"
pkgtool pkg_build "$stage/project.gp4" "$work"
pkg="$work/$content_id.pkg"
test -s "$pkg"
# Verify actual PKG magic, then independently read it with LibOrbisPkg.
test "$(od -An -tx1 -N4 "$pkg" | tr -d ' \n')" = 7f434e54
pkgtool pkg_listentries "$pkg" | tee "$out/pkg-entries.txt"
pkgtool pkg_extract --passcode 00000000000000000000000000000000 "$pkg" "$work/extracted"
# Round trip the executable. No fixture data or research runtime is bundled.
found=$(find "$work/extracted" -type f -name eboot.bin -print -quit)
test -n "$found"
cmp "$eboot" "$found"
cp "$pkg" "$out/PS4-Tailscale-Frontend-TEST.pkg"
(cd "$out" && sha256sum PS4-Tailscale-Frontend-TEST.pkg > SHA256SUMS)
printf '%s\n' 'PKG container verified; extracted eboot matches live frontend.' 'Native Tailscale daemon not included; hardware 14.02 installation untested.' >"$out/BUILD-STATUS.txt"
cat "$out/BUILD-STATUS.txt"
