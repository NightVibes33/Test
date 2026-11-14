# A18Break R/W Probe (iPhone 16 · iOS 27.0.1)

This is a **SideStore-ready, ad-hoc-signed IPA** to measure real POSIX read/write results, plus an experimental worse_query test. It is not a jailbreak and cannot provide unrestricted filesystem or kernel R/W.

## Signing requirements

The app requests `com.apple.security.application-groups` and the build now embeds that requested entitlement in an ad-hoc signature *before* packing the IPA. This is needed so a re-signing tool can see the requirement. GitHub Actions verifies the embedded entitlement. **An ad-hoc signature alone cannot run on stock iOS. SideStore must replace it with a valid provisioning-compatible signature and an App Group.**

Install using SideStore **with an Apple ID**, as described in WQFiles' signing guidance. SideStore is expected to provision an App Group, but that behavior depends on the signer and actual provisioning configuration.

If the in-app WQ report says `signedGroupCount: 0`, SideStore still removed or failed to grant the entitlement. That is a signing issue, not a worse_query compatibility result.

For a paid Apple developer signing workflow: register a real App Group in Apple Developer Identifiers, enable the App Groups capability on an explicit App ID, associate the group, and use a provisioning profile including it. The signed group name does not need to equal the ad-hoc example; the app dynamically selects a usable group.

## Test instructions

1. Download `A18BreakRW-SideStore-ready.ipa` from the latest successful GitHub Actions run and install using SideStore.
2. Open **Test worse_query access** and run the default `/var/containers/Data/System` path.
3. Export the WQ JSON report and inspect `signedGroupCount`, `usableGroup`, `extensionHandleStatus`, `normalRead`, and `extendedRead`.
4. Only if a sandbox extension is actually consumed, test more specific existing container directories. Optional temporary-marker writes are restricted to data-container descendants.
5. Share the JSON (after redacting sensitive paths) for analysis.

Regular R/W checks are a separate baseline and do not indicate sandbox escape.

No existing system files are overwritten or deleted. The upstream worse_query method temporarily replaces **its own App Group Library/Caches** and recreates that directory.

## Interpretation

- `signedGroupCount: 0`: blocker is the signing/provisioning profile
- `extensionHandleStatus` is negative: the WQ request failed
- `extendedRead: PASS` after `normalRead: errno=1`: evidence of expanded directory access on this specific path
- `marker: PASS`: exclusive temporary file written, read back, and removed in that directory only
- Neither result proves kernel R/W, root access, or access to the signed system volume.

Sources: https://github.com/forcequitOS/worse_query and https://github.com/kolbicz/WQFiles
