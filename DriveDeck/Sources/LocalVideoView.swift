import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct LocalVideoView: View {
    @State private var importVideo = false
    @State private var videoURL: URL?
    @State private var player: AVPlayer?
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: "play.rectangle.fill").foregroundStyle(.red)
                Text("Video playback")
                    .font(.title.bold())
                Spacer()
                Button("Choose video") { importVideo = true }
                    .buttonStyle(.borderedProminent)
            }
            if let player {
                VideoPlayer(player: player)
                    .frame(minHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                Button("Play / Resume") { player.play() }.buttonStyle(.bordered)
            } else {
                RoundedRectangle(cornerRadius: 15)
                    .fill(.gray.opacity(0.13))
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "film.stack").font(.largeTitle)
                            Text("Choose a video file from Files")
                        }
                        .foregroundStyle(.secondary)
                    }
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            Text("Video plays in this local DriveDeck dashboard only. No CarPlay video entitlement or projection bypass is provided. Use only when safely parked.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(10)
        .fileImporter(isPresented: $importVideo, allowedContentTypes: [.movie, .mpeg4Movie, .video]) { result in
            do {
                let pickedURL = try result.get()
                let access = pickedURL.startAccessingSecurityScopedResource()
                defer { if access { pickedURL.stopAccessingSecurityScopedResource() } }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("drivedeck-video-" + UUID().uuidString)
                    .appendingPathExtension(pickedURL.pathExtension)
                try FileManager.default.copyItem(at: pickedURL, to: tempURL)
                player?.pause()
                player = AVPlayer(url: tempURL)
                videoURL = tempURL
                player?.play()
                errorMessage = ""
            } catch {
                errorMessage = "Could not open video: " + error.localizedDescription
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
            if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
        }
    }
}
