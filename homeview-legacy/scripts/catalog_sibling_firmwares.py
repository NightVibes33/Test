#!/usr/bin/env python3
"""Summarize public ipsw.me devices that could replace the J490 OTA.

Does not download firmware. A different board is not a J490 candidate.
"""
import argparse
import json
from pathlib import Path

J490_CPID = 0x8140


def newest(firmwares):
    dated = [item for item in firmwares if isinstance(item, dict)]
    if not dated:
        return None
    return max(dated, key=lambda item: str(item.get("releasedate") or ""))


def summarize(devices, firmwares_by_id):
    home = []
    audio = []
    for device in devices:
        if not isinstance(device, dict):
            continue
        ident = str(device.get("identifier") or "")
        if ident.startswith("HomeAccessory"):
            home.append(ident)
        if ident.startswith("AudioAccessory"):
            payload = firmwares_by_id.get(ident) or {}
            firmwares = payload.get("firmwares") if isinstance(payload, dict) else None
            current = newest(firmwares or [])
            cpid = None
            boards = payload.get("boards") if isinstance(payload, dict) else None
            if isinstance(boards, list) and boards and isinstance(boards[0], dict):
                cpid = boards[0].get("cpid")
            audio.append({
                "identifier": ident,
                "board": payload.get("boardconfig") if isinstance(payload, dict) else None,
                "cpid": cpid,
                "same_chip_as_j490": cpid == J490_CPID,
                "newest_build": None if current is None else current.get("buildid"),
                "newest_version": None if current is None else current.get("version"),
                "newest_signed": None if current is None else bool(current.get("signed")),
                "newest_bytes": None if current is None else current.get("filesize"),
            })
    same_chip = [item for item in audio if item["same_chip_as_j490"]]
    return {
        "source": "api.ipsw.me/v4",
        "homeaccessory_identifiers": home,
        "audioaccessory": audio,
        "j490_cpid": J490_CPID,
        "switch_candidate": same_chip[0]["identifier"] if same_chip else None,
        "switch_recommended": False,
        "reason": (
            "ipsw.me lists no HomeAccessory firmware, and the AudioAccessory "
            "boards are not the J490 t8140 chip, so this boot stays on 24V514."
            if not home and not same_chip else
            "A same-chip signed firmware would be required before changing the guest."
        ),
    }


def fetch_public_catalog():
    import urllib.request
    with urllib.request.urlopen("https://api.ipsw.me/v4/devices", timeout=40) as handle:
        devices = json.load(handle)
    firmwares = {}
    for ident in (
        "AudioAccessory5,1", "AudioAccessory6,1", "AudioAccessory11,1",
        "HomeAccessory17,1", "HomeAccessory17,2",
    ):
        url = "https://api.ipsw.me/v4/device/" + ident + "?type=ipsw"
        try:
            with urllib.request.urlopen(url, timeout=40) as handle:
                firmwares[ident] = json.load(handle)
        except Exception as exc:
            firmwares[ident] = {"error": str(exc)[:180]}
    return summarize(devices, firmwares)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--devices")
    parser.add_argument("--firmwares", help="JSON object keyed by identifier")
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.fetch:
        try:
            report = fetch_public_catalog()
        except Exception as exc:
            report = {
                "source": "api.ipsw.me/v4",
                "fetch_error": str(exc)[:180],
                "switch_recommended": False,
                "switch_candidate": None,
            }
    else:
        devices = json.loads(Path(args.devices).read_text())
        firmwares = json.loads(Path(args.firmwares).read_text())
        report = summarize(devices, firmwares)
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "home": len(report["homeaccessory_identifiers"]),
        "switch": report["switch_candidate"],
    }))


if __name__ == "__main__":
    main()
