import Foundation
import Combine
import SwiftUI
import AVFoundation

struct DriveSettings: Codable, Equatable {
    var carPlay = true
    var androidAuto = true
    var ultra = false
    var browser = false
    var airPlay = false
    var airPlayPush = false
    var airPlayControl = true

    var carName = "DriveDeck-D355"
    var carLogo = "Lexus"
    var logoLabel = "LEXUS"
    var drivingPosition = "Left-hand drive"

    var wifiLabel = "Current Wi-Fi"
    var httpPort = 8081
    var webSocketPort = 8888

    var resolution = "Fit this screen"
    var videoPlayback = false
    var showTouches = false
    var portrait = false
    var avoidNotch = true
    var nightMode = "Auto"
    var playSoundHere = true
    var mirrorToolbar = "Right of the mirror"
    var cluster = true

    static let defaults = DriveSettings()
}

@MainActor final class DriveStore: ObservableObject {
    @Published var settings: DriveSettings {
        didSet { save() }
    }
    let deviceID: String
    private static let settingsKey = "DriveDeck.settings.v1"
    private static let deviceKey = "DriveDeck.deviceID"

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(DriveSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaults
        }
        if let saved = defaults.string(forKey: Self.deviceKey) {
            deviceID = saved
        } else {
            let id = String(UUID().uuidString.prefix(12))
            defaults.set(id, forKey: Self.deviceKey)
            deviceID = id
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<DriveSettings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { self.settings[keyPath: keyPath] = $0 })
    }

    func reset() { settings = .defaults }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
}

@MainActor final class InternetRadio: ObservableObject {
    @Published var streamURL = ""
    @Published var state = "Enter a legal live stream URL to listen."
    @Published var isPlaying = false
    @Published var volume: Float = 0.8
    private var player: AVPlayer?

    func toggle() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            state = "Paused"
        } else {
            play()
        }
    }

    func play() {
        guard let url = URL(string: streamURL),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            state = "Use a full http:// or https:// audio-stream URL."
            isPlaying = false
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            state = "Audio session: " + error.localizedDescription
        }
        player?.pause()
        player = AVPlayer(url: url)
        player?.volume = volume
        player?.isMuted = isMuted
        player?.play()
        isPlaying = true
        state = "Loading stream... Playback requires a reachable audio endpoint."
    }

    @Published var isMuted = false

    func updateVolume(_ value: Float) {
        volume = value
        player?.volume = value
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
        if muted && isPlaying { state = "Local audio muted by Display settings." }
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
    }
}
