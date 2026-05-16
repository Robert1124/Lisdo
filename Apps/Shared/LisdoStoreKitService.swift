import Foundation
import LisdoCore
import StoreKit

public enum LisdoStoreKitServiceError: Error, Equatable, Sendable {
    case productUnavailable(String)
    case purchaseCancelled
    case purchasePending
    case unverifiedTransaction
}

extension LisdoStoreKitServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .productUnavailable(let productID):
            return "StoreKit product is unavailable: \(productID)."
        case .purchaseCancelled:
            return "Purchase cancelled."
        case .purchasePending:
            return "Purchase is pending approval."
        case .unverifiedTransaction:
            return "StoreKit could not verify this transaction."
        }
    }
}

public struct LisdoVerifiedStoreKitTransaction {
    public var transaction: Transaction
    public var signedTransactionInfo: String
}

@MainActor
public final class LisdoStoreKitService: ObservableObject {
    @Published public private(set) var products: [String: Product] = [:]
    @Published public private(set) var transactionUpdateSyncStatus = ""

    private var transactionUpdatesTask: Task<Void, Never>?

    public init() {}

    deinit {
        transactionUpdatesTask?.cancel()
    }

    @discardableResult
    public func loadProducts() async throws -> [Product] {
        let loadedProducts = try await Product.products(for: LisdoStoreProductID.allCases.map(\.rawValue))
        products = Dictionary(uniqueKeysWithValues: loadedProducts.map { ($0.id, $0) })
        return loadedProducts
    }

    public func product(for productID: LisdoStoreProductID) async throws -> Product {
        if let product = products[productID.rawValue] {
            return product
        }

        _ = try await loadProducts()
        guard let product = products[productID.rawValue] else {
            throw LisdoStoreKitServiceError.productUnavailable(productID.rawValue)
        }
        return product
    }

    public func purchase(productID: LisdoStoreProductID) async throws -> LisdoVerifiedStoreKitTransaction {
        let product = try await product(for: productID)
        let result = try await product.purchase()

        switch result {
        case .success(let verificationResult):
            return try verifiedTransaction(from: verificationResult)
        case .userCancelled:
            throw LisdoStoreKitServiceError.purchaseCancelled
        case .pending:
            throw LisdoStoreKitServiceError.purchasePending
        @unknown default:
            throw LisdoStoreKitServiceError.purchasePending
        }
    }

    public func restoreVerifiedTransactions() async throws -> [LisdoVerifiedStoreKitTransaction] {
        try await AppStore.sync()

        var transactions: [LisdoVerifiedStoreKitTransaction] = []
        for await result in Transaction.currentEntitlements {
            transactions.append(try verifiedTransaction(from: result))
        }
        return transactions
    }

    public func startTransactionUpdatesListener(
        accountSessionService: LisdoAccountSessionService = LisdoAccountSessionService(),
        onServerVerified: @escaping @MainActor @Sendable (LisdoStoreKitTransactionVerificationResponse) -> Void = { _ in }
    ) {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.syncTransactionUpdate(
                    result,
                    accountSessionService: accountSessionService,
                    onServerVerified: onServerVerified
                )
            }
        }
    }

    public func stopTransactionUpdatesListener() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
    }

    @discardableResult
    public func syncVerifiedTransactionWithBackend(
        _ verifiedTransaction: LisdoVerifiedStoreKitTransaction,
        accountSessionService: LisdoAccountSessionService = LisdoAccountSessionService()
    ) async throws -> LisdoStoreKitTransactionVerificationResponse? {
        guard accountSessionService.currentLisdoBearerToken() != nil else {
            return nil
        }

        return try await accountSessionService.verifyStoreKitTransaction(
            verificationRequest(for: verifiedTransaction)
        )
    }

    public func verificationRequest(for verifiedTransaction: LisdoVerifiedStoreKitTransaction) -> LisdoStoreKitTransactionVerificationRequest {
        let transaction = verifiedTransaction.transaction
        return LisdoStoreKitTransactionVerificationRequest(
            signedTransactionInfo: verifiedTransaction.signedTransactionInfo,
            clientVerified: true,
            transactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            productId: transaction.productID,
            environment: String(describing: transaction.environment),
            purchaseDate: iso8601String(from: transaction.purchaseDate),
            expirationDate: transaction.expirationDate.map(iso8601String(from:))
        )
    }

    private func syncTransactionUpdate(
        _ result: VerificationResult<Transaction>,
        accountSessionService: LisdoAccountSessionService,
        onServerVerified: @escaping @MainActor @Sendable (LisdoStoreKitTransactionVerificationResponse) -> Void
    ) async {
        do {
            let verifiedTransaction = try verifiedTransaction(from: result)
            guard let response = try await syncVerifiedTransactionWithBackend(
                verifiedTransaction,
                accountSessionService: accountSessionService
            ) else {
                transactionUpdateSyncStatus = "StoreKit transaction is waiting for Lisdo sign-in before sync."
                return
            }

            onServerVerified(response)
            await verifiedTransaction.transaction.finish()
            transactionUpdateSyncStatus = "StoreKit transaction synced."
        } catch LisdoStoreKitServiceError.unverifiedTransaction {
            transactionUpdateSyncStatus = "StoreKit delivered an unverified transaction update."
        } catch {
            transactionUpdateSyncStatus = "StoreKit transaction sync failed: \(error.localizedDescription)"
        }
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> LisdoVerifiedStoreKitTransaction {
        switch result {
        case .verified(let transaction):
            return LisdoVerifiedStoreKitTransaction(
                transaction: transaction,
                signedTransactionInfo: result.jwsRepresentation
            )
        case .unverified:
            throw LisdoStoreKitServiceError.unverifiedTransaction
        }
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
