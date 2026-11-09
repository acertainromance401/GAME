import StoreKit
import SwiftUI

enum StoryPurchaseReward: Identifiable {
    case starterOutfit
    case appearance(StoryOpponent)
    case championOutfit
    case championBelt

    static var purchaseRewards: [Self] { [.starterOutfit] }

    static var victoryRewards: [Self] {
        StoryOpponent.allCases.filter(\.hasAppearance).map(Self.appearance)
            + [.championOutfit, .championBelt]
    }

    var id: String {
        switch self {
        case .starterOutfit: "story-starter-outfit"
        case .appearance(let opponent): "appearance-\(opponent.rawValue)"
        case .championOutfit: "final-champion-outfit"
        case .championBelt: "champion-belt"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "person.crop.square"
        case .starterOutfit, .championOutfit: "tshirt.fill"
        case .championBelt: "medal.fill"
        }
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .starterOutfit: OutfitID.storyStarter.label(for: language)
        case .appearance(let opponent):
            "\(opponent.title(for: language)) \(StoryText.appearance.text(for: language))"
        case .championOutfit: OutfitID.storyChampion.label(for: language)
        case .championBelt: StoryText.championBelt.text(for: language)
        }
    }

    func requirement(for language: AppLanguage) -> String {
        switch self {
        case .starterOutfit:
            StoryPurchaseText.starterOutfitDetail.text(for: language)
        case .appearance(let opponent):
            opponent == .southpaw ? StoryPurchaseText.southpawUnlockRequirement.text(for: language)
                + (opponent.isAvailable ? "" : " · " + StoryText.unavailable.text(for: language))
                : StoryPurchaseText.victoryRequirement.text(for: language) + opponent.title(for: language)
        case .championOutfit, .championBelt:
            StoryPurchaseText.championshipVictory.text(for: language)
        }
    }
}

struct StoryPurchaseView: View {
    @ObservedObject var store: StoryPurchaseStore
    @ObservedObject private var loc = LocalizationManager.shared
    let onClose: () -> Void
    let onUnlocked: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.76).ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(PreparationPalette.rule).frame(height: 1)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            posterArtwork
                            sectionTitle(.instantRewards)
                            ForEach(StoryPurchaseReward.purchaseRewards) { reward in
                                benefit(symbol: reward.symbol, title: reward.title(for: loc.language),
                                    detail: reward.requirement(for: loc.language))
                            }
                            Rectangle().fill(PreparationPalette.rule).frame(height: 1)
                            sectionTitle(.availableContent)
                            benefit(symbol: "flag.checkered", title: loc.purchase(.campaignTitle),
                                detail: loc.purchase(.campaignDetail))
                            benefit(symbol: "film", title: loc.purchase(.scenesTitle),
                                detail: loc.purchase(.scenesDetail))
                            Rectangle().fill(PreparationPalette.rule).frame(height: 1)
                            sectionTitle(.earnedRewards)
                            Text(loc.purchase(.rewardsRequireVictory))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(PreparationPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(StoryPurchaseReward.victoryRewards) { reward in
                                benefit(symbol: reward.symbol, title: reward.title(for: loc.language),
                                    detail: reward.requirement(for: loc.language))
                            }
                            benefit(symbol: "figure.boxing", title: loc.story(.southpawStance),
                                detail: loc.purchase(.southpawStanceDetail))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.visible)
                    Rectangle().fill(PreparationPalette.rule).frame(height: 1)
                    footer
                }
                .frame(width: max(0, min(680, proxy.size.width - 32)),
                    height: max(0, min(520, proxy.size.height - 24)))
                .rivalPaperSurface()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task { await store.prepare() }
        .onChange(of: store.hasStoryAccess) { _, unlocked in
            if unlocked { onUnlocked() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.purchase(.offerTitle))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(PreparationPalette.ink)
                    .lineLimit(2).minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
                Text(loc.purchase(.oneTimePurchase))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PreparationPalette.player)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .buttonStyle(RivalPlainButtonStyle())
            .foregroundStyle(PreparationPalette.ink)
            .accessibilityLabel(loc.t(.close))
            .help(loc.t(.close))
            .accessibilityIdentifier("storyPurchaseClose")
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 10)
    }

    private var posterArtwork: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                RivalWordmark(width: 104).accessibilityHidden(true)
                Text(loc.story(.lineupTitle))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MainMenuPalette.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image("ArenaVictory")
                .resizable().scaledToFit()
                .frame(width: 110, height: 128)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MainMenuPalette.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storyOfferArtwork")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.accessState == .checking || store.isLoadingProduct {
                ProgressView(loc.purchase(store.accessState == .checking ? .checkingAccess : .loadingPrice))
                    .font(.system(size: 11, weight: .medium))
                    .tint(PreparationPalette.ink)
                    .foregroundStyle(PreparationPalette.secondary)
            } else if let failure = store.failure {
                Text(loc.purchase(failureText(failure)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PreparationPalette.rival)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.accessState == .unavailable {
                Text(loc.purchase(.accessUnavailable))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PreparationPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(loc.purchase(.victoryOnlyNotice))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PreparationPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { purchaseActions }
                VStack(spacing: 8) { purchaseActions }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder
    private var purchaseActions: some View {
        Button {
            if store.hasStoryAccess {
                onUnlocked()
            } else {
                Task { await store.purchase() }
            }
        } label: {
            HStack(spacing: 8) {
                if store.isPurchasing {
                    ProgressView().tint(PreparationPalette.paper)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: store.hasStoryAccess ? "arrow.right" : "cart.fill")
                        .frame(width: 18, height: 18)
                }
                Text(purchaseTitle)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(RivalMenuButtonStyle(primary: true, onPaper: true))
        .disabled(!store.hasStoryAccess && !store.canPurchase)
        .opacity(store.hasStoryAccess || store.canPurchase ? 1 : 0.5)
        .accessibilityIdentifier("storyPurchaseBuy")
        Button { Task { await store.restore() } } label: {
            HStack(spacing: 8) {
                if store.isRestoring {
                    ProgressView().tint(PreparationPalette.ink).frame(width: 18, height: 18)
                } else {
                    Image(systemName: "arrow.clockwise").frame(width: 18, height: 18)
                }
                Text(loc.purchase(.restorePurchases))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .buttonStyle(RivalMenuButtonStyle(onPaper: true))
        .disabled(store.isBusy)
        .accessibilityIdentifier("storyPurchaseRestore")
        if !store.hasStoryAccess && (store.product == nil || store.accessState == .unavailable) {
            Button { Task { store.clearFailure(); await store.prepare() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath").frame(width: 20, height: 28)
            }
            .buttonStyle(RivalMenuButtonStyle(onPaper: true))
            .disabled(store.isBusy)
            .accessibilityLabel(loc.purchase(.tryAgain))
            .help(loc.purchase(.tryAgain))
        }
    }

    private var purchaseTitle: String {
        if store.hasStoryAccess { return loc.story(.continueStory) }
        guard let product = store.product else { return loc.purchase(.buy) }
        return "\(loc.purchase(.buy))  \(product.displayPrice)"
    }

    private func sectionTitle(_ key: StoryPurchaseText) -> some View {
        Text(loc.purchase(key))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(PreparationPalette.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func benefit(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PreparationPalette.player)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PreparationPalette.ink)
                Text(detail).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PreparationPalette.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func failureText(_ failure: StoryPurchaseStore.Failure) -> StoryPurchaseText {
        switch failure {
        case .productUnavailable: .productUnavailable
        case .verification: .verificationFailed
        case .purchase: .purchaseFailed
        case .restore: .restoreFailed
        case .noPurchases: .noPurchasesFound
        case .pending: .pendingPurchase
        }
    }
}