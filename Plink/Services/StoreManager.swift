import Foundation
import StoreKit

// MARK: - Store Manager (Блок 4 — StoreKit 2)
/// Управление подпиской SyncWatch Premium через StoreKit 2.
///
/// Подписки:
/// - com.syncwatch.raveclone.premium.monthly
/// - com.syncwatch.raveclone.premium.quarterly
/// - com.syncwatch.raveclone.premium.yearly
///
/// При успешной покупке — PremiumStatusManager меняет isPremium на true.

@MainActor
final class StoreManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var errorMessage: String?

    // MARK: - Callbacks

    /// Вызывается при успешной покупке (для PremiumStatusManager).
    var onPurchaseSuccess: ((Date) -> Void)?

    // MARK: - Config

    private let productIDs = [
        "com.syncwatch.raveclone.premium.monthly",
        "com.syncwatch.raveclone.premium.quarterly",
        "com.syncwatch.raveclone.premium.yearly",
    ]

    // MARK: - State

    private var transactionListener: Task<Void, Never>?

    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
        case success
        case failed
        case restoring
    }

    // MARK: - Init

    init() {
        listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        purchaseState = .loading

        do {
            let storeProducts = try await Product.products(for: productIDs)
            // Сортируем по цене (месяц → год)
            products = storeProducts.sorted { $0.price < $1.price }
            purchaseState = .idle
        } catch {
            errorMessage = "Не удалось загрузить продукты: \(error.localizedDescription)"
            purchaseState = .failed
            Logger.store.error("loadProducts failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                guard let transaction = transaction else {
                    purchaseState = .failed
                    return
                }
                handleSuccessfulPurchase(transaction)
                await transaction.finish()
                purchaseState = .success

            case .userCancelled:
                purchaseState = .idle

            case .pending:
                purchaseState = .idle
                errorMessage = "Оплата ожидает подтверждения"

            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed
            errorMessage = "Ошибка покупки: \(error.localizedDescription)"
            Logger.store.error("purchase failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        purchaseState = .restoring
        errorMessage = nil

        do {
            try await AppStore.sync()
            purchaseState = .idle
        } catch {
            purchaseState = .failed
            errorMessage = "Не удалось восстановить покупки: \(error.localizedDescription)"
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() {
        transactionListener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try Self.checkVerified(result)
                    guard let transaction = transaction else { continue }
                    await self?.handleSuccessfulPurchase(transaction)
                    await transaction.finish()
                } catch {
                    Logger.store.error("Transaction verification failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T? {
        switch result {
        case .unverified:
            return nil
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Handle Successful Purchase

    private func handleSuccessfulPurchase(_ transaction: Transaction) {
        // Расчёт даты истечения подписки.
        let expiryDate: Date
        if let expirationDate = transaction.expirationDate {
            expiryDate = expirationDate
        } else {
            // Fallback: 30 дней от покупки.
            expiryDate = Date().addingTimeInterval(30 * 24 * 3600)
        }

        onPurchaseSuccess?(expiryDate)
        purchaseState = .success

        // Через 2 секунды сбрасываем состояние в idle.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.purchaseState = .idle
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
