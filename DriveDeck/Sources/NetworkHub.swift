import Foundation
import Combine
import Network

struct DrivePeer: Identifiable {
    var id: String
    var title: String
    var endpoint: NWEndpoint
}

@MainActor final class NetworkHub: ObservableObject {
    @Published private(set) var peers: [DrivePeer] = []
    @Published private(set) var discoveryMessage = "Searching for local DriveDeck devices..."
    @Published private(set) var browserMessage = "Browser screen is off"
    @Published private(set) var peerMessage = "Select a discovered screen to check it"
    private var nwBrowser: NWBrowser?
    private var listener: NWListener?
    private var listenerPort: Int?
    private var websocket = DriveWebSocketServer()
    private var activeSettings = DriveSettings()
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.nightvibes33.drivedeck.network")

    func startDiscovery() {
        guard nwBrowser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_drivedeck._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .failed(let error): self?.discoveryMessage = error.localizedDescription
                case .ready: self?.discoveryMessage = "Looking for other DriveDeck browser screens..."
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let mapped: [DrivePeer] = results.map { result in
                let endpoint = result.endpoint
                let name: String
                switch endpoint {
                case .service(let serviceName, _, _, _): name = serviceName
                default: name = endpoint.debugDescription
                }
                return DrivePeer(id: endpoint.debugDescription, title: name, endpoint: endpoint)
            }.sorted { $0.title < $1.title }
            DispatchQueue.main.async {
                self?.peers = mapped
                self?.discoveryMessage = mapped.isEmpty ? "No other DriveDeck screens found on this Wi-Fi." : "\(mapped.count) DriveDeck screen(s) detected."
            }
        }
        nwBrowser = browser
        browser.start(queue: queue)
    }

    func stopDiscovery() {
        nwBrowser?.cancel()
        nwBrowser = nil
        peers = []
    }

    func probe(_ peer: DrivePeer) {
        let conn = NWConnection(to: peer.endpoint, using: .tcp)
        peerMessage = "Connecting to \(peer.title)..."
        connections.append(conn)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                conn.send(content: Data("GET /status HTTP/1.1\r\nHost: drivedeck.local\r\nConnection: close\r\n\r\n".utf8),
                          completion: .contentProcessed { _ in })
                conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, error in
                    DispatchQueue.main.async {
                        if let data, let response = String(data: data, encoding: .utf8),
                           response.contains("DriveDeck") {
                            self?.peerMessage = "\(peer.title) responded. This is a dashboard-only LAN link, not CarPlay projection."
                        } else {
                            self?.peerMessage = "No compatible dashboard response: " + (error?.localizedDescription ?? "unrecognized response")
                        }
                        conn.cancel()
                    }
                }
            case .failed(let error):
                DispatchQueue.main.async { self?.peerMessage = error.localizedDescription }
                conn.cancel()
            default: break
            }
        }
        conn.start(queue: queue)
    }

    func configure(_ settings: DriveSettings) {
        activeSettings = settings
        if settings.browser && (1024...65535).contains(settings.httpPort) {
            if listener == nil || listenerPort != settings.httpPort {
                stopServer()
                startServer(port: settings.httpPort)
            }
            if (1024...65535).contains(settings.webSocketPort),
               settings.webSocketPort != settings.httpPort {
                websocket.start(port: settings.webSocketPort, carName: settings.carName)
            } else {
                websocket.stop()
                browserMessage = "WebSocket must use a different valid port."
            }
        } else {
            stopServer()
        }
    }

    private func startServer(port: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            browserMessage = "Invalid local HTTP port"
            return
        }
        do {
            let server = try NWListener(using: .tcp, on: nwPort)
            server.service = NWListener.Service(name: "DriveDeck", type: "_drivedeck._tcp")
            server.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready: self?.browserMessage = DriveNetworkInfo.displayAddress(port: port, enabled: true) + " • HTTP • foreground only"
                    case .failed(let error): self?.browserMessage = "Server failed: " + error.localizedDescription
                    default: break
                    }
                }
            }
            server.newConnectionHandler = { [weak self] conn in
                Task { @MainActor [weak self] in self?.handle(conn) }
            }
            listener = server
            listenerPort = port
            server.start(queue: queue)
        } catch {
            browserMessage = error.localizedDescription
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
                    let input = String(decoding: data ?? Data(), as: UTF8.self)
                    Task { @MainActor in self?.respond(to: input, on: conn) }
                }
            }
        }
        conn.start(queue: queue)
    }

    private func respond(to request: String, on conn: NWConnection) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let route = firstLine.components(separatedBy: " ")
        let path = route.count >= 2 ? route[1] : ""
        let isGet = route.first == "GET"
        let mime: String
        let payload: Data
        let status: String

        if isGet && path == "/status" {
            mime = "application/json; charset=utf-8"
            status = "200 OK"
            let data: [String: Any] = [
                "app": "DriveDeck",
                "version": "1.2",
                "carName": activeSettings.carName,
                "logoLabel": activeSettings.logoLabel,
                "cluster": activeSettings.cluster,
                "resolution": activeSettings.resolution,
                "portrait": activeSettings.portrait,
                "nightMode": activeSettings.nightMode,
                "websocketPort": activeSettings.webSocketPort,
                "ipStatus": "local-only, no remote CarPlay projection",
                "capabilities": ["browser-dashboard", "radio-audio", "websocket-telemetry"],
                "carPlayNegotiated": false
            ]
            payload = (try? JSONSerialization.data(withJSONObject: data)) ?? Data("{}".utf8)
        } else if isGet && (path == "/" || path == "/index.html") {
            mime = "text/html; charset=utf-8"
            status = "200 OK"
            payload = Data(DriveWebPage.html.utf8)
        } else {
            mime = "text/plain; charset=utf-8"
            status = "404 Not Found"
            payload = Data("Not found".utf8)
        }

        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(header.utf8) + payload,
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    func stopServer() {
        listener?.cancel()
        listener = nil
        listenerPort = nil
        websocket.stop()
        browserMessage = "Browser screen is off"
    }

    func stopAll() {
        stopDiscovery()
        stopServer()
        for conn in connections { conn.cancel() }
        connections.removeAll()
    }
}
