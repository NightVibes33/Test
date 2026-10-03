import Foundation

enum ScanEngineKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Camera-only ARKit capture + on-device Gaussian Splat reconstruction.
    case cameraOnly
    /// Apple's guided Object Capture pipeline on supported LiDAR devices.
    case objectCapture
    /// Fixed-phone photogrammetry with the object rotating.
    case turntable
    /// Structured-light depth from the front TrueDepth sensor.
    case trueDepth
    /// RoomPlan LiDAR room capture.
    case roomPlan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cameraOnly: "Camera 3D"
        case .objectCapture: "LiDAR Object"
        case .turntable: "Turntable"
        case .trueDepth: "TrueDepth"
        case .roomPlan: "Room"
        }
    }

    var tagline: String {
        switch self {
        case .cameraOnly: "Works on regular iPhones • realistic 3D appearance"
        case .objectCapture: "LiDAR • guided capture • exportable mesh"
        case .turntable: "Phone stays still • rotate the object"
        case .trueDepth: "Front depth sensor • close-range point cloud"
        case .roomPlan: "LiDAR • walls, doors, furniture and measurements"
        }
    }

    var symbolName: String {
        switch self {
        case .cameraOnly: "viewfinder"
        case .objectCapture: "cube.transparent"
        case .turntable: "arrow.trianglehead.clockwise.rotate.90"
        case .trueDepth: "faceid"
        case .roomPlan: "house"
        }
    }

    var isImplemented: Bool { true }

    var producesMesh: Bool {
        switch self {
        case .objectCapture, .turntable, .roomPlan: true
        case .cameraOnly, .trueDepth: false
        }
    }

    var maturity: Maturity {
        switch self {
        case .objectCapture, .roomPlan: .stable
        case .cameraOnly, .turntable, .trueDepth: .beta
        }
    }

    enum Maturity: Sendable {
        case stable
        case beta

        var badge: String? {
            switch self {
            case .stable: nil
            case .beta: "beta"
            }
        }
    }
}
