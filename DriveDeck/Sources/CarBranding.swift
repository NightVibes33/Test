import SwiftUI
import PhotosUI
import UIKit
import Darwin

struct CarLogoBadge: View {
    let logo: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.04, green: 0.05, blue: 0.10))
            if logo == "Custom", let data = try? Data(contentsOf: Self.customLogoURL),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                VStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                    if logo == "Lexus" {
                        Text("L").font(.system(size: 8, weight: .black, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Car logo: " + logo)
    }

    private var symbol: String {
        switch logo {
        case "Toyota": return "steeringwheel"
        case "Honda": return "car.side.fill"
        case "Tesla": return "bolt.fill"
        case "BMW": return "circle.grid.cross.fill"
        case "Mercedes": return "star.fill"
        case "Bicycle": return "bicycle"
        case "Motorcycle": return "motorcycle"
        default: return "steeringwheel"
        }
    }

    static var customLogoURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("drivedeck-custom-car-logo.png")
    }
}

struct CarLogoPickerView: View {
    @ObservedObject var store: DriveStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageMessage: String?
    private let logos = ["Lexus", "Toyota", "Honda", "Tesla", "BMW", "Mercedes", "Bicycle", "Motorcycle"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose the icon for your own DriveDeck dashboard.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 15) {
                        ForEach(logos, id: \.self) { logo in
                            Button {
                                store.settings.carLogo = logo
                            } label: {
                                VStack(spacing: 7) {
                                    CarLogoBadge(logo: logo)
                                        .frame(width: 72, height: 72)
                                    HStack(spacing: 3) {
                                        if store.settings.carLogo == logo { Image(systemName: "checkmark.circle.fill") }
                                        Text(logo)
                                    }
                                    .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(store.settings.carLogo == logo ? Color.blue.opacity(0.20) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider()
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Import custom square logo", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    if store.settings.carLogo == "Custom" {
                        HStack {
                            CarLogoBadge(logo: "Custom").frame(width: 62, height: 62)
                            Text("Current custom image")
                        }
                    }
                    if let imageMessage {
                        Text(imageMessage).font(.footnote).foregroundStyle(.orange)
                    }
                    Text("Images are stored only on this iPhone. Brand names are labels and icons here, not official manufacturer assets.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Car logo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, next in
                guard let next else { return }
                Task {
                    do {
                        guard let data = try await next.loadTransferable(type: Data.self),
                              data.count <= 12_000_000,
                              let original = UIImage(data: data),
                              let normalized = renderSquare(original, size: 512),
                              let png = normalized.pngData() else {
                            imageMessage = "Choose a supported image smaller than 12 MB."
                            return
                        }
                        try png.write(to: CarLogoBadge.customLogoURL, options: .atomic)
                        store.settings.carLogo = "Custom"
                        imageMessage = "Custom logo saved on-device."
                    } catch {
                        imageMessage = "Image import failed: " + error.localizedDescription
                    }
                }
            }
        }
    }

    private func renderSquare(_ image: UIImage, size: CGFloat) -> UIImage? {
        guard image.size.width > 0 && image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { _ in
            let scale = min(size / image.size.width, size / image.size.height)
            let fitWidth = image.size.width * scale
            let fitHeight = image.size.height * scale
            let rect = CGRect(x: (size - fitWidth) / 2,
                              y: (size - fitHeight) / 2,
                              width: fitWidth, height: fitHeight)
            image.draw(in: rect)
        }
    }
}

enum DriveNetworkInfo {
    static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        var fallback: String?
        while let item = cursor {
            let addr = item.pointee.ifa_addr
            if addr?.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(addr, socklen_t(addr!.pointee.sa_len),
                                         &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                if result == 0 {
                    let ip = String(cString: host)
                    let name = String(cString: item.pointee.ifa_name)
                    if ip != "127.0.0.1" {
                        if name == "en0" { return ip }
                        fallback = fallback ?? ip
                    }
                }
            }
            cursor = item.pointee.ifa_next
        }
        return fallback
    }

    static func displayAddress(port: Int, enabled: Bool) -> String {
        guard enabled else { return "Not serving" }
        guard let ip = localIPv4() else { return "Waiting for Wi-Fi" }
        return "http://" + ip + ":" + String(port)
    }
}
