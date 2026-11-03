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

# The unsigned app must support on-device pairing via its bundled AirLift FFI,
# not just imported desktop pairing records.
info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
assert "_remotepairing-pairable-host._tcp" in info["NSBonjourServices"]
assert "_ota27probe._tcp" in info["NSBonjourServices"]
assert "_remotepairing._tcp" in info["NSBonjourServices"]
assert "audio" in info["UIBackgroundModes"]
assert "localdevvpn" in info["LSApplicationQueriesSchemes"]
pairing_source = (root / "Sources/PairingController.swift").read_text()
assert "al_pairing_run_host" in pairing_source
assert "Pair with OTA27 Blocker" in pairing_source
assert "OTA27 Blocker" in pairing_source
assert "al_syslog_stream_start" in (root / "Sources/AirliftDiagnostics.swift").read_text()
print("On-device RPPairing code and LocalDevVPN app metadata validated.")

assert "al_connection_endpoint_set" in (root / "Sources/AirliftDiagnostics.swift").read_text()
assert (root / "Sources/RemotePairingPortDiscovery.swift").is_file()
assert r"\\(" not in (root / "Sources/AirliftDiagnostics.swift").read_text()
assert r"\\(" not in (root / "Sources/ContentView.swift").read_text()
print("NFCARD dynamic Remote Pairing endpoint wired correctly.")

assert (root / "Sources/GrappaHelper.m").is_file()
assert (root / "Sources/GrappaHelper.h").is_file()
assert "ALGetGrappaToken" in (root / "Sources/GrappaHelper.m").read_text()
assert "-u,_ALGetGrappaToken" in (root / "project.yml").read_text()
print("AirTraffic Grappa bridge verified for linking.")
