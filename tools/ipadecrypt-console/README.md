# ipadecrypt console · replacement for the experimental IPA-only decryptor

This workflow builds the genuine, MIT-licensed [londek/ipadecrypt](https://github.com/londek/ipadecrypt) from pinned upstream commit `9958b9298b62dfef5053d9b6491634c006f3d4e7`. It emits ready-to-run **Windows**, **macOS** and **Linux** console binaries. Source code is pulled from upstream, not replaced by a mocked decrypt button. The App Store decryption and output verification code run on your computer.

**Why not a standalone iPhone IPA?** The upstream CLI is a desktop Go program. Its one-time credential mint needs a jailbroken iPhone/iPad with **root SSH**, an owned App Store app and matching Apple account. There is no demonstrated way to mint the same credential on stock iOS 27.0.1 just from a pairing record, worse_query container access or a LocalDevVPN/RSD socket. Its on-device fallback for older 32-bit apps additionally requires AppSync Unified and appinst. A GitHub runner does not have your licensed iPhone or its keys.

## Windows setup

1. Download the `ipadecrypt-console-windows` artifact from the workflow run. Unzip it.
2. Open PowerShell inside that folder and run `./ipadecrypt.exe bootstrap`. This signs in on **your PC** and performs the one-time credential mint over root SSH to a jailbreak-capable iOS device that has an App Store app owned by the same Apple account. No credentials are ever entered into this GitHub workflow.
3. After a successful bootstrap, decrypt the local iCarCast IPA with:
   ```powershell
   ./run-icarcast.ps1 -IpaPath "C:\\path\\to\\iCarCast-DD937222.ipa"
   ```
4. The wrapper calls `ipadecrypt --redact decrypt ... --no-on-device --extra-verify`, refuses to overwrite an existing file, requires a produced output and prints its SHA-256. Re-sign that IPA before installation.

For macOS/Linux: `./ipadecrypt bootstrap` then `bash ./run-icarcast.sh /path/to/iCarCast-DD937222.ipa`. If unpacked permissions were lost, run `chmod +x ipadecrypt`.

## App install vs repo source

The existing SwiftUI iOS IPADecrypter remains an **experimental device-assisted research app**, not a replacement for upstream ipadecrypt. Its imported-IPA path can inspect but not generally decrypt new iOS 27 uploads. The production CLI workflow is the actual recommended path. Both are kept on the same temporary GitHub branch so you can compare them.

**Safety/privacy:** Do not upload FairPlay credentials, pairing private keys, App Store cookies or encrypted account-bound IPAs to this public repository or to runner secrets. The build only downloads public upstream source and produces binaries. The decrypt process runs locally after bootstrap.

Upstream license: MIT; bundled console source is retrieved from its pinned commit. No third-party source is copied into this repo. The existing Swift source and worse_query components keep their original GPL licenses.
