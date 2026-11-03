import SwiftUI

/// The user-supplied Cinder27 application embedded without its standalone @main.
/// Each module runs only after an explicit tap in the original harness UI.
struct CinderLabHost: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = LabEngine()
    @StateObject private var browser = FileBrowser(path: Container.documents.path)
    @StateObject private var clipboard = FileClipboard()
    @StateObject private var bookmarks = Bookmarks()
    @StateObject private var l10n = L10n.shared

    var body: some View {
        GateView()
            .environmentObject(engine)
            .environmentObject(browser)
            .environmentObject(clipboard)
            .environmentObject(bookmarks)
            .environmentObject(l10n)
            .environment(\.layoutDirection, Lang.resolved.isRTL ? .rightToLeft : .leftToRight)
            .preferredColorScheme(.dark)
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Label("Close Lab", systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.top, 7)
                .padding(.trailing, 8)
            }
    }
}
