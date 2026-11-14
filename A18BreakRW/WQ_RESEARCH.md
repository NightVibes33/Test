# A18Break WQ research build

**Goal:** Verify a genuine sandbox extension and any resulting expanded *container* access on retail iPhone17,3 / iOS 27.0.1. **It is not full filesystem R/W, root or kernel access.**

- Integrates forcequitOS/worse_query GPL-3.0-or-later, retaining original headers and its complete license in `LICENSE-worse_query.txt`.
- The signed App Group entitlement **must be supported by the signing provisioning profile**. Our workflow now ad-hoc signs the binary with the requested entitlement and verifies it before packaging. SideStore can still change or drop the group when applying its provisioning profile.
- The app reads the **actual signed App Groups** at runtime. If none resolves to a usable container URL, it reports UNAVAILABLE rather than inventing success.
- The test records baseline `open()` before requesting a token, token status, then a directory open and listing after consuming the token. No private file contents are included.
- Optional writes use **O_CREAT|O_EXCL**, a random temporary filename, exact read-back and immediate unlink; existing files are never modified or deleted.
- Marker-write destinations are restricted to subdirectories under the container families documented by worse_query. Root-owned directory writes may still fail.
- The PoC temporarily replaces its **own App Group Library/Caches** with a symlink and recreates that cache directory. Use a dedicated App Group; its existing cache contents may be cleared.
- The test starts with `/var/containers/Data/System` to investigate directory visibility. For other containers, paste the exact **existing** full path found on your device.
- A PASS means only that particular operation passed under this app's identity. It does **not** imply unrestricted system R/W.

## Verification status
On iPhone17,3 running 27.0.1 (24A446), after the SideStore-ready ad-hoc packaging fix:
- signedGroupCount=1 and the signed App Group resolved successfully;
- baseline open of `/var/containers/Data/System` returned errno=1 (Operation not permitted);
- worse_query produced a positive handle (2) and the directory opened and enumerated 33 entries;
- marker write was `REFUSED` by A18Break's own path allowlist at the container root, so **no protected write success or failure was observed**.

This proves extra directory access on that **one path**, not arbitrary filesystem R/W.

## v0.4 reporting fix

The previous v0.3 picker only copied a child path into the text field and cleared the write toggle. It did **not** run a test when a child was tapped. Its JSON export serialized only the last `report` dictionary, so selecting a child did not create evidence of that selection or any subsequent write. The user's exported report has only the parent directory path and an app-level REFUSED marker.

The updated interface makes each child row a **Run test on this child** action. The operator can explicitly enable temporary-marker writes before selecting a child; the toggle will not be silently reset. Every invoked probe is appended to an in-memory run history with its requested path and marker-requested boolean. JSON export now contains *all* recorded results, rather than just the current result. The UI shows the number of recorded tests and the most recent result. The app still never edits or deletes existing system files.

Selecting a child while temporary-marker writes are enabled runs one exclusive-create, read-back, cleanup attempt on that chosen directory; this is explicitly labeled in the UI. The report distinguishes app-level REFUSED from system-level DENIED. No elevated system-wide read/write is implied.

## Next on-device evidence
This version lists only immediate, actual child directories in the successful WQ result so the operator can choose a real path without guessing UUIDs. Selecting a row only copies its path into the target field. A separate opt-in toggle enables a single exclusive temporary marker (write/readback/unlink) in container descendants; it never overwrites existing files. `DENIED` is an iOS result, `REFUSED` denotes the app's own safety check. Do not conflate them.

## Upstream
- https://github.com/forcequitOS/worse_query
- https://github.com/kolbicz/WQFiles
