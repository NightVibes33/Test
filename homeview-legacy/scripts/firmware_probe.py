#!/usr/bin/env python3
"""Read-only source verification; does not download Apple firmware."""
import argparse
import json
import pathlib
import re
import sys
import urllib.request

CATALOG = "https://raw.githubusercontent.com/Lakr233/vphone-cli/main/VPhoneKit/VPhoneCoreKit/Firmware/VPhoneFirmwareCatalog.swift"
BRINGUP = "https://raw.githubusercontent.com/Lakr233/vphone-cli/main/Research/Firmware/homeview_bringup.md"


def load(path):
    if path.startswith("https://"):
        request = urllib.request.Request(path, headers={"User-Agent": "HomeViewLegacyResearch/0.1"})
        with urllib.request.urlopen(request, timeout=25) as response:
            return response.read(2000000).decode("utf-8")
    return pathlib.Path(path).read_text(encoding="utf-8")


def inspect(catalog, bringup):
    found = re.search(
        r'productType:\s*"HomeAccessory17,1".{0,300}?'
        r'version:\s*"27\.2".{0,150}?build:\s*"24V514"',
        catalog, re.S)
    if not found:
        raise ValueError("HomeView 27.2 entry not found in upstream firmware catalog")
    if "BreadBoard" not in bringup or "HomeAccessory17,1" not in bringup:
        raise ValueError("HomeView runtime evidence missing")
    return {
        "product": "HomeAccessory17,1", "build": "24V514",
        "firmware_catalog_present": True,
        "upstream_breadboard_documented": True,
        "intel_homeview_boot_verified": False,
        "firmware_downloaded": False
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", default=CATALOG)
    parser.add_argument("--bringup", default=BRINGUP)
    parser.add_argument("--output")
    options = parser.parse_args()
    data = json.dumps(inspect(load(options.catalog), load(options.bringup)), indent=2) + "\n"
    print(data, end="")
    if options.output:
        pathlib.Path(options.output).write_text(data, encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, UnicodeError) as exc:
        print("FIRMWARE_PREFLIGHT_FAILED:", exc, file=sys.stderr)
        sys.exit(1)
