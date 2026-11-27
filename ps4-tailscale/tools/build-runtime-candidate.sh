#!/usr/bin/env bash
# Build-only research. Never deploy the output to a console.
set -euo pipefail
upstream=${1:?path to pinned upstream checkout}
out=${2:?absolute artifact directory}
root=$(go env GOROOT)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -a "$root" "$work/go"
export GOROOT="$work/go" GOTOOLCHAIN=local
patchfile="$upstream/patches/go1.27.1-ps5.patch"
(cd "$GOROOT" && git apply --check "$patchfile" && git apply "$patchfile")
# PS4 SDK headers do not declare PS5's extra 48-byte signal context field.
# This is a research candidate, not evidence that the retail kernel agrees.
python3 - "$GOROOT/src/runtime/defs_freebsd_amd64.go" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1])
s=p.read_text()
lines=s.splitlines(keepends=True)
assert sum("ps5_pad" in line for line in lines)==1
p.write_text("".join(line for line in lines if "ps5_pad" not in line))
PY
cp "$GOROOT/bin/go" "$GOROOT/bin/go-bootstrap"
GOBIN="$GOROOT/bin" "$GOROOT/bin/go-bootstrap" install cmd/go cmd/link
# cmd/link is installed into GOBIN, but go build invokes GOTOOLDIR/link.
cp "$GOROOT/bin/link" "$("$GOROOT/bin/go" env GOTOOLDIR)/link"
mkdir -p "$out"
export GOOS=freebsd GOARCH=amd64 GOAMD64=v1 CGO_ENABLED=0
"$GOROOT/bin/go" build -trimpath -buildmode=pie -ldflags=-linkmode=internal -o "$out/runtime-probe-NOT-PS4-LOADABLE.elf" ./runtime-probe
"$GOROOT/bin/go" build -trimpath -buildmode=pie -ldflags=-linkmode=internal -o "$out/relay-NOT-PS4-LOADABLE.elf" .
readelf -h "$out/runtime-probe-NOT-PS4-LOADABLE.elf" > "$out/elf-header.txt"
readelf -lW "$out/relay-NOT-PS4-LOADABLE.elf" > "$out/relay-program-headers.txt"
