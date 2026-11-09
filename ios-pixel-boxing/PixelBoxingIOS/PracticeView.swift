/*
 PracticeView.swift

 파일 설명:
 - 연습 모드의 SwiftUI 뷰를 정의합니다. 연습 전용 엔진/씬과 상호작용하며, 타이머/점수판/튜토리얼 팁 등을 표시합니다.

 사용 영향 및 주의사항:
 - 연습 모드에서의 입력은 실제 매치 규칙과 동일하지만 점수/통계 처리 방식이 다를 수 있습니다.
 - UI 수정 시 PracticeController와의 연결을 확인하세요.
*/
import SwiftUI

private enum PracticeControlPalette {
    static let left = PreparationPalette.player
    static let right = Color(red: 0.49, green: 0.24, blue: 0.32)
    static let defense = Color(red: 0.55, green: 0.435, blue: 0.227)
}

/// The gym keeps its original scene; poster artwork belongs to the optional practice guide.
struct PracticeView: View {
    @StateObject private var controller: PracticeController
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Binding var screen: AppScreen
    let recordGymSeconds: (Double) -> Void
    @State private var activeStartedAt: Date?
    @State private var showsGymGuide = false

    init(style: FightStyle, stance: BoxingStance = .orthodox, screen: Binding<AppScreen>, recordGymSeconds: @escaping (Double) -> Void) {
        _controller = StateObject(wrappedValue: PracticeController(style: style, stance: stance))
        _screen = screen
        self.recordGymSeconds = recordGymSeconds
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    topBar
                    ZStack(alignment: .bottom) {
                        PracticeSceneView(controller: controller)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                        if !showsGymGuide {
                            controls(safeAreaInsets: proxy.safeAreaInsets)
                        }
                    }
                }
                .allowsHitTesting(!showsGymGuide)
                .accessibilityHidden(showsGymGuide)

                if showsGymGuide {
                    GymGuideView { showsGymGuide = false }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(GymGuideView.paper)
        }
        .task {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
            windowScene.requestGeometryUpdate(preferences)
        }
        .onAppear { startActivePracticeTime() }
        .onChange(of: showsGymGuide) { _, showing in
            controller.releaseHeldControls()
            if showing {
                recordActivePracticeTime()
            } else {
                startActivePracticeTime()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startActivePracticeTime()
            } else {
                controller.releaseHeldControls()
                recordActivePracticeTime()
            }
        }
        .onDisappear {
            controller.releaseHeldControls()
            recordActivePracticeTime()
        }
    }

    private func startActivePracticeTime() {
        guard scenePhase == .active, !showsGymGuide, activeStartedAt == nil else { return }
        activeStartedAt = Date()
    }

    private func recordActivePracticeTime() {
        guard let activeStartedAt else { return }
        self.activeStartedAt = nil
        recordGymSeconds(max(0, Date().timeIntervalSince(activeStartedAt)))
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                RivalWordmark(width: 44, color: PreparationPalette.rival)
                    .accessibilityHidden(true)
                Text(loc.t(.menuGymTitle))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(PreparationPalette.ink)
            }
            Text(loc.t(.gymFreePractice))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PreparationPalette.secondary)
            Spacer()
            if !showsGymGuide {
                Button { showsGymGuide = true } label: {
                    HStack(spacing: 8) {
                        Image("GymPosterArt")
                            .resizable().scaledToFit()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        Text(loc.t(.gymGuideTitle))
                    }
                }
                .buttonStyle(RivalMenuButtonStyle(onPaper: true))
                .accessibilityIdentifier("gymGuide")
                Button { screen = .mainMenu } label: {
                    Label(loc.t(.exitButton), systemImage: "arrow.left")
                }
                    .buttonStyle(RivalMenuButtonStyle(onPaper: true))
                    .accessibilityLabel(loc.t(.exitGymAccessibility))
                    .accessibilityIdentifier("gymExit")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(GymGuideView.paper)
    }

    private struct GymGuideView: View {
        static let paper = Color(red: 233 / 255, green: 224 / 255, blue: 202 / 255)
        @ObservedObject private var loc = LocalizationManager.shared
        let onClose: () -> Void

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    Self.paper.ignoresSafeArea()
                    Image("GymPosterArt")
                        .resizable().scaledToFit()
                        .frame(width: proxy.size.width * 0.46, height: max(0, proxy.size.height - 64))
                        .position(x: proxy.size.width * 0.77, y: proxy.size.height * 0.57)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            RivalWordmark(width: 84, color: PreparationPalette.rival)
                                .accessibilityHidden(true)
                            Spacer()
                            Button(action: onClose) {
                                Label(loc.t(.gymGuideResume), systemImage: "arrow.left")
                            }
                            .buttonStyle(RivalMenuButtonStyle(onPaper: true))
                            .accessibilityIdentifier("gymGuideClose")
                        }
                        .frame(minHeight: 44)

                        HStack(alignment: .top) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 18) {
                                    Text(loc.t(.gymGuideTitle))
                                        .font(.system(size: 32, weight: .semibold))
                                        .accessibilityAddTraits(.isHeader)
                                        .accessibilityIdentifier("gymGuideTitle")
                                    Text(loc.t(.gymGuideIntroduction))
                                        .font(.system(size: 20, weight: .semibold))
                                    Text(loc.t(.gymGuideDistance))
                                    Text(loc.t(.gymGuideDefense))
                                    Text(loc.t(.gymGuideCombinations))
                                    Text(loc.t(.gymFreePractice))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(PreparationPalette.secondary)
                                }
                                .font(.system(size: 15))
                                .foregroundStyle(PreparationPalette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 16)
                            }
                            .scrollIndicators(.visible)
                            .frame(width: proxy.size.width * 0.50)
                            Spacer(minLength: 0)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func controls(safeAreaInsets: EdgeInsets) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            combatPad
            Spacer(minLength: 12)
            attackPad
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.bottom, max(10, safeAreaInsets.bottom + 4))
    }

    private var combatPad: some View {
        let locked = controller.playerLocked
        return Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            GridRow {
                HoldButton(text: loc.t(.weaveLeftControl), label: loc.t(.weaveLeftAccessibility), accent: PracticeControlPalette.left, locked: locked) {
                    controller.weaveButton(direction: -1, active: $0)
                }
                .accessibilityIdentifier("WEAVE_LEFT")
                HoldButton(symbol: "arrow.up", label: loc.t(.moveForwardAccessibility), locked: locked) { controller.move(x: 1, y: 0, active: $0) }
                HoldButton(text: loc.t(.weaveRightControl), label: loc.t(.weaveRightAccessibility), accent: PracticeControlPalette.right, locked: locked) {
                    controller.weaveButton(direction: 1, active: $0)
                }
                .accessibilityIdentifier("WEAVE_RIGHT")
            }
            GridRow {
                HoldButton(symbol: "arrow.left", label: loc.t(.moveLeftAccessibility), locked: locked) { controller.move(x: 0, y: -1, active: $0) }
                HoldButton(symbol: "shield.fill", label: loc.t(.guardAccessibility), accent: PracticeControlPalette.defense, locked: locked, isHeld: controller.modifiers.guarding) {
                    controller.guardButton(active: $0)
                }
                HoldButton(symbol: "arrow.right", label: loc.t(.moveRightAccessibility), locked: locked) { controller.move(x: 0, y: 1, active: $0) }
            }
            GridRow {
                HoldButton(text: loc.t(.duckLeftControl), label: loc.t(.duckLeftAccessibility), accent: PracticeControlPalette.left, locked: locked, isHeld: controller.modifiers.duckDirection == -1) {
                    controller.duckButton(direction: -1, active: $0)
                }
                HoldButton(symbol: "arrow.down", label: loc.t(.moveBackAccessibility), locked: locked) { controller.move(x: -1, y: 0, active: $0) }
                HoldButton(text: loc.t(.duckRightControl), label: loc.t(.duckRightAccessibility), accent: PracticeControlPalette.right, locked: locked, isHeld: controller.modifiers.duckDirection == 1) {
                    controller.duckButton(direction: 1, active: $0)
                }
            }
        }
        .padding(5)
    }

    private var attackPad: some View {
        let locked = controller.playerLocked
        let leftBase: Punch = controller.engine.player.stance.usesLeftHand(for: .jab) ? .jab : .cross
        let rightBase: Punch = leftBase == .jab ? .cross : .jab
        let leftPunch = controller.selectedPunch(base: leftBase)
        let rightPunch = controller.selectedPunch(base: rightBase)
        let leftIdentifier = leftBase == .jab ? "JAB" : "CROSS"
        let rightIdentifier = rightBase == .jab ? "JAB" : "CROSS"
        return VStack(spacing: 6) {
            ActionButton(
                text: loc.t(.backstepAccessibility),
                symbol: "arrow.down.backward",
                color: PracticeControlPalette.defense,
                width: 163,
                height: 44,
                locked: locked,
                accessibility: loc.t(.backstepAccessibility),
                identifier: "BACKSTEP",
                action: controller.backstep
            )
            HStack(spacing: 7) {
                ActionButton(
                    text: leftPunch.controlLabel(for: loc.language),
                    color: PracticeControlPalette.left,
                    width: 78,
                    height: 72,
                    locked: locked,
                    accessibility: leftPunch.localizedName(for: loc.language),
                    identifier: leftIdentifier,
                    subtitle: leftPunch == leftBase ? nil : "\(loc.t(.combinationControl)) · \(leftBase.controlLabel(for: loc.language))",
                    action: { controller.comboAttack(base: leftBase) }
                )
                ActionButton(
                    text: rightPunch.controlLabel(for: loc.language),
                    color: PracticeControlPalette.right,
                    width: 78,
                    height: 72,
                    locked: locked,
                    accessibility: rightPunch.localizedName(for: loc.language),
                    identifier: rightIdentifier,
                    subtitle: rightPunch == rightBase ? nil : "\(loc.t(.combinationControl)) · \(rightBase.controlLabel(for: loc.language))",
                    action: { controller.comboAttack(base: rightBase) }
                )
            }
        }
    }

}

#Preview("Practice Room") {
    PracticeView(style: .standard, screen: .constant(.practice), recordGymSeconds: { _ in })
}
