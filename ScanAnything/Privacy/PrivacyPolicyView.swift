import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ScanAnything Privacy Policy")
                    .font(.largeTitle.bold())

                Text("Last updated October 2, 2026")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                section(
                    "Overview",
                    "ScanAnything performs object capture and 3D reconstruction on the device. The current app does not create an account, does not track you across apps or websites, and does not upload your scans, source images, or 3D models to a developer-operated server."
                )

                section(
                    "Camera and scan data",
                    "Camera access is used to capture images and tracking information needed to create 3D scans. Scan files are stored locally in the app's container unless you explicitly export or share them using iOS."
                )

                section(
                    "Purchases",
                    "In-app purchases are processed by Apple through StoreKit. Apple may process purchase and account information under Apple's privacy terms. ScanAnything receives entitlement and transaction status needed to unlock purchased features."
                )

                section(
                    "Sharing and exports",
                    "When you choose Share or Export, the destination you select receives the file you chose. ScanAnything does not automatically transmit exported files."
                )

                section(
                    "Contact",
                    "For privacy questions, use the developer contact information shown on the ScanAnything App Store product page."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
