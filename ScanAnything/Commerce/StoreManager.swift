import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class StoreManager {
    static let monthlyProductID = "com.nightvibes33.scananything.pro.monthly"
    static let yearlyProductID = "com.nightvibes33.scananything.pro.yearly"

    private static let proProductIDs: Set<String> = [
        monthlyProductID,
        yearlyProductID
    ]

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoading = false
    private(set) var statusMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func prepare() async {
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: Self.proProductIDs)
                .sorted { $0.price < $1.price }
        } catch {
            statusMessage = "The App Store products could not be loaded right now."
        }
    }

    func purchase(_ product: Product) async {
        statusMessage = nil

        do {
            switch try await product.purchase() {
            case .success(let result):
                let transaction = try verified(result)
                await transaction.finish()
                await refreshEntitlements()

            case .pending:
                statusMessage = "Purchase pending approval."

            case .userCancelled:
                break

            @unknown default:
                statusMessage = "The purchase could not be completed."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func restore() async {
        statusMessage = nil

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isPro
                ? "ScanAnything Pro restored."
                : "No active ScanAnything Pro purchase was found."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var entitled = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.proProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }

            if let expirationDate = transaction.expirationDate,
               expirationDate <= Date() {
                continue
            }

            entitled = true
        }

        isPro = entitled
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            guard !Task.isCancelled else { return }
            guard case .verified(let transaction) = result else { continue }

            if Self.proProductIDs.contains(transaction.productID) {
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    private func verified<T>(
        _ result: VerificationResult<T>
    ) throws -> T {
        switch result {
        case .verified(let value):
            value
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

enum StoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            "The App Store transaction could not be verified."
        }
    }
}
