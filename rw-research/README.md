# iPhone 16 filesystem R/W research

This is a non-privileged iOS diagnostic app targeting iPhone17,3 on iOS 27.0.1. It is not a jailbreak, sandbox bypass, kernel read/write primitive, or reboot persistence mechanism.

## Real capabilities
- Opens and enumerates directories with POSIX calls, reporting exact failure errno.
- Does not read or export protected file contents.
- For app-owned folders and a folder explicitly authorized via Files, creates a unique temporary marker, reads it back and deletes it.
- Imports original Apple .ips crash reports locally and checks the PDF shading crash signature.
- Shares JSON results only when the user selects Share, with no network telemetry.

## Build
The GitHub workflow rw-research-ios.yml compiles an arm64 iOS binary without a signing identity and uploads artifact rw-research-unsigned-ipa. To install, sign it with a legitimate development identity or supported installer. Signing cannot fabricate private Apple entitlements.

## Research assessment
- Rust505 CVE-2026-112611 causes CoreGraphics PDF shading memory corruption. Two CGPDFService crashes on an iPhone 16 iOS 27.0.1 establish only reproducible service crashes.
- SKVLENT's IOSurface and Metal observations have not demonstrated cross-process access or kernel R/W.
- AppleAVE2 tests show crashes or kernel panics and unproven OOB candidates, not a working arbitrary kernel write.
- Liter8 is documented for a tethered iPhone 11 jailbreak. It does not work on the iPhone 16 and is not untethered.
- Rootless filesystem access and full writable system volume are not the same capability.

Next milestone: export baseline results and crash signatures. A separate, genuinely working exploit chain would be needed for unrestricted R/W.

Sources:
https://github.com/Rust505/CVE-2026-112611
https://github.com/SKVLENT/iOS27-Research-Exploits
https://github.com/Ping-2o/CVE-2026-112611-cg-shading
https://github.com/Xplo8E/Liter8