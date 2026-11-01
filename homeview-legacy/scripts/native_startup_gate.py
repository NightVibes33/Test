#!/usr/bin/env python3
"""Native HomeView startup acceptance gate.

An EFI Linux screenshot does not satisfy this gate. A genuine Apple guest
must provide recorded native-screen captures, boot provenance, process and
service evidence, and explicit peripheral test results.
"""
import argparse
import json
import pathlib
import sys

STAGES = ("apple_boot", "hello", "hold_iphone_nearby", "breadboard_dashboard")
DEVICES = ("usb", "speakers", "mouse", "keyboard", "gpu", "cpu", "ram", "wifi", "bluetooth")

def verify(folder):
    root = pathlib.Path(folder)
    proof = root / "native-homeview-evidence.json"
    if not proof.is_file():
        return False, {"result": "BLOCKED", "reason": "No native Apple HomeView capture manifest", "native_homeview_verified": False}
    try:
        data = json.loads(proof.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return False, {"result": "FAIL", "reason": str(error), "native_homeview_verified": False}
    problems = []
    if data.get("guest_product") != "HomeAccessory17,1":
        problems.append("device identity HomeAccessory17,1 not proven")
    if data.get("guest_build") != "24V514":
        problems.append("genuine firmware 24V514 not proven")
    if data.get("native_screen_source") != "vphoned.screen.screenshot":
        problems.append("screenshots not from native Apple render server")
    if data.get("native_launcher") != "com.apple.BreadBoard":
        problems.append("native BreadBoard process not verified")
    if data.get("native_setup_assistant") != "com.apple.Setup":
        problems.append("native SetupAssistant process not verified")
    pictures = data.get("screenshots") or {}
    for stage in STAGES:
        filename = pictures.get(stage)
        if not isinstance(filename, str) or pathlib.PurePath(filename).name != filename:
            problems.append(stage + ": missing safe screenshot filename")
            continue
        path = root / filename
        if not path.is_file() or path.stat().st_size < 4096:
            problems.append(stage + ": no captured native screenshot")
            continue
        head = path.read_bytes()[:8]
        if not (head == bytes.fromhex("89504e470d0a1a0a") or head[:3] == bytes.fromhex("ffd8ff")):
            problems.append(stage + ": invalid PNG/JPEG")
    for name in DEVICES:
        if data.get("hardware_tests", {}).get(name) != "pass_on_physical_imac":
            problems.append(name + ": not validated on the physical iMac")
    if data.get("physical_imac_model") != "iMac11,2":
        problems.append("physical hardware iMac11,2 not tested")
    return not problems, {
        "result": "PASS" if not problems else "BLOCKED",
        "native_homeview_verified": not problems,
        "problems": problems,
        "phases": list(STAGES),
        "peripherals": list(DEVICES),
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default="native-evidence")
    parser.add_argument("--output", default="out/native-homeview-gate.json")
    parser.add_argument("--require-pass", action="store_true")
    args = parser.parse_args()
    ok, result = verify(args.evidence)
    path = pathlib.Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if args.require_pass and not ok:
        sys.exit(1)

if __name__ == "__main__":
    main()
