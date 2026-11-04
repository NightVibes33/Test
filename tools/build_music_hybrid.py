#!/usr/bin/env python3
"""Assemble a legacy Music main app and modern extension-only fragment.

Requires a COMPLETE ALREADY-DECRYPTED legacy IPA. Does not decrypt FairPlay,
grant Apple-private entitlements, sign for SideStore, or guarantee runtime.
Inputs and output stay local; never publish Apple's binary to this repository.
"""
import argparse
import hashlib
import json
import plistlib
import sys
import zipfile
from pathlib import Path
from ipa_sideload_audit import audit, macho_slices


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as src:
        for chunk in iter(lambda: src.read(1048576), b""):
            h.update(chunk)
    return h.hexdigest()


def ipa(z):
    entries = [i for i in z.infolist() if not i.is_dir()]
    names = {i.filename for i in entries}
    if len(entries) != len(names):
        raise ValueError("Duplicate ZIP entry")
    if any(n.startswith("/") or "\\" in n or ".." in Path(n).parts for n in names):
        raise ValueError("Unsafe archive member path")
    if any(((i.external_attr >> 16) & 0o170000) == 0o120000 for i in entries):
        raise ValueError("Archive symlink not supported")
    bad = z.testzip()
    if bad:
        raise ValueError("Archive CRC mismatch: " + bad)
    apps = {n.split("/")[1] for n in names if n.startswith("Payload/")
            and len(n.split("/")) > 2 and n.split("/")[1].endswith(".app")}
    if len(apps) != 1:
        raise ValueError("Expected one Payload/*.app root")
    return names, "Payload/" + next(iter(apps)) + "/"


def verify_exe(z, names, root):
    if root + "Info.plist" not in names:
        raise ValueError("Info.plist missing in " + root)
    p = plistlib.loads(z.read(root + "Info.plist"))
    name = p.get("CFBundleExecutable")
    if not isinstance(name, str) or not name or "/" in name or "\\" in name:
        raise ValueError("Invalid CFBundleExecutable in " + root)
    if root + name not in names:
        raise ValueError("Executable missing in " + root)
    if any(s["encrypted"] for s in macho_slices(z.read(root + name))):
        raise ValueError("Executable still FairPlay encrypted in " + root)
    return p


def untrusted_signature(name):
    return ("/_CodeSignature/" in name or
            "/SC_Info/" in name or
            name.endswith("/embedded.mobileprovision"))


def build(legacy, modern, output, app_id, main_only=False, expected_hash=None):
    if not app_id or app_id.startswith("com.apple.") or "." not in app_id:
        raise ValueError("Provide a non-Apple app bundle ID")
    if output.resolve() in (legacy.resolve(), modern.resolve()):
        raise ValueError("Output cannot overwrite an input")
    modern_hash = sha256(modern)
    if expected_hash and modern_hash != expected_hash.lower():
        raise ValueError("Modern fragment SHA-256 mismatch")
    with zipfile.ZipFile(legacy) as old, zipfile.ZipFile(modern) as new:
        old_names, old_root = ipa(old)
        new_names, new_root = ipa(new)
        verify_exe(old, old_names, old_root)
        roots = sorted({n[len(new_root + "PlugIns/"):].split("/")[0]
                        for n in new_names if n.startswith(new_root + "PlugIns/")
                        and n[len(new_root + "PlugIns/"):].split("/")[0].endswith(".appex")})
        if not main_only and not roots:
            raise ValueError("Newer fragment has no extension payloads")
        contents = {}
        for name in sorted(old_names):
            if not name.startswith(old_root):
                continue
            rel = name[len(old_root):]
            if rel.startswith("PlugIns/") or untrusted_signature(name):
                continue
            data = old.read(name)
            if rel == "Info.plist":
                p = plistlib.loads(data)
                p["CFBundleIdentifier"] = app_id
                p["CFBundleDisplayName"] = "Music Hybrid"
                p["MinimumOSVersion"] = "27.0"
                data = plistlib.dumps(p)
            contents[name] = data
        included = []
        if not main_only:
            for ext in roots:
                prefix = new_root + "PlugIns/" + ext + "/"
                info = verify_exe(new, new_names, prefix)
                original_id = info.get("CFBundleIdentifier")
                if not isinstance(original_id, str) or not original_id:
                    raise ValueError("Extension has no bundle ID: " + ext)
                target_id = app_id + "." + original_id.rsplit(".", 1)[-1]
                included.append({"extension": ext, "bundle_id": target_id})
                for name in sorted(new_names):
                    if not name.startswith(prefix) or untrusted_signature(name):
                        continue
                    rel = name[len(prefix):]
                    dest = old_root + "PlugIns/" + ext + "/" + rel
                    data = new.read(name)
                    if rel == "Info.plist":
                        p = plistlib.loads(data)
                        p["CFBundleIdentifier"] = target_id
                        p["MinimumOSVersion"] = "27.0"
                        data = plistlib.dumps(p)
                    contents[dest] = data
        output.parent.mkdir(parents=True, exist_ok=True)
        try:
            with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as dst:
                for name, data in sorted(contents.items()):
                    dst.writestr(name, data)
            inspection = audit(output)
            if not inspection["ready_for_resigning"]:
                raise ValueError("Assembled IPA failed audit: " + "; ".join(inspection["errors"]))
            # Verify ALL retained Mach-O, not only executable and extensions.
            magic = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe",
                     b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce",
                     b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
                     b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca")
            with zipfile.ZipFile(output) as dst:
                for name in dst.namelist():
                    if name.endswith("/"):
                        continue
                    with dst.open(name) as f:
                        head = f.read(4)
                    if head in magic:
                        if any(s["encrypted"] for s in macho_slices(dst.read(name))):
                            raise ValueError("Encrypted Mach-O: " + name)
            report = {
                "result": output.name,
                "sha256": sha256(output),
                "old_ipa_sha256": sha256(legacy),
                "modern_fragment_sha256": modern_hash,
                "bundle_id": app_id,
                "modern_extensions": included,
                "entry_count": len(contents),
                "archive_audit": inspection,
                "limitations": ("Unsigned hybrid only. iOS 15 code is not rebuilt for iOS 27. "
                                "SideStore personal signing cannot grant private Apple Music "
                                "entitlements; runtime/playback unverified."),
            }
            output.with_suffix(".report.json").write_text(json.dumps(report, indent=2) + "\n")
            return report
        except Exception:
            output.unlink(missing_ok=True)
            raise


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--legacy", required=True, type=Path)
    p.add_argument("--modern", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    p.add_argument("--bundle-id", default="com.nightvibes33.applemusic27")
    p.add_argument("--main-only", action="store_true",
                   help="Do not bundle extensions, to reduce App ID provisioning")
    p.add_argument("--modern-sha256",
                   default="d12284c7349ae98dffc72a6e7c01f7c052f11b47def1ba2db33c1f113331aae9")
    a = p.parse_args()
    try:
        print(json.dumps(build(a.legacy, a.modern, a.output, a.bundle_id,
                               a.main_only, a.modern_sha256), indent=2))
    except (OSError, ValueError, zipfile.BadZipFile, plistlib.InvalidFileException) as e:
        p.exit(2, "Hybrid build blocked: " + str(e) + "\n")


if __name__ == "__main__":
    main()
