import SwiftUI

/// The practice room screen — reached from the main menu's "연습실" button. No opponent, no round timer or
/// score: just the player's own rig in a small room, with the camera positioned directly ahead of it so
/// movement/guard/duck/combo inputs can be rehearsed while watching a front-on view of the character.
struct PracticeView: View {
    @StateObject private var controller: PracticeController
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var screen: AppScreen
    let recordGymSeconds: (Double) -> Void
    @State private var enteredAt: Date?

    init(style: FightStyle, outfit: OutfitID, screen: Binding<AppScreen>, recordGymSeconds: @escaping (Double) -> Void) {
        _controller = StateObject(wrappedValue: PracticeController(style: style, outfit: outfit))
        _screen = screen
        self.recordGymSeconds = recordGymSeconds
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PracticeSceneView(controller: controller)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    controls(safeAreaInsets: proxy.safeAreaInsets)
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
        .onAppear { enteredAt = Date() }
        .onDisappear {
            guard let enteredAt else { return }
            recordGymSeconds(Date().timeIntervalSince(enteredAt))
            self.enteredAt = nil
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text(loc.t(.practiceRoomButton))
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule(style: .continuous).fill(.black.opacity(0.62)))
                .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))

            FighterMeter(
                health: 100,
                stamina: controller.stamina,
                color: Color(red: 0.05, green: 0.55, blue: 0.12),
                reverse: false,
                displayName: "ME",
                accessibilityName: loc.t(.playerAccessibility)
            )
            .frame(maxWidth: 200)

            Spacer()

            Button(loc.t(.exitButton)) { screen = .mainMenu }
                .buttonStyle(ModalButtonStyle(accent: .white.opacity(0.22)))
                .accessibilityLabel(loc.t(.exitGymAccessibility))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func controls(safeAreaInsets: EdgeInsets) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            combatPad
            Spacer(minLength: 12)
            attackPad
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.bottom, max(10, safeAreaInsets.bottom + 4))
    }

    private var combatPad: some View {
        let locked = controller.playerLocked
        return Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            GridRow {
                controlSpacer
                HoldButton(symbol: "arrow.up", label: loc.t(.moveForwardAccessibility), locked: locked) { controller.move(x: 1, y: 0, active: $0) }
                controlSpacer
            }
            GridRow {
                HoldButton(symbol: "arrow.left", label: loc.t(.moveLeftAccessibility), locked: locked) { controller.move(x: 0, y: -1, active: $0) }
                HoldButton(symbol: "shield.fill", label: loc.t(.guardAccessibility), accent: Color(red: 0.72, green: 0.50, blue: 0.02), locked: locked) {
                    controller.guardButton(active: $0)
                }
                HoldButton(symbol: "arrow.right", label: loc.t(.moveRightAccessibility), locked: locked) { controller.move(x: 0, y: 1, active: $0) }
            }
            GridRow {
                HoldButton(text: "L\nDUCK", label: loc.t(.duckLeftAccessibility), accent: Color(red: 0.035, green: 0.29, blue: 0.70), locked: locked) {
                    controller.duckButton(direction: -1, active: $0)
                }
                HoldButton(symbol: "arrow.down", label: loc.t(.moveBackAccessibility), locked: locked) { controller.move(x: -1, y: 0, active: $0) }
                HoldButton(text: "R\nDUCK", label: loc.t(.duckRightAccessibility), accent: Color(red: 0.62, green: 0.03, blue: 0.28), locked: locked) {
                    controller.duckButton(direction: 1, active: $0)
                }
            }
        }
    }

    private var controlSpacer: some View {
        Color.clear.frame(width: 56, height: 50)
    }

    private var attackPad: some View {
        let locked = controller.playerLocked
        return VStack(spacing: 6) {
            ActionButton(
                text: "BACKSTEP",
                symbol: "arrow.down.backward",
                color: Color(red: 0.72, green: 0.50, blue: 0.02),
                width: 163,
                height: 38,
                locked: locked,
                action: controller.backstep
            )
            .accessibilityLabel(loc.t(.backstepAccessibility))
            HStack(spacing: 7) {
                ActionButton(
                    text: "JAB",
                    color: Color(red: 0.035, green: 0.29, blue: 0.70),
                    width: 78,
                    height: 72,
                    locked: locked,
                    action: { controller.comboAttack(base: .jab) }
                )
                ActionButton(
                    text: "CROSS",
                    color: Color(red: 0.62, green: 0.03, blue: 0.28),
                    width: 78,
                    height: 72,
                    locked: locked,
                    action: { controller.comboAttack(base: .cross) }
                )
            }
        }
    }
}

#Preview("Practice Room") {
    PracticeView(style: .standard, outfit: .classic, screen: .constant(.practice), recordGymSeconds: { _ in })
}
