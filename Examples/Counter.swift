import SwiftUI

struct CounterView: View {
    @State private var count = 0
    @State private var name = "friend"
    @State private var notificationsEnabled = true
    @State private var volume = 35.0

    var body: some View {
        VStack(spacing: 14) {
            Text("Swift File Runner").font(.title)
            Text("Hello, \(name)!")
            Text("Button taps: \(count)")

            TextField("Your name", text: $name)
            Toggle("Notifications", isOn: $notificationsEnabled)
            Text("Volume: \(volume)")
            Slider(value: $volume, in: 0...100)

            Button("Add one") { count += 1 }
            Button("Reset") { count = 0 }
        }
        .padding()
    }
}
