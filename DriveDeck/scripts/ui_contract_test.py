#!/usr/bin/env python3
"""Screenshot contract checks for the supplied eight iCarCast reference images."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "Sources/DriveDeckUI.swift").read_text()
experience = (ROOT / "Sources/DriveExperience.swift").read_text()
web = (ROOT / "Sources/DriveWebPage.swift").read_text()
state = (ROOT / "Sources/DriveState.swift").read_text()
network = (ROOT / "Sources/NetworkHub.swift").read_text()
radio = (ROOT / "Sources/RadioConsole.swift").read_text()
cast = (ROOT / "Sources/DrivePeerCast.swift").read_text()
bridge = (ROOT / "Sources/ReceiverBridge.swift").read_text()
protocol = (ROOT / "Sources/CarPlayProtocolInspector.swift").read_text()

labels = {
    "home": ["Waiting for iPhone", "Settings", "Connect", "This iPhone", "Android Auto"],
    "modes": ["CarPlay", "Android Auto", "CarPlay Ultra", "Browser screen",
              "AirPlay", "AirPlay push", "AirPlay control", "How to turn on Zoom"],
    "car": ["Car name", "Car logo", "Logo label", "Driving Position"],
    "wifi": ["Wi-Fi for CarPlay", "HTTP port", "WebSocket port"],
    "display": ["Resolution", "Video playback", "Show touches", "Portrait",
                "Avoid notch", "Night mode", "Play sound here", "Mirror toolbar"],
    "cluster_about": ["Instrument cluster", "Version", "Device ID", "Address",
                      "Screen", "Hotspot Setup Guide", "Reset All Settings"]
}
missing = [f"{section}: {label}" for section, values in labels.items()
           for label in values if label not in ui]
assert not missing, "Missing screenshot controls: " + ", ".join(missing)
assert "CarLogoPickerView(store: store)" in ui
assert "DrivePeerCastView(cast: peerCast)" in ui
assert "--drive-screenshot-peer" in ui
assert "DriveExperienceView(store: store, network: network, peerCast: peerCast)" in ui
assert "DriveNetworkInfo.displayAddress" in ui
assert "RadioConsole(radio: radio, dark: dark)" in experience
assert "LocalVideoView()" in experience
assert "DriveDialer()" in experience and "DriveMessenger()" in experience
assert "setMuted(_ muted: Bool)" in state
assert "RadioStation" in radio and "radio.play()" in radio
assert "RPScreenRecorder.shared()" in cast
assert "encryptionPreference: .required" in cast
assert "MCNearbyServiceAdvertiser" in cast and "MCNearbyServiceBrowser" in cast
assert "WKWebView" in bridge
assert "ProtocolInspectorView()" in ui
assert "UIFileSharingEnabled" in (ROOT / "project.yml").read_text()
assert all(name in protocol for name in ("_carplay-ctrl._tcp", "_airplay._tcp", "_raop._tcp", "_carcast-hu._tcp"))
assert "TCP reachable:" in protocol and "CarPlay authentication NOT attempted" in protocol
assert "DriveWebPage.html" in network and "websocket.start" in network
assert 'id="radio"' in web and 'id="cluster"' in web
print("PASS: 5 home controls, 8 mode rows, 4 car rows, 3 Wi-Fi rows, "
      "8 display rows, instrument cluster, 6 About/reset rows and functional modules")
