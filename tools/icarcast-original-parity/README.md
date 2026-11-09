# Original iCarCast parity: minimal decrypted SideStore signing input

This package starts from the user's exact original IPA and inserts only an already-verified decrypted executable.
Other changes: remove obsolete FairPlay SC_Info licensing and invalidated code-signature folders, and enable only two optional Info.plist Files access keys.

The original CarPlay, AirPlay, Bonjour, network and interface resources are preserved. No injected framework, no runtime method swizzle, no synthetic NEHotspotNetwork object, and no new app UI.

Local usage:

    python3 scripts/repack_minimal.py --original /private/original.ipa --decrypted /private/decrypted.ipa --output /private/iCarCast-minimal.ipa --report /private/audit.json

Add --no-files-access to leave the source Info.plist byte-identical. IPA and credential materials remain local and are not placed into GitHub Actions.

Signed entitlement warning: SideStore must regenerate provisioning and code signatures. This repacker cannot grant Access Wi-Fi Information, multicast or Hotspot Configuration entitlements. A SideStore-signed copy may still fail Wi-Fi lookup, and the true CarPlay startup path is not confirmed until tested on physical hardware.

Files access alone does not create debug logs. The previous injected diagnostic and Wi-Fi framework has been removed from this minimal artifact because it deviated from the original and was implicated in an unverified crash.