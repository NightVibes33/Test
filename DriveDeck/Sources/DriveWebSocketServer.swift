import Foundation
import Network
import CryptoKit

/// Read-only dashboard telemetry for browser clients. Not CarPlay or AirPlay.
@MainActor final class DriveWebSocketServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.nightvibes33.drivedeck.ws")
    private var clients: [NWConnection] = []
    private(set) var port: Int?
    private(set) var status = "WebSocket offline"
    private var carName = "DriveDeck"

    func start(port: Int, carName: String) {
        self.carName = carName
        guard listener == nil || self.port != port else { return }
        stop()
        guard let selectedPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            status = "Invalid WebSocket port"
            return
        }
        do {
            let webSocketListener = try NWListener(using: .tcp, on: selectedPort)
            webSocketListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.status = "WebSocket ready at port \(port)"
                    case .failed(let error): self?.status = error.localizedDescription
                    default: break
                    }
                }
            }
            webSocketListener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.handle(conn) }
            }
            self.port = port
            listener = webSocketListener
            webSocketListener.start(queue: queue)
        } catch {
            status = "WebSocket failed: " + error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
        for connection in clients { connection.cancel() }
        clients.removeAll()
        status = "WebSocket offline"
    }

    private func handle(_ connection: NWConnection) {
        clients.append(connection)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
                    guard error == nil, let data else { connection.cancel(); return }
                    Task { @MainActor in self?.handshake(data: data, connection: connection) }
                }
            }
        }
        connection.start(queue: queue)
    }

    private func handshake(data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8),
              request.hasPrefix("GET / "),
              request.contains("Upgrade: websocket") || request.contains("Upgrade: WebSocket") else {
            connection.cancel()
            return
        }
        let lines = request.components(separatedBy: "\r\n")
        guard let keyLine = lines.first(where: { $0.lowercased().hasPrefix("sec-websocket-key:") }) else {
            connection.cancel()
            return
        }
        let key = keyLine.components(separatedBy: ":").dropFirst().joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count <= 128, let decoded = Data(base64Encoded: key), decoded.count == 16 else {
            connection.cancel()
            return
        }
        let salt = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + salt).utf8))
        let accepted = Data(digest).base64EncodedString()
        let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accepted)\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            if error != nil { connection.cancel(); return }
            Task { @MainActor in
                guard let self else { return }
                self.sendStatus(on: connection)
                self.receiveFrame(on: connection)
            }
        })
    }

    private func sendStatus(on connection: NWConnection) {
        let json: [String: Any] = [
            "type": "status",
            "app": "DriveDeck",
            "car": carName,
            "receiver": "local-dashboard",
            "carPlayNegotiated": false
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              data.count < 126 else { return }
        var frame = Data([0x81, UInt8(data.count)])
        frame.append(data)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receiveFrame(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2048) { [weak self] data, _, _, error in
            guard error == nil, let data, data.count >= 2 else {
                connection.cancel()
                return
            }
            let opcode = data[data.startIndex] & 0x0f
            if opcode == 0x8 {
                connection.cancel()
                return
            }
            Task { @MainActor in
                guard let self else { return }
                if opcode == 0x9 {
                    let pong = Data([0x8a, 0x00])
                    connection.send(content: pong, completion: .contentProcessed { _ in })
                } else {
                    // Ignore commands. The browser socket intentionally exposes read-only telemetry.
                    self.sendStatus(on: connection)
                }
                self.receiveFrame(on: connection)
            }
        }
    }
}
