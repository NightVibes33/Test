#!/usr/bin/env python3
"""Read at most 64 bytes from Apple's real 6.5 GB encrypted HomeView OTA.

This checks provenance, not extraction, boot or HomeView graphics.
"""
import argparse
import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request

CATALOG_URL = "https://raw.githubusercontent.com/Lakr233/vphone-cli/main/VPhoneKit/VPhoneCoreKit/Firmware/VPhoneFirmwareCatalog.swift"
PRODUCT = "HomeAccessory17,1"
BUILD = "24V514"
EXPECTED_SIZE = 6_509_559_808

def find_official_asset(catalog):
    entry = re.search(
        r'productType:\s*"HomeAccessory17,1"\s*,\s*version:\s*"27\.2"\s*,\s*'
        r'build:\s*"24V514"\s*,\s*url:\s*"([^"]+)"\s*,\s*size:\s*([\d_]+)',
        catalog)
    if not entry:
        raise ValueError("Pinned HomeView 27.2 OTA not found in upstream catalog")
    url, size = entry.group(1), int(entry.group(2).replace("_", ""))
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != "updates.cdn-apple.com" or not parsed.path.endswith(".aea"):
        raise ValueError("Upstream OTA URL is not an official Apple HTTPS AEA asset")
    if size != EXPECTED_SIZE:
        raise ValueError(f"Unexpected OTA size: {size} (pinned {EXPECTED_SIZE})")
    return url, size

def check_asset(url, expected_size, opener=urllib.request.urlopen):
    if urllib.parse.urlsplit(url).hostname != "updates.cdn-apple.com":
        raise ValueError("Refusing to connect to non-Apple host")
    request = urllib.request.Request(
        url,
        headers={"Range": "bytes=0-63", "Accept-Encoding": "identity", "User-Agent": "HomeViewLegacyOTAProbe/1.0"})
    with opener(request, timeout=45) as response:
        status = response.status
        content_range = response.headers.get("Content-Range", "")
        content_type = response.headers.get("Content-Type", "")
        prefix = response.read(64)
    if status != 206:
        raise ValueError(f"Apple CDN did not honor bounded byte range (status={status})")
    match = re.fullmatch(r"bytes\s+0-(\d+)/(\d+)", content_range)
    if not match or int(match.group(2)) != expected_size or int(match.group(1)) > 63:
        raise ValueError(f"Unexpected OTA Content-Range: {content_range!r}")
    if not prefix.startswith(b"AEA1"):
        raise ValueError(f"Apple CDN range does not start with AEA1 magic: {prefix[:8].hex()}")
    return {
        "official_apple_cdn": True, "product": PRODUCT, "build": BUILD,
        "archive_bytes": expected_size, "http_status": status,
        "range": content_range, "content_type": content_type,
        "aea_magic_verified": True, "read_bytes": len(prefix),
        "full_archive_downloaded": False, "homeview_decrypted": False,
        "homeview_booted_on_intel": False, "homeview_gui_verified": False
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", default=CATALOG_URL)
    parser.add_argument("--output", default="out/official-homeview-ota-probe.json")
    args = parser.parse_args()
    result = {"product": PRODUCT, "build": BUILD, "verified": False}
    try:
        if args.catalog.startswith("https://"):
            with urllib.request.urlopen(args.catalog, timeout=30) as resp:
                catalog = resp.read(1_000_000).decode("utf-8")
        else:
            catalog = pathlib.Path(args.catalog).read_text(encoding="utf-8")
        url, size = find_official_asset(catalog)
        result.update(check_asset(url, size))
        result["verified"] = True
    except (OSError, ValueError, UnicodeError) as exc:
        result["error"] = str(exc)
    path = pathlib.Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["verified"] else 1

if __name__ == "__main__":
    sys.exit(main())
