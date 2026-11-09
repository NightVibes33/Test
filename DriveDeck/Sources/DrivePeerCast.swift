import SwiftUI
import Foundation
import Combine
import MultipeerConnectivity
import ReplayKit
import AVFoundation
import CoreImage

/// Actual encrypted, consent-based iOS-to-iOS video transport.
/// This sends DriveDeck's on-screen content via ReplayKit, NOT an Apple CarPlay session.
@MainActor
final class DrivePeerCast: NSObject, ObservableObject {
    @Published private(set) var nearby: [MCPeerID] = []
    @Published private(set) var connectedNames: [String] = []
    @Published private(set) var status = "Receiver ready to start"
    @Published private(set) var pendingInvitation: String?
    @Published private(set) var isCapturing = false
    @Published private(set) var image: UIImage?
    @Published private(set) var receivedFrameCount = 0
    @Published var remoteCommand: String?

    private let peerID: MCPeerID
    private lazy var session: MCSession = {
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var pendingReply: ((Bool, MCSession?) -> Void)?
    private var lastCaptureTime = 0.0
    private let renderContext = CIContext(options: [.useSoftwareRenderer: false])
    private var isActive = false
    private let serviceType = "ddcast"

    override init() {
        let defaults = UserDefaults.standard
        let key = "DriveDeck.cast.peer-uuid"
        let suffix: String
        if let current = defaults.string(forKey: key) {
            suffix = current
        } else {
            suffix = String(UUID().uuidString.prefix(8))
            defaults.set(suffix, forKey: key)
        }
        peerID = MCPeerID(displayName: "DriveDeck-" + suffix)
        super.init()
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        _ = session
        let advertisement = MCNearbyServiceAdvertiser(peer: peerID,
                                                       discoveryInfo: ["protocol": "ddcast-v1",
                                                                       "role": "sender-receiver"],
                                                       serviceType: serviceType)
        advertisement.delegate = self
        advertiser = advertisement
        advertisement.startAdvertisingPeer()

        let search = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        search.delegate = self
        browser = search
        search.startBrowsingForPeers()
        status = "Discovering other DriveDeck screens. Invite or accept a peer to connect."
    }

    func stop() {
        stopCapture()
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        browser = nil
        advertiser = nil
        isActive = false
        pendingReply?(false, nil)
        pendingReply = nil
        pendingInvitation = nil
        session.disconnect()
        nearby = []
        connectedNames = []
        image = nil
        status = "Peer casting stopped."
    }

    func invite(_ remote: MCPeerID) {
        start()
        guard !session.connectedPeers.contains(remote) else {
            status = "Already connected to " + remote.displayName
            return
        }
        browser?.invitePeer(remote, to: session, withContext: nil, timeout: 25)
        status = "Inviting " + remote.displayName + "..."
    }

    func acceptInvitation() {
        guard let reply = pendingReply else { return }
        pendingReply = nil
        pendingInvitation = nil
        reply(true, session)
        status = "Pairing accepted. Establishing encrypted connection..."
    }

    func refuseInvitation() {
        pendingReply?(false, nil)
        pendingReply = nil
        pendingInvitation = nil
        status = "Invitation declined."
    }

    func startCapture() {
        guard !isCapturing else { return }
        guard !session.connectedPeers.isEmpty else {
            status = "Connect another DriveDeck before broadcasting."
            return
        }
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            status = "ReplayKit screen recording is unavailable on this device."
            return
        }
        recorder.isMicrophoneEnabled = false
        status = "Requesting ReplayKit screen capture authorization..."
        recorder.startCapture(handler: { [weak self] sample, type, error in
            guard type == .video, error == nil else { return }
            Task { @MainActor [weak self] in
                self?.sendVideoFrame(sample)
            }
        }, completionHandler: { [weak self] error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.status = "ReplayKit could not start: " + error.localizedDescription
                    self?.isCapturing = false
                } else {
                    self?.isCapturing = true
                    self?.status = "Live local screen video sending. Audio is not transmitted."
                }
            }
        })
    }

    func stopCapture() {
        guard isCapturing else { return }
        RPScreenRecorder.shared().stopCapture { [weak self] error in
            Task { @MainActor [weak self] in
                self?.isCapturing = false
                self?.status = error == nil ? "Screen sharing stopped." : "Stop capture: " + error!.localizedDescription
            }
        }
    }

    /// Bounded CPU/throughput: 7 JPEG frames/s, ~960 px max, 280 kB max per frame.
    private func sendVideoFrame(_ sample: CMSampleBuffer) {
        guard isCapturing, !session.connectedPeers.isEmpty else { return }
        let currentTime = Date().timeIntervalSince1970
        guard currentTime - lastCaptureTime >= 0.14 else { return }
        lastCaptureTime = currentTime
        guard let pixel = CMSampleBufferGetImageBuffer(sample) else { return }

        let image = CIImage(cvPixelBuffer: pixel)
        let scale = min(1.0, 960.0 / max(image.extent.width, image.extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = renderContext.createCGImage(scaled, from: scaled.extent),
              let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.48),
              jpeg.count < 280_000 else { return }
        var packet = Data([0x01])
        packet.append(jpeg)
        do {
            try session.send(packet, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            status = "Video frame failed: " + error.localizedDescription
        }
    }

    func sendCommand(_ name: String) {
        guard ["Home", "Maps", "Radio", "Cluster", "Music"].contains(name),
              !session.connectedPeers.isEmpty else { return }
        var packet = Data([0x02])
        packet.append(Data(name.utf8))
        do {
            try session.send(packet, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            status = "Remote action failed: " + error.localizedDescription
        }
    }

    private func updateConnected() {
        connectedNames = session.connectedPeers.map(\.displayName).sorted()
        if !connectedNames.isEmpty {
            status = "Encrypted link active: " + connectedNames.joined(separator: ", ")
        } else {
            status = "No connected DriveDeck screens."
            stopCapture()
        }
    }

    private func receive(_ data: Data) {
        guard let opcode = data.first else { return }
        switch opcode {
        case 0x01:
            guard data.count <= 512_000, data.count >= 30,
                  let nextFrame = UIImage(data: data.dropFirst()) else { return }
            image = nextFrame
            receivedFrameCount += 1
        case 0x02:
            let name = String(decoding: data.dropFirst(), as: UTF8.self)
            guard ["Home", "Maps", "Radio", "Cluster", "Music"].contains(name) else { return }
            remoteCommand = name
        default: break
        }
    }
}

extension DrivePeerCast: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak self] in
            self?.status = "Could not advertise receiver: " + error.localizedDescription
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                               didReceiveInvitationFromPeer peerID: MCPeerID,
                               withContext context: Data?,
                               invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { invitationHandler(false, nil); return }
            self.pendingReply?(false, nil)
            self.pendingReply = invitationHandler
            self.pendingInvitation = peerID.displayName
            self.status = "Incoming request from " + peerID.displayName
        }
    }
}

extension DrivePeerCast: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            self?.status = "Discovery failed: " + error.localizedDescription
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        guard info?["protocol"] == "ddcast-v1" else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.nearby.contains(peerID) else { return }
            self.nearby.append(peerID)
            self.nearby.sort { $0.displayName < $1.displayName }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.nearby.removeAll { $0 == peerID }
        }
    }
}

extension DrivePeerCast: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            self?.updateConnected()
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.receive(data) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
