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
The earlier iPhone17,3 runtime report (24A446) had signedGroupCount=0 and usableGroup=NONE, so worse_query never initialized. The subsequent build embeds an ad-hoc App Group entitlement; re-signing and runtime results are not yet verified. Do not report expanded access until a real device JSON report demonstrates it.

## Upstream
- https://github.com/forcequitOS/worse_query
- https://github.com/kolbicz/WQFiles
