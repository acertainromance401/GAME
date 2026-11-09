/*
 MainMenuView.swift

 파일 설명:
 - 게임의 메인 메뉴 UI를 구성하는 SwiftUI 뷰 모음입니다. 대전 선택, 스타일/의상 선택, 설정 진입 등의
     상호작용을 포함합니다.

 사용 영향 및 주의사항:
 - 메뉴 내에서 선택된 값은 `GameController`/`Settings`로 전달되어 실제 매치에 반영됩니다.
 - UI 변경은 사용자 흐름에 직접적 영향을 주므로 레이아웃 변경 시 연결된 액션들을 함께 점검하세요.
*/
import SwiftUI

/// Only the foreground observes game records. The portrait owns an isolated, non-playing scene.
struct MainMenuView: View {
    private enum Overlay: Equatable { case waitingRoom, settings, leaderboard, reset, rivalAnalysis, storyPurchase }

    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var purchases = StoryPurchaseStore.shared
    @Binding var screen: AppScreen
    var storyProgress: StoryProgress? = nil
    @RivalReducedMotion private var reducedMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .title2) private var headingSize: CGFloat = 30
    @ScaledMetric(relativeTo: .title2) private var recordSize: CGFloat = 25
    @State private var overlay: Overlay? = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RIVAL_PRESENTATION_TEST"] == "story-offer" {
            return .storyPurchase
        }
        #endif
        return nil
    }()

    var body: some View {
        GeometryReader { proxy in
            let layout = MainMenuLayout(size: proxy.size)
            ZStack {
                MainMenuPalette.background.ignoresSafeArea()

                RivalPortraitView(isActive: overlay == nil, presentationBackground: UIColor(MainMenuPalette.background))
                    .frame(width: proxy.size.width * 0.62, height: max(0, proxy.size.height - 50))
                    .padding(.top, 50)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                if overlay == nil {
                    menuContent(layout: layout)
                }

                if let overlay {
                    MainMenuPalette.background.opacity(0.82).ignoresSafeArea()
                    overlayContent(overlay)
                        .rivalPanelTransition()
                }
            }
            .animation(.easeOut(duration: reducedMotion ? UIStyleKit.microDuration : UIStyleKit.fastDuration), value: overlay)
        }
        .onAppear {
            controller.releaseHeldControls()
        }
        .task { await purchases.refreshAccess() }
        .task {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }

    private func menuContent(layout: MainMenuLayout) -> some View {
        VStack(spacing: 0) {
                    masthead
                    HStack(alignment: .top, spacing: MainMenuLayout.gutter) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(loc.t(.menuHeadline))
                                    .font(.system(size: headingSize, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.isHeader)
                                Text(loc.t(.menuCornerLine))
                                    .font(.system(size: labelSize))
                                    .foregroundStyle(MainMenuPalette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                recordStrip
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollIndicators(.visible)
                        .frame(width: layout.featureWidth)
                        Spacer(minLength: layout.portraitClearWidth)
                        ScrollView {
                            storyButton
                        }
                        .scrollIndicators(.visible)
                        .frame(width: layout.storyWidth)
                    }
                    .padding(.horizontal, MainMenuLayout.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxHeight: .infinity)
                    fightButton
                        .padding(.horizontal, MainMenuLayout.horizontalPadding)
                        .padding(.vertical, 10)
                    navigation
                }
                .foregroundStyle(MainMenuPalette.paper)
                .accessibilityElement(children: .contain)
    }

    private var masthead: some View {
        HStack(spacing: 8) {
            RivalWordmark(width: 82)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("mainMenuWordmark")
            Spacer(minLength: 8)
            utilityButton(.leaderboardButton, hint: .leaderboardSubtitle, symbol: "trophy", id: "mainMenuLeaderboard") {
                overlay = .leaderboard
            }
            utilityButton(.rivalAnalysisButton, hint: .rivalAnalysisSubtitle, symbol: "book.closed", id: "mainMenuRivalAnalysis") {
                overlay = .rivalAnalysis
            }
            Button { overlay = .reset } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
            }
            .buttonStyle(MainMenuPressStyle())
            .accessibilityLabel(loc.t(.newGameButton))
            .accessibilityHint(loc.t(.newGameSubtitle))
            .accessibilityIdentifier("mainMenuNewGame")
            Button { overlay = .settings } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
            }
            .buttonStyle(MainMenuPressStyle())
            .accessibilityLabel(loc.t(.settingsTitle))
            .accessibilityIdentifier("mainMenuSettings")
        }
        .padding(.horizontal, MainMenuLayout.horizontalPadding)
        .frame(minHeight: 50)
        .background(MainMenuPalette.background.opacity(0.97))
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            Text("RIVAL")
                .font(.system(size: labelSize, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(MainMenuPalette.surface, in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(MainMenuPalette.rule, lineWidth: 1)
                }
                .overlay(alignment: .bottom) { Rectangle().fill(MainMenuPalette.rival).frame(height: 2) }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel(loc.purchase(.rivalBout))
                .accessibilityAddTraits(.isSelected)
            navigationButton(loc.story(.title), id: "mainMenuStoryNavigation") { screen = .storySelection }
            navigationButton(loc.t(.waitingRoomButton), id: "mainMenuWaitingRoom") { overlay = .waitingRoom }
            navigationButton(loc.t(.menuGymTitle), id: "mainMenuGym") { screen = .practice }
        }
        .padding(.horizontal, MainMenuLayout.horizontalPadding)
        .padding(.vertical, 4)
    }

    private func navigationButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: labelSize, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(MainMenuPalette.surface, in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(MainMenuPalette.rule, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(MainMenuPressStyle())
        .accessibilityIdentifier(id)
    }

    private var storyButton: some View {
        let opponent = storyProgress?.nextOpponent ?? .basic
        return Button {
            screen = .storySelection
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.purchase(.offerTitle))
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(MainMenuPalette.story)
                Text(loc.story(.lineupTitle))
                    .font(.system(size: labelSize + 6, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(purchases.hasStoryAccess ? opponent.title(for: loc.language) : loc.story(.lineupDetail))
                    .font(.system(size: labelSize))
                    .foregroundStyle(MainMenuPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if purchases.hasStoryAccess {
                    if let bout = storyProgress?.activeBout?.bout {
                        Text("\(bout.round) / \(bout.opponent.maximumRounds) \(loc.t(.roundLabel))")
                            .font(.system(size: captionSize, weight: .medium)).monospacedDigit()
                    } else {
                        Text("\(storyProgress?.clearedOpponents.filter { $0.isAvailable && $0 != .rival }.count ?? 0) / \(StoryOpponent.allCases.filter { $0.isAvailable && $0 != .rival }.count)")
                            .font(.system(size: captionSize, weight: .medium)).monospacedDigit()
                    }
                } else {
                    Text(loc.t(.outfitPreviewLabel))
                        .font(.system(size: captionSize, weight: .semibold))
                }
            }
            .foregroundStyle(MainMenuPalette.paper)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
            .background(MainMenuPalette.background.opacity(0.97))
        }
        .buttonStyle(MainMenuPressStyle())
        .accessibilityIdentifier("mainMenuStory")
        .accessibilityLabel("\(loc.story(.title)), \(purchases.hasStoryAccess ? opponent.title(for: loc.language) : loc.t(.outfitPreviewLabel))")
    }

    private var fightButton: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.purchase(.rivalBout))
                    .font(.system(size: labelSize, weight: .semibold))
                Text("\(loc.t(.roundLabel)) \(String(format: "%02d", controller.snapshot.round))")
                    .font(.system(size: captionSize)).monospacedDigit()
                    .foregroundStyle(MainMenuPalette.secondary)
            }
            Spacer(minLength: 8)
            Button {
                controller.start()
                screen = .vsSplash
            } label: {
                HStack(spacing: 12) {
                    Text(loc.t(.menuFightAction))
                        .font(.system(size: labelSize + 4, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                }
                .foregroundStyle(MainMenuPalette.background)
                .padding(.horizontal, 24)
                .frame(minWidth: 180, minHeight: 52)
                .background(MainMenuPalette.paper, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(MainMenuPressStyle())
            .accessibilityLabel("\(loc.purchase(.rivalBout)), \(loc.t(.menuFightAction)), \(loc.t(.roundLabel)) \(controller.snapshot.round)")
            .accessibilityHint(loc.t(.continueButton))
            .accessibilityIdentifier("mainMenuContinue")
        }
    }

    private func utilityButton(_ title: L, hint: L, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 16, height: 22)
                    .accessibilityHidden(true)
                Text(loc.t(title))
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(MainMenuPalette.paper)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(MainMenuPressStyle())
        .accessibilityLabel(loc.t(title))
        .accessibilityHint(loc.t(hint))
        .accessibilityIdentifier(id)
    }

    private var recordStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t(.menuRecordTitle))
                .font(.system(size: captionSize, weight: .medium))
                .foregroundStyle(MainMenuPalette.secondary)
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    record(value: controller.playerStats.totalWins, label: .menuTotalWins, id: "menuTotalWins")
                    record(value: controller.playerStats.bestWinStreak, label: .menuBestStreak, id: "menuBestStreak")
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    record(value: controller.playerStats.totalWins, label: .menuTotalWins, id: "menuTotalWins")
                    Rectangle().fill(MainMenuPalette.rule).frame(width: 1, height: 34)
                    record(value: controller.playerStats.bestWinStreak, label: .menuBestStreak, id: "menuBestStreak")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func record(value: Int, label: L, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(format: "%02d", value))
                .font(.system(size: recordSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(MainMenuPalette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(loc.t(label))
                .font(.system(size: captionSize, weight: .medium))
                .foregroundStyle(MainMenuPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.t(label))
        .accessibilityValue(String(value))
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func overlayContent(_ item: Overlay) -> some View {
        switch item {
        case .waitingRoom:
            WaitingRoomView(controller: controller) { overlay = nil }
        case .settings:
            SettingsMenuView(controller: controller, showsLanguageRow: true) { overlay = nil }
        case .leaderboard:
            LeaderboardView(controller: controller) { overlay = nil }
        case .reset:
            LearningResetConfirmView(onCancel: { overlay = nil }, onConfirm: {
                controller.resetLearning()
                overlay = nil
                screen = .vsSplash
            })
        case .rivalAnalysis:
            RivalAnalysisView(snapshot: controller.snapshot) { overlay = nil }
        case .storyPurchase:
            StoryPurchaseView(store: purchases, onClose: {
                overlay = nil
                if screen == .storySelection { screen = .mainMenu }
            }, onUnlocked: {
                overlay = nil
                screen = .storySelection
            })
        }
    }
}

private struct MainMenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rivalPressFeedback(isPressed: configuration.isPressed)
    }
}

#Preview("Main Menu") {
    MainMenuView(controller: GameController(persistsProgress: false, feedbackEnabled: false), screen: .constant(.mainMenu))
}

private struct RivalAnalysisView: View {
    let snapshot: CombatSnapshot
    let onClose: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var valueSize: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MainMenuPalette.background.opacity(0.76).ignoresSafeArea()
                VStack(spacing: 12) {
                    RivalScreenHeader(
                        kicker: loc.t(.rivalAnalysisKicker),
                        title: loc.t(.rivalAnalysisTitle),
                        closeTitle: loc.t(.close),
                        closeID: "rivalAnalysisClose",
                        onClose: onClose,
                        onPaper: true
                    )
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            analysisRow(loc.t(.rivalAnalysisReadLabel), readTitle)
                            analysisRow(loc.t(.rivalAnalysisPlayerDodgeLabel), String(snapshot.roundPlayerDodgeCount))
                            analysisRow(loc.t(.rivalAnalysisEnemyDodgeLabel), String(snapshot.roundEnemyDodgeCount))
                            analysisRow(loc.t(.rivalAnalysisPlayerTopAttackLabel), snapshot.roundPlayerTopAttack?.localizedName(for: loc.language) ?? loc.t(.roundStatsNoAttack))
                            analysisRow(loc.t(.rivalAnalysisEnemyTopAttackLabel), snapshot.roundEnemyTopAttack?.localizedName(for: loc.language) ?? loc.t(.roundStatsNoAttack))
                            Rectangle().fill(PreparationPalette.rule).frame(height: 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc.t(.rivalAnalysisCoachLabel))
                                    .font(.system(size: labelSize, weight: .semibold))
                                    .foregroundStyle(PreparationPalette.ink)
                                Text(snapshot.rivalRead.cornerReport(for: loc.language) ?? loc.t(.rivalAnalysisTipNeutral))
                                    .font(.system(size: valueSize, weight: .regular))
                                    .foregroundStyle(PreparationPalette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(20)
                .frame(width: min(440, proxy.size.width - 32), height: min(396, proxy.size.height - 24))
                .rivalPaperSurface()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var readTitle: String {
        switch snapshot.rivalRead {
        case .none:
            return loc.t(.rivalAnalysisReadNone)
        case .jabPattern:
            return loc.t(.rivalAnalysisReadJab)
        case .bodyPattern:
            return loc.t(.rivalAnalysisReadBody)
        case .guardShell:
            return loc.t(.rivalAnalysisReadGuard)
        case .duckLeftPattern:
            return loc.t(.rivalAnalysisReadDuckLeft)
        case .duckRightPattern:
            return loc.t(.rivalAnalysisReadDuckRight)
        case .retreatPattern:
            return loc.t(.rivalAnalysisReadRetreat)
        case .pressurePattern:
            return loc.t(.rivalAnalysisReadPressure)
        }
    }

    private func analysisRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(PreparationPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(size: valueSize, weight: .regular))
                .foregroundStyle(PreparationPalette.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(PreparationPalette.rule).frame(height: 1) }
    }
}
