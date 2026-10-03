import ARKit
import AVFoundation
import RealityKit
import RoomPlan
import SwiftUI

@MainActor
enum DeviceCapabilities {
    static var supportsCameraOnly: Bool {
        ARWorldTrackingConfiguration.isSupported &&
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    static var supportsObjectCapture: Bool {
        ObjectCaptureSession.isSupported
    }

    static var supportsPhotogrammetry: Bool {
        PhotogrammetrySession.isSupported
    }

    static var hasTrueDepthCamera: Bool {
        AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
    }

    static var supportsSceneReconstruction: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    static var supportsRoomCapture: Bool {
        RoomCaptureSession.isSupported
    }

    static var cameraAuthorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestCameraAccess() async -> Bool {
        if cameraAuthorization == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .video)
    }

    static var rearCaptureDevices: [(label: String, isVirtual: Bool)] {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInLiDARDepthCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
        ]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .back
        )
        return session.devices.map {
            (label: $0.localizedName, isVirtual: !$0.constituentDevices.isEmpty)
        }
    }

    static var physicalRearLensCount: Int {
        rearCaptureDevices.filter { !$0.isVirtual }.count
    }

    static var blockingHardwareWarning: String? {
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) == nil {
            return "A rear camera is required to scan objects."
        }
        if !supportsCameraOnly && !supportsObjectCapture {
            return "3D scanning is not supported on this device."
        }
        return nil
    }

    static var hasFrontToRearCalibration: Bool {
        guard let rear = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let front = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
        else { return false }
        return AVCaptureDevice.extrinsicMatrix(from: rear, to: front) != nil
    }

    static var summary: [(label: String, value: Bool)] {
        [
            ("Camera-only 3D", supportsCameraOnly),
            ("Apple Object Capture", supportsObjectCapture),
            ("On-device photogrammetry", supportsPhotogrammetry),
            ("RoomPlan", supportsRoomCapture),
            ("LiDAR scene mesh", supportsSceneReconstruction),
            ("TrueDepth", hasTrueDepthCamera),
        ]
    }
}
