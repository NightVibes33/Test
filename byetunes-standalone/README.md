# ByeTunes standalone (Filza 27 edition)

Exact source pins:
- Filza-27 main: ede65f4bb23899a83176713c59986bd0722da252
- EduAlexxis/ByeTunes: 54491b21c9949fd0410f760cfca9e8cf11f06f1d (2.5)
- NFCARD / AirCard / idevice: original Filza scripts' immutable pins.

The native Xcode app is built from the pinned upstream project with the extracted Filza patches and Swift compatibility modules in this directory. It keeps the original onboarding, music library, backup/repair, lyrics, album colors and custom Airlift/LocalDevVPN pairing. A manual pairing-file importer is restored alongside the iOS 27 on-device pairing host. Filza UI, file manager and wallet UI are not packaged. The upstream license is preserved; do not use this for media you do not have rights to.

Build: run the standalone workflow on this branch, or run prepare.sh from a fresh checkout on macOS with Xcode 26.2 and Rust and build the MusicManager scheme. The output is an unsigned IPA for user signing. Minimum deployment target is iOS 17 (Airlift). On-device pairing specifically requires iOS 27; manual import remains available. Device pairing and library writes need real-device validation; CI compile is not such a test. The app uses a distinct bundle ID and no mandatory app-group entitlement.
