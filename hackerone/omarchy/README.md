# Omarchy HackerOne Hunt — 2026-10-04

## Target
- HackerOne program: `omarchy`
- In-scope source: https://github.com/omacom/omarchy
- Required target branch: `quattro`
- HackerOne structured scope ID: `1041203`
- Maximum in-scope severity: Critical
- Public bounty opened: 2026-10-01
- Disclosed reports observed at hunt start: 0

## Current target commit
- `65c0f3306e9b4af676f32d3b9fa187b53d9ca155`

## Active candidate — privileged migration environment override

`migrations/1791125650.sh` accepts these environment-controlled operands:

- `OMARCHY_FPRINTD_RESUME_SRC`
- `OMARCHY_FPRINTD_RESUME_DST`
- `OMARCHY_FPRINTD_STOP_TIMEOUT_SRC`
- `OMARCHY_FPRINTD_STOP_TIMEOUT_DST`
- `OMARCHY_LOCK_FINGERPRINT_PAM`

The migration checks the override paths as the invoking user and then passes the source/destination directly to:

```bash
sudo install -Dm755 "$hook_src" "$hook_dst"
```

`bin/omarchy-update` authorizes sudo before migrations and keeps the authorization alive while `omarchy-migrate` runs. The update environment sanitizer removes Bash startup/injection variables but does not remove the `OMARCHY_FPRINTD_*` migration overrides.

### Reproduction

Run:

```bash
bash hackerone/omarchy/poc.sh
```

The PoC uses the real `omarchy-migrate` runner and the upstream migration at the pinned commit. It:

1. creates an unprivileged, caller-controlled payload;
2. supplies a caller-controlled regular file as `OMARCHY_LOCK_FINGERPRINT_PAM` so the migration enters the install path;
3. supplies the payload as `OMARCHY_FPRINTD_RESUME_SRC`;
4. supplies a root-only path under `/root` as `OMARCHY_FPRINTD_RESUME_DST`;
5. establishes sudo authorization, matching the authorization state held by `omarchy update`;
6. executes the real migrator with all unrelated migrations marked complete;
7. verifies the resulting file is byte-for-byte attacker-controlled and `root:root 0755`.

Expected terminal proof:

```text
PASS: user-controlled bytes were installed at a root-only destination
OWNER_GROUP_MODE=0:0:755
BYTES=OMARCHY_H1_POC_PAYLOAD_v1
```

The PoC deliberately uses a harmless marker under `/root`; it does not install a systemd hook, alter PAM, or create persistence. The vulnerable primitive itself allows the destination operand to be changed.

## Reverse-skill tracks used
- code-audit
- supply-chain-security
- privileged-boundary / taint review
- attack-chain triage

## Validated dead ends
1. Update post-update hooks share the update sudo authorization, but current source and tests explicitly define this as intentional behavior.
2. Third-party plugin `omarchy.clonedFrom` can inherit a first-party capability profile, but no credential read or independent authentication bypass was demonstrated.
3. Shipped `NOPASSWD` DNS and browser-policy helpers pin root PATH and constrain arguments.
4. Timezone `NOPASSWD` shadowing did not match the passwordless sudo rule.
5. The Oct 2 `/etc/pam.d/polkit-1` rewrite itself does not expose a practical ordinary-user symlink race because the live file and backup are under root-owned `/etc/pam.d`.

## Status
PoC committed. GitHub Actions is the reproducibility check. Do not submit until the runner passes and the impact boundary is reviewed against Omarchy's intentional update-hook trust model.
