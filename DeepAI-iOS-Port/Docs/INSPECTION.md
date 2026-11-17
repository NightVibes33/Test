# Binary inspection of the uploaded DeepAI Code 0.3.40 DMG

**Original input:** DeepAI-Code-0.3.40-arm64.dmg, 169,059,658 bytes.

SHA-256: `12fc7d32446abbb4e9571c6da977890b2da12d3bca3780053ef0584963ccb973`.

Verified internal structure (using a standard-library-only parser):

| Layer | Evidence |
|---|---|
| DMG | Apple `koly` UDIF trailer, XML block maps |
| Disk | GPT with Apple_HFS partition, HFS+ volume signature `0x482b` |
| HFS+ | 451,555,328 bytes, 4,096-byte blocks, 202 catalog file records |
| Application | `DeepAI Code.app/Contents/MacOS/DeepAI Code` |
| Package metadata | `CFBundleIdentifier=org.deepai.code`, `CFBundleShortVersionString=0.3.40` |
| Electron bundle | `Contents/Resources/app.asar` (172,827,051 bytes) |
| Frontend | `apps/server/dist/client` contains 2,436 real files, totaling 48,000,143 bytes |
| Server | `apps/server/dist/binCli-D_ZLjpIS.mjs` (14,819,834 bytes) |
| Desktop code | `apps/desktop/dist-electron/main.cjs` (5,674,961 bytes) |
| Native dependencies | `node-pty`, `ffi-rs`, `@cursor/sdk` darwin ARM64 binaries, others |
| Lineage | App package includes `t3codeCommitHash=1998142fc9f7` |

### Extraction verification

The extraction script was run on the original uploaded file and independently compared to a manual HFS+/ASAR extraction. Both produced 2,436 files and the same SHA-256 for `OriginalWebClient/index.html`:

`583872f6ac23113a3d0a5c3fe62603506a9159beba1f300340ea44d090edfbdf`

### Port boundary

The frontend is built using browser-facing React code, so it can be rendered in iOS WebKit. The coding agent's Node.js execution layer depends on operating system facilities and architecture-specific native plugins absent on iOS. The provided port is therefore a genuine client port of the *original frontend*, not a standalone replacement for the entire desktop server. The on-device proxy forwards actual HTTP and WebSocket messages to an existing compatible server and contains no artificial agent logic.

### Verification not yet achieved

- iOS SDK compilation through `xcodebuild`
- Launch on simulator and on iPhone 16 / iOS 27
- End-to-end authentication and pairing against a live DeepAI Code 0.3.40 server
- Command execution, live agent streaming, and Git diff behavior from a device

These are requirements for a full functional release. Do not call an unsigned IPA build a finished port without these checks.
