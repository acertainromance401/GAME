/*
 PracticeView.swift

 파일 설명:
 - 연습 모드의 SwiftUI 뷰를 정의합니다. 연습 전용 엔진/씬과 상호작용하며, 타이머/점수판/튜토리얼 팁 등을 표시합니다.

 사용 영향 및 주의사항:
 - 연습 모드에서의 입력은 실제 매치 규칙과 동일하지만 점수/통계 처리 방식이 다를 수 있습니다.
 - UI 수정 시 PracticeController와의 연결을 확인하세요.
*/
import SwiftUI

/// The gym keeps its existing space and bag; its title/navigation and combat controls use the shared UI.
struct PracticeView: View {
    @StateObject private var controller: PracticeController
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Binding var screen: AppScreen
    let recordGymSeconds: (Double) -> Void
    @State private var activeStartedAt: Date?

    init(style: FightStyle, screen: Binding<AppScreen>, recordGymSeconds: @escaping (Double) -> Void) {
        _controller = StateObject(wrappedValue: PracticeController(style: style))
        _screen = screen
        self.recordGymSeconds = recordGymSeconds
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                topBar
                ZStack(alignment: .bottom) {
                    PracticeSceneView(controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    controls(safeAreaInsets: proxy.safeAreaInsets)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(MainMenuPalette.background)
        }
        .task {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
            windowScene.requestGeometryUpdate(preferences)
        }
        .onAppear { startActivePracticeTime() }
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
        guard scenePhase == .active, activeStartedAt == nil else { return }
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
                Text(loc.t(.trainingKicker))
                    .font(.system(size: 8, weight: .semibold)).tracking(2)
                    .foregroundStyle(MainMenuPalette.secondary)
                Text(loc.t(.menuGymTitle))
                    .font(.system(size: 22, weight: .black)).fontWidth(.condensed)
                    .foregroundStyle(MainMenuPalette.paper)
            }
            Text(loc.t(.gymFreePractice))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MainMenuPalette.secondary)
            Spacer()
            Button { screen = .mainMenu } label: {
                Label(loc.t(.exitButton), systemImage: "arrow.left")
            }
                .buttonStyle(RivalMenuButtonStyle())
                .accessibilityLabel(loc.t(.exitGymAccessibility))
                .accessibilityIdentifier("gymExit")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(MainMenuPalette.background.opacity(0.96))
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
                HoldButton(text: loc.t(.weaveLeftControl), label: loc.t(.weaveLeftAccessibility), accent: Color(red: 0.035, green: 0.29, blue: 0.70), locked: locked) {
                    controller.weaveButton(direction: -1, active: $0)
                }
                .accessibilityIdentifier("WEAVE_LEFT")
                HoldButton(symbol: "arrow.up", label: loc.t(.moveForwardAccessibility), locked: locked) { controller.move(x: 1, y: 0, active: $0) }
                HoldButton(text: loc.t(.weaveRightControl), label: loc.t(.weaveRightAccessibility), accent: Color(red: 0.62, green: 0.03, blue: 0.28), locked: locked) {
                    controller.weaveButton(direction: 1, active: $0)
                }
                .accessibilityIdentifier("WEAVE_RIGHT")
            }
            GridRow {
                HoldButton(symbol: "arrow.left", label: loc.t(.moveLeftAccessibility), locked: locked) { controller.move(x: 0, y: -1, active: $0) }
                HoldButton(symbol: "shield.fill", label: loc.t(.guardAccessibility), accent: Color(red: 0.72, green: 0.50, blue: 0.02), locked: locked, isHeld: controller.modifiers.guarding) {
                    controller.guardButton(active: $0)
                }
                HoldButton(symbol: "arrow.right", label: loc.t(.moveRightAccessibility), locked: locked) { controller.move(x: 0, y: 1, active: $0) }
            }
            GridRow {
                HoldButton(text: "L\nDUCK", label: loc.t(.duckLeftAccessibility), accent: Color(red: 0.035, green: 0.29, blue: 0.70), locked: locked, isHeld: controller.modifiers.duckDirection == -1) {
                    controller.duckButton(direction: -1, active: $0)
                }
                HoldButton(symbol: "arrow.down", label: loc.t(.moveBackAccessibility), locked: locked) { controller.move(x: -1, y: 0, active: $0) }
                HoldButton(text: "R\nDUCK", label: loc.t(.duckRightAccessibility), accent: Color(red: 0.62, green: 0.03, blue: 0.28), locked: locked, isHeld: controller.modifiers.duckDirection == 1) {
                    controller.duckButton(direction: 1, active: $0)
                }
            }
        }
        .padding(5)
    }

    private var attackPad: some View {
        let locked = controller.playerLocked
        return VStack(spacing: 6) {
            ActionButton(
                text: "BACKSTEP",
                symbol: "arrow.down.backward",
                color: Color(red: 0.72, green: 0.50, blue: 0.02),
                width: 163,
                height: 44,
                locked: locked,
                accessibility: loc.t(.backstepAccessibility),
                action: controller.backstep
            )
            HStack(spacing: 7) {
                ActionButton(
                    text: controller.selectedPunch(base: .jab).controlLabel(for: loc.language),
                    color: Color(red: 0.035, green: 0.29, blue: 0.70),
                    width: 78,
                    height: 72,
                    locked: locked,
                    accessibility: controller.selectedPunch(base: .jab).localizedName(for: loc.language),
                    identifier: "JAB",
                    subtitle: controller.selectedPunch(base: .jab) == .jab ? nil : "JAB",
                    action: { controller.comboAttack(base: .jab) }
                )
                ActionButton(
                    text: controller.selectedPunch(base: .cross).controlLabel(for: loc.language),
                    color: Color(red: 0.62, green: 0.03, blue: 0.28),
                    width: 78,
                    height: 72,
                    locked: locked,
                    accessibility: controller.selectedPunch(base: .cross).localizedName(for: loc.language),
                    identifier: "CROSS",
                    subtitle: controller.selectedPunch(base: .cross) == .cross ? nil : "CROSS",
                    action: { controller.comboAttack(base: .cross) }
                )
            }
        }
    }

}

#Preview("Practice Room") {
    PracticeView(style: .standard, screen: .constant(.practice), recordGymSeconds: { _ in })
}
