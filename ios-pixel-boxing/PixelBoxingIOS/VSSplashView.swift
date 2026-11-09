/*
 VSSplashView.swift

 파일 설명:
 - 메인 메뉴에서 전투로 넘어갈 때 짧게 재생되는 스플래시/인트로 뷰를 정의합니다.
 - 씬/리그 리소스를 재사용해 전환 비용을 줄이고, 간단한 카메라/조명/사운드 연출을 담당합니다.

 사용 영향 및 주의사항:
 - 시각적 연출이므로 주로 애니메이션/타이밍 관련 코드가 포함됩니다.
 - 이 주석은 설명용이며 실제 로직에는 영향을 주지 않습니다.
*/
// - 짧은 연출(자동 진행)과 사용자가 탭으로 건너뛸 수 있는 동작을 제공합니다.

import SwiftUI

/// 대결 인트로 뷰: 3D 아레나를 배경으로 ME vs RIVAL 텍스트와 라운드 정보를 표시합니다.
struct VSSplashView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    let onFinished: () -> Void

    @RivalReducedMotion private var reduceMotion
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

            VStack(spacing: 0) {
                HStack {
                    Text("RIVAL")
                        .font(.system(size: 18, weight: .black))
                        .fontWidth(.condensed)
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
                    .accessibilityLabel(loc.t(.cinematicSkip))
                    .accessibilityIdentifier("skipFightIntro")
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

                Spacer()
                HStack(spacing: 0) {
                    Text("ME")
                        .foregroundStyle(FightNightPalette.blue)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel(loc.t(.playerAccessibility))
                    Text("VS")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(FightNightPalette.paper)
                        .padding(.horizontal, 16)
                    Text("RIVAL")
                        .foregroundStyle(FightNightPalette.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(loc.t(.rivalAccessibility))
                }
                .font(.system(size: 42, weight: .black))
                .fontWidth(.condensed)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(FightNightPalette.ink.opacity(0.92))
                .overlay(alignment: .top) {
                    HStack(spacing: 0) {
                        Rectangle().fill(FightNightPalette.blue)
                        Rectangle().fill(FightNightPalette.red)
                    }
                    .frame(height: 3)
                }
                .opacity(titleVisible ? 1 : 0)
                Text("ROUND \(controller.snapshot.round)")
                    .accessibilityLabel("\(loc.t(.roundLabel)) \(controller.snapshot.round)")
                    .font(.system(size: 13, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(FightNightPalette.paper)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(FightNightPalette.ink.opacity(0.92))
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
