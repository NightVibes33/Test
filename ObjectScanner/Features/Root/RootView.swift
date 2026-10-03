import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Scan", systemImage: "viewfinder") {
                NavigationStack { ScanSetupView() }
            }
            Tab("Library", systemImage: "square.stack.3d.up") {
                NavigationStack { LibraryView() }
            }
        }
    }
}

#Preview {
    RootView()
        .environment(ScanStorage())
        .preferredColorScheme(.dark)
}
