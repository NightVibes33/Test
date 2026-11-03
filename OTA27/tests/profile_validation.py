#!/usr/bin/env python3
"""Static tests: the bundled profile must match the inspected source's OTA DNS policy."""
import pathlib
import plistlib

root = pathlib.Path(__file__).resolve().parents[1]
profile = plistlib.loads((root / "Resources/blockota.mobileconfig").read_bytes())
assert profile["PayloadType"] == "Configuration"
assert profile["PayloadIdentifier"] == "dev.mineek.otablocker"
assert len(profile["PayloadContent"]) == 1
dns = profile["PayloadContent"][0]
assert dns["PayloadType"] == "com.apple.dnsSettings.managed"
assert dns["DNSSettings"]["DNSProtocol"] == "HTTPS"
assert dns["DNSSettings"]["ServerURL"] == "https://hi.frcoal"
assert dns["DNSSettings"]["SupplementalMatchDomains"] == ["gdmf.apple.com"]
assert dns["OnDemandRules"] == [{"Action": "Connect"}]
assert (root / "Sources/AirliftDiagnostics.swift").exists()
print("Profile and source layout validated; runtime OTA blocking not tested.")
