import ImageIO
import SwiftUI
import UIKit

struct HeroThumbnailView: View {
    let url: URL
    let side: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .clipShape(.rect(cornerRadius: 10))
        .task(id: url) {
            image = await Self.loadThumbnail(from: url, side: side)
        }
        .accessibilityHidden(true)
    }

    private static func loadThumbnail(
        from url: URL,
        side: CGFloat
    ) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil)
            else {
                return nil
            }

            let scale = UIScreen.main.scale
            let maxDimension = max(128, Int(side * scale * 2))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else {
                return nil
            }

            return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        }.value
    }
}
