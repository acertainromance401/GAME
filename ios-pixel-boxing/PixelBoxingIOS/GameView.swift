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
                .accessibilityHidden(controller.isPlayingStoryScene || (controller.storyBout != nil
                    && (showsSettings || controller.snapshot.phase == .paused
                        || (controller.storyBout?.phase == .finished && controller.snapshot.showsRoundResult))))

                CombatSignatureView(presentation: controller.presentation)
                    .opacity(controller.isPlayingStoryScene ? 0 : 1)
                    .padding(.top, max(68, proxy.safeAreaInsets.top + 64))
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
                            onRivalScene: storyRivalSceneAction)
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
        .padding(.trailing, max(14, safeAreaInsets.trailing + 8))
        .padding(.top, max(6, safeAreaInsets.top + 4))
    }

    private func battleHUD(safeAreaInsets: EdgeInsets) -> some View {
            /// 상단 전투 HUD
            /// - 왼쪽/오른쪽에 체력(HP)·스태미나 바(`FighterMeter`)
            /// - 중앙에 라운드/타이머/스코어/토스트 메시지를 표시
            /// - 접근성 라벨은 HUD의 핵심 정보(라운드/남은 시간/스코어)를 음성으로 읽을 수 있게 구성
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                FighterMeter(
                    health: controller.snapshot.playerHP,
                    maximumHealth: controller.engine.player.maximumHealth,
                    stamina: controller.snapshot.playerStamina,
                    color: Color(red: 0.18, green: 0.82, blue: 1),
                    reverse: false,
                    displayName: "ME",
                    accessibilityName: loc.t(.playerAccessibility)
                )
                if let bout = controller.storyBout {
                    StoryRoundClock(bout: bout, remainingTime: controller.snapshot.time, presentation: controller.presentation)
                } else {
                    CombatRoundClock(snapshot: controller.snapshot, presentation: controller.presentation)
                }
                FighterMeter(
                    health: controller.snapshot.enemyHP,
                    maximumHealth: controller.engine.enemy.maximumHealth,
                    stamina: controller.snapshot.enemyStamina,
                    color: Color(red: 1, green: 0.25, blue: 0.40),
                    reverse: true,
                    displayName: controller.storyBout?.opponent.title(for: loc.language) ?? "RIVAL",
                    accessibilityName: controller.storyBout?.opponent.title(for: loc.language) ?? loc.t(.rivalAccessibility)
                )
            }
            .padding(.horizontal, 16)
            .padding(.trailing, 48)
            .padding(.bottom, 6)

            Text(controller.snapshot.message)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: 410, minHeight: 18)
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .background(.black.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, max(5, safeAreaInsets.top + 2))
        // Live values never crossfade. Only the clock's KO label and separate counter cue animate.
        .transaction { $0.animation = nil }
    }

    /// Revealed after the KO fall (or a short decision break), never over the finishing impact itself.
    private var roundResultOverlay: some View {
            /// 라운드 결과 패널
            /// - KO 또는 판정으로 라운드가 끝난 뒤 보여지는 오버레이
            /// - 승/패/무에 따라 색상과 텍스트가 달라지며, 회피·상대의 주요 공격·결정타 등의 통계를 표시
            /// - `controller.continueToNextRound()`가 버튼 액션으로 연결되어 다음 라운드로 진행
        let outcome = controller.snapshot.lastRoundOutcome
        let knockout = controller.snapshot.lastRoundWasKnockout
        let title = outcome.title(knockout: knockout, language: loc.language)
        let color: Color
        let titleColor: Color
        switch outcome {
        case .playerWin:
            color = Color(red: 0.035, green: 0.29, blue: 0.70)
            titleColor = Color(red: 0.20, green: 0.62, blue: 1.0)
        case .playerLoss:
            color = Color(red: 0.68, green: 0.035, blue: 0.11)
            titleColor = Color(red: 1.0, green: 0.20, blue: 0.26)
        case .draw:
            color = Color(red: 0.72, green: 0.50, blue: 0.02)
            titleColor = Color(red: 1.0, green: 0.78, blue: 0.12)
        }
        let snapshot = controller.snapshot
        let rivalRead = snapshot.rivalRead.cornerReport(for: loc.language)
        return VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 32, weight: .black, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(titleColor)
                Text("\(snapshot.playerScore) : \(snapshot.enemyScore)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 26) {
                    roundStatColumn(name: "ME", dodgeCount: snapshot.roundPlayerDodgeCount, topAttack: snapshot.roundPlayerTopAttack)
                    roundStatColumn(name: "RIVAL", dodgeCount: snapshot.roundEnemyDodgeCount, topAttack: snapshot.roundEnemyTopAttack)
                }
                .padding(.top, 2)
                if knockout, let finishingPunch = snapshot.roundFinishingPunch {
                    Text("\(loc.t(.roundStatsFinishingBlowLabel)) · \(snapshot.roundFinishingBlowByPlayer ? "ME" : "RIVAL") \(finishingPunch.localizedName(for: loc.language))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(titleColor.opacity(0.9))
                        .padding(.top, 2)
                }
                if let rivalRead {
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(titleColor.opacity(0.45))
                            .frame(width: 28, height: 2)
                        Text(loc.t(.roundStatsRivalCornerLabel))
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(titleColor.opacity(0.9))
                        Text(rivalRead)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: 280)
                    }
                    .padding(.top, 3)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(CombatText.roundResult(snapshot, language: loc.language))

            Button(loc.t(.nextRoundButton)) {
                controller.continueToNextRound()
            }
            .buttonStyle(FightButtonStyle())
            .accessibilityIdentifier("nextRound")
            .disabled(!snapshot.canAdvanceRound)
            .opacity(snapshot.canAdvanceRound ? 1 : 0.45)
            .animation(.easeOut(duration: 0.2), value: snapshot.canAdvanceRound)
            .accessibilityLabel(loc.t(.nextRoundButton))
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 20)
        .glowPanel(accent: color)
    }

    private func roundStatColumn(name: String, dodgeCount: Int, topAttack: Punch?) -> some View {
            /// 라운드 결과 내의 통계 열(플레이어 또는 라이벌)
            /// - `name`: 컬럼 상단 이름("ME" / "RIVAL")
            /// - `dodgeCount`: 해당 플레이어의 회피 성공 횟수
            /// - `topAttack`: 가장 많이 사용된 공격(없으면 `nil`)
        VStack(spacing: 4) {
            Text(name)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Text("\(loc.t(.roundStatsDodgeLabel)) \(dodgeCount)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
            Text("\(loc.t(.roundStatsTopAttackLabel)) \(topAttack?.localizedName(for: loc.language) ?? loc.t(.roundStatsNoAttack))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(minWidth: 96)
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
        .padding(.leading, max(4, safeAreaInsets.leading))
        .padding(.trailing, max(4, safeAreaInsets.trailing))
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
                    HoldButton(text: loc.t(.weaveLeftControl), label: loc.t(.weaveLeftAccessibility), accent: Color(red: 0.035, green: 0.29, blue: 0.70), width: width, height: height, locked: locked) {
                        controller.weaveButton(direction: -1, active: $0)
                    }
                    .accessibilityIdentifier("WEAVE_LEFT")
                    HoldButton(symbol: "arrow.up", label: loc.t(.moveForwardAccessibility), width: width, height: height, locked: locked) { controller.move(x: 1, y: 0, active: $0) }
                    HoldButton(text: loc.t(.weaveRightControl), label: loc.t(.weaveRightAccessibility), accent: Color(red: 0.62, green: 0.03, blue: 0.28), width: width, height: height, locked: locked) {
                        controller.weaveButton(direction: 1, active: $0)
                    }
                    .accessibilityIdentifier("WEAVE_RIGHT")
                }
                GridRow {
                    HoldButton(symbol: "arrow.left", label: loc.t(.moveLeftAccessibility), width: width, height: height, locked: locked) { controller.move(x: 0, y: -1, active: $0) }
                    HoldButton(symbol: "shield.fill", label: loc.t(.guardAccessibility), accent: Color(red: 0.72, green: 0.50, blue: 0.02), width: width, height: height, locked: locked, isHeld: controller.modifiers.guarding) {
                        controller.guardButton(active: $0)
                    }
                    HoldButton(symbol: "arrow.right", label: loc.t(.moveRightAccessibility), width: width, height: height, locked: locked) { controller.move(x: 0, y: 1, active: $0) }
                }
                GridRow {
                    HoldButton(text: "L\nDUCK", label: loc.t(.duckLeftAccessibility), accent: Color(red: 0.035, green: 0.29, blue: 0.70), width: width, height: height, locked: locked, isHeld: controller.modifiers.duckDirection == -1) {
                        controller.duckButton(direction: -1, active: $0)
                    }
                    HoldButton(symbol: "arrow.down", label: loc.t(.moveBackAccessibility), width: width, height: height, locked: locked) { controller.move(x: -1, y: 0, active: $0) }
                    HoldButton(text: "R\nDUCK", label: loc.t(.duckRightAccessibility), accent: Color(red: 0.62, green: 0.03, blue: 0.28), width: width, height: height, locked: locked, isHeld: controller.modifiers.duckDirection == 1) {
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
            /// - 하단: 잽/크로스 버튼 — `controller.comboAttack(base:)` 호출
        let locked = controller.snapshot.playerLocked
        return VStack(spacing: 6) {
            ActionButton(
                text: "BACKSTEP",
                symbol: "arrow.down.backward",
                color: Color(red: 0.72, green: 0.50, blue: 0.02),
                width: width * 2 + 8,
                height: 44,
                locked: locked,
                accessibility: loc.t(.backstepAccessibility),
                action: controller.backstep
            )
            HStack(spacing: 7) {
                ActionButton(
                    text: controller.selectedPunch(base: .jab).controlLabel(for: loc.language),
                    color: Color(red: 0.035, green: 0.29, blue: 0.70),
                    width: width,
                    height: height,
                    locked: locked,
                    accessibility: controller.selectedPunch(base: .jab).localizedName(for: loc.language),
                    identifier: "JAB",
                    subtitle: controller.selectedPunch(base: .jab) == .jab ? nil : "JAB",
                    action: { controller.comboAttack(base: .jab) }
                )
                ActionButton(
                    text: controller.selectedPunch(base: .cross).controlLabel(for: loc.language),
                    color: Color(red: 0.62, green: 0.03, blue: 0.28),
                    width: width,
                    height: height,
                    locked: locked,
                    accessibility: controller.selectedPunch(base: .cross).localizedName(for: loc.language),
                    identifier: "CROSS",
                    subtitle: controller.selectedPunch(base: .cross) == .cross ? nil : "CROSS",
                    action: { controller.comboAttack(base: .cross) }
                )
            }
        }
    }

    private var pauseOverlay: some View {
            /// 경기 일시정지 오버레이
            /// - 재개 버튼은 `controller.pause()`를 트리거하여 토글 방식으로 동작
        VStack(spacing: 12) {
            Text(loc.t(.pausedTitle))
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Button(loc.t(.resumeButton), action: controller.pause)
                .buttonStyle(FightButtonStyle())
        }
        .padding(24)
        .glowPanel(accent: Color(red: 0.72, green: 0.50, blue: 0.02))
    }

    private func iconButton(_ symbol: String, accessibility: String, action: @escaping () -> Void) -> some View {
            /// 상단/우측의 작은 아이콘 버튼(원형)
            /// - `symbol`: SF Symbol 이름
            /// - `accessibility`: 음성 안내용 라벨
            /// - `action`: 탭 이벤트 핸들러
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

/// Observes the presentation directly rather than waiting for the 0.08s HUD snapshot cadence.
/// The timer slot stays reserved through the KO break; it never overlaps the fading KO text.
private struct CombatRoundClock: View {
    let snapshot: CombatSnapshot
    @ObservedObject var presentation: CombatPresentation
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        let phase = presentation.knockoutClockPhase
        let showsKnockout = phase == .visible
        VStack(spacing: 0) {
            Text("ROUND \(snapshot.round)")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
            Text(String(format: "%02d", Int(ceil(snapshot.time))))
                .font(.system(size: 19, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .opacity(phase == .inactive ? 1 : 0)
                .frame(width: 50, height: 26)
                .overlay {
                    Text(CombatSignature.knockout.title(for: loc.language))
                        .font(.system(size: 22, weight: .black))
                        .fontWidth(.condensed)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                        .opacity(showsKnockout ? 1 : 0)
                        // Opacity only, including Reduce Motion; reset cancels any residual fade.
                        .animation(phase == .inactive ? nil : .easeOut(duration: 0.10), value: showsKnockout)
                }
            Text("\(snapshot.playerScore) : \(snapshot.enemyScore)")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 50)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showsKnockout
            ? "\(CombatText.clock(snapshot, language: loc.language)), \(CombatSignature.knockout.title(for: loc.language))"
            : CombatText.clock(snapshot, language: loc.language))
        .accessibilityIdentifier("combatRoundClock")
    }
}

private struct CombatSignatureView: View {
    @ObservedObject var presentation: CombatPresentation
    @ObservedObject private var loc = LocalizationManager.shared
    @RivalReducedMotion private var reducedMotion

    var body: some View {
        Group {
            if let signature = presentation.signature, signature != .knockout {
                Text(signature.title(for: loc.language))
                    .font(.system(size: 19, weight: .black))
                    .fontWidth(.condensed)
                    .tracking(1.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.025, green: 0.030, blue: 0.040).opacity(0.94))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(signature == .counterWindow ? Color(red: 0.28, green: 0.70, blue: 1) : Color.white.opacity(0.72))
                            .frame(height: 2)
                    }
                    .id(signature)
                    .transition(reducedMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    .accessibilityIdentifier("combatSignature")
            }
        }
        .animation(.easeOut(duration: UIStyleKit.microDuration), value: presentation.signature)
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

    var body: some View {
        VStack(alignment: reverse ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 4) {
                if reverse {
                    Text("HP \(health)")
                    Spacer(minLength: 0)
                    Text(displayName)
                } else {
                    Text(displayName)
                    Spacer(minLength: 0)
                    Text("HP \(health)")
                }
            }
            .font(.system(size: 8, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.82))
            meter(value: Double(health) / Double(max(1, maximumHealth)), color: color, height: 6)
            meter(value: stamina / 100, color: Color(red: 0.35, green: 0.92, blue: 0.52), height: 3)
        }
        .frame(maxWidth: 178)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CombatText.fighter(name: accessibilityName, health: health, stamina: stamina, language: loc.language))
    }

    private func meter(value: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(1, max(0, value))
            ZStack(alignment: reverse ? .trailing : .leading) {
                Capsule(style: .continuous).fill(Color(red: 0.07, green: 0.11, blue: 0.17))
                Capsule(style: .continuous).fill(color).frame(width: width)
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
    let onPress: (Bool) -> Void
    @State private var isPressed = false
    @RivalReducedMotion private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    private var highlighted: Bool { !locked && (isHeld ?? isPressed) }

    init(symbol: String, label: String, accent: Color = .white.opacity(0.28), width: CGFloat = 56, height: CGFloat = 50, locked: Bool = false, isHeld: Bool? = nil, onPress: @escaping (Bool) -> Void) {
        self.symbol = symbol
        text = nil
        self.label = label
        self.accent = accent
        self.width = width
        self.height = height
        self.locked = locked
        self.isHeld = isHeld
        self.onPress = onPress
    }

    init(text: String, label: String, accent: Color = .white.opacity(0.28), width: CGFloat = 56, height: CGFloat = 50, locked: Bool = false, isHeld: Bool? = nil, onPress: @escaping (Bool) -> Void) {
        symbol = nil
        self.text = text
        self.label = label
        self.accent = accent
        self.width = width
        self.height = height
        self.locked = locked
        self.isHeld = isHeld
        self.onPress = onPress
    }

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .black))
            } else {
                Text(text ?? "")
                    .font(.system(size: 10, weight: .bold))
                    .fontWidth(.condensed)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: UIStyleKit.combatControlCornerRadius, style: .continuous)
                .fill(
                    highlighted
                        ? accent
                        : Color(red: 0.075, green: 0.085, blue: 0.105)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIStyleKit.combatControlCornerRadius, style: .continuous)
                .stroke(highlighted ? Color.white.opacity(0.8) : accent.opacity(0.6), lineWidth: highlighted ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
        .opacity(locked ? 0.4 : 1)
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
        .accessibilityLabel(label)
        .accessibilityValue(loc.t(locked ? .inputUnavailable : ((isHeld ?? isPressed) ? .controlHeld : .controlReleased)))
        .accessibilityHint(loc.t(.holdControlHint))
        .accessibilityAddTraits(.isButton)
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
    let width: CGFloat
    let height: CGFloat
    let locked: Bool
    let accessibility: String?
    let identifier: String
    let subtitle: String?
    let action: () -> Void

    init(text: String, symbol: String? = nil, color: Color, width: CGFloat = 60, height: CGFloat = 44, locked: Bool = false, accessibility: String? = nil, identifier: String? = nil, subtitle: String? = nil, action: @escaping () -> Void) {
        self.text = text
        self.symbol = symbol
        self.color = color
        self.width = width
        self.height = height
        self.locked = locked
        self.accessibility = accessibility
        self.identifier = identifier ?? text
        self.subtitle = subtitle
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
                        .tracking(1)
                        .opacity(0.72)
                        .accessibilityHidden(true)
                }
            }
                .foregroundStyle(.white)
                .frame(width: width, height: height)
        }
        .buttonStyle(AttackButtonStyle(color: color, locked: locked, combination: subtitle != nil))
        .disabled(locked)
        .accessibilityLabel(accessibility ?? text)
        .accessibilityValue(locked ? loc.t(.inputUnavailable) : "")
        .accessibilityHint(symbol == nil ? loc.t(.comboAccessibilityHint) : "")
        .accessibilityIdentifier(identifier)
    }
}

private struct AttackButtonStyle: PrimitiveButtonStyle {
    let color: Color
    let locked: Bool
    let combination: Bool

    func makeBody(configuration: Configuration) -> some View {
        ImmediateAttackSurface(label: configuration.label, color: color, locked: locked,
                               combination: combination, trigger: configuration.trigger)
    }
}

/// Capture the held modifier on touch-down, not after the attack finger lifts. Drag cancellation
/// resets only the touch latch; it never repeats an attack or adds another action on release.
private struct ImmediateAttackSurface<Label: View>: View {
    let label: Label
    let color: Color
    let locked: Bool
    let combination: Bool
    let trigger: () -> Void
    @GestureState private var touching = false
    @State private var fired = false
    @RivalReducedMotion private var reducedMotion

    var body: some View {
        let pressed = touching && !locked
        label
            .background(
                RoundedRectangle(cornerRadius: UIStyleKit.combatControlCornerRadius, style: .continuous)
                    .fill(pressed ? color : color.opacity(0.76))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIStyleKit.combatControlCornerRadius, style: .continuous)
                    .stroke(.white.opacity(pressed ? 0.85 : (combination ? 0.65 : 0.24)), lineWidth: pressed || combination ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            .opacity(locked ? 0.4 : 1)
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
            .accessibilityAction { if !locked { trigger() } }
    }
}

private struct FightButtonStyle: ButtonStyle {
    @RivalReducedMotion private var reducedMotion

    func makeBody(configuration: Configuration) -> some View {
        let accent = Color(red: 0.035, green: 0.29, blue: 0.70)
        configuration.label
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 34)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: UIStyleKit.controlCornerRadius, style: .continuous)
                    .fill(accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIStyleKit.controlCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: accent.opacity(configuration.isPressed ? 0.15 : 0.3), radius: configuration.isPressed ? 4 : 10, y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: UIStyleKit.microDuration), value: configuration.isPressed)
    }
}

/// The style/outfit selection screen. Reused both from the in-fight settings menu and directly from the
/// main menu (so players can gear up before ever starting a fight) — extracted out of `GameView` so both
/// call sites share one implementation instead of two copies.
struct WaitingRoomView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var purchases = StoryPurchaseStore.shared
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 12
    private enum LockerTab { case styles, outfits, storyRewards }
    @State private var tab = LockerTab.styles
    @State private var previewAppearance: StoryOpponent?
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
                MainMenuPalette.background.ignoresSafeArea()
                VStack(spacing: 14) {
                    RivalScreenHeader(kicker: storyOpponent?.title(for: loc.language) ?? loc.t(.lockerKicker), title: loc.t(.waitingRoomButton),
                                      closeTitle: loc.t(.close), closeID: "waitingRoomClose", onClose: onClose)
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            StylePreviewView(style: controller.playerStyle, outfit: previewOutfit, appearance: previewAppearance,
                                championBelt: controller.championBeltEquipped)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(MainMenuPalette.surface)
                                .overlay(Rectangle().stroke(MainMenuPalette.rule, lineWidth: 1))
                                .clipped()
                                .accessibilityLabel(loc.t(.previewCharacterAccessibility))
                            if !dynamicType.isAccessibilitySize { previewSummary }
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 12) {
                            Picker(loc.t(.waitingRoomButton), selection: $tab) {
                                Text(loc.t(.styleTabLabel)).tag(LockerTab.styles)
                                Text(loc.t(.outfitLabel)).tag(LockerTab.outfits)
                                Text(loc.story(.title)).tag(LockerTab.storyRewards)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("lockerTabs")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            ScrollView {
                                VStack(spacing: 8) {
                                    if dynamicType.isAccessibilitySize { previewSummary.padding(.bottom, 8) }
                                    switch tab {
                                    case .outfits:
                                        rewardHeader(.freeRewards, detail: .freeRewardsDetail)
                                        ForEach(OutfitID.allCases.filter { $0 != .storyStarter && $0 != .storyChampion }, id: \.self) {
                                            outfitButton($0)
                                        }
                                    case .storyRewards:
                                        rewardHeader(.storyRewards, detail: .storyRewardsDetail)
                                        if !purchases.hasStoryAccess {
                                            Button { showsStoryPurchase = true } label: {
                                                Label(loc.purchase(.purchaseToEarn), systemImage: "lock.open")
                                                    .lineLimit(2).minimumScaleFactor(0.75)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .buttonStyle(RivalMenuButtonStyle())
                                            .foregroundStyle(MainMenuPalette.story)
                                            .accessibilityIdentifier("lockerStoryPurchase")
                                        }
                                        rewardHeader(.instantRewards, detail: .starterOutfitDetail)
                                        ForEach(StoryPurchaseReward.purchaseRewards) { storyRewardRow($0) }
                                        Rectangle().fill(MainMenuPalette.rule).frame(height: 1).padding(.vertical, 4)
                                        rewardHeader(.earnedRewards, detail: .rewardsRequireVictory)
                                        ForEach(StoryPurchaseReward.victoryRewards) { storyRewardRow($0) }
                                    case .styles:
                                        ForEach(FightStyle.allCases, id: \.self) { styleButton($0) }
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            if let onChallenge {
                                Button(action: onChallenge) {
                                    Label(loc.story(.challenge), systemImage: "arrow.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(RivalMenuButtonStyle(primary: true))
                                .accessibilityIdentifier("storyStartFresh")
                            }
                        }
                        .frame(width: max(260, (proxy.size.width - 60) * (dynamicType.isAccessibilitySize ? 0.58 : 0.48)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .allowsHitTesting(!showsStoryPurchase)
                .accessibilityHidden(showsStoryPurchase)
                if showsStoryPurchase {
                    StoryPurchaseView(store: purchases, onClose: { showsStoryPurchase = false },
                        onUnlocked: { showsStoryPurchase = false })
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { controller.refreshStoryEquipment() }
        .task { await purchases.refreshAccess() }
    }

    private func rewardHeader(_ title: StoryPurchaseText, detail: StoryPurchaseText) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(loc.purchase(title))
                .font(.system(size: labelSize, weight: .bold))
                .foregroundStyle(title == .storyRewards ? MainMenuPalette.story : MainMenuPalette.paper)
                .accessibilityAddTraits(.isHeader)
            Text(loc.purchase(detail))
                .font(.system(size: detailSize, weight: .medium))
                .foregroundStyle(MainMenuPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                    .foregroundStyle(MainMenuPalette.paper)
            }
            .tint(MainMenuPalette.story)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .accessibilityIdentifier("lockerChampionBelt")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(loc.story(.championBelt), systemImage: "lock.fill")
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(MainMenuPalette.paper)
                Text(controller.championBeltEarned && !purchases.hasStoryAccess
                    ? loc.purchase(.storyAccessRequired)
                    : StoryPurchaseReward.championBelt.requirement(for: loc.language))
                    .font(.system(size: detailSize, weight: .medium))
                    .foregroundStyle(MainMenuPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rivalSelection(isSelected: false)
        }
    }

    private var previewSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(controller.playerStyle.label(for: loc.language))
                .font(.system(size: labelSize, weight: .bold))
                .foregroundStyle(MainMenuPalette.paper)
            Text("\(previewAppearance?.title(for: loc.language) ?? previewOutfit.label(for: loc.language)) · \(loc.t(previewAppearance == controller.equippedAppearance && (previewAppearance != nil || previewOutfit == controller.equippedOutfit) ? .outfitEquippedLabel : .outfitPreviewLabel))")
                .font(.system(size: detailSize, weight: .medium))
                .foregroundStyle(MainMenuPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lockerPreviewStatus")
        }
    }

    private func styleButton(_ style: FightStyle) -> some View {
        let isSelected = controller.playerStyle == style
        return Button {
            controller.setPlayerStyle(style)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(style.label(for: loc.language))
                        .font(.system(size: labelSize, weight: .bold))
                    Spacer(minLength: 4)
                    if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
                }
                Text(style.summary(for: loc.language))
                    .font(.system(size: detailSize, weight: .regular))
                    .foregroundStyle(MainMenuPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(MainMenuPalette.paper)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .rivalSelection(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.label(for: loc.language)), \(style.summary(for: loc.language))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("lockerStyle-\(style.rawValue)")
    }

    private func outfitButton(_ outfit: OutfitID) -> some View {
        let unlocked = controller.isOutfitUnlocked(outfit)
        let isEquipped = controller.equippedOutfit == outfit && controller.equippedAppearance == nil
        let isPreviewing = previewOutfit == outfit && previewAppearance == nil
        let requirement = !purchases.hasStoryAccess && controller.championOutfitEarned
            && (outfit == .champion || outfit == .storyChampion)
            ? loc.purchase(.storyAccessRequired) : outfit.unlockDescription(for: loc.language)
        return Button {
            // Always update the live 3D preview, even for a locked outfit -- only actually equip it
            // (persist as the outfit worn into real matches) once it's unlocked.
            previewOutfit = outfit
            previewAppearance = nil
            if unlocked {
                controller.setEquippedOutfit(outfit)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
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
                            .foregroundStyle(MainMenuPalette.paper)
                    }
                    Spacer(minLength: 0)
                }
                if !unlocked || outfit == .storyStarter {
                    Text(requirement)
                        .font(.system(size: detailSize, weight: .regular))
                        .foregroundStyle(MainMenuPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(MainMenuPalette.paper)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .rivalSelection(isSelected: isPreviewing)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPreviewing ? .isSelected : [])
        .accessibilityIdentifier("lockerOutfit-\(outfit.rawValue)")
        .accessibilityLabel(
            unlocked
                ? "\(outfit.label(for: loc.language)), \(loc.t(isEquipped ? .outfitEquippedLabel : .outfitPreviewLabel))"
                : "\(outfit.label(for: loc.language)), \(loc.t(.outfitPreviewLabel)), \(requirement)"
        )
    }

    private func appearanceButton(_ opponent: StoryOpponent) -> some View {
        let available = opponent.hasAppearance
        let unlocked = controller.isAppearanceUnlocked(opponent)
        let equipped = controller.equippedAppearance == opponent
        let previewing = previewAppearance == opponent
        let title = StoryPurchaseReward.appearance(opponent).title(for: loc.language)
        let requirement = controller.clearedStoryOpponents.contains(opponent) && !purchases.hasStoryAccess
            ? loc.purchase(.storyAccessRequired)
            : StoryPurchaseReward.appearance(opponent).requirement(for: loc.language)
        return Button {
            guard available else { return }
            previewAppearance = opponent
            if unlocked { controller.setEquippedAppearance(opponent) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if !unlocked || !available { Image(systemName: "lock.fill").accessibilityHidden(true) }
                    Text(title).font(.system(size: labelSize, weight: .semibold))
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if equipped { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                }
                if !unlocked || !available {
                    Text(!available ? loc.story(.unavailable) : requirement)
                        .font(.system(size: detailSize, weight: .regular))
                        .foregroundStyle(MainMenuPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(MainMenuPalette.paper)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .rivalSelection(isSelected: previewing)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        .accessibilityAddTraits(previewing ? .isSelected : [])
        .accessibilityIdentifier("lockerAppearance-\(opponent.rawValue)")
        .accessibilityLabel("\(title), \(loc.t(equipped ? .outfitEquippedLabel : .outfitPreviewLabel))")
        .accessibilityHint(unlocked ? "" : requirement)
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
                                      closeTitle: loc.t(.close), closeID: "settingsClose", onClose: onClose)
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
                .background(MainMenuPalette.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(MainMenuPalette.rule, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t(.language))
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(MainMenuPalette.secondary)
            HStack(spacing: 8) {
                ForEach(AppLanguage.allCases, id: \.self) { candidate in
                    let isSelected = loc.language == candidate
                    Button {
                        loc.setLanguage(candidate)
                    } label: {
                        Text(candidate.nativeName)
                            .font(.system(size: labelSize, weight: .semibold))
                            .foregroundStyle(MainMenuPalette.paper)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .rivalSelection(isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
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
                    .foregroundStyle(MainMenuPalette.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(MainMenuPalette.paper)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(MainMenuPalette.surface, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
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
                                      closeTitle: loc.t(.cancel), closeID: "resetCancel", onClose: onCancel)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(loc.t(.resetConfirmTitle))
                                .font(.system(size: bodySize, weight: .semibold))
                                .foregroundStyle(MainMenuPalette.paper)
                            Text(loc.t(.resetConfirmBody))
                                .font(.system(size: bodySize, weight: .regular))
                                .foregroundStyle(MainMenuPalette.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    Button(role: .destructive, action: onConfirm) {
                        Text(loc.t(.resetConfirmButton)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RivalMenuButtonStyle(destructive: true))
                    .accessibilityLabel(loc.t(.resetConfirmButton))
                    .accessibilityIdentifier("resetConfirm")
                }
                .padding(20)
                .frame(width: min(420, proxy.size.width - 32), height: min(326, proxy.size.height - 24))
                .background(MainMenuPalette.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(MainMenuPalette.rule, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
