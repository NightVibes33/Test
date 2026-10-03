import Foundation

enum ScanEngineKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case cameraOnly
    case objectCapture
    case turntable
    case trueDepth
    case roomPlan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cameraOnly: "Camera 3D"
        case .objectCapture: "Object"
        case .turntable: "Turntable"
        case .trueDepth: "TrueDepth"
        case .roomPlan: "Room"
        }
    }

    var tagline: String {
        switch self {
        case .cameraOnly: "Rear camera • no LiDAR required"
        case .objectCapture: "LiDAR • guided 3D capture"
        case .turntable: "Fixed camera • rotating object"
        case .trueDepth: "Front depth sensor • close-range geometry"
        case .roomPlan: "LiDAR • walls, doors and furniture"
        }
    }

    var symbolName: String {
        switch self {
        case .cameraOnly: "viewfinder"
        case .objectCapture: "camera.viewfinder"
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
