import SwiftUI
import MapKit
import MessageUI

enum DriveScreen: String, CaseIterable, Identifiable {
    case home = "Home"
    case maps = "Maps"
    case radio = "Radio"
    case phone = "Phone"
    case messages = "Messages"
    case music = "Music"
    case cluster = "Cluster"
    case video = "Videos"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .maps: return "map.fill"
        case .radio: return "radio.fill"
        case .phone: return "phone.fill"
        case .messages: return "message.fill"
        case .music: return "music.note"
        case .cluster: return "gauge.with.needle"
        case .video: return "play.rectangle.fill"
        }
    }
    var accent: Color {
        switch self {
        case .home: return .blue
        case .maps: return .green
        case .radio: return .orange
        case .phone: return .green
        case .messages: return .green
        case .music: return .pink
        case .cluster: return .indigo
        case .video: return .red
        }
    }
}

struct DriveExperienceView: View {
    @ObservedObject var store: DriveStore
    @ObservedObject var network: NetworkHub
    @ObservedObject var peerCast: DrivePeerCast
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var radio = InternetRadio()
    @State private var screen: DriveScreen = .home
    @State private var showSettings = false
    @State private var touchPoint: CGPoint?
    @State private var showFullCluster = false
    @State private var showExitConfirm = false

    private var dark: Bool {
        store.settings.nightMode == "Dark" ||
        (store.settings.nightMode == "Auto" && systemColorScheme == .dark)
    }
    private var foreground: Color { dark ? .white : Color(red: 0.08, green: 0.12, blue: 0.20) }
    private var surface: Color { dark ? Color(red: 0.12, green: 0.15, blue: 0.24) : .white }
    private var background: Color { dark ? Color(red: 0.035, green: 0.045, blue: 0.09) : Color(red: 0.89, green: 0.93, blue: 0.98) }

    private var dockPositionLeft: Bool {
        let toolbar = store.settings.mirrorToolbar
        if toolbar == "Hidden" { return false }
        let driverRight = store.settings.drivingPosition == "Right-hand drive"
        return toolbar == "Left of the mirror" ? !driverRight : driverRight
    }

    private var displayRatio: CGFloat? {
        switch store.settings.resolution {
        case "1920 × 720": return 1920 / 720
        case "1280 × 720": return 1280 / 720
        case "1024 × 768": return 1024 / 768
        case "800 × 480": return 800 / 480
        default: return nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 650 || store.settings.portrait
            ZStack {
                background.ignoresSafeArea()
                VStack(spacing: 0) {
                    titleBar
                    HStack(spacing: 0) {
                        if dockPositionLeft && store.settings.mirrorToolbar != "Hidden" {
                            dock(compact: compact)
                        }
                        mainDisplay(compact: compact)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if !dockPositionLeft && store.settings.mirrorToolbar != "Hidden" {
                            dock(compact: compact)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, store.settings.avoidNotch ? 12 : 0)
                    footer
                }
                .foregroundStyle(foreground)
                if store.settings.showTouches, let touchPoint {
                    Circle()
                        .stroke(Color.cyan, lineWidth: 3)
                        .background(Circle().fill(.cyan.opacity(0.25)))
                        .frame(width: 42, height: 42)
                        .position(touchPoint)
                        .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { gesture in
                    if store.settings.showTouches { touchPoint = gesture.location }
                }
                .onEnded { _ in touchPoint = nil })
        }
        .statusBarHidden(false)
        .sheet(isPresented: $showSettings) { SettingsView(store: store, network: network) }
        .sheet(isPresented: $showFullCluster) { ClusterPanel() }
        .confirmationDialog("Leave the DriveDeck dashboard?", isPresented: $showExitConfirm) {
            Button("Leave dashboard") { dismiss() }
        }
        .onAppear {
            radio.setMuted(!store.settings.playSoundHere)
            peerCast.start()
        }
        .onReceive(peerCast.$remoteCommand) { name in
            guard let name, let next = DriveScreen(rawValue: name) else { return }
            screen = next
        }
        .onChange(of: store.settings.playSoundHere) { _, enabled in radio.setMuted(!enabled) }
        .onDisappear {
            radio.stop()
            peerCast.stopCapture()
        }
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            CarLogoBadge(logo: store.settings.carLogo)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.settings.logoLabel.isEmpty ? "DRIVEDECK" : store.settings.logoLabel)
                    .font(.headline).lineLimit(1)
                Text("LOCAL DASHBOARD • NOT CARPLAY")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(dark ? .gray : .secondary)
            }
            Spacer()
            Text(Date.now, format: .dateTime.hour().minute())
                .font(.system(.headline, design: .rounded)).monospacedDigit()
            Button {
                if peerCast.isCapturing { peerCast.stopCapture() }
                else { peerCast.startCapture() }
            } label: {
                Image(systemName: peerCast.isCapturing ? "record.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(peerCast.isCapturing ? .red : foreground)
                    .padding(8)
                    .background(surface, in: Circle())
            }
            .accessibilityLabel(peerCast.isCapturing ? "Stop broadcasting local dashboard" : "Broadcast local dashboard to paired screen")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .padding(8)
                    .background(surface, in: Circle())
            }
            .accessibilityLabel("Settings")
            Button { showExitConfirm = true } label: {
                Image(systemName: "xmark")
                    .font(.headline).padding(9)
                    .background(surface, in: Circle())
            }
            .accessibilityLabel("Exit dashboard")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(surface.opacity(0.78))
    }

    private func dock(compact: Bool) -> some View {
        VStack(spacing: compact ? 18 : 24) {
            ForEach([DriveScreen.home, .maps, .radio, .music], id: \.self) { item in
                Button {
                    screen = item
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: compact ? 21 : 27))
                        .foregroundStyle(screen == item ? .white : item.accent)
                        .frame(width: compact ? 43 : 55, height: compact ? 43 : 55)
                        .background(screen == item ? item.accent : surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel(item.rawValue)
            }
            Spacer(minLength: 8)
            if store.settings.cluster {
                Button { screen = .cluster } label: {
                    Image(systemName: DriveScreen.cluster.icon)
                        .font(.title3)
                        .foregroundStyle(screen == .cluster ? .white : .purple)
                        .frame(width: compact ? 43 : 55, height: compact ? 43 : 55)
                        .background(screen == .cluster ? Color.purple : surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Cluster")
            }
        }
        .padding(.horizontal, compact ? 5 : 10)
        .padding(.top, 16)
        .padding(.bottom, 15)
        .background(surface.opacity(0.5))
    }

    private func mainDisplay(compact: Bool) -> some View {
        ScrollView {
            Group {
                switch screen {
                case .home: homeScreen(compact: compact)
                case .maps: mapScreen
                case .radio: RadioConsole(radio: radio, dark: dark)
                case .phone: DriveDialer()
                case .messages: DriveMessenger()
                case .music: musicScreen
                case .cluster: clusterScreen
                case .video: LocalVideoView()
                }
            }
            .padding(compact ? 12 : 20)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(surface.opacity(0.13))
        .modifier(DisplayRatioModifier(ratio: displayRatio))
    }

    private func homeScreen(compact: Bool) -> some View {
        VStack(spacing: 18) {
            if !compact {
                HStack(spacing: 14) {
                    mapQuickCard
                    musicQuickCard
                }
                .frame(height: 225)
            } else {
                mapQuickCard.frame(height: 195)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 13), count: compact ? 3 : 4), spacing: 21) {
                ForEach(DriveScreen.allCases.filter { $0 != .home && ($0 != .cluster || store.settings.cluster) && ($0 != .video || store.settings.videoPlayback) }) { item in
                    Button {
                        screen = item
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.system(size: compact ? 24 : 32))
                                .foregroundStyle(.white)
                                .frame(width: compact ? 62 : 79, height: compact ? 62 : 79)
                                .background(item.accent.gradient, in: RoundedRectangle(cornerRadius: 18))
                            Text(item.rawValue)
                                .font(.footnote)
                                .foregroundStyle(foreground)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            if store.settings.cluster {
                Button {
                    showFullCluster = true
                } label: {
                    HStack {
                        Image(systemName: "gauge.with.needle")
                        Text("Open second instrument-cluster panel")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .padding()
                    .background(surface, in: RoundedRectangle(cornerRadius: 18))
                }
                .foregroundStyle(foreground)
            }
        }
    }

    private var mapQuickCard: some View {
        Button { screen = .maps } label: {
            ZStack(alignment: .bottomLeading) {
                Map(interactionModes: [])
                    .allowsHitTesting(false)
                Label("Maps", systemImage: "map.fill")
                    .font(.headline).padding(11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var musicQuickCard: some View {
        Button { screen = .radio } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("NOW PLAYING").font(.caption.bold()).foregroundStyle(.gray)
                Image(systemName: "music.note.list")
                    .font(.system(size: 48)).foregroundStyle(.orange)
                Text("DriveDeck Radio").font(.title3.bold())
                Text("Tap to tune an internet station").font(.caption)
                Spacer()
                Label("Open player", systemImage: "play.circle.fill")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(20)
            .background(surface, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
    }

    private var mapScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maps").font(.title.bold())
            Map()
                .mapControls { MapCompass(); MapScaleView() }
                .frame(minHeight: 380)
                .clipShape(RoundedRectangle(cornerRadius: 17))
            Text("Interactive Apple Map. Navigation requires selecting a route in Maps.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var musicScreen: some View {
        VStack(spacing: 22) {
            Image(systemName: "music.note")
                .font(.system(size: 65)).foregroundStyle(.pink)
            Text("Music").font(.title.bold())
            Text("Open Apple Music to use your existing subscriptions and music library.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: "music://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Music", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
            Button("Use DriveDeck Internet Radio instead") { screen = .radio }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
    }

    private var clusterScreen: some View {
        VStack(spacing: 20) {
            Text("Instrument cluster").font(.title.bold())
            Text("SIMULATED DATA")
                .font(.caption.bold()).foregroundStyle(.orange)
            HStack(spacing: 14) {
                clusterMetric("Speed", "0", "mph", .cyan)
                clusterMetric("RPM", "0", "rpm", .orange)
                clusterMetric("Fuel", "100", "%", .green)
            }
            Map(interactionModes: [])
                .allowsHitTesting(false)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 17))
            Button("Open adjustable gauge simulator") { showFullCluster = true }
                .buttonStyle(.borderedProminent)
            Text("No vehicle data, CarPlay Ultra video feed, or OBD/CAN connection is present.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical)
    }

    private func clusterMetric(_ label: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 33, weight: .semibold, design: .rounded)).foregroundStyle(tint)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(unit).font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(.green).frame(width: 7, height: 7)
            Text("Dashboard ready")
            Spacer()
            Text(store.settings.carName).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 17)
        .padding(.vertical, 5)
        .background(surface)
    }
}

struct DisplayRatioModifier: ViewModifier {
    let ratio: CGFloat?
    func body(content: Content) -> some View {
        if let ratio {
            content.aspectRatio(ratio, contentMode: .fit)
        } else {
            content
        }
    }
}

struct DriveDialer: View {
    @State private var phoneNumber = ""
    @State private var alertMessage: String?
    private let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
    var body: some View {
        VStack(spacing: 22) {
            Text("Phone").font(.title.bold())
            Text("Calls are placed through your iPhone's Phone app after confirmation.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(phoneNumber.isEmpty ? "Enter a number" : phoneNumber)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 11) {
                ForEach(digits, id: \.self) { digit in
                    Button(digit) { if phoneNumber.count < 25 { phoneNumber += digit } }
                        .font(.title2)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 13))
                }
            }
            HStack(spacing: 25) {
                Button {
                    if !phoneNumber.isEmpty { phoneNumber.removeLast() }
                } label: {
                    Image(systemName: "delete.left").font(.title2)
                }
                Button {
                    let allowed = phoneNumber.filter { "0123456789+*#".contains($0) }
                    guard !allowed.isEmpty, let url = URL(string: "tel:\(allowed)") else {
                        alertMessage = "Enter a phone number first."
                        return
                    }
                    UIApplication.shared.open(url) { success in
                        if !success { alertMessage = "iOS could not open the Phone app." }
                    }
                } label: {
                    Label("Call", systemImage: "phone.fill")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .padding()
        .alert("Phone", isPresented: Binding(get: { alertMessage != nil },
                                              set: { if !$0 { alertMessage = nil } })) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }
}

struct DriveMessenger: View {
    @State private var recipient = ""
    @State private var bodyText = ""
    @State private var showComposer = false
    @State private var showNoSMS = false
    var body: some View {
        VStack(spacing: 15) {
            Text("Messages").font(.title.bold())
            Text("Compose a message using the system Messages composer.")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("Recipient number", text: $recipient)
                .textContentType(.telephoneNumber).keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)
            TextField("Message", text: $bodyText, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)
            Button {
                if MFMessageComposeViewController.canSendText() { showComposer = true }
                else { showNoSMS = true }
            } label: {
                Label("Open message composer", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .disabled(recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .sheet(isPresented: $showComposer) {
                SMSComposeSheet(recipient: recipient, message: bodyText)
            }
            .alert("Messages unavailable", isPresented: $showNoSMS) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The system SMS composer is unavailable on this device or simulator.")
            }
        }
        .padding()
    }
}

struct SMSComposeSheet: UIViewControllerRepresentable {
    let recipient: String
    let message: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [recipient]
        controller.body = message
        controller.messageComposeDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
        }
    }
}
