import StoreKit
import SwiftUI

struct ProPaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 58, weight: .light))
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityHidden(true)

                        Text("ScanAnything Pro")
                            .font(.largeTitle.bold())

                        Text("Advanced scan and export tools for ScanAnything.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        benefit("Pro scan and export tools", symbol: "square.and.arrow.up")
                        benefit("Maximum reconstruction quality", symbol: "sparkles")
                        benefit("Pro mesh and splat export tools", symbol: "square.and.arrow.up")
                        benefit("Advanced processing and export workflows", symbol: "viewfinder")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 22))

                    if store.isPro {
                        Label("ScanAnything Pro is active", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else if store.isLoading && store.products.isEmpty {
                        ProgressView("Loading App Store products…")
                    } else if store.products.isEmpty {
                        ContentUnavailableView(
                            "Products unavailable",
                            systemImage: "cart.badge.questionmark",
                            description: Text("The App Store products have not been configured for this build yet.")
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.products) { product in
                                Button {
                                    Task { await store.purchase(product) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(product.displayName)
                                                .font(.headline)
                                            Text(product.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(product.displayPrice)
                                                .font(.headline.monospacedDigit())
                                            if let period = billingPeriod(for: product) {
                                                Text(period)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    Button("Restore Purchases") {
                        Task { await store.restore() }
                    }
                    .buttonStyle(.bordered)

                    if let message = store.statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel in your App Store account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 18) {
                        NavigationLink("Privacy Policy") {
                            PrivacyPolicyView()
                        }
                        Link(
                            "Terms",
                            destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                        )
                    }
                    .font(.footnote)
                }
                .padding()
            }
            .navigationTitle("Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if store.products.isEmpty {
                    await store.prepare()
                }
            }
        }
    }

    private func billingPeriod(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else {
            return nil
        }

        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: return nil
        }

        return "every \(period.value) \(unit)"
    }

    private func benefit(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.tint)
        }
    }
}

#Preview {
    ProPaywallView()
        .environment(StoreManager())
}
