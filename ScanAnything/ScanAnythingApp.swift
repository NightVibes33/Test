import SwiftUI

@main
struct ScanAnythingApp: App {
    @State private var storage = ScanStorage()
    @State private var store = StoreManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(storage)
                .environment(store)
                .preferredColorScheme(.dark)
                .task {
                    await store.prepare()
                }
        }
    }
}
