import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Scan", systemImage: "viewfinder") {
                NavigationStack { ScanHomeView() }
            }

            Tab("Library", systemImage: "square.stack.3d.up") {
                NavigationStack { LibraryView() }
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { ScanAnythingSettingsView() }
            }
        }
    }
}

private struct ScanHomeView: View {
    @State private var isPresentingObjectCapture = false
    @State private var permissionDenied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 18)

                VStack(spacing: 10) {
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 62, weight: .light))
                        .symbolRenderingMode(.hierarchical)

                    Text("Scan Anything")
                        .font(.largeTitle.bold())

                    Text("Take a few good photos and turn real objects and spaces into clean 3D assets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        guard await DeviceCapabilities.requestCameraAccess() else {
                            permissionDenied = true
                            return
                        }
                        isPresentingObjectCapture = true
                    }
                } label: {
                    Label("Scan Object", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                NavigationLink {
                    ScanSetupView()
                } label: {
                    Label("More scan modes", systemImage: "square.grid.2x2")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Text("Object  •  Room  •  Product  •  Freeform")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    feature(
                        "A few good views",
                        "Capture the subject from different sides instead of recording hundreds of frames.",
                        "camera.on.rectangle"
                    )
                    feature(
                        "Automatic cleanup",
                        "Object scans isolate the foreground before reconstruction to reduce table and wall background.",
                        "wand.and.stars"
                    )
                    feature(
                        "Works without Pro hardware",
                        "LiDAR and depth sensors improve supported scans automatically but never unlock the mode.",
                        "iphone.gen3"
                    )
                    feature(
                        "3D library",
                        "Finished objects and spaces stay organized locally for preview and export.",
                        "square.stack.3d.up"
                    )
                }
                .padding()
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 22))
            }
            .padding()
        }
        .navigationTitle("Scan")
        .fullScreenCover(isPresented: $isPresentingObjectCapture) {
            CameraOnlyCaptureView(purpose: .object)
        }
        .alert("Camera access is off", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable Camera access for ScanAnything in Settings to create 3D scans.")
        }
    }

    private func feature(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct ScanAnythingSettingsView: View {
    @Environment(StoreManager.self) private var store

    var body: some View {
        List {
            Section("ScanAnything Pro") {
                NavigationLink {
                    ProPaywallView()
                } label: {
                    HStack {
                        Label("Pro", systemImage: "sparkles")
                        Spacer()
                        Text(store.isPro ? "Active" : "Free")
                            .foregroundStyle(store.isPro ? .green : .secondary)
                    }
                }
            }

            Section("This Device") {
                LabeledContent("Universal scanning", value: DeviceCapabilities.supportsCameraOnly ? "Ready" : "Unavailable")
                enhancement("LiDAR enhancement", DeviceCapabilities.supportsSceneReconstruction)
                enhancement("Object Capture enhancement", DeviceCapabilities.supportsObjectCapture)
                enhancement("RoomPlan enhancement", DeviceCapabilities.supportsRoomCapture)
                enhancement("TrueDepth enhancement", DeviceCapabilities.hasTrueDepthCamera)
            }

            Section("About") {
                LabeledContent("App", value: "ScanAnything")
                LabeledContent("Minimum iOS", value: "18")
                NavigationLink("Privacy Policy") {
                    PrivacyPolicyView()
                }
                Link(
                    "Terms of Use",
                    destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                )
            }
        }
        .navigationTitle("Settings")
    }

    private func enhancement(_ title: String, _ available: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(available ? "Available" : "Not present")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RootView()
        .environment(ScanStorage())
        .environment(StoreManager())
        .preferredColorScheme(.dark)
}
