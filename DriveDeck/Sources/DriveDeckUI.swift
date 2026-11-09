import SwiftUI
import UIKit
import MapKit

@main
struct DriveDeckApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
    }
}

struct HomeView: View {
    @StateObject private var store = DriveStore()
    @StateObject private var network = NetworkHub()
    @StateObject private var peerCast = DrivePeerCast()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showDashboard = false
    @State private var showConnect = false
    @State private var showAndroid = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.065, green: 0.065, blue: 0.07).ignoresSafeArea()
                VStack(spacing: 25) {
                    Spacer()
                    Image(systemName: "airplay.video")
                        .font(.system(size: 60, weight: .light))
                        .frame(width: 105, height: 105)
                        .foregroundStyle(.white)
                        .background(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 25))
                    Text(store.settings.carName)
                        .font(.system(size: min(geometry.size.width * 0.085, 38), weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal)
                    Text("Waiting for iPhone")
                        .font(.title3)
                        .foregroundStyle(.gray)
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                            .font(.title2)
                    }
                    .padding(.top, 3)
                    HStack(spacing: 35) {
                        Button {
                            showConnect = true
                        } label: {
                            Label("Connect", systemImage: "iphone.radiowaves.left.and.right")
                        }
                        Button {
                            showDashboard = true
                        } label: {
                            Label("This iPhone", systemImage: "iphone")
                        }
                    }
                    .font(.system(size: 19))
                    .padding(.top, 7)
                    Button {
                        showAndroid = true
                    } label: {
                        Label("Android Auto", systemImage: "location.north.fill")
                            .font(.title3)
                    }
                    .padding(.top, 3)
                    Text("Receiver & Viewer • Secure local screen casting. CarPlay protocol compatibility still under development.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 35)
                    Spacer()
                }
                .tint(.blue)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store, network: network)
        }
        .fullScreenCover(isPresented: $showDashboard) {
            DriveExperienceView(store: store, network: network, peerCast: peerCast)
        }
        .sheet(isPresented: $showConnect) {
            DrivePeerCastView(cast: peerCast)
        }
        .sheet(isPresented: $showAndroid) {
            ModeNoticeView(title: "Android Auto",
                           message: "The Android Auto head-unit protocol has not been implemented. The app does not advertise a fake Android Auto connection.")
        }
        .onAppear {
            network.configure(store.settings)
            if ProcessInfo.processInfo.arguments.contains("--drive-screenshot-settings") {
                showSettings = true
            } else if ProcessInfo.processInfo.arguments.contains("--drive-screenshot-dashboard") {
                showDashboard = true
            } else if ProcessInfo.processInfo.arguments.contains("--drive-screenshot-peer") {
                showConnect = true
            }
        }
        .onChange(of: store.settings) { _, next in
            if scenePhase == .active { network.configure(next) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { network.configure(store.settings) }
            else if phase == .background { network.stopAll(); peerCast.stopCapture() }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: DriveStore
    @ObservedObject var network: NetworkHub
    @Environment(\.dismiss) private var dismiss
    @State private var edit: EditableSetting?
    @State private var showZoom = false
    @State private var showHotspot = false
    @State private var confirmReset = false
    @State private var showLogoPicker = false
    @State private var showProtocolInspector = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    modesSection
                    carSection
                    wifiSection
                    displaySection
                    clusterSection
                    aboutSection
                    resetSection
                }
                .padding(18)
                .padding(.bottom, 40)
            }
            .background(Color.black)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 47, height: 47)
                            .background(.blue, in: Circle())
                    }
                }
            }
        }
        .tint(.blue)
        .sheet(item: $edit) { field in
            EditSettingView(field: field, store: store)
        }
        .sheet(isPresented: $showLogoPicker) {
            CarLogoPickerView(store: store)
        }
        .sheet(isPresented: $showProtocolInspector) {
            ProtocolInspectorView()
        }
        .sheet(isPresented: $showZoom) {
            GuideView(title: "Zoom control",
                      text: "Open iPhone Settings > Accessibility > Zoom and turn Zoom on. Device accessibility behavior is controlled by iOS, not by DriveDeck. AirPlay touch forwarding is not yet supported.")
        }
        .sheet(isPresented: $showHotspot) {
            GuideView(title: "Wi-Fi and Hotspot",
                      text: "Connect both iOS devices to the same Wi-Fi network. Enable Browser screen on the receiving device, then open http://DEVICE-LAN-IP:PORT from another device on that network. Replace DEVICE-LAN-IP with the receiver's actual local IP and PORT with the HTTP port in Settings. The receiver runs only while the app is active. This is a local browser status view, not wireless CarPlay.")
        }
        .confirmationDialog("Restore every setting to its default?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset All Settings", role: .destructive) { store.reset() }
        }
    }


    private var modesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                    section("Modes") {
                        SettingToggle("CarPlay", icon: "car.fill", tint: .green, isOn: store.binding(\.carPlay))
                        settingDivider()
                        SettingToggle("Android Auto", icon: "location.north.fill", tint: .blue, isOn: store.binding(\.androidAuto))
                        settingDivider()
                        SettingToggle("CarPlay Ultra", icon: "gauge.with.dots.needle.bottom.50percent", tint: .orange, isOn: store.binding(\.ultra))
                        settingDivider()
                        SettingToggle("Browser screen", icon: "globe", tint: .cyan, isOn: store.binding(\.browser))
                        settingDivider()
                        SettingToggle("AirPlay", icon: "airplay.video", tint: .indigo, isOn: store.binding(\.airPlay))
                        settingDivider()
                        SettingToggle("AirPlay push", icon: "play.rectangle.fill", tint: .red,
                                      isOn: store.binding(\.airPlayPush), disabled: !store.settings.airPlay)
                        settingDivider()
                        SettingToggle("AirPlay control", icon: "hand.tap.fill", tint: .purple, isOn: store.binding(\.airPlayControl))
                        settingDivider()
                        SettingAction("How to turn on Zoom", icon: "plus.magnifyingglass", tint: .gray) {
                            showZoom = true
                        }
                    }
                    note("Mode switches save your requested configuration. The local dashboard and browser screen work; Apple CarPlay, Android Auto, AirPlay and Ultra projection require receiver implementations that are not included. AirPlay push is dependent on AirPlay.")


        }
    }

    private var carSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                    section("Car") {
                        SettingAction("Car name", icon: "car.side.fill", tint: .blue, value: store.settings.carName) { edit = .carName }
                        settingDivider()
                        SettingAction("Car logo", icon: "photo.fill", tint: .green, value: store.settings.carLogo) { showLogoPicker = true }
                        settingDivider()
                        SettingAction("Logo label", icon: "textformat", tint: .orange, value: store.settings.logoLabel) { edit = .logoLabel }
                        settingDivider()
                        SettingAction("Driving Position", icon: "steeringwheel", tint: .gray,
                                      value: store.settings.drivingPosition) { edit = .drivingPosition }
                    }
                    note("The name and logo customize DriveDeck's local dashboard. Driving position moves its side dock. These settings do not change a real CarPlay head unit.")


        }
    }

    private var wifiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                    section("Wi-Fi") {
                        SettingAction("Wi-Fi for CarPlay", icon: "wifi", tint: .blue,
                                      value: store.settings.wifiLabel) { edit = .wifiLabel }
                        settingDivider()
                        SettingAction("HTTP port", icon: "lock.open.fill", tint: .green,
                                      value: String(store.settings.httpPort)) { edit = .httpPort }
                        settingDivider()
                        SettingAction("WebSocket port", icon: "arrow.left.arrow.right", tint: .orange,
                                      value: String(store.settings.webSocketPort)) { edit = .webSocketPort }
                    }
                    note("The chosen network name is a label, not a verified Wi-Fi SSID. Browser mode serves unencrypted HTTP while foregrounded on the configured port. WebSocket provides read-only local telemetry on its configured port while browser mode is active; it is not CarPlay.")
                    if store.settings.browser {
                        Text(network.browserMessage)
                            .foregroundStyle(.blue)
                            .font(.footnote)
                    }


        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
                    section("Display") {
                        SettingAction("Resolution", icon: "rectangle.split.2x1.fill", tint: .purple,
                                      value: store.settings.resolution) { edit = .resolution }
                        settingDivider()
                        SettingToggle("Video playback", icon: "play.rectangle.fill", tint: .red, isOn: store.binding(\.videoPlayback))
                        settingDivider()
                        SettingToggle("Show touches", icon: "hand.tap.fill", tint: .green, isOn: store.binding(\.showTouches))
                        settingDivider()
                        SettingToggle("Portrait", icon: "iphone", tint: .blue, isOn: store.binding(\.portrait))
                        settingDivider()
                        SettingToggle("Avoid notch", icon: "iphone.gen3", tint: .gray, isOn: store.binding(\.avoidNotch))
                        settingDivider()
                        SettingAction("Night mode", icon: "moon.fill", tint: .indigo,
                                      value: store.settings.nightMode) { edit = .nightMode }
                        settingDivider()
                        SettingToggle("Play sound here", icon: "speaker.wave.2.fill", tint: .pink, isOn: store.binding(\.playSoundHere))
                        settingDivider()
                        SettingAction("Mirror toolbar", icon: "sidebar.right", tint: .gray,
                                      value: store.settings.mirrorToolbar) { edit = .mirrorToolbar }
                    }
                    note("Display preferences persist. Portrait, night mode, sound and toolbar layout affect the local dashboard when supported. CarPlay-specific playback and mirroring features need a protocol engine.")


        }
    }

    private var clusterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                    section("Instrument cluster") {
                        SettingToggle("Instrument cluster", icon: "gauge.with.needle", tint: .orange,
                                      isOn: store.binding(\.cluster))
                    }
                    note("An optional second local demo panel for a map and simulated gauges. Not a decoded CarPlay instrument-cluster feed.")


        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                    section("About") {
                        SettingInfo("Version", icon: "info.circle.fill", value: "1.3 (20)")
                        settingDivider()
                        SettingInfo("Device ID", icon: "number", value: store.deviceID)
                        settingDivider()
                        SettingInfo("Address", icon: "wifi", value: DriveNetworkInfo.displayAddress(port: store.settings.httpPort, enabled: store.settings.browser))
                        settingDivider()
                        SettingInfo("Screen", icon: "rectangle.on.rectangle", value: "Native iOS screen, cluster: \(store.settings.cluster ? "on" : "off")")
                        settingDivider()
                        SettingAction("Hotspot Setup Guide", icon: "link", tint: .orange) { showHotspot = true }
                        settingDivider()
                        SettingAction("CarPlay protocol inspector", icon: "network", tint: .blue) { showProtocolInspector = true }
                    }
                    note("Changes to preferences are saved immediately. Browser and discovery are foreground-only. No pairing secrets or local network traffic are uploaded.")

        }
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .padding(.top, 12)
                    note("Restores default preferences and car details. Your generated device ID stays unchanged.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.gray)
            .padding(.horizontal, 8)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.gray).padding(.horizontal, 8)
            VStack(spacing: 0) { content() }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 23))
        }
    }
}

struct SettingToggle: View {
    let title: String
    let icon: String
    let tint: Color
    @Binding var isOn: Bool
    var disabled = false

    init(_ title: String, icon: String, tint: Color, isOn: Binding<Bool>, disabled: Bool = false) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self._isOn = isOn
        self.disabled = disabled
    }

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(name: icon, color: tint)
            Text(title)
                .font(.body)
                .foregroundStyle(disabled ? Color.gray : Color.white)
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden().disabled(disabled)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 57)
    }
}

struct SettingAction: View {
    let title: String
    let icon: String
    let tint: Color
    var value: String = ""
    let action: () -> Void

    init(_ title: String, icon: String, tint: Color, value: String = "", action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.value = value
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SymbolTile(name: icon, color: tint)
                Text(title).foregroundStyle(.white)
                Spacer(minLength: 4)
                if !value.isEmpty {
                    Text(value)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right").foregroundStyle(.gray)
            }
            .font(.body)
            .padding(.horizontal, 16)
            .frame(minHeight: 57)
        }
        .buttonStyle(.plain)
    }
}

struct SettingInfo: View {
    let title: String
    let icon: String
    let value: String

    init(_ title: String, icon: String, value: String) {
        self.title = title
        self.icon = icon
        self.value = value
    }

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(name: icon, color: .gray)
            Text(title)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(.gray).lineLimit(1)
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 57)
    }
}

struct SymbolTile: View {
    let name: String
    let color: Color
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingDivider: View {
    var body: some View { Divider().overlay(.gray.opacity(0.1)).padding(.leading, 59).padding(.trailing, 16) }
}
@ViewBuilder func settingDivider() -> some View { SettingDivider() }

enum EditableSetting: String, Identifiable {
    case carName, carLogo, logoLabel, drivingPosition, wifiLabel, httpPort, webSocketPort
    case resolution, nightMode, mirrorToolbar
    var id: String { rawValue }
    var title: String {
        switch self {
        case .carName: return "Car name"
        case .carLogo: return "Car logo"
        case .logoLabel: return "Logo label"
        case .drivingPosition: return "Driving Position"
        case .wifiLabel: return "Wi-Fi network label"
        case .httpPort: return "HTTP port"
        case .webSocketPort: return "WebSocket port (reserved)"
        case .resolution: return "Resolution"
        case .nightMode: return "Night mode"
        case .mirrorToolbar: return "Mirror toolbar"
        }
    }
    var options: [String] {
        switch self {
        case .carLogo: return ["Lexus", "Toyota", "Honda", "Tesla", "BMW", "Mercedes", "Custom"]
        case .drivingPosition: return ["Left-hand drive", "Right-hand drive"]
        case .resolution: return ["Fit this screen", "1920 × 720", "1280 × 720", "1024 × 768", "800 × 480"]
        case .nightMode: return ["Auto", "Light", "Dark"]
        case .mirrorToolbar: return ["Right of the mirror", "Left of the mirror", "Hidden"]
        default: return []
        }
    }
    func current(_ settings: DriveSettings) -> String {
        switch self {
        case .carName: return settings.carName
        case .carLogo: return settings.carLogo
        case .logoLabel: return settings.logoLabel
        case .drivingPosition: return settings.drivingPosition
        case .wifiLabel: return settings.wifiLabel
        case .httpPort: return String(settings.httpPort)
        case .webSocketPort: return String(settings.webSocketPort)
        case .resolution: return settings.resolution
        case .nightMode: return settings.nightMode
        case .mirrorToolbar: return settings.mirrorToolbar
        }
    }
    @MainActor func apply(_ value: String, store: DriveStore) {
        switch self {
        case .carName: store.settings.carName = value
        case .carLogo: store.settings.carLogo = value
        case .logoLabel: store.settings.logoLabel = value
        case .drivingPosition: store.settings.drivingPosition = value
        case .wifiLabel: store.settings.wifiLabel = value
        case .httpPort: if let port = Int(value), (1024...65535).contains(port) { store.settings.httpPort = port }
        case .webSocketPort: if let port = Int(value), (1024...65535).contains(port) { store.settings.webSocketPort = port }
        case .resolution: store.settings.resolution = value
        case .nightMode: store.settings.nightMode = value
        case .mirrorToolbar: store.settings.mirrorToolbar = value
        }
    }
}

struct EditSettingView: View {
    let field: EditableSetting
    @ObservedObject var store: DriveStore
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    var body: some View {
        NavigationStack {
            Form {
                if field.options.isEmpty {
                    TextField(field.title, text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(field == .httpPort || field == .webSocketPort ? .numberPad : .default)
                } else {
                    ForEach(field.options, id: \.self) { option in
                        Button {
                            value = option
                        } label: {
                            HStack {
                                Text(option).foregroundStyle(.primary)
                                Spacer()
                                if value == option { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                if field == .httpPort || field == .webSocketPort {
                    Text("Valid ports: 1024–65535. Only the local HTTP listener is implemented.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        field.apply(String(value.prefix(80)), store: store)
                        dismiss()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { value = field.current(store.settings) }
        }
        .presentationDetents([.medium, .large])
    }
}

struct GuideView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct ConnectView: View {
    @ObservedObject var network: NetworkHub
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This discovers other DriveDeck browser servers over Bonjour. It can probe their status, but cannot transmit native Apple CarPlay video.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Nearby screens") {
                    if network.peers.isEmpty {
                        Text(network.discoveryMessage).foregroundStyle(.secondary)
                    }
                    ForEach(network.peers) { peer in
                        Button {
                            network.probe(peer)
                        } label: {
                            Label(peer.title, systemImage: "display")
                        }
                    }
                }
                Section("Connection status") {
                    Text(network.peerMessage)
                }
            }
            .navigationTitle("Connect")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { network.stopDiscovery(); network.startDiscovery() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { network.startDiscovery() }
            .onDisappear { network.stopDiscovery() }
        }
    }
}

struct ModeNoticeView: View {
    let title: String
    let message: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 50)).foregroundStyle(.yellow)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(30)
            .padding(.top, 45)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

enum DashboardTool: String, Identifiable {
    case maps, radio, cluster, help
    var id: String { rawValue }
}

struct DashboardView: View {
    @ObservedObject var store: DriveStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedTool: DashboardTool?
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [.black, Color(red: 0.10, green: 0.14, blue: 0.25)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        HStack {
                            Text(store.settings.logoLabel)
                                .font(.title3.bold())
                            Spacer()
                            Text(Date.now, format: .dateTime.hour().minute())
                                .font(.title3.monospacedDigit())
                            Button("Exit") { dismiss() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)
                        Text("DriveDeck · Local dashboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 20) {
                            appTile("Maps", "map.fill", .green) { selectedTool = .maps }
                            appTile("Music", "music.note", .pink) { open("music://") }
                            appTile("Phone", "phone.fill", .green) { open("tel:") }
                            appTile("Messages", "message.fill", .green) { open("sms:") }
                            appTile("Internet Radio", "radio.fill", .orange) { selectedTool = .radio }
                            appTile("Dashboard Info", "info.circle.fill", .blue) { selectedTool = .help }
                            if store.settings.cluster {
                                appTile("Cluster", "gauge.with.needle", .purple) { selectedTool = .cluster }
                            }
                        }
                        .padding()
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 25))
                        HStack {
                            Image(systemName: "car.side")
                            Text("Car: \(store.settings.carName)")
                            Spacer()
                            Text(store.settings.drivingPosition == "Right-hand drive" ? "RHD" : "LHD")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text("Local app UI, not projected CarPlay. Phone, Messages, Music and Maps use supported iOS app handoffs.")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
        }
        .sheet(item: $selectedTool) { tool in
            switch tool {
            case .maps: MapPanel()
            case .radio: RadioPanel()
            case .cluster: ClusterPanel()
            case .help:
                GuideView(title: "Dashboard Info",
                          text: "DriveDeck is a native iOS dashboard and radio app. It does not impersonate a certified CarPlay head unit or project the iPhone's entire screen.")
            }
        }
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        openURL(url)
    }

    private func appTile(_ label: String, _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 29, weight: .medium))
                    .frame(width: 66, height: 66)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                Text(label).font(.caption).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct MapPanel: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Map()
                .mapControls {
                    MapCompass()
                    MapUserLocationButton()
                }
                .navigationTitle("Maps")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct RadioPanel: View {
    @StateObject private var radio = InternetRadio()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "radio.fill")
                        .font(.system(size: 75)).foregroundStyle(.orange)
                        .padding(.top, 35)
                    Text("Internet Radio").font(.largeTitle.bold())
                    Text("FM frequencies shown as presets would be decorative: iPhones do not expose an FM tuner. This plays actual online station streams.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    TextField("https://station.example/live.mp3", text: $radio.streamURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        radio.toggle()
                    } label: {
                        Label(radio.isPlaying ? "Pause" : "Play stream",
                              systemImage: radio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: Binding(get: { Double(radio.volume) },
                                              set: { radio.updateVolume(Float($0)) }), in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    Text(radio.state)
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .navigationTitle("Radio")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onDisappear { radio.stop() }
        }
    }
}

struct ClusterPanel: View {
    @State private var simulatedSpeed = 0.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("SIMULATED INSTRUMENTS")
                        .font(.caption.bold()).foregroundStyle(.orange)
                    HStack(spacing: 15) {
                        gauge("Speed", value: simulatedSpeed, range: 0...140, unit: "mph")
                        gauge("RPM", value: simulatedSpeed * 38, range: 0...7000, unit: "rpm")
                    }
                    Text("Demo speed")
                        .font(.headline)
                    Slider(value: $simulatedSpeed, in: 0...140, step: 1)
                    Text("The slider supplies simulated data; DriveDeck does not read vehicle CAN bus signals or an incoming CarPlay Ultra cluster stream.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Map()
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    Text("Map preview • not active turn-by-turn guidance")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Instrument cluster")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
    private func gauge(_ name: String, value: Double, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(spacing: 10) {
            Gauge(value: value, in: range) {
                Text(name)
            } currentValueLabel: {
                Text("\(Int(value))")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.orange)
            .scaleEffect(1.65)
            .frame(height: 130)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}
