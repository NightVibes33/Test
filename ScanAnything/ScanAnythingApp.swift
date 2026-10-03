import SwiftUI

@main
struct ScanAnythingApp: App {
    @State private var storage = ScanStorage()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(storage)
                .preferredColorScheme(.dark)
        }
    }
}
