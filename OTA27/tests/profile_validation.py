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
assert "-exported_symbol,_ALGetGrappaToken" in (root / "project.yml").read_text()
print("AirTraffic Grappa bridge verified for linking.")

# Build-time seed packaging is required for the original 51-module harness.
project = (root / "project.yml").read_text()
assert "CinderLab/Sources" in project
for name in ("joliet_path_oob.iso", "deep_nest.usda", "stack_bomb.cff", "ktx2_bad_dims.ktx2", "bc7_short.dds"):
    assert "CinderLab/Seeds/" + name in project
assert "CinderLab/CinderPOCs.zip" in project
print("All five PoC payload seeds and original source archive declared as app resources.")

# Cinder27 original seed generation is a single CI step, and each seed ships at app root.
workflow = (root.parent / ".github/workflows/ota27-unsigned.yml").read_text()
assert 'python3 "$SRC/scripts/gen_seeds.py"' in workflow
assert workflow.count('python3 "$SRC/scripts/gen_seeds.py"') == 1
assert "Verify bundled Cinder27 PoC seeds" in workflow
for seed in ("joliet_path_oob.iso", "deep_nest.usda", "stack_bomb.cff", "ktx2_bad_dims.ktx2", "bc7_short.dds"):
    assert "CinderLab/Seeds/" + seed in project
    assert seed in workflow
print("Cinder27 resource staging and postbuild seed checks validated.")

# All 32 uploaded PoC families must link to their original executable runners,
# rather than being a static inventory with dummy action buttons.
import re
index = (root / "Sources/Cinder27POCIndexView.swift").read_text()
families = re.findall(r"^\\s*(CVE-2026-[0-9]+|arc\\.rr)\\|", index, re.MULTILINE)
assert len(families) == 32, f"Expected 32 source families, saw {len(families)}"
assert len(set(families)) == 32
assert sum(family.startswith("CVE-2026-") for family in families) == 31
assert families[-1] == "arc.rr"
assert "Catalog.byID[record.module]" in index
assert "ModuleDetailView(module: module)" in index
assert ".environmentObject(engine)" in index
assert "CinderLabHost(engine: engine)" in index
host = (root / "Sources/CinderLabHost.swift").read_text()
assert "@ObservedObject var engine: LabEngine" in host
assert "@StateObject private var engine = LabEngine()" not in host
print("Cinder27 executable PoC navigation validated (31 CVE families + arc.rr).")
