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
    @State private var isPresentingCapture = false
    @State private var permissionDenied = false

    private var usesEnhancedPipeline: Bool {
        DeviceCapabilities.supportsObjectCapture && DeviceCapabilities.supportsPhotogrammetry
    }

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

                    Text("Turn real objects into 3D with your iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button {
                        Task {
                            guard await DeviceCapabilities.requestCameraAccess() else {
                                permissionDenied = true
                                return
                            }
                            isPresentingCapture = true
                        }
                    } label: {
                        Label("Scan Anything", systemImage: "camera.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    HStack(spacing: 8) {
                        Image(systemName: usesEnhancedPipeline ? "sensor.tag.radiowaves.forward.fill" : "camera.fill")
                        Text(usesEnhancedPipeline ? "Enhanced LiDAR + photogrammetry" : "Camera 3D • no LiDAR required")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    feature("Move around it", "Capture every side while the app keeps the best tracked views.", "rotate.3d")
                    feature("Build it on-device", "Processing stays on your iPhone; no upload is required.", "iphone.gen3")
                    feature("Keep and share it", "Save your scans in a local library and export supported formats.", "square.and.arrow.up")
                }
                .padding()
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 22))

                NavigationLink {
                    ScanSetupView()
                } label: {
                    HStack {
                        Label("More scan modes", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .navigationTitle("Scan")
        .fullScreenCover(isPresented: $isPresentingCapture) {
            if usesEnhancedPipeline {
                ObjectCaptureFlowView()
            } else {
                CameraOnlyCaptureView()
            }
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
    private var enhanced: Bool {
        DeviceCapabilities.supportsObjectCapture && DeviceCapabilities.supportsPhotogrammetry
    }

    var body: some View {
        List {
            Section("This iPhone") {
                LabeledContent("Object scanning", value: enhanced ? "Enhanced" : "Camera 3D")
                capability("LiDAR scene mesh", DeviceCapabilities.supportsSceneReconstruction)
                capability("Object Capture", DeviceCapabilities.supportsObjectCapture)
                capability("Room scanning", DeviceCapabilities.supportsRoomCapture)
                capability("TrueDepth", DeviceCapabilities.hasTrueDepthCamera)
            }

            Section("About") {
                LabeledContent("App", value: "ScanAnything")
                LabeledContent("Minimum iOS", value: "18")
                NavigationLink("Open-source acknowledgements") {
                    List {
                        Section("ObjectScanner") {
                            Text("Original scanning foundation by Burak Şahinkaya. Apache License 2.0. The upstream LICENSE and NOTICE files are included with this source tree.")
                        }
                        Section("msplat-ios") {
                            Text("On-device Gaussian Splatting training. Apache License 2.0.")
                        }
                        Section("MetalSplatter") {
                            Text("Gaussian Splatting renderer for Apple platforms. MIT License.")
                        }
                    }
                    .navigationTitle("Acknowledgements")
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func capability(_ title: String, _ available: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
    }
}

#Preview {
    RootView()
        .environment(ScanStorage())
        .preferredColorScheme(.dark)
}
