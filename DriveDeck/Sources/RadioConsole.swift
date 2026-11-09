import SwiftUI
import AVFoundation

struct RadioStation: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var frequency: Double
}

@MainActor final class RadioLibrary: ObservableObject {
    @Published var presets: [RadioStation] = [] {
        didSet { save() }
    }
    private let key = "DriveDeck.radio.presets.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let stored = try? JSONDecoder().decode([RadioStation].self, from: data) {
            presets = stored
        }
    }

    func add(name: String, url: String, frequency: Double) -> Bool {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let link = URL(string: url),
              ["http", "https"].contains(link.scheme?.lowercased() ?? ""),
              link.host != nil else { return false }
        presets.append(RadioStation(name: String(title.prefix(60)), url: url, frequency: frequency))
        return true
    }

    func remove(at offsets: IndexSet) { presets.remove(atOffsets: offsets) }
    func reset() { presets = [] }
    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct RadioConsole: View {
    @ObservedObject var radio: InternetRadio
    @StateObject private var library = RadioLibrary()
    @State private var stationName = ""
    @State private var band: RadioBand = .fm
    @State private var frequency = 101.9
    @State private var message = ""
    @State private var showPresets = true
    let dark: Bool

    enum RadioBand: String, CaseIterable, Identifiable {
        case fm = "FM"
        case am = "AM"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "radio.fill").foregroundStyle(.orange)
                Text("DriveDeck Radio")
                    .font(.title2.bold())
                Spacer()
                Text("INTERNET + TUNER DEMO")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 5)

            VStack(spacing: 18) {
                HStack {
                    Picker("Band", selection: $band) {
                        ForEach(RadioBand.allCases) { band in
                            Text(band.rawValue).tag(band)
                        }
                    }
                    .pickerStyle(.segmented)
                    Spacer(minLength: 10)
                    Label(radio.isPlaying ? "STREAM ON" : "STREAM OFF",
                          systemImage: radio.isPlaying ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(radio.isPlaying ? .green : .gray)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(band == .fm ? String(format: "%.1f", frequency) : String(Int(frequency)))
                        .font(.system(size: 55, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(band == .fm ? "MHz" : "kHz")
                        .font(.subheadline).foregroundStyle(.gray)
                }
                HStack(spacing: 15) {
                    Button { adjustFrequency(-1) } label: { Image(systemName: "backward.end.fill") }
                    Slider(value: $frequency,
                           in: band == .fm ? 87.5...108 : 530...1710,
                           step: band == .fm ? 0.2 : 10)
                    Button { adjustFrequency(1) } label: { Image(systemName: "forward.end.fill") }
                }
                .tint(.orange)
                Text("FM/AM dial is a visual simulator. iPhone hardware does not supply an accessible RF tuner.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .background(Color(red: 0.06, green: 0.08, blue: 0.13), in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 14) {
                Label("Live internet stream", systemImage: "waveform")
                    .font(.headline)
                TextField("Station name", text: $stationName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                TextField("https://your-station.example/live.mp3", text: $radio.streamURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    Button {
                        radio.toggle()
                    } label: {
                        Label(radio.isPlaying ? "Pause" : "Play",
                              systemImage: radio.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        if library.add(name: stationName, url: radio.streamURL, frequency: frequency) {
                            message = "Station saved."
                        } else {
                            message = "Enter a station name and a valid http(s) stream URL."
                        }
                    } label: {
                        Label("Save preset", systemImage: "bookmark.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                    Slider(value: Binding(get: { Double(radio.volume) },
                                          set: { radio.updateVolume(Float($0)) }), in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                }
                Text(radio.state)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
            }
            .padding(16)
            .background((dark ? Color.white : Color.black).opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showPresets.toggle()
                } label: {
                    HStack {
                        Text("Saved stations (\(library.presets.count))").font(.headline)
                        Spacer()
                        Image(systemName: showPresets ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.plain)
                if showPresets {
                    if library.presets.isEmpty {
                        Text("Save a station above to make its preset available here.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(library.presets) { station in
                        HStack {
                            Button {
                                stationName = station.name
                                radio.streamURL = station.url
                                frequency = station.frequency
                                radio.play()
                                message = "Tuned to " + station.name
                            } label: {
                                HStack {
                                    Image(systemName: "play.circle.fill").foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(station.name).font(.subheadline.weight(.semibold))
                                        Text(station.url).font(.caption2).lineLimit(1)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                library.presets.removeAll { $0.id == station.id }
                            } label: { Image(systemName: "trash") }
                        }
                        Divider()
                    }
                }
            }
            .padding(15)
            .background((dark ? Color.white : Color.black).opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

            Text("Audio plays through AVPlayer while DriveDeck is active. A valid audio stream URL is required, not a radio station webpage.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onChange(of: band) { _, next in
            frequency = next == .fm ? 101.9 : 1000
        }
    }

    private func adjustFrequency(_ direction: Double) {
        let step = band == .fm ? 0.2 : 10.0
        let minValue = band == .fm ? 87.5 : 530.0
        let maxValue = band == .fm ? 108.0 : 1710.0
        frequency = min(maxValue, max(minValue, frequency + direction * step))
    }
}
