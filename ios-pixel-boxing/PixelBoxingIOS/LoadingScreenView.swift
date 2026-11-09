/*
 LoadingScreenView.swift

 파일 설명:
 - 앱 시작 시 사용자에게 보여주는 로딩/진입 화면을 정의합니다.
 - 기존 3D 복싱 오프닝 위에 정적 시작 화면과 같은 워드마크를 표시합니다.

 사용 영향 및 주의사항:
 - 네트워크/디스크 I/O 대기 시 표시되는 UI로, 성능 민감 코드와 분리되어야 합니다.
 - 주석 추가만으로는 동작에 영향이 없습니다.
*/

import SwiftUI

/// 로딩 스크린: 앱 시작 시 짧게 보여주는 연출. 전투 엔진은 cinematic 모드로 멈춘 상태에서
/// 3D 씬의 안무는 유지하고 시작 화면과 같은 위치에 공통 워드마크를 표시합니다.
struct LoadingScreenView: View {
    @ObservedObject var controller: GameController
    let onFinished: () -> Void

    @RivalReducedMotion private var reduceMotion
    @State private var sceneVisible = false
    @State private var markVisible = true
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
            Color("LaunchBackground").ignoresSafeArea()

            Arena3DView(controller: controller)
                .ignoresSafeArea()
                .opacity(sceneVisible ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            RivalWordmark(width: 148, color: Color(red: 237 / 255, green: 234 / 255, blue: 226 / 255))
            .opacity(markVisible ? 1 : 0)
            .scaleEffect(markVisible ? 1 : 0.96)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 32)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appOpening")
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

            if holdsForVisualTest { return }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            finish()
        }
    }
}
