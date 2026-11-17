# Port fidelity matrix

| Capability | Status | Evidence/next requirement |
|---|---|---|
| Original DeepAI React UI | Included | Recovered 2,436 exact files from supplied DMG |
| Original UI served on iPhone | Implemented, untested on iOS | Swift `NWListener` loopback asset server + WKWebView |
| iOS ARM64 package | Build scripts created, unbuilt | Xcode SDK required |
| Real server API and WebSocket traffic | Proxy implemented, untested | Must test with live compatible host |
| Original DeepAI identity/theme | Bundled frontend | React UI not recreated |
| Sign-in/pairing | Not verified | May need host/cookie/OAuth adaptations |
| Git diff/edit/stage/commit | Host-dependent | Server-owned source control operations |
| Real terminal/subprocess tools | Host-dependent | iOS app cannot execute original macOS binaries |
| Offline, standalone coding agent on iOS | Not implemented | Requires a separate iOS runtime port |
| SideStore install | Not verified | Build unsigned IPA, then sign with SideStore |
