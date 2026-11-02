#!/usr/bin/env python3
"""Install user-supplied, QEMU-prepared HomeView firmware onto Linux research USB.

This does NOT decrypt Apple updates or validate Apple signatures. SHA256
records protect copies against corruption; build/device fields are claims
from the user's manifest, never provenance or genuine-boot evidence.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile

DEVICE = "HomeAccessory17,1"
BUILD = "24V514"
FORMAT = "homeview-qemu-prepared-v1"
FILES = frozenset(("bootkc", "dtree", "sptm", "txm", "ramdisk.dmg",
                   "ramdisk.tc", "ramdisk-su.dmg", "ramdisk-su.tc"))
MAX_FILE = 3 * 1024**3
MAX_TOTAL = 8 * 1024**3
HEX = re.compile(r"^[a-f0-9]{64}$")


def sha_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_file(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Not a regular firmware input: " + path.name)
    metadata = path.stat()
    if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= MAX_FILE:
        raise ValueError("Invalid firmware file length: " + path.name)
    return metadata.st_size


def check_file_set(names):
    names = set(names)
    if not names <= FILES:
        raise ValueError("Unexpected firmware file names")
    if not {"bootkc", "dtree", "sptm", "txm"} <= names:
        raise ValueError("Missing prepared Apple kernel, DT, SPTM or TXM")
    pairs = ({"ramdisk.dmg", "ramdisk.tc"},
             {"ramdisk-su.dmg", "ramdisk-su.tc"})
    if not any(pair <= names for pair in pairs):
        raise ValueError("No complete Apple restore or software-update ramdisk pair")
    if any(bool(pair & names) != (pair <= names) for pair in pairs):
        raise ValueError("Partial restore/software-update pair")


def file_details(folder, names):
    result = {}
    total = 0
    for name in sorted(names):
        length = safe_file(folder / name)
        total += length
        if total > MAX_TOTAL:
            raise ValueError("Firmware package exceeds bounded maximum")
        result[name] = {"size": length, "sha256": sha_file(folder / name)}
    return result


def manifest_from_directory(folder):
    names = {p.name for p in folder.iterdir() if p.is_file()
             and p.name in FILES}
    check_file_set(names)
    return {"schema": 1, "format": FORMAT, "device": DEVICE,
            "build": BUILD, "files": file_details(folder, names),
            "integrity_only_not_Apple_signature_verification": True}


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate manifest key: " + key)
        result[key] = value
    return result


def load_manifest(folder):
    file = folder / "manifest.json"
    if file.is_symlink() or not file.is_file() or file.stat().st_size > 32768:
        raise ValueError("Manifest missing, symlinked, or too large")
    data = json.loads(file.read_text(), object_pairs_hook=no_duplicate_keys)
    if not isinstance(data, dict) or (data.get("schema"), data.get("format"),
            data.get("device"), data.get("build")) != (1, FORMAT, DEVICE, BUILD):
        raise ValueError("Unsupported/mismatched user-claimed Apple firmware identity")
    records = data.get("files")
    if not isinstance(records, dict):
        raise ValueError("Firmware file manifest absent")
    check_file_set(records)
    for name, record in records.items():
        if not isinstance(record, dict):
            raise ValueError("Invalid manifest record")
        length = record.get("size")
        digest = record.get("sha256")
        if (type(length) is not int or not 0 < length <= MAX_FILE
                or not isinstance(digest, str) or not HEX.fullmatch(digest)):
            raise ValueError("Invalid length or SHA256 digest for " + name)
    if sum(v["size"] for v in records.values()) > MAX_TOTAL:
        raise ValueError("Manifest exceeds maximum package size")
    return data


def verify_directory(folder, manifest):
    entries = manifest["files"]
    observed = file_details(folder, entries)
    if observed != entries:
        raise ValueError("Firmware SHA256 or file sizes disagree with manifest")
    return observed


def write_manifest(folder):
    folder = Path(folder)
    data = manifest_from_directory(folder)
    destination = folder / "manifest.json"
    if destination.is_symlink():
        raise ValueError("Refusing to overwrite manifest symlink")
    tmp = folder / ".manifest.json.tmp"
    try:
        tmp.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n")
        os.replace(tmp, destination)
    finally:
        tmp.unlink(missing_ok=True)
    return data


def install(source, dest):
    source, dest = Path(source), Path(dest)
    if source.resolve() == dest.resolve():
        raise ValueError("Source and destination must differ")
    manifest = load_manifest(source)
    verify_directory(source, manifest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink():
        raise ValueError("Destination cannot be a symlink")
    if dest.exists():
        try:
            old = load_manifest(dest)
            if old["files"] == manifest["files"]:
                verify_directory(dest, old)
                return "already_verified"
        except (ValueError, OSError, json.JSONDecodeError):
            pass
    stage = Path(tempfile.mkdtemp(prefix=".homeview-import-", dir=dest.parent))
    backup = dest.parent / (dest.name + ".previous-import")
    try:
        for name in manifest["files"]:
            shutil.copyfile(source / name, stage / name, follow_symlinks=False)
            (stage / name).chmod(0o600)
        (stage / "manifest.json").write_text(json.dumps(manifest, sort_keys=True) + "\n")
        verify_directory(stage, manifest)
        stage.chmod(0o700)
        if backup.exists():
            raise ValueError("Existing firmware backup; refusing unsafe replacement")
        if dest.exists():
            os.replace(dest, backup)
        try:
            os.replace(stage, dest)
        except OSError:
            if backup.exists():
                os.replace(backup, dest)
            raise
        if backup.exists():
            shutil.rmtree(backup)
        return "installed"
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--destination")
    ap.add_argument("--create-manifest", action="store_true")
    args = ap.parse_args()
    try:
        if args.create_manifest:
            data = write_manifest(args.source)
            print("HOMEVIEW_FIRMWARE_MANIFEST_CREATED:",
                  ",".join(sorted(data["files"])))
        else:
            if not args.destination:
                ap.error("--destination is required for import")
            result = install(args.source, args.destination)
            print("HOMEVIEW_FIRMWARE_IMPORT:", result,
                  "checksums_verified; Apple authenticity NOT verified")
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print("HOMEVIEW_FIRMWARE_IMPORT_REJECTED:", exc, file=__import__("sys").stderr)
        raise SystemExit(78)


if __name__ == "__main__":
    main()
