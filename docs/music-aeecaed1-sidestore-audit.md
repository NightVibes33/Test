# Music-AEECAED1.ipa → SideStore readiness audit

Source inspected: user-provided \`Music-AEECAED1.ipa\` (November 3, 2026).
The original IPA has **not** been committed to this public repository.

## Proven facts

- SHA-256 of archive: \`d12284c7349ae98dffc72a6e7c01f7c052f11b47def1ba2db33c1f113331aae9\`
- Archive size: approximately 13 MiB; 685 ZIP entries; **ZIP CRC check passed**.
- App directory: \`Payload/Music.app/\`.
- \`Payload/Music.app/Info.plist\`: **missing**.
- \`Payload/Music.app/Music\` (main executable): **missing**. In fact, there are **no immediate regular files at the root of Music.app**.
- Included \`MusicNotificationContentExtension.appex/MusicNotificationContentExtension\`: Mach-O exists; no LC_ENCRYPTION_INFO command.
- Included \`MusicMessagesApp.appex/MusicMessagesApp\`: Mach-O exists; no LC_ENCRYPTION_INFO command.
- Both extension Info.plists declare a minimum iOS version of 27.0.
- The two extensions are **not** a substitute for the missing primary Music executable or main Info.plist.

## Outcome

**BLOCKED: cannot create a functional decrypted, SideStore-installable Apple Music IPA from this archive.**

No cryptid edit, re-sign, bundle identifier change, or ZIP repack can recreate the missing application binary. A replacement or blank executable would create a different, nonfunctional app. Apple system-app identifiers and restricted entitlements are an additional obstacle even with complete files. SideStore's personal-development signing cannot grant Apple-only entitlements.

For an ordinary third-party app, provide a legitimately obtained **complete IPA** containing \`Payload/<App>.app/Info.plist\`, its referenced Mach-O executable, and its required frameworks/resources. An encrypted third-party executable must already be legitimately decrypted; editing its cryptid does not decrypt its bytes. SideStore then signs the compatible IPA with the user's signing credentials and applicable entitlements. SideStore installation is not guaranteed by structural validation alone.

## Repeatable local audit

\`\`\`sh
python3 tools/ipa_sideload_audit.py Music-AEECAED1.ipa --json music-audit.json
# Exit code 2: not ready.
python3 -m unittest discover -s tests -p 'test_ipa_sideload_audit.py' -v
\`\`\`

For a *complete, unencrypted, compatible* third-party app:

\`\`\`sh
python3 tools/ipa_sideload_audit.py CompleteApp.ipa --copy-ready CompleteApp-SideStore.ipa
\`\`\`

The tool copies the original bytes **unchanged** after structural checks; it does not produce FairPlay-decrypted data or Apple signing credentials.
