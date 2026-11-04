# Legacy Music + iOS 27 fragment: SideStore hybrid experiment

## Sources found

- **Legacy working attempt:** \`NightVibes33/Codex-DEB-Test\`, branch \`temp/apple-music-iphone7-extract-20261017\`. The actual complete Apple Music source was from an **iOS 15.8.8 iPhone 6s**, not iOS 16. It was repackaged on October 17 as \`AppleMusic-iOS27-Last-Playable-Recovery-unsigned.ipa\` (a copy of the HEIC compatibility baseline, reportedly last confirmed to produce local audio in FlekDeck).
- **Modern fragment:** user-supplied \`Music-AEECAED1.ipa\` (SHA-256 \`d12284c7349ae98dffc72a6e7c01f7c052f11b47def1ba2db33c1f113331aae9\`). Contains only MusicNotificationContentExtension and MusicMessagesApp plus localized extension assets; no primary Music executable or root Info.plist.
- Previous legacy GitHub Actions runs were located, but their downloadable IPA artifacts **were not available** when checked November 3, 2026. No legacy IPA was attached to the current conversation. No Apple app binary is included in this public repository.

## Implementation on this isolated branch

\`tools/build_music_hybrid.py\`:
1. Reads two user-provided IPAs and rejects malformed, unsafe, duplicate, or CRC-invalid members.
2. Requires a complete, actually unencrypted legacy main Music executable + Info.plist. Does not fake a decrypt by zeroing cryptid.
3. Preserves **old Music binary, frameworks, and old main UI resources**; rewrites main Info.plist bundle ID to \`com.nightvibes33.applemusic27\`, display name to \`Music Hybrid\`, minimum OS to 27.0.
4. Removes old extensions, then (by default) merges the **two newer extension bundles** and rebases their executable bundle identifiers to the new app ID.
5. Drops stale \`_CodeSignature\`, \`SC_Info\`, and \`embedded.mobileprovision\` resources. This does **not** clear or decrypt embedded Mach-O code signatures, and does not generate signing credentials.
6. Verifies all included Mach-O encryption load commands, the merged app's required entries, and a full ZIP CRC check. Writes a SHA-256-stamped \`*.report.json\`.
7. For SideStore extension provisioning conflicts, \`--main-only\` drops **all** extensions. This changes functionality but reduces the number of App IDs SideStore must provision.

## Run locally with both actual IPAs

\`\`\`sh
python3 tools/build_music_hybrid.py \
  --legacy AppleMusic-iOS27-Last-Playable-Recovery-unsigned.ipa \
  --modern Music-AEECAED1.ipa \
  --output Music-iOS27-Hybrid-SideStore.ipa
\`\`\`

The builder pins the exact provided modern fragment SHA-256 by default. Optional minimum extension assembly:

\`\`\`sh
python3 tools/build_music_hybrid.py \
  --legacy AppleMusic-iOS27-Last-Playable-Recovery-unsigned.ipa \
  --modern Music-AEECAED1.ipa \
  --output Music-iOS27-Hybrid-MainOnly.ipa \
  --main-only
\`\`\`

The output is **unsigned and only structurally audited**. Import it into SideStore for signing under the user's own Apple provisioning. It is not a verified "decrypted iOS 27 Apple Music" app: iOS 15 MusicApplication and iOS 27 extensions may require unavailable private frameworks/symbols and Apple-only music, protected-playback, app-group, service, or account entitlements. SideStore cannot confer those entitlements by repackaging. Neither device installation nor playback has been verified.

**Current status: CI synthetic tests green; actual hybrid output BLOCKED until the complete legacy IPA bytes are made available in the working environment.**
