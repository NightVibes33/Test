# DeepAI Code 0.3.40: iOS client port (work-in-progress)

This is a genuine **client-side port of the original DeepAI Code 0.3.40 React application** extracted from the supplied Mac DMG. It is **not** a DMG rewrapper, an iOS version of Electron, an invented screen, or a claim that macOS shell programs execute on iPhone.

## What this includes

- The **original 2,436-file React client** extracted from the supplied `DeepAI-Code-0.3.40-arm64.dmg` (see `OriginalWebClient/`).
- A native **SwiftUI / WKWebView iOS shell** with server configuration.
- An on-device **loopback HTTP asset server** with raw TCP and WebSocket proxying of real server API requests.
- An alternative **direct-host mode** for authentication flows incompatible with proxying.
- A dependency-free **UDIF -> HFS+ -> ASAR -> client** extraction tool, independently tested against the supplied DMG.
- XcodeGen project specification, a macOS unsigned IPA build script and a GitHub Actions workflow.

## Important: what's not ported

DeepAI's **server-side agent, terminal processes, Git operations, node-pty, native `.node`/`.dylib` addons and macOS executables** still require a compatible server on another machine. This client does **not** run the full desktop coding engine on iOS. The backend should be the same DeepAI Code version, with secure network access and its own authentication/pairing. We have not yet validated the complete live pairing flow against a running DeepAI Code server; it may require compatibility work. The Swift source passed parser validation but has **not** been Xcode-compiled or run on an iPhone or simulator in this environment.

The project is intentionally honest about partial port status. A full standalone port would require reimplementing the Node agent runtime, its subprocess/tool system, and the native dependencies for an iOS-compatible execution sandbox; merely switching the ARM64 Mach-O platform cannot achieve that.

## Build from this ZIP on macOS

1. Install full Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
2. The original web client is already included. If missing, regenerate from your DMG using `python3 Scripts/extract_deepai_dmg.py /path/to/DeepAI-Code-0.3.40-arm64.dmg`.
3. Run `Scripts/build-ipa.sh`. It produces `build/DeepAI-Code-iOS-0.3.40-unsigned.ipa`.
4. Have SideStore sign this *unsigned* IPA using a provisioning profile compatible with the bundle identifier `org.deepai.code.ios.port`.
5. Enter the URL of your compatible DeepAI Code server. The server must be explicitly reachable and access-controlled. A local `127.0.0.1` URL on the computer is not reachable from the iPhone.

## Build through GitHub Actions

Push the **source files** to a `deepai-ios` or `deepai-ios-port` branch. The workflow downloads the official macOS image, verifies SHA-256 against the uploaded 0.3.40 image, extracts the exact frontend, compiles the iOS simulator target, builds an unsigned device IPA and uploads it as a workflow artifact.

- SHA-256 of supplied DMG: `12fc7d32446abbb4e9571c6da977890b2da12d3bca3780053ef0584963ccb973`.
- If the download URL starts returning a newer version, the hash check will fail **on purpose**, rather than silently packaging the wrong DeepAI version. Provide the pinned 0.3.40 DMG to the workflow to continue.
- `OriginalWebClient` is excluded from Git and is reconstructed in CI. It is included in this local ZIP for inspection and building without redownloading.

## Security and limitations

- The local asset server is bound to `127.0.0.1` on the iPhone; its route proxy only reaches the server URL explicitly configured by the user. It doesn't fabricate agent responses.
- HTTPS is required for non-private hostnames; HTTP is offered only to local/private network endpoints. Use a properly encrypted connection and a pairing/token mechanism. Never expose a coding agent with file and terminal permissions on a public address without authentication.
- Some OAuth, cookie domain, passkey and WebSocket origin assumptions are specific to DeepAI's desktop frontend. If bundled-mode login fails, try **Direct-host mode** while the compatibility work is completed.
- Full remote compatibility is not confirmed. CI success would demonstrate iOS compilation, **not** full agent functionality.
- The source app's `package.json` identifies version `0.3.40` and an MIT license, but contains third-party components and DeepAI trademarks. Respect upstream terms if redistributing beyond personal testing.

## Origin and findings

- Original bundle ID: `org.deepai.code`; iOS port uses a distinct bundle identifier to avoid colliding with the macOS product.
- `apps/server/dist/client` contains the original React frontend.
- `apps/server/dist/binCli-D_ZLjpIS.mjs` is a server bundle with HTTP/RPC/WebSocket routes.
- `apps/desktop/dist-electron` and native ARM64 addons are desktop-only.
- `t3codeCommitHash` in the original package: `1998142fc9f7` (not proof that all current T3 Code mobile source/API is wire-compatible).

See [`Docs/INSPECTION.md`](Docs/INSPECTION.md).
