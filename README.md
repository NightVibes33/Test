# LiveContainer + Swift Playground

This repository starts from the official [LiveContainer](https://github.com/LiveContainer/LiveContainer) source pinned as a submodule. The overlay adds a **Swift Playground** tab to that real app.

The playground imports or edits a `.swift` file, checks it with Swift's parser, interprets an allowlisted SwiftUI subset, and renders supported controls with native SwiftUI. Imported source is not compiled or loaded as machine code; unsupported Swift constructs show diagnostics. This is an educational prototype, not a general Swift runtime.

Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/NightVibes33/Test.git
```

GitHub Actions tests the interpreter, applies the overlay to the pinned LiveContainer checkout, archives the iOS app unsigned, and uploads `LiveContainer-unsigned-ipa`. An Apple signing profile is required to install the IPA.
