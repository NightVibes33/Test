#!/usr/bin/env bash
# Local wrapper: verify the upstream tool actually produces an IPA.
set -euo pipefail
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: ./run-icarcast.sh /path/to/iCarCast.ipa [output.ipa]" >&2
  exit 2
fi
src="$1"
[ -f "$src" ] || { echo "Missing IPA: $src" >&2; exit 2; }
case "$src" in *.ipa) ;; *) echo "Input must end with .ipa" >&2; exit 2 ;; esac
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cli="$here/ipadecrypt"
[ -x "$cli" ] || { echo "Make the ipadecrypt binary executable: chmod +x '$cli'" >&2; exit 2; }
out="${2:-${src%.ipa}-decrypted.ipa}"
[ "$src" != "$out" ] || { echo 'Output must differ from input' >&2; exit 2; }
[ ! -e "$out" ] || { echo "Refusing to overwrite $out" >&2; exit 2; }
echo 'Requires a credential previously minted with ipadecrypt bootstrap on a jailbroken device.'
"$cli" --redact decrypt "$src" --output "$out" --no-on-device --extra-verify
[ -s "$out" ] || { echo 'No decrypted IPA produced' >&2; exit 1; }
echo "Created: $out"
