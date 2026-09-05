import SwiftUI

/// The first in-app presentation after Apple's static launch screen. It reuses the live arena and boxer
/// rigs while cinematic mode keeps the combat engine paused, so it is a visual entrance rather than a fight.
struct LoadingScreenView: View {
    @ObservedObject var controller: GameController
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sceneVisible = false
    @State private var markVisible = false
    @State private var hasFinished = false

    private var holdsForVisualTest: Bool {
        ProcessInfo.processInfo.environment["RIVAL_OPENING_VISUAL_TEST"] == "1"
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        withAnimation(.easeIn(duration: 0.22)) {
            sceneVisible = false
            markVisible = false
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            controller.setCinematicMode(false)
            onFinished()
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Arena3DView(controller: controller)
                .ignoresSafeArea()
                .opacity(sceneVisible ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("RIVAL")
                    .font(.system(size: 44, weight: .black, design: .default))
                    .foregroundStyle(.white)
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.78, blue: 0.12))
                    .frame(width: 42, height: 2)
            }
            .opacity(markVisible ? 1 : 0)
            .scaleEffect(markVisible ? 1 : 0.96)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 28)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
        .onAppear {
            controller.setCinematicMode(true, presentation: .appOpening)
            withAnimation(.easeOut(duration: 0.32)) {
                sceneVisible = true
            }
        }
        .onDisappear {
            controller.setCinematicMode(false)
        }
        .task {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.18)) {
                    sceneVisible = true
                    markVisible = true
                }
                try? await Task.sleep(nanoseconds: 450_000_000)
                finish()
                return
            }

            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !hasFinished else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                markVisible = true
            }
            if holdsForVisualTest { return }
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            finish()
        }
    }
}
