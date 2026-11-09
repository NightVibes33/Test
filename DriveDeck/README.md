# DriveDeck 1.3 (20) for iOS 27

An original, screenshot-guided car-style dashboard for iPhone and iPad. **The UI and local features are implemented**, but **it is not a working Apple CarPlay / CarPlay Ultra / Android Auto / AirPlay receiver**. The project contains no CarCast proprietary receiver code.

## Native screen receiver, screen sender and compatible viewer

- **Receiver and viewer on iOS:** Discover nearby DriveDeck devices, explicitly accept pairing, and view actual screen frames streamed over an encrypted peer session.
- **Transmitter:** From the local dashboard, start a ReplayKit capture on-screen after permission and send bounded JPEG frames to paired DriveDeck devices. This currently captures the app display; it does **not** capture other apps or launch native CarPlay.
- **Remote dashboard controls:** Send approved screen navigation commands (Home, Maps, Radio, Cluster, Music) across the same encrypted session. This does not inject system-wide iOS touches.
- **Compatible remote CarPlay browser:** Open an HTTPS viewer URL from an existing authorized CarPlay receiver. The receiver provides the actual session; this app does not implement MFi/iAP2 pairing yet. URL kept in Keychain. 
- **Reference analysis:** See [uploaded iCarCast static protocol audit](docs/ICARCAST_BINARY_AUDIT.md). No proprietary binary is copied into the build.

## Protocol discovery and diagnostic evidence

- In Settings → About → CarPlay protocol inspector, scan for actual CarPlay, AirPlay, RAOP and CarCast services on the same local network. The scan reports Bonjour metadata and optionally probes TCP reachability. It **does not claim authentication or native CarPlay support**.
- Export events as `DriveDeck-CarPlay-Protocol-Log.json`. With File Sharing enabled, the report is also accessible through Files → On My iPhone → DriveDeck.
- No pairing secrets, embedded MFi keys, or iCarCast proprietary binaries are shipped. To verify CarPlay interoperability, a genuine receiving session and MFi/iAP2 authentication are still necessary.

## What works
- iCarCast-style home screen and native grouped Settings sections matching all eight supplied screenshots.
- Persisted mode choices, car name, driver position, logo label, choice of logos or custom Photos image.
- Real dashboard with icon grid, responsive dock, real MapKit, Apple Music launch, real Phone dialer, and system SMS composer.
- Internet radio using AVPlayer: direct audio stream URL, volume, play/pause and persistent stations.
- Optional visual FM/AM dial simulator (not iPhone RF radio hardware).
- Optional local video file playback using AVKit. Avoid use while driving.
- Local browser dashboard served over unencrypted HTTP on configurable port, and read-only WebSocket telemetry on configured port. Bonjour discovery and peer connectivity check. All services foreground only.
- Local simulated map/gauge cluster, display aspect ratio, portrait responsiveness, night mode, show touches, notch inset, toolbar placement, and audio mute.
- Dynamic LAN address and on-device device ID, help guides and reset.
- Static screenshot-feature contract test and optional iPhone simulator screenshot capture in GitHub Actions.

## Build
Requires a macOS Xcode runner, XcodeGen and iOS SDK:
```sh
brew install xcodegen
python3 DriveDeck/scripts/ui_contract_test.py
python3 DriveDeck/scripts/create_icon.py DriveDeck/Resources/Assets.xcassets/AppIcon.appiconset/icon.png
cd DriveDeck && xcodegen generate
xcodebuild -project DriveDeck.xcodeproj -scheme DriveDeck -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```
GitHub Actions publishes `DriveDeck-unsigned.ipa` and, where a simulator is available, UI screenshots. You must sign the IPA with your own valid development or sideloading certificate before installing on a device.

## Boundaries
No fake connection-success messaging. The independent peer-to-peer receiver is real, but it is not the Apple CarPlay protocol; CarPlay, CarPlay Ultra, Android Auto, and AirPlay modes remain unavailable without compatible protocol stacks. CarPlay Ultra and the instrument cluster screens are clearly simulated. The LAN dashboard is not HTTPS and should only be exposed on a trusted network. Read [feature matrix](docs/PROTOCOL_MATRIX.md) before testing.

**Working rebrand:** DriveDeck; bundle identifier `com.nightvibes33.drivedeck`; current version 1.3 (20). Compatible target iOS 17+ with no confirmed physical iOS 27 test.
