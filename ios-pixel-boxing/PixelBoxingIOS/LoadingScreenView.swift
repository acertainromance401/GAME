/*
 LoadingScreenView.swift

 파일 설명:
 - 앱 시작 시 사용자에게 보여주는 로딩/진입 화면을 정의합니다.
 - 3D 아레나/라인업 리소스를 재사용하여 일관된 비주얼을 제공하고 초기 데이터 로딩 상태를 표시합니다.

 사용 영향 및 주의사항:
 - 네트워크/디스크 I/O 대기 시 표시되는 UI로, 성능 민감 코드와 분리되어야 합니다.
 - 주석 추가만으로는 동작에 영향이 없습니다.
*/

import SwiftUI

/// 로딩 스크린: 앱 시작 시 짧게 보여주는 연출. 전투 엔진은 cinematic 모드로 멈춘 상태에서
/// 3D 씬을 재사용하므로 별도 스프라이트 자산이 필요 없습니다.
struct LoadingScreenView: View {
    @ObservedObject var controller: GameController
    let onFinished: () -> Void

    @RivalReducedMotion private var reduceMotion
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
