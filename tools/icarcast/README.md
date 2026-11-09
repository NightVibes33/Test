# iCarCast authorized IPA decryption runner

The original uploaded iCarCast IPA has SHA-256 a7d53382bc2bb8ab664fd133c2be022e89832a85362e3d764aee4bff89a6c1c9.
Bundle: ai.rplay.carcast.ios, version 1.0 (17).
Main binary: Payload/CarCast.app/CarCast, cryptoff=204800, cryptsize=4096, cryptid=1.
The unencrypted CarCastAirPlay framework is already readable. FairPlay SINF and version-3/5 SUPF records exist.

The original IPA **cannot be genuinely decrypted by a generic cloud runner alone**. The repo https://github.com/EthanArbuckle/fairplay-decrypt (pinned to d81d98b13656c9dbb340f04dd0838137278f44a5) derives the decryption keys using a 16-byte credential from the Apple account that owns this IPA. Its credential-retrieval process requires a supported jailbroken device. This is not your Apple ID password or a pairing file.

Configure GitHub repo Settings > Secrets and variables > Actions:
1. ICARCAST_IPA_URL: private, expiring HTTPS download URL for the original encrypted IPA.
2. FAIRPLAY_CREDENTIAL_B64: base64-encoded 16-byte credential.bin retrieved through the upstream authorized device method.

Never put an IPA with account-bound SC_Info records or an owner credential into git. Do not share the credential in chat. The runner fails clearly when keys are unavailable, runs real decryption when supplied, and refuses a fake cryptid-only patch. Verify device execution/signing separately. The branch does not alter main.

**Public repository caution:** GitHub Action artifacts in this public repository may be available to its viewers. A successful decrypted IPA artifact is retained for only one day; use a private repository if it must not be shared. This workflow requires a push to this temp branch to run; workflow_dispatch on an unmerged branch may not be offered by GitHub.
