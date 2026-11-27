from pathlib import Path
import hashlib
import sys
boot = Path(sys.argv[1]).read_bytes()
relay = Path(sys.argv[2]).read_bytes()
assert len(relay) > 10_000_000 and relay.startswith(b"\x7fELF")
assert b"PS4TS_ENTER_GO_EXPERIMENTAL" in boot, "not the daemon entry launcher"
assert b"EMULATOR FIXTURE - NOT AUTHENTICATED" not in boot, "fixture executable"
pos = boot.find(relay)
assert pos >= 0, "entire original Go relay must be inside the packaged SELF"
print(f"Embedded relay: {len(relay)} bytes at SELF offset {pos}")
print("Embedded relay SHA-256:", hashlib.sha256(relay).hexdigest())
print("Daemon SELF SHA-256:", hashlib.sha256(boot).hexdigest())
