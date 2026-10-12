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

/// A boxing-poster composition: the next bout on the left, the actual rival on the right.
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
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11
    @ScaledMetric(relativeTo: .title2) private var recordSize: CGFloat = 25
    @State private var overlay: Overlay?

    var body: some View {
        GeometryReader { proxy in
            let layout = MainMenuLayout(size: proxy.size)
            ZStack {
                MainMenuPalette.background.ignoresSafeArea()

                HStack(alignment: .top, spacing: layout.gutter) {
                    menuColumn(layout: layout)
                        .frame(width: layout.menuWidth, height: layout.contentHeight)
                    portraitColumn
                        .frame(width: layout.heroWidth, height: layout.contentHeight)
                }
                .padding(.horizontal, MainMenuLayout.horizontalPadding)
                .padding(.vertical, MainMenuLayout.verticalPadding)
                .allowsHitTesting(overlay == nil)
                .accessibilityHidden(overlay != nil)

                if let overlay {
                    MainMenuPalette.background.opacity(0.82).ignoresSafeArea()
                    overlayContent(overlay)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: reducedMotion ? UIStyleKit.microDuration : UIStyleKit.fastDuration), value: overlay)
        }
        .onAppear {
            controller.releaseHeldControls()
            if screen == .storySelection && !purchases.hasStoryAccess { overlay = .storyPurchase }
        }
        .task { await purchases.refreshAccess() }
        .task {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }

    private func menuColumn(layout: MainMenuLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    masthead(displaySize: layout.displaySize, compact: layout.contentHeight < 340)
                    Spacer(minLength: 8)
                    fightButton.padding(.top, 4)
                    storyButton.padding(.top, 8)

                    // Utilities are deliberately secondary: one ink color, no competing colored cards.
                    let columns = dynamicType.isAccessibilitySize ? 1 : (layout.menuWidth < 320 ? 2 : 3)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns), spacing: 8) {
                        utilityButton(.waitingRoomButton, hint: .waitingRoomSubtitle, symbol: "tshirt", id: "mainMenuWaitingRoom") {
                            overlay = .waitingRoom
                        }
                        utilityButton(.menuGymTitle, hint: .practiceRoomSubtitle, symbol: "figure.boxing", id: "mainMenuGym") {
                            screen = .practice
                        }
                        utilityButton(.leaderboardButton, hint: .leaderboardSubtitle, symbol: "trophy", id: "mainMenuLeaderboard") {
                            overlay = .leaderboard
                        }
                    }
                    .padding(.top, 12)
                    if dynamicType.isAccessibilitySize { recordStrip.padding(.top, 20) }
                }
                .frame(maxWidth: .infinity, minHeight: max(0, layout.contentHeight - 44), alignment: .leading)
            }
            .scrollIndicators(.visible)

            Button {
                overlay = .reset
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                    Text(loc.t(.newGameButton))
                        .font(.system(size: captionSize, weight: .medium))
                }
                .foregroundStyle(MainMenuPalette.secondary)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(MainMenuPressStyle())
            .accessibilityLabel(loc.t(.newGameButton))
            .accessibilityHint(loc.t(.newGameSubtitle))
            .accessibilityIdentifier("mainMenuNewGame")
        }
    }

    private func masthead(displaySize: CGFloat, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !compact {
                HStack(spacing: 9) {
                    Rectangle().fill(MainMenuPalette.rival).frame(width: 19, height: 3)
                    Text(loc.t(.boxingKicker))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MainMenuPalette.secondary)
                }
                .accessibilityHidden(true)
            }
            Text("RIVAL")
                .font(.system(size: displaySize, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(MainMenuPalette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("mainMenuWordmark")
            if !compact {
                Text(loc.t(.tagline))
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundStyle(MainMenuPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
    }

    private var storyButton: some View {
        let opponent = storyProgress?.activeBout?.bout.opponent
            ?? StoryOpponent.allCases.first(where: {
                storyProgress?.isUnlocked($0) == true && storyProgress?.clearedOpponents.contains($0) == false
            }) ?? .pressure
        return Button {
            if purchases.hasStoryAccess {
                screen = .storySelection
            } else {
                overlay = .storyPurchase
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.story(.title))
                        .font(.system(size: 24, weight: .black)).fontWidth(.condensed)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text(purchases.hasStoryAccess ? opponent.title(for: loc.language) : loc.purchase(.storyButtonSubtitle))
                        .font(.system(size: captionSize, weight: .medium))
                        .foregroundStyle(MainMenuPalette.secondary)
                        .lineLimit(2).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 2)
                if !purchases.hasStoryAccess {
                    Text(purchases.product?.displayPrice ?? loc.purchase(.purchaseBenefits))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MainMenuPalette.story)
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else if let bout = storyProgress?.activeBout?.bout {
                    Text("\(bout.round) / \(bout.opponent.maximumRounds)")
                        .font(.system(size: 20, weight: .bold)).monospacedDigit()
                } else {
                    Text("\(storyProgress?.clearedOpponents.filter { $0 != .rival }.count ?? 0) / 4")
                        .font(.system(size: 20, weight: .bold)).monospacedDigit()
                }
                Image(systemName: purchases.hasStoryAccess ? "arrow.up.right" : "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MainMenuPalette.story)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(MainMenuPalette.paper)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(MainMenuPalette.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MainMenuPalette.story.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(MainMenuPressStyle())
        .accessibilityIdentifier("mainMenuStory")
        .accessibilityLabel("\(loc.story(.title)), \(purchases.hasStoryAccess ? opponent.title(for: loc.language) : loc.purchase(.purchaseBenefits))")
    }

    private var fightButton: some View {
        Button {
            controller.start()
            screen = .vsSplash
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("RIVAL")
                        .font(.system(size: 28, weight: .black))
                        .fontWidth(.condensed)
                    Text(loc.purchase(.freePlay))
                        .font(.system(size: captionSize, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                Rectangle().fill(MainMenuPalette.background.opacity(0.18)).frame(width: 1, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ROUND")
                        .font(.system(size: 8, weight: .bold))
                    Text(String(format: "%02d", controller.snapshot.round))
                        .font(.system(size: 27, weight: .bold))
                        .fontWidth(.condensed)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 19, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(MainMenuPalette.background)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(MainMenuPalette.paper, in: RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .leading) {
                Rectangle().fill(MainMenuPalette.rival).frame(width: 3).padding(.vertical, 14)
            }
        }
        .buttonStyle(MainMenuPressStyle())
        .accessibilityLabel("RIVAL, \(loc.purchase(.freePlay)), \(loc.t(.roundLabel)) \(controller.snapshot.round)")
        .accessibilityHint(loc.t(.continueButton))
        .accessibilityIdentifier("mainMenuContinue")
    }

    private func utilityButton(_ title: L, hint: L, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MainMenuPalette.secondary)
                    .frame(width: 20, height: 22)
                    .accessibilityHidden(true)
                Text(loc.t(title))
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(MainMenuPalette.paper)
                    .lineLimit(2).minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(MainMenuPalette.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MainMenuPalette.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(MainMenuPressStyle())
        .accessibilityLabel(loc.t(title))
        .accessibilityHint(loc.t(hint))
        .accessibilityIdentifier(id)
    }

    private var portraitColumn: some View {
        ZStack(alignment: .bottomLeading) {
            RivalPortraitView(isActive: overlay == nil)
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("RIVAL")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(MainMenuPalette.paper)
                        if !dynamicType.isAccessibilitySize {
                            Text(loc.t(.menuRedCorner))
                                .font(.system(size: captionSize, weight: .semibold))
                                .foregroundStyle(MainMenuPalette.secondary)
                        }
                    }
                    .padding(12)
                    .background(MainMenuPalette.background.opacity(0.92))
                    Spacer(minLength: 4)
                    VStack(spacing: 8) {
                        Button { overlay = .settings } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(MainMenuPalette.paper)
                                .frame(width: 44, height: 44)
                                .background(MainMenuPalette.background.opacity(0.94))
                                .overlay(Rectangle().stroke(MainMenuPalette.rule, lineWidth: 1))
                        }
                        .buttonStyle(MainMenuPressStyle())
                        .accessibilityLabel(loc.t(.settingsTitle))
                        .accessibilityIdentifier("mainMenuSettings")

                        Button {
                            overlay = .rivalAnalysis
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 13, weight: .semibold))
                                    .accessibilityHidden(true)
                                Text(loc.t(.rivalAnalysisButton))
                                    .font(.system(size: 9, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .foregroundStyle(MainMenuPalette.paper)
                            .frame(width: 84, height: 44)
                            .background(MainMenuPalette.background.opacity(0.94))
                            .overlay(Rectangle().stroke(MainMenuPalette.rule, lineWidth: 1))
                        }
                        .buttonStyle(MainMenuPressStyle())
                        .accessibilityLabel(loc.t(.rivalAnalysisButton))
                        .accessibilityHint(loc.t(.rivalAnalysisSubtitle))
                        .accessibilityIdentifier("mainMenuRivalAnalysis")
                    }
                }
                Spacer(minLength: 8)
                if !dynamicType.isAccessibilitySize { recordStrip }
            }
            .padding(12)
        }
        .background(MainMenuPalette.surface)
        .clipped()
        .overlay(Rectangle().stroke(MainMenuPalette.rule, lineWidth: 1))
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MainMenuPalette.background.opacity(0.96))
    }

    private func record(value: Int, label: L, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(format: "%02d", value))
                .font(.system(size: recordSize, weight: .bold))
                .fontWidth(.condensed)
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
    @RivalReducedMotion private var reducedMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: UIStyleKit.microDuration), value: configuration.isPressed)
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
                        onClose: onClose
                    )
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            analysisRow(loc.t(.rivalAnalysisReadLabel), readTitle)
                            analysisRow(loc.t(.rivalAnalysisConfidenceLabel), percent(snapshot.rivalReadConfidence))
                            analysisRow(loc.t(.rivalAnalysisAdaptationLabel), percent(snapshot.adaptation))
                            analysisRow(loc.t(.rivalAnalysisFavoriteAttackLabel), localizedPunch(snapshot.favoriteAttack))
                            analysisRow(loc.t(.rivalAnalysisPlayerDodgeLabel), String(snapshot.roundPlayerDodgeCount))
                            analysisRow(loc.t(.rivalAnalysisEnemyDodgeLabel), String(snapshot.roundEnemyDodgeCount))
                            analysisRow(loc.t(.rivalAnalysisPlayerTopAttackLabel), snapshot.roundPlayerTopAttack.map(localizedPunch) ?? loc.t(.roundStatsNoAttack))
                            analysisRow(loc.t(.rivalAnalysisEnemyTopAttackLabel), snapshot.roundEnemyTopAttack.map(localizedPunch) ?? loc.t(.roundStatsNoAttack))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc.t(.rivalAnalysisCoachLabel))
                                    .font(.system(size: labelSize, weight: .semibold))
                                    .foregroundStyle(MainMenuPalette.paper)
                                Text(snapshot.rivalRead.cornerReport(for: loc.language) ?? loc.t(.rivalAnalysisTipNeutral))
                                    .font(.system(size: valueSize, weight: .regular))
                                    .foregroundStyle(MainMenuPalette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MainMenuPalette.surface, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MainMenuPalette.rule, lineWidth: 1))
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(20)
                .frame(width: min(440, proxy.size.width - 32), height: min(396, proxy.size.height - 24))
                .background(MainMenuPalette.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(MainMenuPalette.rule, lineWidth: 1))
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

    private func localizedPunch(_ punch: Punch) -> String {
        switch punch {
        case .jab: L.pick(ko: "왼손 잽", en: "Left jab", ja: "左ジャブ", language: loc.language)
        case .cross: L.pick(ko: "오른손 크로스", en: "Right cross", ja: "右クロス", language: loc.language)
        case .leftBody: L.pick(ko: "왼손 바디샷", en: "Left body shot", ja: "左ボディ", language: loc.language)
        case .rightBody: L.pick(ko: "오른손 바디샷", en: "Right body shot", ja: "右ボディ", language: loc.language)
        case .leftHook: L.pick(ko: "왼손 훅", en: "Left hook", ja: "左フック", language: loc.language)
        case .rightHook: L.pick(ko: "오른손 훅", en: "Right hook", ja: "右フック", language: loc.language)
        case .leftUppercut: L.pick(ko: "왼손 어퍼컷", en: "Left uppercut", ja: "左アッパー", language: loc.language)
        case .rightUppercut: L.pick(ko: "오른손 어퍼컷", en: "Right uppercut", ja: "右アッパー", language: loc.language)
        }
    }

    private func percent(_ value: Double) -> String {
        let percentValue = Int((min(1, max(0, value)) * 100).rounded())
        return "\(percentValue)%"
    }

    private func analysisRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(MainMenuPalette.paper)
            Text(value)
                .font(.system(size: valueSize, weight: .regular))
                .foregroundStyle(MainMenuPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MainMenuPalette.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(MainMenuPalette.rule, lineWidth: 1))
    }
}
