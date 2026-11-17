import Foundation
import Network
import SwiftUI

/// Hosts the unmodified DeepAI 0.3.40 React client in WKWebView. Requests for
/// actual agent data are sent to the real DeepAI Code server, never simulated.
struct OriginalDeepAIClientView: View {
    let remote: URL
    @StateObject private var runtime = OriginalDeepAIRuntime()

    var body: some View {
        Group {
            if let url = runtime.localURL {
                DeepAIWebView(url: url)
            } else if let error = runtime.errorDescription {
                ContentUnavailableView("Web client unavailable", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView("Starting original DeepAI client…")
            }
        }
        .task(id: remote.absoluteString) {
            runtime.connect(remote: remote)
        }
    }
}

@MainActor
final class OriginalDeepAIRuntime: ObservableObject {
    @Published private(set) var localURL: URL?
    @Published private(set) var errorDescription: String?
    private var gateway: LoopbackAssetGateway?

    func connect(remote: URL) {
        gateway?.stop()
        gateway = nil
        localURL = nil
        errorDescription = nil
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("OriginalWebClient", isDirectory: true),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path) else {
            errorDescription = "The original React client was not packaged. Re-run the build's DMG extraction step."
            return
        }
        let gateway = LoopbackAssetGateway(root: directory, remote: remote)
        self.gateway = gateway
        gateway.start { [weak self] result in
            Task { @MainActor [weak self] in
                switch result {
                case .success(let url): self?.localURL = url
                case .failure(let error): self?.errorDescription = error.localizedDescription
                }
            }
        }
    }

    deinit { gateway?.stop() }
}

/// One loopback-only listener, serving immutable assets from the user's DMG
/// and tunneling server API traffic, including WebSocket upgrades.
final class LoopbackAssetGateway {
    private let queue = DispatchQueue(label: "org.deepai.ios.assetproxy", qos: .userInitiated)
    private let root: URL
    private let remote: URL
    private var listener: NWListener?
    private var pending = [UUID: NWConnection]()
    private var relays = [UUID: SocketRelay]()

    init(root: URL, remote: URL) {
        self.root = root.standardizedFileURL
        self.remote = remote
    }

    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: .any)
            let listener = try NWListener(using: params, on: .any)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let port = listener.port else { return }
                    completion(.success(URL(string: "http://127.0.0.1:\(port.rawValue)/")!))
                case .failed(let error):
                    completion(.failure(error))
                    self?.stop()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.start(queue: queue)
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            for socket in pending.values { socket.cancel() }
            pending.removeAll()
            for relay in relays.values { relay.close() }
            relays.removeAll()
        }
    }

    private func handle(_ conn: NWConnection) {
        let id = UUID()
        pending[id] = conn
        conn.start(queue: queue)
        readRequest(conn, id: id, buffer: Data())
    }

    private func readRequest(_ conn: NWConnection, id: UUID, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, ended, error in
            guard let self else { return }
            var received = buffer
            if let data { received.append(data) }
            if received.count > 128 * 1024 {
                self.finish(conn, id: id, status: 431, message: "Request headers too large")
                return
            }
            if let marker = received.range(of: Data("\r\n\r\n".utf8)) {
                self.route(conn, id: id, bytes: received, headerEnd: marker.upperBound)
                return
            }
            if ended || error != nil {
                self.pending.removeValue(forKey: id)
                conn.cancel()
            } else {
                self.readRequest(conn, id: id, buffer: received)
            }
        }
    }

    private func route(_ conn: NWConnection, id: UUID, bytes: Data, headerEnd: Int) {
        let requestHeader = String(decoding: bytes.prefix(headerEnd), as: UTF8.self)
        let firstLine = requestHeader.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else {
            finish(conn, id: id, status: 400, message: "Malformed HTTP request")
            return
        }
        let method = String(parts[0]).uppercased()
        let rawPath = String(parts[1])
        let parsedPath = URLComponents(string: "http://localhost" + rawPath)?.percentEncodedPath.removingPercentEncoding ?? ""
        if method == "GET" || method == "HEAD" {
            let path = parsedPath == "/" ? "/index.html" : parsedPath
            if let file = safeFile(path) {
                sendFile(conn, id: id, file: file, headOnly: method == "HEAD")
                return
            }
            // Client-side routes render from the real React SPA rather than a mocked screen.
            if !path.contains(".") && !path.hasPrefix("/api/") && !path.hasPrefix("/rpc/") {
                if let index = safeFile("/index.html") {
                    sendFile(conn, id: id, file: index, headOnly: method == "HEAD")
                    return
                }
            }
        }
        guard let hostname = remote.host else {
            finish(conn, id: id, status: 502, message: "Server host missing")
            return
        }
        let relay = SocketRelay(client: conn, remote: remote, queue: queue) { [weak self] in
            self?.relays.removeValue(forKey: id)
        }
        pending.removeValue(forKey: id)
        relays[id] = relay
        relay.start(firstRequest: bytes, headerEnd: headerEnd, remoteHost: hostname)
    }

    private func safeFile(_ path: String) -> URL? {
        guard path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return nil }
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains(".."), !components.contains(".") else { return nil }
        let file = components.reduce(root) { url, segment in
            url.appendingPathComponent(segment, isDirectory: false)
        }.standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        return file
    }

    private func sendFile(_ conn: NWConnection, id: UUID, file: URL, headOnly: Bool) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let size = attributes[.size] as? NSNumber ?? 0
            let response = "HTTP/1.1 200 OK\r\nContent-Type: \(mimeType(file.pathExtension))\r\nContent-Length: \(size)\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            var payload = Data(response.utf8)
            if !headOnly { payload.append(try Data(contentsOf: file, options: .mappedIfSafe)) }
            conn.send(content: payload, completion: .contentProcessed { [weak self] _ in
                self?.pending.removeValue(forKey: id)
                conn.cancel()
            })
        } catch {
            finish(conn, id: id, status: 500, message: "Asset could not be read")
        }
    }

    private func finish(_ conn: NWConnection, id: UUID, status: Int, message: String) {
        let body = Data(message.utf8)
        let response = Data("HTTP/1.1 \(status) Error\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
        conn.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.pending.removeValue(forKey: id)
            conn.cancel()
        })
    }

    private func mimeType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "webmanifest": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "wasm": return "application/wasm"
        case "glb": return "model/gltf-binary"
        case "mp4": return "video/mp4"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}

/// Unmodified byte-level bidirectional tunnel for the original API, including
/// streamed responses and WebSocket upgrades. Does not invent API responses.
private final class SocketRelay {
    let client: NWConnection
    let upstream: NWConnection
    let queue: DispatchQueue
    let remote: URL
    let onClose: () -> Void
    private var closed = false

    init(client: NWConnection, remote: URL, queue: DispatchQueue, onClose: @escaping () -> Void) {
        self.client = client
        self.remote = remote
        self.queue = queue
        self.onClose = onClose
        let host = NWEndpoint.Host(remote.host ?? "")
        let port = NWEndpoint.Port(rawValue: UInt16(remote.port ?? (remote.scheme == "https" ? 443 : 80)))!
        upstream = NWConnection(host: host, port: port, using: remote.scheme == "https" ? .tls : .tcp)
    }

    func start(firstRequest: Data, headerEnd: Int, remoteHost: String) {
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                var lines = String(decoding: firstRequest.prefix(headerEnd), as: UTF8.self)
                    .components(separatedBy: "\r\n")
                let hostHeader = remote.port.map { "\(remoteHost):\($0)" } ?? remoteHost
                let origin = "\(remote.scheme ?? "http")://\(hostHeader)"
                for i in lines.indices {
                    let lower = lines[i].lowercased()
                    if lower.hasPrefix("host:") { lines[i] = "Host: \(hostHeader)" }
                    if lower.hasPrefix("origin:") { lines[i] = "Origin: \(origin)" }
                }
                var outgoing = Data(lines.joined(separator: "\r\n").utf8)
                outgoing.append(firstRequest.dropFirst(headerEnd))
                upstream.send(content: outgoing, completion: .contentProcessed { [weak self] error in
                    if error == nil {
                        self?.pipe(self!.client, to: self!.upstream)
                        self?.pipe(self!.upstream, to: self!.client)
                    } else { self?.close() }
                })
            case .failed:
                self.close()
            case .cancelled:
                self.close()
            default: break
            }
        }
        upstream.start(queue: queue)
    }

    private func pipe(_ source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] bytes, _, complete, error in
            guard let self, !self.closed else { return }
            if let bytes, !bytes.isEmpty {
                destination.send(content: bytes, completion: .contentProcessed { [weak self] sendError in
                    guard let self else { return }
                    if sendError != nil || complete || error != nil { self.close() }
                    else { self.pipe(source, to: destination) }
                })
            } else if complete || error != nil {
                self.close()
            } else {
                self.pipe(source, to: destination)
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        client.cancel()
        upstream.cancel()
        onClose()
    }
}
