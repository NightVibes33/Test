# LiveContainer

This repository uses the official [LiveContainer](https://github.com/LiveContainer/LiveContainer) source as a Git submodule. It is pinned to upstream commit `4dbe0f9a626de801184a42c0be8d2cb105058e3d`. The separate `NightVibes33` LiveContainer fork is not used or modified.

Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/NightVibes33/Test.git
```

If you already cloned the repository:

```sh
git submodule update --init --recursive
```

The GitHub Actions workflow archives the real LiveContainer iOS app without signing and uploads `LiveContainer-unsigned-ipa` under the run's **Artifacts** section. Signing it for installation is a separate step.
