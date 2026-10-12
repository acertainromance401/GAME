import Combine
import Foundation
import StoreKit

@MainActor
final class StoryPurchaseStore: ObservableObject {
    static let shared = StoryPurchaseStore()
    static let productID = "com.acertainromance401.pixelboxing.story"
    static let lastPaidBuildVersion = "4"

    enum AccessState {
        case checking, locked, unlocked, unavailable
    }

    enum Failure {
        case productUnavailable, verification, purchase, restore, noPurchases, pending
    }

    @Published private(set) var accessState = AccessState.checking
    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var failure: Failure?

    var hasStoryAccess: Bool { accessState == .unlocked }
    var isLegacyPaidCustomer: Bool { hasLegacyPaidAccess }
    var isBusy: Bool {
        accessState == .checking || isLoadingProduct || isPurchasing || isRestoring
    }
    var canPurchase: Bool { accessState == .locked && product != nil && !isBusy }

    private var hasPurchasedStory = false
    private var hasLegacyPaidAccess = false
    private var hasVerifiedAppTransaction = false
    private var hasUnverifiedStoryTransaction = false
    private var entitlementRevision = 0
    private var accessTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?

    init() {
        #if DEBUG
        if StoryProgress.temporarilyUnlockStory {
            accessState = .unlocked
            return
        }
        #endif
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                await self.receive(result)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func prepare() async {
        await refreshAccess()
        if !hasStoryAccess { await loadProduct() }
    }

    func refreshAccess() async {
        #if DEBUG
        if StoryProgress.temporarilyUnlockStory {
            accessState = .unlocked
            failure = nil
            return
        }
        #endif
        if let accessTask {
            await accessTask.value
            return
        }
        let task = Task { await self.readVerifiedAccess() }
        accessTask = task
        await task.value
        accessTask = nil
    }

    func purchase() async {
        guard canPurchase, let product else { return }
        isPurchasing = true
        failure = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await receive(result)
            case .pending:
                failure = .pending
            case .userCancelled:
                break
            @unknown default:
                failure = .purchase
            }
        } catch {
            failure = .purchase
        }
    }

    func restore() async {
        #if DEBUG
        if StoryProgress.temporarilyUnlockStory { return }
        #endif
        guard !isBusy else { return }
        isRestoring = true
        failure = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshAccess()
            if !hasStoryAccess {
                _ = try? await AppTransaction.refresh()
                await refreshAccess()
            }
            if !hasStoryAccess {
                failure = accessState == .unavailable ? .verification : .noPurchases
            }
        } catch {
            failure = .restore
        }
    }

    func clearFailure() {
        failure = nil
    }

    private func loadProduct() async {
        guard !isLoadingProduct, product == nil else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await Product.products(for: [Self.productID]).first {
                $0.id == Self.productID && $0.type == .nonConsumable
            }
            if product == nil { failure = .productUnavailable }
        } catch {
            failure = .productUnavailable
        }
    }

    private func readVerifiedAccess() async {
        let revision = entitlementRevision
        var purchasedStory = false
        var unverifiedStory = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == Self.productID,
                   transaction.productType == .nonConsumable,
                   transaction.revocationDate == nil, !transaction.isUpgraded {
                    purchasedStory = true
                }
            case .unverified(let transaction, _):
                if transaction.productID == Self.productID { unverifiedStory = true }
            }
        }

        if purchasedStory {
            guard revision == entitlementRevision else { return }
            hasPurchasedStory = true
            hasUnverifiedStoryTransaction = unverifiedStory
            updateAccessState()
            return
        }

        var legacyPaidAccess = hasLegacyPaidAccess
        var verifiedApp = hasVerifiedAppTransaction
        do {
            switch try await AppTransaction.shared {
            case .verified(let transaction):
                verifiedApp = transaction.bundleID == Bundle.main.bundleIdentifier
                legacyPaidAccess = verifiedApp && transaction.environment == .production
                    && Self.isLegacyPaidBuild(transaction.originalAppVersion)
            case .unverified:
                verifiedApp = false
                legacyPaidAccess = false
            }
        } catch {
        }

        guard revision == entitlementRevision else { return }
        hasPurchasedStory = purchasedStory
        hasLegacyPaidAccess = legacyPaidAccess
        hasVerifiedAppTransaction = verifiedApp
        hasUnverifiedStoryTransaction = unverifiedStory
        updateAccessState()
    }

    private func receive(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard transaction.productID == Self.productID,
                  transaction.productType == .nonConsumable else { return }
            entitlementRevision += 1
            hasPurchasedStory = transaction.revocationDate == nil && !transaction.isUpgraded
            hasUnverifiedStoryTransaction = false
            updateAccessState()
            if hasStoryAccess { failure = nil }
            await transaction.finish()
        case .unverified(let transaction, _):
            guard transaction.productID == Self.productID else { return }
            failure = .verification
        }
    }

    private func updateAccessState() {
        if hasPurchasedStory || hasLegacyPaidAccess {
            accessState = .unlocked
        } else if hasVerifiedAppTransaction && !hasUnverifiedStoryTransaction {
            accessState = .locked
        } else {
            accessState = .unavailable
        }
    }

    private static func isLegacyPaidBuild(_ version: String) -> Bool {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 3,
              components.allSatisfy({ component in
                  !component.isEmpty && component.allSatisfy({ $0.isASCII && $0.isNumber })
                      && Int(component) != nil
              }), let majorVersion = Int(components[0]), majorVersion > 0 else { return false }
        return version.compare(lastPaidBuildVersion, options: .numeric) != .orderedDescending
    }
}