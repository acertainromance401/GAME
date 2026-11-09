/*
 GameView.swift

 파일 설명:
 - 경기 화면 전체 레이아웃(3D 아레나 뷰, HUD, 컨트롤 패드, 오버레이)을 구성하는 SwiftUI 뷰입니다.
 - HUD는 플레이어/라이벌 상태, 라운드/타이머/스코어를 표시하고, 사용자 입력(공격/이동)을 캡처해
     `GameController`로 전달합니다.

 사용 영향 및 주의사항:
 - 이 파일은 사용자 입력과 시각 피드백의 경계이므로 입력 지연/반응성에 주의해야 합니다.
 - 추가 주석은 이해를 돕기 위한 것이며 코드 동작에는 영향을 주지 않습니다.
*/
// - 중앙 배경: 3D 아레나 뷰(Arena3DView)
// - 하단: 조작 패드(이동, 가드, 더킹)와 공격 버튼(ActionButton)
// - 오버레이: 인트로/일시정지/라운드 결과/설정/대기실 등 모달
// 컨트롤과 표시 상태는 `GameController`의 `snapshot`와 `presentation`을 관찰하여 실시간으로 갱신됩니다.

import SwiftUI

/// `GameView`
/// - 역할: 경기 화면의 최상위 `View`로, 3D 아레나, HUD, 조작부, 오버레이를 조합해서 전체 경기 장면을 구성합니다.
/// - 의존: `GameController`를 관찰하여 게임 상태(`snapshot`)와 표시용 데이터(`presentation`)를 가져와 렌더링합니다.
/// - 접근성: 화면 요소들에 대해 적절한 `accessibilityLabel`과 식별자를 부여합니다.
struct GameView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @RivalReducedMotion private var reducedMotion
    @Binding var screen: AppScreen
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSettings = false
    @State private var menuPausedFight = false
        /// `LocalizationManager` 싱글톤. 뷰에서 표시할 모든 문자열을 이 객체로부터 가져옵니다.
        /// 사용자가 기기 수준에서 '모션 감소'를 선택했는지 또는 테스트 오버라이드인지
        /// - 이 값이 `true`면 복잡한 애니메이션과 스케일, 과도한 모션이 억제됩니다.
        /// 루트 뷰가 관리하는 화면 전환 상태(`loading`, `mainMenu`, `battle` 등).
        /// - `GameView`는 라우터로부터 이 바인딩을 받아 특정 동작(예: 메뉴로 돌아가기)을 트리거합니다.
        /// 내부 모달 상태: 대기실/설정 모달을 화면에 표시할지 여부를 제어합니다.
        /// - 이 상태는 버튼 액션으로 토글되며, 모달이 열리면 메인 인터랙션을 차단합니다.
        /// 설정 메뉴 진입 시 전투를 일시정지했는지 기억하는 플래그.
        /// - 설정을 닫을 때 이 값이 `true`이면 `controller.pause()`를 통해 전투를 다시 멈춥니다.

    var body: some View {
            /// 루트 뷰 구성
            /// - GeometryReader: 화면 크기와 안전영역을 수신하여 요소 크기/위치를 동적으로 조정
            /// - ZStack 계층: 3D 아레나, HUD, 컨트롤 패드, 오버레이(인트로/일시정지/라운드결과/설정) 등을 겹쳐서 배치
            /// - 상태 기반 렌더링: `controller.snapshot.phase`와 같은 상태에 따라 특정 오버레이가 표시됩니다.
        GeometryReader { proxy in
            ZStack {
                Arena3DView(controller: controller)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    battleHUD(safeAreaInsets: proxy.safeAreaInsets)
                    Spacer()
                    controls(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)
                        .allowsHitTesting(controller.snapshot.phase == .fight && !controller.isPlayingStoryScene)
                        .accessibilityHidden(controller.snapshot.phase != .fight || controller.isPlayingStoryScene)
                        .opacity(battleControlsOpacity)
                        .animation(.easeOut(duration: reducedMotion ? UIStyleKit.microDuration : 0.16),
                                   value: controller.snapshot.phase)
                }
                .opacity(controller.isPlayingStoryScene ? 0 : 1)
                .animation(.easeOut(duration: reducedMotion ? UIStyleKit.microDuration : 0.16),
                           value: controller.isPlayingStoryScene)
                .allowsHitTesting(!controller.isPlayingStoryScene)
                .accessibilityHidden(controller.isPlayingStoryScene || showsSettings
                    || controller.snapshot.phase == .paused || controller.snapshot.showsRoundResult)

                CombatFeedbackView(presentation: controller.presentation, message: fightCommentary)
                    .opacity(controller.isPlayingStoryScene ? 0 : 1)
                    .padding(.top, CombatFeedbackView.topInset(safeAreaTop: proxy.safeAreaInsets.top,
                                                              isStory: controller.storyBout != nil))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                topActions(safeAreaInsets: proxy.safeAreaInsets)
                    .opacity(controller.isPlayingStoryScene ? 0 : 1)
                    .allowsHitTesting(!controller.isPlayingStoryScene)
                    .accessibilityHidden(controller.isPlayingStoryScene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                Group {
                    if let scene = controller.storyRivalScene {
                        StoryRivalSceneOverlay(scene: scene, onSkip: controller.finishStoryRivalScene)
                    } else if let introduction = controller.storyIntroduction {
                        StoryIntroductionOverlay(introduction: introduction,
                            onSkip: controller.finishStoryIntroduction,
                            onExit: { screen = .storySelection })
                    } else if controller.snapshot.phase == .paused {
                        pauseOverlay
                    } else if let bout = controller.storyBout {
                        StoryBoutOverlay(bout: bout, showsResult: controller.snapshot.showsRoundResult,
                            onContinue: controller.continueToNextRound, onRetry: controller.retryStoryBout,
                            onExit: { screen = .storySelection },
                            onRivalScene: storyRivalSceneAction, roundRecord: controller.snapshot)
                    } else if controller.snapshot.showsRoundResult {
                        roundResultOverlay
                            .transition(reducedMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
                    }
                }
                .animation(.easeOut(duration: UIStyleKit.fastDuration), value: controller.snapshot.phase)
                .animation(.easeOut(duration: reducedMotion ? UIStyleKit.microDuration : UIStyleKit.transitionDuration), value: controller.snapshot.showsRoundResult)
                .allowsHitTesting(controller.storyRoundTransition == nil || controller.snapshot.phase == .paused)
                .accessibilityHidden(controller.storyRoundTransition != nil && controller.snapshot.phase != .paused)

                if let transition = controller.storyRoundTransition, controller.snapshot.phase != .paused {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        Text("ROUND \(transition.round)")
                            .font(.system(size: 28, weight: .black)).monospacedDigit()
                            .foregroundStyle(.white)
                            .opacity(transition.titleOpacity)
                    }
                    .opacity(transition.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                if showsSettings {
                    SettingsMenuView(
                        controller: controller,
                        onExitToMenu: {
                            showsSettings = false
                            menuPausedFight = false
                            controller.saveStoryProgress()
                            screen = controller.storyBout == nil ? .mainMenu : .storySelection
                        },
                        onClose: {
                            if menuPausedFight { controller.pause() }
                            menuPausedFight = false
                            showsSettings = false
                        }
                    )
                }

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color(red: 0.035, green: 0.078, blue: 0.153))
        }
        .task {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
            windowScene.requestGeometryUpdate(preferences)
        }
        .onDisappear {
            controller.stopBattleSound()
            controller.releaseHeldControls()
            controller.saveStoryProgress()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, controller.storyBout != nil { menuPausedFight = false }
            if phase == .active { controller.resumeStoryIntroduction() }
        }
        .onChange(of: controller.storyRivalScene == nil) { wasIdle, isIdle in
            if !wasIdle && isIdle { screen = .storySelection }
        }
    }

    private var storyRivalSceneAction: (() -> Void)? {
        guard controller.canPlayStoryRivalScene else { return nil }
        return { controller.beginStoryRivalScene() }
    }

    private var battleControlsOpacity: Double {
        if controller.storyBout != nil, controller.snapshot.phase != .fight { return 0 }
        if controller.snapshot.phase == .roundBreak {
            return controller.snapshot.lastRoundWasKnockout ? 0 : 0.25
        }
        return 1
    }

    private func topActions(safeAreaInsets: EdgeInsets) -> some View {
            /// 화면 우측 상단의 작은 액션 버튼(설정)을 반환
            /// - `safeAreaInsets`로 오른쪽/상단 여백을 보정
            /// - 버튼 탭 시 `showsSettings`를 `true`로 설정하고, 전투 중이면 `controller.pause()`를 호출
        iconButton("gearshape.fill", accessibility: loc.t(.settingsTitle)) {
            menuPausedFight = controller.snapshot.phase == .fight
                || (controller.storyBout != nil && controller.snapshot.phase == .roundBreak && controller.storyBout?.phase != .finished)
            if menuPausedFight { controller.pause() }
            showsSettings = true
        }
        .accessibilityIdentifier("combatSettings")
        .padding(.trailing, max(14, safeAreaInsets.trailing + 8))
        .padding(.top, max(6, safeAreaInsets.top + 4))
    }

    private func battleHUD(safeAreaInsets: EdgeInsets) -> some View {
            /// 상단 전투 HUD
            /// - 왼쪽/오른쪽에 체력(HP)·스태미나 바(`FighterMeter`)
            /// - 중앙에 라운드/타이머/스코어를 표시
            /// - 접근성 라벨은 HUD의 핵심 정보(라운드/남은 시간/스코어)를 음성으로 읽을 수 있게 구성
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                FighterMeter(
                    health: controller.snapshot.playerHP,
                    maximumHealth: controller.engine.player.maximumHealth,
                    stamina: controller.snapshot.playerStamina,
                    color: FightNightPalette.blue,
                    reverse: false,
                    displayName: loc.t(.leaderboardYouLabel),
                    accessibilityName: loc.t(.playerAccessibility),
                    onRing: true
                )
                Group {
                    if let bout = controller.storyBout {
                        StoryRoundClock(bout: bout, remainingTime: controller.snapshot.time, presentation: controller.presentation)
                    } else {
                        CombatRoundClock(snapshot: controller.snapshot, presentation: controller.presentation)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(FightNightPalette.ink, in: RoundedRectangle(cornerRadius: 3))
                FighterMeter(
                    health: controller.snapshot.enemyHP,
                    maximumHealth: controller.engine.enemy.maximumHealth,
                    stamina: controller.snapshot.enemyStamina,
                    color: FightNightPalette.red,
                    reverse: true,
                    displayName: controller.storyBout?.opponent.fighterName(for: loc.language) ?? "RIVAL",
                    accessibilityName: controller.storyBout?.opponent.fighterName(for: loc.language) ?? loc.t(.rivalAccessibility),
                    onRing: true
                )
            }

        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, max(64, max(safeAreaInsets.leading, safeAreaInsets.trailing) + 64))
        .padding(.top, max(5, safeAreaInsets.top + 2))
        // Live values never crossfade. Only the clock's KO label and separate counter cue animate.
        .transaction { $0.animation = nil }
    }

    private var fightCommentary: String? {
        guard controller.snapshot.phase == .fight, !showsSettings, !controller.isPlayingStoryScene,
              controller.presentation.knockoutClockPhase == .inactive,
              controller.storyBout == nil || controller.storyBout?.phase == .fighting else { return nil }
        return controller.snapshot.message
    }

    private var roundResultOverlay: some View {
        CombatRoundResultView(snapshot: controller.snapshot, onContinue: controller.continueToNextRound)
    }

    private func controls(size: CGSize, safeAreaInsets: EdgeInsets) -> some View {
            /// 하단 조작부 컨테이너
            /// - 화면 `size`에 따라 컴팩트 레이아웃 전환
            /// - 좌측 `combatPad`(이동·가드·더킹), 우측 `attackPad`(백스텝·JAB·CROSS)
        let compact = size.height < 390 || size.width < 700
        let controlWidth: CGFloat = compact ? 52 : 58
        let controlHeight: CGFloat = compact ? 46 : 54
        let attackWidth: CGFloat = compact ? 80 : 94
        let attackHeight: CGFloat = compact ? 66 : 76

        return HStack(alignment: .bottom, spacing: 8) {
            combatPad(width: controlWidth, height: controlHeight)
            Spacer(minLength: 12)
            attackPad(width: attackWidth, height: attackHeight)
        }
        .frame(maxWidth: .infinity)
        // GeometryReader already respects the horizontal safe area.
        .padding(.horizontal, 4)
        .padding(.top, compact ? 10 : 16)
        .padding(.bottom, max(10, safeAreaInsets.bottom + 5))
    }

    private func combatPad(width: CGFloat, height: CGFloat) -> some View {
            /// 이동 및 방어용 패드 레이아웃
            /// - 3x3 그리드: 상/중/하/좌/우 버튼과 가드·더킹 버튼으로 구성
            /// - 각 버튼은 `HoldButton`이며, 누르고 있는 동안 `controller`에 상태 콜백을 보냅니다.
        let locked = controller.snapshot.playerLocked
        return VStack(spacing: 0) {
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    HoldButton(text: loc.t(.weaveLeftControl), label: loc.t(.weaveLeftAccessibility), accent: FightNightPalette.blue, width: width, height: height, locked: locked, onRing: true) {
                        controller.weaveButton(direction: -1, active: $0)
                    }
                    .accessibilityIdentifier("WEAVE_LEFT")
                    HoldButton(symbol: "arrow.up", label: loc.t(.moveForwardAccessibility), accent: FightNightPalette.paper, width: width, height: height, locked: locked, onRing: true) { controller.move(x: 1, y: 0, active: $0) }
                    HoldButton(text: loc.t(.weaveRightControl), label: loc.t(.weaveRightAccessibility), accent: FightNightPalette.red, width: width, height: height, locked: locked, onRing: true) {
                        controller.weaveButton(direction: 1, active: $0)
                    }
                    .accessibilityIdentifier("WEAVE_RIGHT")
                }
                GridRow {
                    HoldButton(symbol: "arrow.left", label: loc.t(.moveLeftAccessibility), accent: FightNightPalette.paper, width: width, height: height, locked: locked, onRing: true) { controller.move(x: 0, y: -1, active: $0) }
                    HoldButton(symbol: "shield.fill", label: loc.t(.guardAccessibility), accent: FightNightPalette.gold, width: width, height: height, locked: locked, isHeld: controller.modifiers.guarding, onRing: true) {
                        controller.guardButton(active: $0)
                    }
                    HoldButton(symbol: "arrow.right", label: loc.t(.moveRightAccessibility), accent: FightNightPalette.paper, width: width, height: height, locked: locked, onRing: true) { controller.move(x: 0, y: 1, active: $0) }
                }
                GridRow {
                    HoldButton(text: loc.t(.duckLeftControl), label: loc.t(.duckLeftAccessibility), accent: FightNightPalette.blue, width: width, height: height, locked: locked, isHeld: controller.modifiers.duckDirection == -1, onRing: true) {
                        controller.duckButton(direction: -1, active: $0)
                    }
                    HoldButton(symbol: "arrow.down", label: loc.t(.moveBackAccessibility), accent: FightNightPalette.paper, width: width, height: height, locked: locked, onRing: true) { controller.move(x: -1, y: 0, active: $0) }
                    HoldButton(text: loc.t(.duckRightControl), label: loc.t(.duckRightAccessibility), accent: FightNightPalette.red, width: width, height: height, locked: locked, isHeld: controller.modifiers.duckDirection == 1, onRing: true) {
                        controller.duckButton(direction: 1, active: $0)
                    }
                }
            }
        }
        .padding(5)
    }

    private func attackPad(width: CGFloat, height: CGFloat) -> some View {
            /// 공격 버튼 패드
            /// - 상단: 백스텝(ActionButton) — 길게 눌러도 동작은 즉시 트리거
            /// - 하단: 잽/크로스 버튼 — `controller.comboAttack(base:)`가 터치다운에 호출됨
        let locked = controller.snapshot.playerLocked
        let leftBase: Punch = controller.playerStance.usesLeftHand(for: .jab) ? .jab : .cross
        let rightBase: Punch = leftBase == .jab ? .cross : .jab
        let leftPunch = controller.selectedPunch(base: leftBase)
        let rightPunch = controller.selectedPunch(base: rightBase)
        let leftIdentifier = leftBase == .jab ? "JAB" : "CROSS"
        let rightIdentifier = rightBase == .jab ? "JAB" : "CROSS"
        return VStack(spacing: 6) {
            ActionButton(
                text: loc.t(.backstepAccessibility),
                symbol: "arrow.down.backward",
                color: RingControlPalette.surface,
                width: width * 2 + 8,
                height: 44,
                locked: locked,
                accessibility: loc.t(.backstepAccessibility),
                identifier: "BACKSTEP",
                onRing: true,
                action: controller.backstep
            )
            HStack(spacing: 7) {
                ActionButton(
                    text: leftPunch.controlLabel(for: loc.language),
                    color: RingControlPalette.jab,
                    foreground: FightNightPalette.ink,
                    width: width,
                    height: height,
                    locked: locked,
                    accessibility: leftPunch.localizedName(for: loc.language),
                    identifier: leftIdentifier,
                    subtitle: leftPunch == leftBase ? nil : "\(loc.t(.combinationControl)) · \(leftBase.controlLabel(for: loc.language))",
                    onRing: true,
                    action: { controller.comboAttack(base: leftBase) }
                )
                ActionButton(
                    text: rightPunch.controlLabel(for: loc.language),
                    color: RingControlPalette.cross,
                    foreground: FightNightPalette.ink,
                    width: width,
                    height: height,
                    locked: locked,
                    accessibility: rightPunch.localizedName(for: loc.language),
                    identifier: rightIdentifier,
                    subtitle: rightPunch == rightBase ? nil : "\(loc.t(.combinationControl)) · \(rightBase.controlLabel(for: loc.language))",
                    onRing: true,
                    action: { controller.comboAttack(base: rightBase) }
                )
            }
        }
    }

    private var pauseOverlay: some View {
            /// 경기 일시정지 오버레이
            /// - 재개 버튼은 `controller.pause()`를 트리거하여 토글 방식으로 동작
        VStack(spacing: 12) {
            Text(loc.t(.pausedTitle))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PreparationPalette.ink)
            Button(loc.t(.resumeButton), action: controller.pause)
                .buttonStyle(RivalMenuButtonStyle(primary: true, onPaper: true))
        }
        .padding(24)
        .rivalPaperSurface()
    }

    private func iconButton(_ symbol: String, accessibility: String, action: @escaping () -> Void) -> some View {
            /// 상단/우측의 작은 액션 버튼을 반환
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(accessibility)
    }
}

/// The caller preserves the existing KO/decision reveal timing; this view only presents confirmed data.
struct CombatRoundResultView: View {
    let snapshot: CombatSnapshot
    let onContinue: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        let knockout = snapshot.lastRoundWasKnockout
        let title = snapshot.lastRoundOutcome.title(knockout: knockout, language: loc.language)
        let titleColor: Color
        switch snapshot.lastRoundOutcome {
        case .playerWin:
            titleColor = PreparationPalette.player
        case .playerLoss:
            titleColor = PreparationPalette.rival
        case .draw:
            titleColor = PreparationPalette.ink
        }
        let rivalRead = snapshot.rivalRead.cornerReport(for: loc.language)
        return GeometryReader { proxy in
            Color.black.opacity(0.42).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(loc.t(.roundLabel)) \(snapshot.round)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PreparationPalette.secondary)
                                Text(title)
                                    .font(.title.weight(.semibold))
                                    .foregroundStyle(titleColor)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(loc.t(.scoreLabel))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PreparationPalette.secondary)
                                Text("\(snapshot.playerScore) : \(snapshot.enemyScore)")
                                    .font(.title2.weight(.bold)).monospacedDigit()
                                    .foregroundStyle(PreparationPalette.ink)
                            }
                        }
                        RoundRecordTable(snapshot: snapshot)
                        if knockout, let finishingPunch = snapshot.roundFinishingPunch {
                            Text("\(loc.t(.roundStatsFinishingBlowLabel)) · \(snapshot.roundFinishingBlowByPlayer ? loc.t(.leaderboardYouLabel) : "RIVAL") \(finishingPunch.localizedName(for: loc.language))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PreparationPalette.ink)
                        }
                        if let rivalRead {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.t(.roundStatsRivalCornerLabel))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(PreparationPalette.ink)
                                Text(rivalRead)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .foregroundStyle(PreparationPalette.secondary)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(CombatText.roundResult(snapshot, language: loc.language))
                    .accessibilityIdentifier("roundSummary")
                }
                .scrollBounceBehavior(.basedOnSize)
                Button(action: onContinue) {
                    Text(loc.t(.nextRoundButton)).frame(maxWidth: .infinity)
                }
                .buttonStyle(RivalMenuButtonStyle(primary: true, onPaper: true))
                .accessibilityIdentifier("nextRound")
                .disabled(!snapshot.canAdvanceRound)
                .opacity(snapshot.canAdvanceRound ? 1 : 0.45)
                .animation(.easeOut(duration: UIStyleKit.microDuration), value: snapshot.canAdvanceRound)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: 600, maxHeight: min(340, proxy.size.height - 24))
            .rivalPaperSurface()
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("roundResult")
        }
    }

}

/// Observes the presentation directly rather than waiting for the 0.08s HUD snapshot cadence.
/// The timer slot stays reserved through the KO break; it never overlaps the fading KO text.
struct CombatRoundClock: View {
    let snapshot: CombatSnapshot
    @ObservedObject var presentation: CombatPresentation
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        let phase = presentation.knockoutClockPhase
        let showsKnockout = phase == .visible
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("\(loc.t(.roundLabel)) \(snapshot.round)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FightNightPalette.paper.opacity(0.7))
                Spacer(minLength: 0)
                Text("\(snapshot.playerScore) : \(snapshot.enemyScore)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            Text(CombatText.roundTime(snapshot.time))
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .opacity(phase == .inactive ? 1 : 0)
                .frame(width: 100, height: 32)
                .overlay {
                    Text(CombatSignature.knockout.title(for: loc.language))
                        .font(.system(size: 26, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                        .opacity(showsKnockout ? 1 : 0)
                        // Opacity only, including Reduce Motion; reset cancels any residual fade.
                        .animation(phase == .inactive ? nil : .easeOut(duration: 0.10), value: showsKnockout)
                }
        }
        .frame(width: 100)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showsKnockout
            ? "\(CombatText.clock(snapshot, language: loc.language)), \(CombatSignature.knockout.title(for: loc.language))"
            : CombatText.clock(snapshot, language: loc.language))
        .accessibilityIdentifier("combatRoundClock")
    }
}

struct CombatFeedbackView: View {
    static let height: CGFloat = 18
    static let maximumWidth: CGFloat = 500

    static func topInset(safeAreaTop: CGFloat, isStory: Bool) -> CGFloat {
        max(isStory ? 77 : 61, safeAreaTop + (isStory ? 74 : 58))
    }

    @ObservedObject var presentation: CombatPresentation
    let message: String?
    @ObservedObject private var loc = LocalizationManager.shared
    @RivalReducedMotion private var reducedMotion

    var body: some View {
        Group {
            if let signature = presentation.signature, signature != .knockout {
                Text(signature.title(for: loc.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 1)
                    .background(Color(red: 0.025, green: 0.030, blue: 0.040).opacity(0.94))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(signature == .counterWindow ? Color(red: 0.28, green: 0.70, blue: 1) : Color.white.opacity(0.72))
                            .frame(height: 2)
                    }
                    .id(signature)
                    .transition(reducedMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    .accessibilityIdentifier("combatSignature")
            } else if presentation.signature == nil, let message,
                      !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: Self.maximumWidth, minHeight: Self.height, maxHeight: Self.height)
                    .background(FightNightPalette.ink.opacity(0.86), in: RoundedRectangle(cornerRadius: 3))
                    .accessibilityIdentifier("combatCommentary")
                    .accessibilityLabel(message)
                    .transaction { $0.animation = nil }
            }
        }
        .frame(height: Self.height)
        // Two calls share one lane; switching to commentary must not crossfade overlapping text.
        .animation(message == nil ? .easeOut(duration: UIStyleKit.microDuration) : nil,
                   value: presentation.signature)
    }
}

private struct IconButtonStyle: ButtonStyle {
    @RivalReducedMotion private var reducedMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.black.opacity(configuration.isPressed ? 0.72 : 0.86)))
            .overlay(Circle().stroke(.white.opacity(configuration.isPressed ? 0.45 : 0.26), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.96 : 1)
            .animation(.easeOut(duration: UIStyleKit.microDuration), value: configuration.isPressed)
    }
}

struct FighterMeter: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let health: Int
    let maximumHealth: Int
    let stamina: Double
    let color: Color
    let reverse: Bool
    let displayName: String
    let accessibilityName: String
    var onRing = false

    var body: some View {
        VStack(alignment: reverse ? .trailing : .leading, spacing: onRing ? 2 : 3) {
            HStack(spacing: 4) {
                if reverse {
                    Text(onRing ? "\(health)" : "HP \(health)")
                    Spacer(minLength: 0)
                    Text(displayName)
                } else {
                    Text(displayName)
                    Spacer(minLength: 0)
                    Text(onRing ? "\(health)" : "HP \(health)")
                }
            }
            .font(.system(size: 11, weight: .bold))
            .lineLimit(1).minimumScaleFactor(0.8)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.82))
            meter(value: Double(health) / Double(max(1, maximumHealth)), color: color, height: onRing ? 6 : 8)
            meter(value: stamina / 100, color: FightNightPalette.paper.opacity(0.8), height: onRing ? 2 : 3)
            Text("\(loc.t(.staminaLabel)) \(Int(stamina))")
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(FightNightPalette.paper.opacity(0.65))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, onRing ? 6 : 0)
        .padding(.vertical, onRing ? 3 : 0)
        .background(onRing ? FightNightPalette.ink : .clear)
        .frame(maxWidth: onRing ? .infinity : 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CombatText.fighter(name: accessibilityName, health: health, stamina: stamina, language: loc.language))
        .accessibilityIdentifier(reverse ? "combatRivalMeter" : "combatPlayerMeter")
    }

    private func meter(value: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(1, max(0, value))
            ZStack(alignment: reverse ? .trailing : .leading) {
                Rectangle().fill(Color(red: 0.14, green: 0.16, blue: 0.19))
                Rectangle().fill(color).frame(width: width)
            }
        }
        .frame(height: height)
    }
}

struct HoldButton: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let symbol: String?
    let text: String?
    let label: String
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    let locked: Bool
    let isHeld: Bool?
    let onRing: Bool
    let onPress: (Bool) -> Void
    @State private var isPressed = false
    @RivalReducedMotion private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    private var highlighted: Bool { !locked && (isHeld ?? isPressed) }

    init(symbol: String, label: String, accent: Color = .white.opacity(0.28), width: CGFloat = 56, height: CGFloat = 50, locked: Bool = false, isHeld: Bool? = nil, onRing: Bool = false, onPress: @escaping (Bool) -> Void) {
        self.symbol = symbol
        text = nil
        self.label = label
        self.accent = accent
        self.width = width
        self.height = height
        self.locked = locked
        self.isHeld = isHeld
        self.onRing = onRing
        self.onPress = onPress
    }

    init(text: String, label: String, accent: Color = .white.opacity(0.28), width: CGFloat = 56, height: CGFloat = 50, locked: Bool = false, isHeld: Bool? = nil, onRing: Bool = false, onPress: @escaping (Bool) -> Void) {
        symbol = nil
        self.text = text
        self.label = label
        self.accent = accent
        self.width = width
        self.height = height
        self.locked = locked
        self.isHeld = isHeld
        self.onRing = onRing
        self.onPress = onPress
    }

    var body: some View {
        let cornerRadius: CGFloat = onRing ? RingControlPalette.cornerRadius : UIStyleKit.combatControlCornerRadius
        let foreground: Color = onRing ? (highlighted ? FightNightPalette.ink : FightNightPalette.paper) : .white
        let background: Color = highlighted ? accent
            : (onRing ? RingControlPalette.surface : Color(red: 0.075, green: 0.085, blue: 0.105))
        let outline: Color = highlighted ? .white.opacity(0.8)
            : (onRing ? .white.opacity(0.12) : accent.opacity(0.6))
        let heldMark: Color = onRing ? FightNightPalette.ink : .white
        return Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .black))
            } else {
                Text(text ?? "")
                    .font(.system(size: 11, weight: .bold))
                    .fontWidth(.condensed)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(foreground)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(outline, lineWidth: highlighted ? 2 : 1)
        )
        .overlay(alignment: .bottom) {
            Capsule().fill(heldMark).frame(width: 18, height: 3)
                .padding(.bottom, 5).opacity(highlighted ? 1 : 0)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if locked {
                Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                    .padding(5).accessibilityHidden(true)
            }
        }
        .shadow(color: .black.opacity(onRing ? 0 : 0.28), radius: 3, y: 2)
        .opacity(locked ? 0.55 : 1)
        .saturation(locked ? 0.3 : 1)
        .scaleEffect(highlighted && !reducedMotion ? 0.98 : 1)
        .animation(.easeOut(duration: 0.07), value: highlighted)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 44, pressing: { pressing in
            guard !pressing || !locked else { return }
            guard pressing != isPressed else { return }
            isPressed = pressing
            onPress(pressing)
        }, perform: {})
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                onPress(false)
                isPressed = false
            }
        }
        .onDisappear {
            if isPressed { onPress(false) }
            isPressed = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(loc.t(locked ? .inputUnavailable : ((isHeld ?? isPressed) ? .controlHeld : .controlReleased)))
        .accessibilityHint(loc.t(.holdControlHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
        .accessibilityAction {
            guard !locked else { return }
            isPressed.toggle()
            onPress(isPressed)
        }
    }
}

struct ActionButton: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let text: String
    let symbol: String?
    let color: Color
    let foreground: Color
    let width: CGFloat
    let height: CGFloat
    let locked: Bool
    let accessibility: String?
    let identifier: String
    let subtitle: String?
    let onRing: Bool
    let action: () -> Void

    init(text: String, symbol: String? = nil, color: Color, foreground: Color = .white, width: CGFloat = 60, height: CGFloat = 44, locked: Bool = false, accessibility: String? = nil, identifier: String? = nil, subtitle: String? = nil, onRing: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.symbol = symbol
        self.color = color
        self.foreground = foreground
        self.width = width
        self.height = height
        self.locked = locked
        self.accessibility = accessibility
        self.identifier = identifier ?? text
        self.subtitle = subtitle
        self.onRing = onRing
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    if let symbol { Image(systemName: symbol) }
                    Text(text)
                }
                .font(.system(size: symbol == nil && height >= 60 ? 17 : 11, weight: .bold))
                .fontWidth(.condensed)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .opacity(0.72)
                        .accessibilityHidden(true)
                }
            }
                .foregroundStyle(foreground)
                .frame(width: width, height: height)
        }
        .buttonStyle(AttackButtonStyle(color: color, foreground: foreground, locked: locked, combination: subtitle != nil, onRing: onRing))
        .disabled(locked)
        .accessibilityLabel(accessibility ?? text)
        .accessibilityValue(locked ? loc.t(.inputUnavailable) : (subtitle != nil ? loc.t(.combinationControl) : ""))
        .accessibilityHint(symbol == nil ? loc.t(.comboAccessibilityHint) : "")
        .accessibilityIdentifier(identifier)
    }
}

private struct AttackButtonStyle: PrimitiveButtonStyle {
    let color: Color
    let foreground: Color
    let locked: Bool
    let combination: Bool
    let onRing: Bool

    func makeBody(configuration: Configuration) -> some View {
        ImmediateAttackSurface(label: configuration.label, color: color, foreground: foreground, locked: locked,
                               combination: combination, onRing: onRing, trigger: configuration.trigger)
    }
}

/// Capture the held modifier on touch-down, not after the attack finger lifts. Drag cancellation
/// resets only the touch latch; it never repeats an attack or adds another action on release.
private struct ImmediateAttackSurface<Label: View>: View {
    let label: Label
    let color: Color
    let foreground: Color
    let locked: Bool
    let combination: Bool
    let onRing: Bool
    let trigger: () -> Void
    @GestureState private var touching = false
    @State private var fired = false
    @RivalReducedMotion private var reducedMotion

    var body: some View {
        let pressed = touching && !locked
        label
            .background(
                RoundedRectangle(cornerRadius: onRing ? RingControlPalette.cornerRadius : UIStyleKit.combatControlCornerRadius, style: .continuous)
                    .fill(color)
                    .brightness(pressed ? 0.12 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: onRing ? RingControlPalette.cornerRadius : UIStyleKit.combatControlCornerRadius, style: .continuous)
                    .stroke(foreground.opacity(pressed ? 0.85 : (combination ? 0.65 : 0.24)), lineWidth: pressed || combination ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(foreground).padding(6).accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(onRing ? 0 : 0.3), radius: 3, y: 2)
            .opacity(locked ? 0.55 : 1)
            .saturation(locked ? 0.3 : 1)
            .scaleEffect(pressed && !reducedMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.07), value: pressed)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($touching) { _, value, _ in value = true }
                .onChanged { _ in
                    guard !locked, !fired else { return }
                    fired = true
                    trigger()
                }
                .onEnded { _ in fired = false })
            .onChange(of: touching) { _, value in if !value { fired = false } }
            .onDisappear { fired = false }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if !locked { trigger() } }
    }
}

struct FightButtonStyle: ButtonStyle {
    @RivalReducedMotion private var reducedMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .lineLimit(2).minimumScaleFactor(0.8)
            .foregroundStyle(FightNightPalette.ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: UIStyleKit.controlCornerRadius, style: .continuous)
                    .fill(FightNightPalette.paper)
                    .brightness(configuration.isPressed ? -0.10 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIStyleKit.controlCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.98 : 1)
            .animation(.easeOut(duration: UIStyleKit.microDuration), value: configuration.isPressed)
    }
}

/// The style/outfit selection screen. Reused both from the in-fight settings menu and directly from the
/// main menu (so players can gear up before ever starting a fight) — extracted out of `GameView` so both
/// call sites share one implementation instead of two copies.
extension OutfitID {
    var lockerSampleAssetName: String { "LockerOutfit-\(rawValue)" }
}

extension FightStyle {
    var lockerSampleAssetName: String { "LockerStyle-\(rawValue)" }
}

struct WaitingRoomView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var purchases = StoryPurchaseStore.shared
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    @RivalReducedMotion private var reducedMotion
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 12
    private enum LockerTab { case styles, outfits, stances, storyRewards }
    @State private var tab = LockerTab.styles
    @State private var previewAppearance: StoryOpponent?
    @State private var previewsSouthpawStance = false
    @State private var showsStoryPurchase = false

    // Decoupled from `controller.equippedOutfit` so tapping a LOCKED outfit can preview its look in the 3D
    // rig above without actually equipping it (equipping still requires the outfit to be unlocked).
    @State private var previewOutfit: OutfitID

    private let storyOpponent: StoryOpponent?
    private let onChallenge: (() -> Void)?

    init(controller: GameController, storyOpponent: StoryOpponent? = nil,
         onChallenge: (() -> Void)? = nil, onClose: @escaping () -> Void) {
        self.controller = controller
        self.storyOpponent = storyOpponent
        self.onChallenge = onChallenge
        self.onClose = onClose
        _previewOutfit = State(initialValue: controller.equippedOutfit)
        _previewAppearance = State(initialValue: controller.equippedAppearance)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PreparationPalette.paper.ignoresSafeArea()
                if !showsStoryPurchase {
                    VStack(spacing: 10) {
                        preparationHeader
                        if dynamicType.isAccessibilitySize {
                            lockerTabs
                            lockerChoices
                        } else {
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 6) {
                                    StylePreviewView(style: controller.playerStyle, outfit: previewOutfit, appearance: previewAppearance,
                                        championBelt: controller.championBeltEquipped, southpawPreview: previewsSouthpawStance,
                                        preparationBackground: UIColor(PreparationPalette.paper), enlargedPreview: true)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .clipped()
                                        .accessibilityLabel(loc.t(.previewCharacterAccessibility))
                                        .accessibilityIdentifier("lockerBoxerPreview")
                                    previewSummary
                                }
                                .frame(width: max(0, (proxy.size.width - 60) * 0.40))
                                VStack(spacing: 8) {
                                    lockerTabs
                                    lockerChoices
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        preparationActions
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .foregroundStyle(PreparationPalette.ink)
                    .rivalPanelTransition()
                }
                if showsStoryPurchase {
                    StoryPurchaseView(store: purchases, onClose: { showsStoryPurchase = false },
                        onUnlocked: { showsStoryPurchase = false })
                        .rivalPanelTransition()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .animation(.easeOut(duration: reducedMotion ? UIStyleKit.microDuration : UIStyleKit.fastDuration),
                   value: showsStoryPurchase)
        .onAppear {
            controller.refreshStoryEquipment()
            previewsSouthpawStance = controller.playerStance == .southpaw
        }
        .task { await purchases.refreshAccess() }
    }

    private var preparationHeader: some View {
        HStack(spacing: 12) {
            Text("RIVAL")
                .font(.system(size: 18, weight: .bold))
                .accessibilityHidden(true)
            Text(storyOpponent?.title(for: loc.language) ?? loc.t(.waitingRoomButton))
                .font(.system(size: labelSize, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .layoutPriority(-1)
                .accessibilityIdentifier("lockerTitle")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Label(loc.t(.close), systemImage: "arrow.left")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(RivalMenuButtonStyle(onPaper: true))
            .accessibilityIdentifier("waitingRoomClose")
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(PreparationPalette.rule).frame(height: 1) }
    }

    private var preparationActions: some View {
        HStack(spacing: 12) {
            if !dynamicType.isAccessibilitySize {
                Text(storyOpponent == nil ? loc.t(.waitingRoomSubtitle) : loc.t(.lockerPreparation))
                    .font(.system(size: detailSize, weight: .medium))
                    .foregroundStyle(PreparationPalette.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            Button(action: onChallenge ?? onClose) {
                Label(loc.t(onChallenge == nil ? .lockerReady : .menuFightAction), systemImage: "arrow.right")
                    .lineLimit(2)
                    .frame(maxWidth: dynamicType.isAccessibilitySize ? .infinity : nil)
            }
            .buttonStyle(RivalMenuButtonStyle(primary: true, onPaper: true))
            .accessibilityIdentifier(onChallenge == nil ? "lockerDone" : "storyStartFresh")
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(PreparationPalette.rule).frame(height: 1) }
    }

    private var lockerTabs: some View {
        HStack(spacing: 2) {
            lockerTab(.styles, title: loc.t(.styleTabLabel), identifier: "lockerStyleTab")
            lockerTab(.outfits, title: loc.t(.outfitLabel), identifier: "lockerOutfitTab")
            lockerTab(.stances, title: loc.story(.stance).localizedCapitalized, identifier: "lockerStanceTab")
            lockerTab(.storyRewards, title: loc.story(.title), identifier: "lockerStoryTab")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lockerTabs")
    }

    private func lockerTab(_ candidate: LockerTab, title: String, identifier: String) -> some View {
        Button { tab = candidate } label: {
            Text(title)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(tab == candidate ? PreparationPalette.ink : PreparationPalette.secondary)
                .lineLimit(2)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(tab == candidate ? PreparationPalette.ink : PreparationPalette.rule)
                        .frame(height: tab == candidate ? 2 : 1)
                }
                .animation(reducedMotion ? nil : .easeOut(duration: UIStyleKit.fastDuration), value: tab)
        }
        .buttonStyle(RivalPlainButtonStyle())
        .accessibilityAddTraits(tab == candidate ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var lockerChoices: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                switch tab {
                case .outfits:
                    sectionTitle(loc.t(.lockerOutfitsTitle))
                    selectedOutfitDetails
                    LazyVGrid(columns: choiceColumns, alignment: .leading, spacing: 8) {
                        ForEach(OutfitID.allCases.filter { $0 != .storyStarter && $0 != .storyChampion }, id: \.self) {
                            outfitButton($0)
                        }
                    }
                    Text(loc.t(.lockerSelectionHint))
                        .font(.system(size: detailSize))
                        .foregroundStyle(PreparationPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .storyRewards:
                    rewardHeader(.storyRewards, detail: .storyRewardsDetail)
                    if !purchases.hasStoryAccess {
                        Button { showsStoryPurchase = true } label: {
                            Label(loc.purchase(.purchaseToEarn), systemImage: "lock.open")
                                .lineLimit(2).minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(RivalMenuButtonStyle(onPaper: true))
                        .accessibilityIdentifier("lockerStoryPurchase")
                    }
                    rewardHeader(.instantRewards, detail: .starterOutfitDetail)
                    ForEach(StoryPurchaseReward.purchaseRewards) { storyRewardRow($0) }
                    Rectangle().fill(PreparationPalette.rule).frame(height: 1).padding(.vertical, 4)
                    rewardHeader(.earnedRewards, detail: .rewardsRequireVictory)
                    ForEach(StoryPurchaseReward.victoryRewards) { storyRewardRow($0) }
                    southpawStanceReward
                case .styles:
                    sectionTitle(loc.t(.lockerStylesTitle))
                    LazyVGrid(columns: choiceColumns, alignment: .leading, spacing: 8) {
                        ForEach(FightStyle.allCases, id: \.self) { styleButton($0) }
                    }
                    Text(controller.playerStyle.summary(for: loc.language))
                        .font(.system(size: detailSize))
                        .foregroundStyle(PreparationPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("lockerSelectedStyleDetail")
                case .stances:
                    sectionTitle(loc.t(.lockerStancesTitle))
                    orthodoxStanceButton
                    southpawStanceReward
                }
            }
            .padding(.bottom, 8)
            .foregroundStyle(PreparationPalette.ink)
        }
        .id(tab)
        .transition(.opacity)
        .scrollIndicators(.visible)
        .accessibilityIdentifier("lockerOptions")
        .animation(reducedMotion ? nil : .easeOut(duration: UIStyleKit.fastDuration), value: tab)
    }

    private var choiceColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicType.isAccessibilitySize ? 1 : 3)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: labelSize, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private func outfitRequirement(_ outfit: OutfitID) -> String {
        !purchases.hasStoryAccess && controller.championOutfitEarned
            && (outfit == .champion || outfit == .storyChampion)
            ? loc.purchase(.storyAccessRequired) : outfit.unlockDescription(for: loc.language)
    }

    private var selectedOutfitDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicType.isAccessibilitySize {
                Text("\(previewAppearance?.title(for: loc.language) ?? previewOutfit.label(for: loc.language)) · \(loc.t(previewIsEquipped ? .outfitEquippedLabel : .outfitPreviewLabel))")
                    .font(.system(size: labelSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lockerPreviewStatus")
            } else {
                Text(previewAppearance?.title(for: loc.language) ?? previewOutfit.label(for: loc.language))
                    .font(.system(size: labelSize, weight: .semibold))
            }
            Text(previewAppearance.map { appearanceRequirement($0) } ?? outfitRequirement(previewOutfit))
                .font(.system(size: detailSize))
                .foregroundStyle(PreparationPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lockerSelectedOutfitRequirement")
        }
        .padding(.top, 4)
    }

    private func rewardHeader(_ title: StoryPurchaseText, detail: StoryPurchaseText) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(loc.purchase(title))
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(PreparationPalette.ink)
                .accessibilityAddTraits(.isHeader)
            if !dynamicType.isAccessibilitySize {
                Text(loc.purchase(detail))
                    .font(.system(size: detailSize, weight: .medium))
                    .foregroundStyle(PreparationPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func storyRewardRow(_ reward: StoryPurchaseReward) -> some View {
        switch reward {
        case .starterOutfit: outfitButton(.storyStarter)
        case .appearance(let opponent): appearanceButton(opponent)
        case .championOutfit: outfitButton(.storyChampion)
        case .championBelt: championBeltReward
        }
    }

    @ViewBuilder
    private var championBeltReward: some View {
        if controller.championBeltUnlocked {
            Toggle(isOn: Binding(get: { controller.championBeltEquipped },
                set: { equipped in controller.setChampionBeltEquipped(equipped) })) {
                Label(loc.story(.championBelt), systemImage: "medal.fill")
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(PreparationPalette.ink)
            }
            .tint(PreparationPalette.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .accessibilityIdentifier("lockerChampionBelt")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(loc.story(.championBelt), systemImage: "lock.fill")
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(PreparationPalette.ink)
                Text(controller.championBeltEarned && !purchases.hasStoryAccess
                    ? loc.purchase(.storyAccessRequired)
                    : StoryPurchaseReward.championBelt.requirement(for: loc.language))
                    .font(.system(size: detailSize, weight: .medium))
                    .foregroundStyle(PreparationPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rivalSelection(isSelected: false, onPaper: true)
        }
    }

    private var previewIsEquipped: Bool {
        previewAppearance == controller.equippedAppearance
            && (previewAppearance != nil || previewOutfit == controller.equippedOutfit)
    }

    private var previewSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(controller.playerStyle.label(for: loc.language))
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(PreparationPalette.ink)
                    .layoutPriority(1)
                    .accessibilityIdentifier("lockerSelectedStyle")
                Spacer(minLength: 0)
                Text("\(loc.story(.stance)): \(loc.story(previewsSouthpawStance ? .southpawStance : .orthodox)) · \(loc.t(previewsSouthpawStance == (controller.playerStance == .southpaw) ? .outfitEquippedLabel : .outfitPreviewLabel))")
                    .font(.system(size: detailSize, weight: .medium))
                    .foregroundStyle(PreparationPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lockerStancePreviewStatus")
            }
            Text("\(previewAppearance?.title(for: loc.language) ?? previewOutfit.label(for: loc.language)) · \(loc.t(previewIsEquipped ? .outfitEquippedLabel : .outfitPreviewLabel))")
                .font(.system(size: detailSize, weight: .medium))
                .foregroundStyle(PreparationPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lockerPreviewStatus")
        }
    }

    private var orthodoxStanceButton: some View {
        Button {
            previewsSouthpawStance = false
            controller.setPlayerStance(.orthodox)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(loc.story(.orthodox).localizedCapitalized,
                      systemImage: controller.playerStance == .orthodox ? "checkmark.circle.fill" : "figure.boxing")
                    .font(.system(size: labelSize, weight: .semibold))
                if !dynamicType.isAccessibilitySize || !controller.canChangeStance {
                    Text(controller.canChangeStance ? loc.t(controller.playerStance == .orthodox ? .outfitEquippedLabel : .outfitOwnedLabel)
                        : loc.story(.stanceBeforeMatch))
                        .font(.system(size: detailSize))
                        .foregroundStyle(PreparationPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .rivalSelection(isSelected: !previewsSouthpawStance, onPaper: true)
        }
        .buttonStyle(RivalPlainButtonStyle())
        .accessibilityIdentifier("lockerStance-orthodox")
        .accessibilityAddTraits(!previewsSouthpawStance ? .isSelected : [])
    }

    private var southpawStanceReward: some View {
        let unlocked = controller.isStanceUnlocked(.southpaw)
        let equipped = controller.playerStance == .southpaw
        let requirementText = Text(loc.purchase(.southpawUnlockRequirement))
            .font(.system(size: detailSize, weight: .regular))
            .foregroundStyle(PreparationPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        let statusText = Text(!unlocked ? loc.purchase(.stancePreviewOnly) : !controller.canChangeStance ? loc.story(.stanceBeforeMatch)
            : loc.t(equipped ? .outfitEquippedLabel : .outfitPreviewLabel))
            .font(.system(size: detailSize, weight: .medium))
            .foregroundStyle(PreparationPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                previewsSouthpawStance = true
                controller.setPlayerStance(.southpaw)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(loc.story(.southpawStance), systemImage: unlocked ? (equipped ? "checkmark.circle.fill" : "figure.boxing") : "lock.fill")
                        .font(.system(size: labelSize, weight: .semibold))
                    if !dynamicType.isAccessibilitySize {
                        requirementText
                        statusText
                    }
                }
                .foregroundStyle(PreparationPalette.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .rivalSelection(isSelected: previewsSouthpawStance, onPaper: true)
            }
            .buttonStyle(RivalPlainButtonStyle())
            .accessibilityIdentifier("lockerStance-southpaw")
            .accessibilityLabel("\(loc.story(.southpawStance)), \(loc.t(equipped ? .outfitEquippedLabel : .outfitPreviewLabel)), \(loc.purchase(.southpawUnlockRequirement))")
            .accessibilityAddTraits(previewsSouthpawStance ? .isSelected : [])
            if dynamicType.isAccessibilitySize {
                requirementText.padding(.horizontal, 14)
                statusText.padding(.horizontal, 14)
            }
        }
    }

    private func styleButton(_ style: FightStyle) -> some View {
        let isSelected = controller.playerStyle == style
        return Button {
            controller.setPlayerStyle(style)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                if !dynamicType.isAccessibilitySize {
                    Image(style.lockerSampleAssetName)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .accessibilityHidden(true)
                }
                HStack {
                    Text(style.label(for: loc.language))
                        .font(.system(size: labelSize, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
                }
            }
            .foregroundStyle(PreparationPalette.ink)
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .rivalSelection(isSelected: isSelected, onPaper: true)
        }
        .buttonStyle(RivalPlainButtonStyle())
        .accessibilityLabel("\(style.label(for: loc.language)), \(style.summary(for: loc.language))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("lockerStyle-\(style.rawValue)")
    }

    private func outfitButton(_ outfit: OutfitID) -> some View {
        let unlocked = controller.isOutfitUnlocked(outfit)
        let isEquipped = controller.equippedOutfit == outfit && controller.equippedAppearance == nil
        let isPreviewing = previewOutfit == outfit && previewAppearance == nil
        let requirement = outfitRequirement(outfit)
        let status = loc.t(isEquipped ? .outfitEquippedLabel : unlocked ? .outfitOwnedLabel : .outfitPreviewLabel)
        let isStoryOutfit = outfit == .storyStarter || outfit == .storyChampion
        let requirementText = Text(requirement)
            .font(.system(size: detailSize, weight: .regular))
            .foregroundStyle(PreparationPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                // Always update the live 3D preview, even for a locked outfit -- only actually equip it
                // (persist as the outfit worn into real matches) once it's unlocked.
                previewOutfit = outfit
                previewAppearance = nil
                if unlocked {
                    controller.setEquippedOutfit(outfit)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if !dynamicType.isAccessibilitySize {
                        Image(outfit.lockerSampleAssetName)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 5) {
                        if !unlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(outfit.label(for: loc.language))
                            .font(.system(size: labelSize, weight: .semibold))
                        if isEquipped {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PreparationPalette.ink)
                        }
                        Spacer(minLength: 0)
                        if dynamicType.isAccessibilitySize {
                            Text(!unlocked && !isPreviewing ? loc.story(.locked) : status)
                                .font(.system(size: detailSize, weight: .medium))
                                .foregroundStyle(PreparationPalette.secondary)
                        }
                    }
                    if !dynamicType.isAccessibilitySize {
                        Text(!unlocked && !isPreviewing ? loc.story(.locked) : status)
                            .font(.system(size: detailSize, weight: .medium))
                            .foregroundStyle(PreparationPalette.secondary)
                    }
                    if isStoryOutfit && !dynamicType.isAccessibilitySize {
                        requirementText
                    }
                }
                .foregroundStyle(PreparationPalette.ink)
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .rivalSelection(isSelected: isPreviewing, onPaper: true)
            }
            .buttonStyle(RivalPlainButtonStyle())
            .accessibilityAddTraits(isPreviewing ? .isSelected : [])
            .accessibilityIdentifier("lockerOutfit-\(outfit.rawValue)")
            .accessibilityLabel(
                unlocked
                    ? "\(outfit.label(for: loc.language)), \(status)"
                    : "\(outfit.label(for: loc.language)), \(loc.story(.locked)), \(loc.t(.outfitPreviewLabel)), \(requirement)"
            )
            if isStoryOutfit && dynamicType.isAccessibilitySize {
                requirementText.padding(.horizontal, 8)
                    .accessibilityIdentifier("lockerOutfitRequirement-\(outfit.rawValue)")
            }
        }
    }

    private func appearanceRequirement(_ opponent: StoryOpponent) -> String {
        opponent == .southpaw ? StoryPurchaseReward.appearance(opponent).requirement(for: loc.language)
            : controller.clearedStoryOpponents.contains(opponent) && !purchases.hasStoryAccess
            ? loc.purchase(.storyAccessRequired)
            : StoryPurchaseReward.appearance(opponent).requirement(for: loc.language)
    }

    private func appearanceButton(_ opponent: StoryOpponent) -> some View {
        let available = opponent.hasAppearance
        let unlocked = controller.isAppearanceUnlocked(opponent)
        let equipped = controller.equippedAppearance == opponent
        let previewing = previewAppearance == opponent
        let title = StoryPurchaseReward.appearance(opponent).title(for: loc.language)
        let requirement = appearanceRequirement(opponent)
        let requirementText = Text(!available ? loc.story(.unavailable) : requirement)
            .font(.system(size: detailSize, weight: .regular))
            .foregroundStyle(PreparationPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        return VStack(alignment: .leading, spacing: 3) {
            Button {
                guard available else { return }
                previewAppearance = opponent
                if unlocked { controller.setEquippedAppearance(opponent) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if !dynamicType.isAccessibilitySize {
                            Image(opponent.storyBustAssetName)
                                .resizable().scaledToFit().frame(width: 36, height: 36)
                                .accessibilityHidden(true)
                        }
                        if !unlocked || !available { Image(systemName: "lock.fill").accessibilityHidden(true) }
                        Text(title).font(.system(size: labelSize, weight: .semibold))
                            .lineLimit(2).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if equipped { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                    }
                    if (!unlocked || !available) && !dynamicType.isAccessibilitySize {
                        requirementText
                    }
                }
                .foregroundStyle(PreparationPalette.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .rivalSelection(isSelected: previewing, onPaper: true)
            }
            .buttonStyle(RivalPlainButtonStyle())
            .disabled(!available)
            .opacity(available ? 1 : 0.45)
            .accessibilityAddTraits(previewing ? .isSelected : [])
            .accessibilityIdentifier("lockerAppearance-\(opponent.rawValue)")
            .accessibilityLabel("\(title), \(loc.t(equipped ? .outfitEquippedLabel : .outfitPreviewLabel))")
            .accessibilityHint(unlocked ? "" : requirement)
            if (!unlocked || !available) && dynamicType.isAccessibilitySize {
                requirementText.padding(.horizontal, 14)
            }
        }
    }
}

/// The single consolidated settings surface: sound + haptics toggles everywhere, plus context-specific
/// extras — mid-fight (`onExitToMenu` provided) adds an exit-to-main-menu row; the main menu
/// (`showsLanguageRow: true`) adds a language picker instead. Deliberately narrow (exactly 3 rows in each
/// context) rather than one big shared menu with everything visible at once.
struct SettingsMenuView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var haptics = HapticsManager.shared
    var showsLanguageRow = false
    var onExitToMenu: (() -> Void)? = nil
    var onClose: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 13

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MainMenuPalette.background.opacity(0.76).ignoresSafeArea()
                VStack(spacing: 12) {
                    RivalScreenHeader(kicker: loc.t(.settingsKicker), title: loc.t(.settingsTitle),
                                      closeTitle: loc.t(.close), closeID: "settingsClose", onClose: onClose, onPaper: true)
                    ScrollView {
                        VStack(spacing: 8) {
                            settingsRow(
                                symbol: controller.isSoundMuted ? "speaker.slash" : "speaker.wave.2",
                                title: controller.isSoundMuted ? loc.t(.soundOff) : loc.t(.soundOn),
                                enabled: !controller.isSoundMuted, id: "settingsSound"
                            ) { controller.setSoundMuted(!controller.isSoundMuted) }
                            settingsRow(
                                symbol: "iphone.radiowaves.left.and.right",
                                title: haptics.isEnabled ? loc.t(.hapticsOn) : loc.t(.hapticsOff),
                                enabled: haptics.isEnabled, id: "settingsHaptics"
                            ) { haptics.setEnabled(!haptics.isEnabled) }
                            if showsLanguageRow { languageRow.padding(.top, 4) }
                            if let onExitToMenu {
                                settingsRow(symbol: "rectangle.portrait.and.arrow.right", title: loc.t(.exitToMenu),
                                            enabled: nil, id: "settingsExit", action: onExitToMenu)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(20)
                .frame(width: min(390, proxy.size.width - 32), height: min(346, proxy.size.height - 24))
                .rivalPaperSurface()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t(.language))
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(PreparationPalette.secondary)
            HStack(spacing: 8) {
                ForEach(AppLanguage.allCases, id: \.self) { candidate in
                    let isSelected = loc.language == candidate
                    Button {
                        loc.setLanguage(candidate)
                    } label: {
                        Text(candidate.nativeName)
                            .font(.system(size: labelSize, weight: .semibold))
                            .foregroundStyle(PreparationPalette.ink)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .rivalSelection(isSelected: isSelected, onPaper: true)
                    }
                    .buttonStyle(RivalPlainButtonStyle())
                    .accessibilityLabel(candidate.nativeName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func settingsRow(symbol: String, title: String, enabled: Bool?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: labelSize, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: enabled.map { $0 ? "checkmark.circle.fill" : "circle" } ?? "arrow.up.right")
                    .foregroundStyle(PreparationPalette.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(PreparationPalette.ink)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .rivalSelection(isSelected: enabled == true, onPaper: true)
        }
        .buttonStyle(RivalPlainButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(enabled == true ? .isSelected : [])
    }
}

/// The "reset rival learning" confirmation — shared by the main menu's "새로하기" flow (its own default
/// entry point; in-fight settings no longer offers a reset shortcut, so this is main-menu-only now).
struct LearningResetConfirmView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var bodySize: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MainMenuPalette.background.opacity(0.76).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    RivalScreenHeader(kicker: loc.t(.resetKicker), title: loc.t(.newGameButton),
                                      closeTitle: loc.t(.cancel), closeID: "resetCancel", onClose: onCancel, onPaper: true)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(loc.t(.resetConfirmTitle))
                                .font(.system(size: bodySize, weight: .semibold))
                                .foregroundStyle(PreparationPalette.ink)
                            Text(loc.t(.resetConfirmBody))
                                .font(.system(size: bodySize, weight: .regular))
                                .foregroundStyle(PreparationPalette.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    Button(role: .destructive, action: onConfirm) {
                        Text(loc.t(.resetConfirmButton)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RivalMenuButtonStyle(destructive: true, onPaper: true))
                    .accessibilityLabel(loc.t(.resetConfirmButton))
                    .accessibilityIdentifier("resetConfirm")
                }
                .padding(20)
                .frame(width: min(420, proxy.size.width - 32), height: min(326, proxy.size.height - 24))
                .rivalPaperSurface()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
