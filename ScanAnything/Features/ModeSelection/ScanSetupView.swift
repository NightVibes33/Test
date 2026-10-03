import SwiftUI

/// User-facing scan choices.
///
/// These are intents, not hardware engines. Every choice stays available on a
/// supported iPhone/iPad. LiDAR, TrueDepth, RoomPlan and Apple's Object Capture
/// are implementation details that may improve a scan when present, never a
/// requirement the user has to understand.
private enum ScanIntent: String, CaseIterable, Identifiable {
    case object
    case room
    case product
    case freeform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .object: "Object"
        case .room: "Room / Space"
        case .product: "Product / Turntable"
        case .freeform: "Freeform"
        }
    }

    var subtitle: String {
        switch self {
        case .object:
            "Take a small set of photos and build a clean standalone 3D object."
        case .room:
            "Walk through a room or space. LiDAR improves it automatically when available."
        case .product:
            "Capture an item from every side. A fixed-camera turntable is used when supported."
        case .freeform:
            "Furniture, vehicles, larger items and scenes without a hardware-specific workflow."
        }
    }

    var symbol: String {
        switch self {
        case .object: "cube.transparent"
        case .room: "house"
        case .product: "arrow.trianglehead.2.clockwise.rotate.90"
        case .freeform: "viewfinder"
        }
    }
}

struct ScanSetupView: View {
    @State private var selectedIntent: ScanIntent = .object
    @State private var isPresentingCapture = false
    @State private var permissionDenied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What are you scanning?")
                        .font(.largeTitle.bold())

                    Text("Choose the result you want. ScanAnything picks the best available camera, depth and reconstruction path automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(ScanIntent.allCases) { intent in
                        Button {
                            selectedIntent = intent
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: intent.symbol)
                                    .font(.title2)
                                    .frame(width: 32)
                                    .foregroundStyle(selectedIntent == intent ? .primary : .secondary)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(intent.title)
                                        .font(.headline)
                                    Text(intent.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: selectedIntent == intent ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIntent == intent ? .tint : .tertiary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedIntent == intent
                                    ? Color.accentColor.opacity(0.13)
                                    : Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(intent.title)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("No Pro-model iPhone or iPad is required.", systemImage: "iphone.gen3")
                    Label("Extra depth sensors are used automatically when they can improve the result.", systemImage: "sensor.tag.radiowaves.forward")
                    Label("ScanAnything Pro is an app subscription and remains separate from device hardware.", systemImage: "sparkles")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(16)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))

                Button {
                    Task {
                        guard await DeviceCapabilities.requestCameraAccess() else {
                            permissionDenied = true
                            return
                        }
                        isPresentingCapture = true
                    }
                } label: {
                    Label("Start \(selectedIntent.title)", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!DeviceCapabilities.supportsCameraOnly)
            }
            .padding()
        }
        .navigationTitle("New Scan")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isPresentingCapture) {
            switch selectedIntent {
            case .object:
                CameraOnlyCaptureView()
            case .room:
                if RoomCaptureEngine.availability.isUsable {
                    RoomFlowView()
                } else {
                    CameraOnlyCaptureView()
                }
            case .product:
                if TurntableCaptureEngine.availability.isUsable {
                    TurntableFlowView()
                } else {
                    CameraOnlyCaptureView()
                }
            case .freeform:
                CameraOnlyCaptureView()
            }
        }
        .alert("Camera access is off", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable Camera access for ScanAnything in Settings to create 3D scans.")
        }
    }
}

#Preview {
    NavigationStack { ScanSetupView() }
        .environment(ScanStorage())
        .environment(StoreManager())
        .preferredColorScheme(.dark)
}
