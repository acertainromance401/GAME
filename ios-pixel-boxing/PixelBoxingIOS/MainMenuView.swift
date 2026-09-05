import SwiftUI

/// The game's front door: shown before any fight starts, gating access to continuing/restarting a session,
/// the waiting room (style/outfit), settings, and the practice room — instead of dropping straight into a
/// fight the moment the app launches.
struct MainMenuView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var screen: AppScreen
    @State private var showsNewGameConfirmation = false
    @State private var showsWaitingRoom = false
    @State private var showsSettings = false
    @State private var showsLeaderboard = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 410
            let menuWidth = min(272, max(220, proxy.size.width * (compact ? 0.30 : 0.32)))
            let leadingInset: CGFloat = 16

            ZStack {
                Color(red: 0.012, green: 0.016, blue: 0.024)
                    .ignoresSafeArea()

                // Preserve the approved live arena and boxer composition as the menu's visual subject.
                Arena3DView(controller: controller)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                    menuHeader(compact: compact)

                    primaryMatchButton(compact: compact) {
                        controller.start()
                        screen = .vsSplash
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        utilityButton(loc.t(.waitingRoomButton), symbol: "tshirt.fill", accent: Color(red: 0.72, green: 0.50, blue: 0.02), compact: compact) {
                            showsWaitingRoom = true
                        }
                        utilityButton(loc.t(.practiceRoomButton), symbol: "figure.boxing", accent: Color(red: 0.05, green: 0.55, blue: 0.12), compact: compact) {
                            screen = .practice
                        }
                        utilityButton(loc.t(.leaderboardButton), symbol: "trophy.fill", accent: Color(red: 1.0, green: 0.78, blue: 0.12), compact: compact) {
                            showsLeaderboard = true
                        }
                        utilityButton(loc.t(.settingsTitle), symbol: "gearshape.fill", accent: .white.opacity(0.62), compact: compact) {
                            showsSettings = true
                        }
                    }

                    Button {
                        showsNewGameConfirmation = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold))
                            Text(loc.t(.newGameButton))
                                .font(.system(size: 11, weight: .bold, design: .default))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color(red: 1.0, green: 0.36, blue: 0.40))
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: compact ? 40 : 44)
                    }
                    .buttonStyle(MainMenuPressStyle())
                    .accessibilityLabel("\(loc.t(.newGameButton)), \(loc.t(.newGameSubtitle))")
                }
                .frame(width: menuWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, leadingInset)
                .padding(.trailing, 12)
                .padding(.top, max(compact ? 14 : 24, proxy.safeAreaInsets.top + 8))
                .padding(.bottom, max(compact ? 14 : 24, proxy.safeAreaInsets.bottom + 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if showsWaitingRoom {
                    WaitingRoomView(controller: controller) {
                        showsWaitingRoom = false
                    }
                }

                if showsSettings {
                    SettingsMenuView(
                        controller: controller,
                        showsLanguageRow: true,
                        onClose: {
                            showsSettings = false
                        }
                    )
                }

                if showsLeaderboard {
                    LeaderboardView {
                        showsLeaderboard = false
                    }
                }

                if showsNewGameConfirmation {
                    LearningResetConfirmView(
                        onCancel: { showsNewGameConfirmation = false },
                        onConfirm: {
                            controller.resetLearning()
                            showsNewGameConfirmation = false
                            screen = .vsSplash
                        }
                    )
                }
            }
        }
        .task {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
            windowScene.requestGeometryUpdate(preferences)
        }
    }

    private func menuHeader(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text("RIVAL")
                .font(.system(size: compact ? 38 : 52, weight: .black, design: .default))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.75), radius: 8, y: 3)
            Rectangle()
                .fill(Color(red: 1.0, green: 0.78, blue: 0.12))
                .frame(width: compact ? 30 : 38, height: 2)
            Text(loc.t(.tagline))
                .font(.system(size: compact ? 11 : 13, weight: .semibold, design: .default))
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("ROUND \(controller.snapshot.round)")
                Circle()
                    .fill(.white.opacity(0.28))
                    .frame(width: 3, height: 3)
                Text("\(controller.snapshot.playerScore) : \(controller.snapshot.enemyScore)")
                    .monospacedDigit()
            }
            .font(.system(size: compact ? 9 : 10, weight: .black, design: .default))
            .foregroundStyle(.white.opacity(0.42))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RIVAL, \(loc.t(.tagline)), 라운드 \(controller.snapshot.round), 스코어 \(controller.snapshot.playerScore) 대 \(controller.snapshot.enemyScore)")
    }

    private func primaryMatchButton(compact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "figure.boxing")
                    .font(.system(size: compact ? 19 : 22, weight: .bold))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t(.continueButton))
                        .font(.system(size: compact ? 16 : 18, weight: .black, design: .default))
                    Text("ROUND \(controller.snapshot.round) · \(controller.snapshot.playerScore) : \(controller.snapshot.enemyScore)")
                        .font(.system(size: compact ? 9 : 10, weight: .bold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .black))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 52 : 62)
            .background(Color(red: 0.02, green: 0.14, blue: 0.40))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(MainMenuPressStyle())
        .accessibilityLabel("\(loc.t(.continueButton)), 라운드 \(controller.snapshot.round), 스코어 \(controller.snapshot.playerScore) 대 \(controller.snapshot.enemyScore)")
        .accessibilityIdentifier("mainMenuContinue")
    }

    private func utilityButton(_ title: String, symbol: String, accent: Color, compact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 13 : 15, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .black, design: .default))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 38 : 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.040, green: 0.047, blue: 0.060))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(accent.opacity(0.38), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(MainMenuPressStyle())
        .accessibilityLabel(title)
    }
}

private struct MainMenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("Main Menu") {
    MainMenuView(controller: GameController(), screen: .constant(.mainMenu))
}
