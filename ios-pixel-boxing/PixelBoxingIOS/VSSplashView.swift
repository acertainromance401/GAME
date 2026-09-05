import SwiftUI

/// A brief "get ready" stare-down shown between the main menu and the fight itself. Reuses the exact same
/// live 3D ring/fighters rig the battle screen renders (started by the caller just before switching to
/// this screen, so the two boxers are already posed at their round-start positions) — no separate art
/// asset needed. Purely a beat of drama before the HUD/controls appear; auto-advances on its own.
struct VSSplashView: View {
    @ObservedObject var controller: GameController
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasStartedTimer = false
    @State private var titleVisible = false
    @State private var hasFinished = false

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        controller.setCinematicMode(false)
        onFinished()
    }

    var body: some View {
        ZStack {
            Arena3DView(controller: controller)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.black.opacity(0.82), .black.opacity(0.08), .black.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Text("RIVAL")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer()
                    Button(action: finish) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.black.opacity(0.38)))
                            .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1))
                    }
                    .accessibilityLabel(LocalizationManager.shared.t(.cinematicSkip))
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 20) {
                    Text("ME")
                        .foregroundStyle(Color(red: 0.2, green: 0.62, blue: 1.0))
                    Text("VS")
                        .foregroundStyle(.white)
                    Text("RIVAL")
                        .foregroundStyle(Color(red: 1.0, green: 0.2, blue: 0.26))
                }
                .font(.system(size: 38, weight: .black, design: .rounded))
                .shadow(color: .black.opacity(0.75), radius: 12)
                .opacity(titleVisible ? 1 : 0)
                .scaleEffect(titleVisible ? 1 : 1.08)
                Text("ROUND \(controller.snapshot.round)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 8)
                    .opacity(titleVisible ? 1 : 0)
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear {
            controller.setCinematicMode(true)
            withAnimation(.easeOut(duration: 0.28)) {
                titleVisible = true
            }
        }
        .onDisappear {
            controller.setCinematicMode(false)
        }
        .task {
            guard !hasStartedTimer else { return }
            hasStartedTimer = true
            if reduceMotion {
                finish()
                return
            }
            do {
                try await Task.sleep(nanoseconds: 1_900_000_000)
            } catch {
                return
            }
            finish()
        }
    }
}
