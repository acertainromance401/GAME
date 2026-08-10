import SwiftUI

struct GameView: View {
    @StateObject private var controller = GameController()
    @State private var showsResetConfirmation = false
    @State private var resetPausedFight = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Arena3DView(controller: controller)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        battleHUD
                        topActions
                    }
                    Spacer()
                    controls(safeAreaInsets: proxy.safeAreaInsets)
                }

                if controller.snapshot.phase == .intro {
                    introOverlay
                } else if controller.snapshot.phase == .paused {
                    pauseOverlay
                }

                if showsResetConfirmation {
                    resetConfirmationOverlay
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
    }

    private var topActions: some View {
        HStack(spacing: 8) {
            iconButton("pause.fill", accessibility: "일시정지", action: controller.pause)
            iconButton("brain.head.profile", accessibility: "라이벌 학습 초기화") {
                resetPausedFight = controller.snapshot.phase == .fight
                if resetPausedFight { controller.pause() }
                showsResetConfirmation = true
            }
        }
        .padding(.trailing, max(12, 18))
        .padding(.top, 7)
    }

    private var battleHUD: some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                FighterMeter(
                    health: controller.snapshot.playerHP,
                    stamina: controller.snapshot.playerStamina,
                    color: Color(red: 0.18, green: 0.82, blue: 1),
                    reverse: false,
                    accessibilityName: "플레이어"
                )
                VStack(spacing: 0) {
                    Text("ROUND \(controller.snapshot.round)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.24))
                    Text(String(format: "%02d", Int(ceil(controller.snapshot.time))))
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 64)
                FighterMeter(
                    health: controller.snapshot.enemyHP,
                    stamina: controller.snapshot.enemyStamina,
                    color: Color(red: 1, green: 0.25, blue: 0.40),
                    reverse: true,
                    accessibilityName: "라이벌"
                )
            }
            Text(controller.snapshot.message)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .id(controller.snapshot.message)
                .transition(.opacity)
            .frame(maxWidth: .infinity, minHeight: 22)
        }
        .frame(maxWidth: 610)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.black.opacity(0.72))
        .animation(.easeOut(duration: 0.18), value: controller.snapshot.message)
        .padding(.top, 5)
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
        VStack(spacing: 0) {
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    controlSpacer
                    HoldButton(symbol: "arrow.up", label: "전진") { controller.move(x: 1, y: 0, active: $0) }
                    controlSpacer
                }
                GridRow {
                    HoldButton(symbol: "arrow.left", label: "왼쪽 이동") { controller.move(x: 0, y: -1, active: $0) }
                    HoldButton(symbol: "shield.fill", label: "가드", accent: Color(red: 1, green: 0.78, blue: 0.24)) {
                        controller.guardButton(active: $0)
                    }
                    HoldButton(symbol: "arrow.right", label: "오른쪽 이동") { controller.move(x: 0, y: 1, active: $0) }
                }
                GridRow {
                    HoldButton(text: "L\nDUCK", label: "왼쪽 더킹", accent: Color(red: 0.40, green: 0.82, blue: 1)) {
                        controller.duckButton(direction: -1, active: $0)
                    }
                    HoldButton(symbol: "arrow.down", label: "후퇴") { controller.move(x: -1, y: 0, active: $0) }
                    HoldButton(text: "R\nDUCK", label: "오른쪽 더킹", accent: Color(red: 1, green: 0.42, blue: 0.56)) {
                        controller.duckButton(direction: 1, active: $0)
                    }
                }
            }
        }
    }

    private var controlSpacer: some View {
        Color.clear
            .frame(width: 56, height: 50)
    }

    private var attackPad: some View {
        VStack(spacing: 6) {
            ActionButton(
                text: "BACKSTEP",
                symbol: "arrow.down.backward",
                color: Color(red: 1, green: 0.78, blue: 0.24),
                width: 163,
                height: 38,
                action: controller.backstep
            )
            .accessibilityLabel("백스텝")
            HStack(spacing: 7) {
                ActionButton(
                    text: "JAB",
                    color: Color(red: 0.40, green: 0.82, blue: 1),
                    width: 78,
                    height: 72,
                    action: { controller.comboAttack(base: .jab) }
                )
                ActionButton(
                    text: "CROSS",
                    color: Color(red: 1, green: 0.42, blue: 0.56),
                    width: 78,
                    height: 72,
                    action: { controller.comboAttack(base: .cross) }
                )
            }
        }
    }

    private var introOverlay: some View {
        VStack(spacing: 9) {
            Text("ADAPTIVE COMBAT")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.83, blue: 0.43))
            Text("상대는 당신을 기억한다")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("반복하는 공격과 방어 습관을 RIVAL이 학습합니다.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.67, green: 0.76, blue: 0.88))
            HStack(alignment: .top, spacing: 24) {
                instructionColumn(
                    title: "MOVE & DEFENSE",
                    lines: ["↑ 전진  ·  ↓ 후퇴", "← / → 좌우 이동", "L / R DUCK 회피", "GUARD 방어  ·  BACKSTEP"]
                )
                instructionColumn(
                    title: "JAB / CROSS 조합",
                    lines: ["단독: 잽 / 크로스", "GUARD: 좌 / 우 어퍼컷", "L DUCK: 좌 바디 / 우 훅", "R DUCK: 좌 훅 / 우 바디"]
                )
            }
            Button("FIGHT", action: controller.start)
                .buttonStyle(FightButtonStyle())
                .accessibilityLabel("경기 시작")
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 14)
        .background(.black.opacity(0.88))
        .overlay(Rectangle().stroke(Color(red: 0.40, green: 0.82, blue: 1), lineWidth: 2))
    }

    private func instructionColumn(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.83, blue: 0.43))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: 175, alignment: .leading)
    }

    private var resetConfirmationOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.24))
            Text("라이벌 학습을 초기화할까요?")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("학습 메모리와 현재 점수가 삭제되고 ROUND 1부터 다시 시작됩니다.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(red: 0.72, green: 0.80, blue: 0.90))
                .frame(maxWidth: 330)
            HStack(spacing: 10) {
                Button("취소") {
                    if resetPausedFight { controller.pause() }
                    resetPausedFight = false
                    showsResetConfirmation = false
                }
                .buttonStyle(ModalButtonStyle(accent: .white.opacity(0.26)))
                .accessibilityLabel("초기화 취소")
                Button("초기화 · ROUND 1") {
                    controller.resetLearning()
                    resetPausedFight = false
                    showsResetConfirmation = false
                }
                .buttonStyle(ModalButtonStyle(accent: Color(red: 1, green: 0.36, blue: 0.40)))
                .accessibilityLabel("학습 초기화 후 라운드 1 재시작")
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .background(.black.opacity(0.94))
        .overlay(Rectangle().stroke(Color(red: 1, green: 0.36, blue: 0.40), lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var pauseOverlay: some View {
        VStack(spacing: 12) {
            Text("PAUSED")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Button("RESUME", action: controller.pause)
                .buttonStyle(FightButtonStyle())
        }
        .padding(24)
        .background(.black.opacity(0.9))
        .overlay(Rectangle().stroke(Color(red: 1, green: 0.83, blue: 0.43), lineWidth: 2))
    }

    private func iconButton(_ symbol: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 38, height: 34)
                .foregroundStyle(.white)
                .background(.black.opacity(0.68))
                .overlay(Rectangle().stroke(.white.opacity(0.24), lineWidth: 1))
        }
        .accessibilityLabel(accessibility)
    }
}

private struct FighterMeter: View {
    let health: Int
    let stamina: Double
    let color: Color
    let reverse: Bool
    let accessibilityName: String

    var body: some View {
        VStack(spacing: 3) {
            meter(value: Double(health) / 100, color: color, height: 8)
            meter(value: stamina / 100, color: Color(red: 0.35, green: 0.92, blue: 0.52), height: 3)
        }
        .frame(maxWidth: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityName) 체력 \(health), 스태미나 \(Int(stamina))")
    }

    private func meter(value: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(1, max(0, value))
            ZStack(alignment: reverse ? .trailing : .leading) {
                Rectangle().fill(Color(red: 0.07, green: 0.11, blue: 0.17))
                Rectangle()
                    .fill(color)
                    .frame(width: width)
            }
        }
        .frame(height: height)
        .overlay(Rectangle().stroke(.white.opacity(0.18), lineWidth: 1))
    }
}

private struct HoldButton: View {
    let symbol: String?
    let text: String?
    let label: String
    let accent: Color
    let onPress: (Bool) -> Void

    init(symbol: String, label: String, accent: Color = .white.opacity(0.28), onPress: @escaping (Bool) -> Void) {
        self.symbol = symbol
        text = nil
        self.label = label
        self.accent = accent
        self.onPress = onPress
    }

    init(text: String, label: String, accent: Color = .white.opacity(0.28), onPress: @escaping (Bool) -> Void) {
        symbol = nil
        self.text = text
        self.label = label
        self.accent = accent
        self.onPress = onPress
    }

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .black))
            } else {
                Text(text ?? "")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 56, height: 50)
        .background(Color(red: 0.065, green: 0.08, blue: 0.105))
        .overlay(Rectangle().stroke(accent, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 30, pressing: onPress, perform: {})
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

private struct ActionButton: View {
    let text: String
    let symbol: String?
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    init(text: String, symbol: String? = nil, color: Color, width: CGFloat = 60, height: CGFloat = 44, action: @escaping () -> Void) {
        self.text = text
        self.symbol = symbol
        self.color = color
        self.width = width
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(text)
            }
                .font(.system(size: 9, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(.white)
                .frame(width: width, height: height)
                .background(Color(red: 0.065, green: 0.08, blue: 0.105))
                .overlay(Rectangle().stroke(color, lineWidth: 2))
        }
            .buttonStyle(.plain)
        .accessibilityLabel(text)
    }
}

private struct FightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(Color(red: 0.03, green: 0.08, blue: 0.15))
            .padding(.horizontal, 34)
            .frame(height: 40)
            .background(Color(red: 0.40, green: 0.82, blue: 1).opacity(configuration.isPressed ? 0.7 : 1))
    }
}

private struct ModalButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 112, minHeight: 36)
            .background(accent.opacity(configuration.isPressed ? 0.66 : 1))
            .overlay(Rectangle().stroke(.white.opacity(0.28), lineWidth: 1))
    }
}
