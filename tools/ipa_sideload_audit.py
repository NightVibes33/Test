#!/usr/bin/env python3
"""Audit an IPA for structural completeness and iOS executable encryption.

This does NOT bypass FairPlay, decrypt applications, produce signatures, or
guarantee an app can be installed. SideStore must sign compatible apps.
"""
import argparse
import hashlib
import json
import plistlib
import shutil
import struct
import sys
import zipfile
from pathlib import Path

THIN = {
    b"\xcf\xfa\xed\xfe": ("<", True),
    b"\xce\xfa\xed\xfe": ("<", False),
    b"\xfe\xed\xfa\xcf": (">", True),
    b"\xfe\xed\xfa\xce": (">", False),
}
FAT = {
    b"\xca\xfe\xba\xbe": (">", False),
    b"\xbe\xba\xfe\xca": ("<", False),
    b"\xca\xfe\xba\xbf": (">", True),
    b"\xbf\xba\xfe\xca": ("<", True),
}
LC_ENCRYPTION_INFO = {0x21, 0x2C}


def macho_slices(data):
    """Return per-architecture encryption status; raise on malformed Mach-O."""
    if len(data) < 4:
        raise ValueError("Executable too short")
    magic = data[:4]
    if magic in FAT:
        endian, fat64 = FAT[magic]
        if len(data) < 8:
            raise ValueError("Truncated FAT header")
        nfat = struct.unpack_from(endian + "I", data, 4)[0]
        if nfat > 128:
            raise ValueError("Excessive FAT architecture count")
        result = []
        off = 8
        entry_size = 32 if fat64 else 20
        for _ in range(nfat):
            if off + entry_size > len(data):
                raise ValueError("Truncated FAT architecture table")
            if fat64:
                slice_off, size = struct.unpack_from(endian + "QQ", data, off + 8)
            else:
                slice_off, size = struct.unpack_from(endian + "II", data, off + 8)
            if size == 0 or slice_off + size > len(data):
                raise ValueError("FAT slice outside file")
            result.extend(macho_slices(data[slice_off:slice_off + size]))
            off += entry_size
        return result
    if magic not in THIN:
        raise ValueError("Not a Mach-O executable")
    endian, is64 = THIN[magic]
    header_size = 32 if is64 else 28
    if len(data) < header_size:
        raise ValueError("Truncated Mach-O header")
    ncmds, sizeofcmds = struct.unpack_from(endian + "II", data, 16)
    if ncmds > 100000 or header_size + sizeofcmds > len(data):
        raise ValueError("Invalid Mach-O load commands")
    off = header_size
    cryptids = []
    for _ in range(ncmds):
        if off + 8 > header_size + sizeofcmds:
            raise ValueError("Truncated load command")
        cmd, size = struct.unpack_from(endian + "II", data, off)
        if size < 8 or off + size > header_size + sizeofcmds:
            raise ValueError("Invalid load command size")
        if cmd in LC_ENCRYPTION_INFO:
            if size < 20:
                raise ValueError("Truncated encryption load command")
            cryptids.append(struct.unpack_from(endian + "I", data, off + 16)[0])
        off += size
    return [{"encrypted": any(x != 0 for x in cryptids),
             "cryptids": cryptids}]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as src:
        for part in iter(lambda: src.read(1024 * 1024), b""):
            h.update(part)
    return h.hexdigest()


def audit(path):
    result = {
        "file": Path(path).name,
        "sha256": sha256(path),
        "ready_for_resigning": False,
        "limitations": ("Structural audit only; does not decrypt FairPlay, validate "
                        "entitlements, or guarantee SideStore installation."),
        "errors": [],
        "warnings": [],
        "executables": [],
    }
    errors = result["errors"]
    try:
        with zipfile.ZipFile(path) as z:
            names = {n for n in z.namelist() if not n.endswith("/")}
            if any(n.startswith("/") or ".." in Path(n).parts or "\\" in n for n in names):
                errors.append("Unsafe archive paths")
                return result
            roots = {n.split("/")[1] for n in names
                     if n.startswith("Payload/") and
                     len(n.split("/")) >= 3 and n.split("/")[1].endswith(".app")}
            if len(roots) != 1:
                errors.append("Expected exactly one Payload/*.app root, got " +
                              repr(sorted(roots)))
                return result
            app = "Payload/" + next(iter(roots)) + "/"
            result["app_path"] = app
            plist_path = app + "Info.plist"
            if plist_path not in names:
                errors.append("Missing main app Info.plist: " + plist_path)
            else:
                try:
                    info = plistlib.loads(z.read(plist_path))
                    result["bundle_id"] = info.get("CFBundleIdentifier")
                    executable = info.get("CFBundleExecutable")
                    if not executable or "/" in executable or "\\" in executable:
                        errors.append("Missing or unsafe CFBundleExecutable")
                    else:
                        path_in_zip = app + executable
                        if path_in_zip not in names:
                            errors.append("Missing main executable: " + path_in_zip)
                        else:
                            inspect_executable(z, path_in_zip, errors, result)
                    bundle_id = info.get("CFBundleIdentifier", "")
                    if not isinstance(bundle_id, str) or not bundle_id:
                        errors.append("Missing CFBundleIdentifier")
                    elif bundle_id.startswith("com.apple."):
                        errors.append("Reserved Apple bundle identifier: " + bundle_id)
                except (ValueError, TypeError, KeyError, plistlib.InvalidFileException) as e:
                    errors.append("Invalid main Info.plist: " + str(e))
            # Inspect extension bundles independently, even when the main app is missing.
            extension_plists = sorted(n for n in names if n.startswith(app + "PlugIns/")
                                      and n.endswith(".appex/Info.plist"))
            for pl in extension_plists:
                try:
                    info = plistlib.loads(z.read(pl))
                    exe = info.get("CFBundleExecutable")
                    parent = pl.rsplit("/", 1)[0] + "/"
                    if not exe or "/" in exe or "\\" in exe:
                        errors.append("Invalid extension executable in " + pl)
                    elif parent + exe not in names:
                        errors.append("Missing extension executable: " + parent + exe)
                    else:
                        inspect_executable(z, parent + exe, errors, result)
                except (ValueError, TypeError, KeyError, plistlib.InvalidFileException) as e:
                    errors.append("Invalid extension Info.plist: " + str(e))
            # Explicit CRC verification prevents treating corrupt ZIP bytes as a valid IPA.
            corrupt = z.testzip()
            if corrupt:
                errors.append("Archive CRC mismatch: " + corrupt)
    except (OSError, zipfile.BadZipFile, zipfile.LargeZipFile) as e:
        errors.append("Cannot read IPA: " + str(e))
    result["ready_for_resigning"] = not errors
    return result


def inspect_executable(z, name, errors, result):
    try:
        slices = macho_slices(z.read(name))
        result["executables"].append({"path": name, "slices": slices})
        if any(s["encrypted"] for s in slices):
            errors.append("Encrypted Mach-O: " + name +
                          " (requires a legitimately decrypted executable)")
    except (ValueError, KeyError) as e:
        errors.append("Invalid executable " + name + ": " + str(e))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--json", dest="report", type=Path,
                        help="Write inspection results as JSON")
    parser.add_argument("--copy-ready", type=Path,
                        help="Copy an unchanged structurally valid IPA for SideStore signing")
    args = parser.parse_args()
    if not args.ipa.is_file():
        parser.error("IPA not found: " + str(args.ipa))
    result = audit(args.ipa)
    print(json.dumps(result, indent=2))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + "\n")
    if result["ready_for_resigning"] and args.copy_ready:
        if args.ipa.resolve() != args.copy_ready.resolve():
            args.copy_ready.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(args.ipa, args.copy_ready)
        print("Copied unchanged IPA; SideStore still must sign it.")
    elif args.copy_ready:
        print("No output created: IPA is incomplete, encrypted, or otherwise invalid.",
              file=sys.stderr)
    return 0 if result["ready_for_resigning"] else 2


if __name__ == "__main__":
    sys.exit(main())
