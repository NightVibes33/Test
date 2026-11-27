# ByeTunes standalone (Filza 27 edition)

Exact source pins:
- Filza-27 feature/erozzion-airlift-ios18-27: 92fa69df7f08e5af617a50b25f3564a37bf5dcbc
- EduAlexxis/ByeTunes: 54491b21c9949fd0410f760cfca9e8cf11f06f1d (2.5)
- NFCARD: 16f8bfd20a88a474f59c2d6eda291164a1cc015f; AirCard: 097a058c984ffc33ccb697b9dfe8058be3e86244; Erosion: a8dc7e48b13e130e69c28269a43fc4a8b456952a. The latest Filza build centralizes pairing; its pairing-removal patches are intentionally not applied here. The standalone app restores a dedicated Device Pairing screen from the shared settings design, not a link into Filza.

The native Xcode app is built from the pinned upstream project with the extracted Filza patches and Swift compatibility modules in this directory. It keeps the original onboarding, music library, backup/repair, lyrics, album colors and custom Airlift/LocalDevVPN pairing. A manual pairing-file importer is restored alongside the iOS 27 on-device pairing host. Filza UI, file manager and wallet UI are not packaged. The upstream license is preserved; do not use this for media you do not have rights to.

Build: run the standalone workflow on this branch, or run prepare.sh from a fresh checkout on macOS with Xcode 26.2 and Rust and build the MusicManager scheme. The output is an unsigned IPA for user signing. Minimum deployment target is iOS 17 (Airlift). On-device pairing specifically requires iOS 27; manual import remains available. Device pairing and library writes need real-device validation; CI compile is not such a test. The app uses a distinct bundle ID and no mandatory app-group entitlement.
