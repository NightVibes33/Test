import SwiftUI

struct ScanSetupView: View {
    @State private var activeKind: ScanEngineKind?
    @State private var permissionDenied = false

    private var primaryKind: ScanEngineKind {
        ObjectCaptureEngine.availability.isUsable ? .objectCapture : .cameraOnly
    }

    private var availableModes: [ScanEngineKind] {
        ScanEngineKind.allCases.filter { blockedReason(for: $0) == nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                modeGrid
                capabilityCard
            }
            .padding()
        }
        .navigationTitle("Scan Anything")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeKind) { kind in
            switch kind {
            case .cameraOnly: CameraOnlyFlowView()
            case .objectCapture: ObjectCaptureFlowView()
            case .turntable: TurntableFlowView()
            case .trueDepth: TrueDepthFlowView()
            case .roomPlan: RoomFlowView()
            }
        }
        .alert("Camera access is off", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable camera access for ScanAnything in Settings to scan objects.")
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            Image(systemName: primaryKind == .objectCapture ? "cube.transparent" : "viewfinder")
                .font(.system(size: 64, weight: .light))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Turn anything into 3D")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(primaryKind == .objectCapture
                     ? "Your iPhone supports enhanced LiDAR scanning."
                     : "Camera-only 3D works on this iPhone — no LiDAR required.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                start(primaryKind)
            } label: {
                Label("Start Scan", systemImage: "viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
    }

    private var modeGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan modes")
                .font(.headline)

            ForEach(availableModes) { kind in
                Button {
                    start(kind)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: kind.symbolName)
                            .font(.title2)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(kind.displayName)
                                    .font(.headline)
                                if kind == primaryKind {
                                    Text("Recommended")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.tint.opacity(0.16), in: Capsule())
                                }
                            }
                            Text(kind.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 18))
            }
        }
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                DeviceCapabilities.supportsObjectCapture ? "Pro hardware detected" : "Regular iPhone mode",
                systemImage: DeviceCapabilities.supportsObjectCapture ? "dot.radiowaves.left.and.right" : "iphone"
            )
            .font(.headline)

            Text(
                DeviceCapabilities.supportsObjectCapture
                ? "LiDAR modes create exportable meshes. Camera 3D remains available for appearance-focused Gaussian scans."
                : "ScanAnything uses ARKit camera tracking and on-device Gaussian reconstruction instead of requiring a Pro model."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 18))
    }

    private func start(_ kind: ScanEngineKind) {
        Task {
            guard await DeviceCapabilities.requestCameraAccess() else {
                permissionDenied = true
                return
            }
            activeKind = kind
        }
    }

    private func blockedReason(for kind: ScanEngineKind) -> String? {
        switch kind {
        case .cameraOnly: CameraOnlyCaptureEngine.availability.blockedReason
        case .objectCapture: ObjectCaptureEngine.availability.blockedReason
        case .turntable: TurntableCaptureEngine.availability.blockedReason
        case .trueDepth: TrueDepthEngine.availability.blockedReason
        case .roomPlan: RoomCaptureEngine.availability.blockedReason
        }
    }
}

#Preview {
    NavigationStack { ScanSetupView() }
        .environment(ScanStorage())
        .preferredColorScheme(.dark)
}
