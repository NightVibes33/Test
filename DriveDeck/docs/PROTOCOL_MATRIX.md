# DriveDeck 1.1 feature/compatibility matrix

This project is built from scratch using the user-supplied iCarCast **UI screenshots** as a reference. It does not copy proprietary app source or keys. It is designed for iOS 17+ (including iOS 27), with real iOS 27 device testing outstanding.

| Screenshot function | DriveDeck implementation | Reality check |
|---|---|---|
| Waiting screen | Branded name, icon, Connect, This iPhone, Android Auto, Settings | Real CarPlay receiver absent |
| Modes | All seven mode switches (AirPlay push depends on AirPlay) | CarPlay/Android Auto/Ultra/AirPlay switches persist but cannot negotiate protocols |
| Car name/logo/label | Editable and applied to local dashboard | Custom Photos logo stored on-device |
| Driver position | Relocates dashboard dock | No real vehicle control |
| Wi-Fi name | User-selected network label | iOS cannot freely read/change SSID without location/entitlement constraints |
| HTTP and WebSocket | Actual foreground LAN services | HTTP is unencrypted; WebSocket is read-only telemetry, not remote input or CarPlay |
| Resolution | Aspect ratio changes local dashboard display | Physical panel resolution cannot be changed |
| Video playback | Local Files import via AVKit | Not CarPlay app video projection; intended only while parked |
| Show touches | Visual touch marker | Local only |
| Portrait | Responsive local dashboard | Does not force iOS system rotation |
| Avoid notch | Additional display inset | iOS still manages system safe area |
| Night mode | Auto/light/dark dashboard themes | Does not modify CarPlay |
| Play sound here | Mutes or unmutes internet radio output | Does not route original CarPlay audio elsewhere |
| Mirror toolbar | Moves/hides local dashboard dock | Local only |
| Instrument cluster | Second in-app gauge/map simulation | No vehicle telemetry or CarPlay Ultra decoding |
| About | Version, stable generated ID, live LAN address, screen status, guide, reset | Does not forge MAC address |
| Car-style app grid | Maps, internet radio, video, calls, SMS, Music handoff | These are ordinary iOS native functions |
| Internet radio | Stream from valid URL, volume, named station presets | The FM/AM frequency display is a simulator, not FM radio hardware |

## Independent protocol research (not included in the IPA)

- Apple's MFi program lists CarPlay, AirPlay, and iAP2 among its licensed technologies: https://mfi.apple.com/en/how-it-works
- CatPlay claims a Rust CarPlay transmitter/receiver implementation and targets Linux embedded dongles with MFi chip hardware. It does not provide a drop-in iOS app library and does not currently support CarPlay Ultra: https://github.com/catplay-labs/catplay
- CarCast's public project provides its guides and releases rather than the iCarCast source: https://github.com/rPlayAI/carcast-public

A true CarPlay/iAP2/AirPlay receiver requires substantial separate protocol research, pairing/authentication work, AV streaming decode, hardware testing, and authorization/compliance as applicable. Do not present a simple Bonjour discovery or local HTML dashboard as equivalent.


### Protocol inspector (v1.3)

The app discovers `_carplay-ctrl._tcp`, `_airplay._tcp`, `_raop._tcp` and `_carcast-hu._tcp`, shows their Bonjour metadata, tests basic TCP reachability and exports on-device JSON logs through Files. It never treats a reachable TCP port as a paired CarPlay session.
