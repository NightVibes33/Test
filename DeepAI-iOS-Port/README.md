# DeepAI Code 0.3.40: on-device iOS engine port experiment

This branch attempts to run the *original DeepAI 0.3.40* Node.js coding server **inside the iPhone process** rather than connecting to a Mac/PC server.

## Source and runtime

- The pinned official DeepAI 0.3.40 DMG is checked with SHA-256 and extracted at GitHub Actions build time. The build recovers the original React client and **the original bundled `apps/server/dist` and JavaScript dependencies**. No proprietary assets or credentials are checked into Git.
- `NodeMobile.xcframework` v24.22.1-0 (full version with `node:sqlite`) is downloaded from the publicly distributed mobile Node project, verified by its release SHA-256, and linked into the iOS ARM64 binary. This is real Node.js executing in the app sandbox, not a fake terminal or browser proxy.
- Objective-C++ bridge starts original `apps/server/dist/bin.mjs serve --host 127.0.0.1 --port 37730 --base-dir <app-support> --cwd <Documents>`.
- SwiftUI loads the local original server web interface, if the server successfully boots. There is no remote-host configuration and no remote computer requirement to start the backend.
- App Documents are exposed through the Files app. Original startup stdout/stderr goes into `Library/Application Support/DeepAI/embedded-node.log`, accessible through the Diagnostics UI.

## Current verification state

This is **a native embedded-backend port attempt, not yet a working standalone agent**. Node.js Mobile supports filesystem, network, Node SQLite, and pure JS modules on iOS, but it cannot launch the original desktop subprocesses. The original server's `node-pty`, platform-native Git, and provider executable adapters may fail at startup or when used. These need native iOS replacements. Unsupported functionality is not silently simulated.

The GitHub workflow independently compiles for simulator and device, then attempts a real launch and saves Node startup logs. Do not call a green build proof that login, agents, Git or terminal work end-to-end.

## Build

The hosted workflow at `.github/workflows/deepai-code-ios.yml` downloads the official DMG and NodeMobile binary, verifies both hashes, extracts the original resources, compiles the simulator and iPhone targets, and uploads the unsigned IPA for SideStore signing.

For local builds on macOS, use:

```bash
python3 Scripts/extract_deepai_dmg.py DeepAI-Code-0.3.40-arm64.dmg --with-server
bash Scripts/get-node-mobile.sh
bash Scripts/build-ipa.sh
```

Do not commit the extracted `OriginalServer`, `OriginalWebClient`, or `Frameworks` directories. They are reproducible build inputs.
