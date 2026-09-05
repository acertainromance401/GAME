import SwiftUI

struct GameView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var screen: AppScreen
    @State private var showsWaitingRoom = false
    @State private var showsSettings = false
    @State private var menuPausedFight = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Arena3DView(controller: controller)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    battleHUD(safeAreaInsets: proxy.safeAreaInsets)
                    Spacer()
                    controls(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)
                }

                topActions(safeAreaInsets: proxy.safeAreaInsets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                Group {
                    if controller.snapshot.phase == .intro {
                        introOverlay
                    } else if controller.snapshot.phase == .paused {
                        pauseOverlay
                    } else if controller.snapshot.phase == .roundBreak {
                        roundResultOverlay
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: controller.snapshot.phase)

                if showsSettings {
                    SettingsMenuView(
                        controller: controller,
                        onExitToMenu: {
                            showsSettings = false
                            menuPausedFight = false
                            screen = .mainMenu
                        },
                        onClose: {
                            if menuPausedFight { controller.pause() }
                            menuPausedFight = false
                            showsSettings = false
                        }
                    )
                }

                if showsWaitingRoom {
                    WaitingRoomView(controller: controller) {
                        showsWaitingRoom = false
                    }
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

    private func topActions(safeAreaInsets: EdgeInsets) -> some View {
        iconButton("gearshape.fill", accessibility: loc.t(.settingsTitle)) {
            menuPausedFight = controller.snapshot.phase == .fight
            if menuPausedFight { controller.pause() }
            showsSettings = true
        }
        .padding(.trailing, max(14, safeAreaInsets.trailing + 8))
        .padding(.top, max(6, safeAreaInsets.top + 4))
    }

    private func battleHUD(safeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                FighterMeter(
                    health: controller.snapshot.playerHP,
                    stamina: controller.snapshot.playerStamina,
                    color: Color(red: 0.18, green: 0.82, blue: 1),
                    reverse: false,
                    displayName: "ME",
                    accessibilityName: "플레이어"
                )
                VStack(spacing: 0) {
                    Text("ROUND \(controller.snapshot.round)")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
                    Text(String(format: "%02d", Int(ceil(controller.snapshot.time))))
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("\(controller.snapshot.playerScore) : \(controller.snapshot.enemyScore)")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: 50)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("라운드 \(controller.snapshot.round), 남은 시간 \(Int(ceil(controller.snapshot.time)))초, 스코어 \(controller.snapshot.playerScore) 대 \(controller.snapshot.enemyScore)")
                FighterMeter(
                    health: controller.snapshot.enemyHP,
                    stamina: controller.snapshot.enemyStamina,
                    color: Color(red: 1, green: 0.25, blue: 0.40),
                    reverse: true,
                    displayName: "RIVAL",
                    accessibilityName: "라이벌"
                )
            }
            .padding(.horizontal, 16)
            .padding(.trailing, 48)
            .padding(.bottom, 6)

            Text(controller.snapshot.message)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.92))
                .id(controller.snapshot.message)
                .transition(.opacity)
                .frame(maxWidth: 410, minHeight: 18)
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .background(.black.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, max(5, safeAreaInsets.top + 2))
        .animation(.easeOut(duration: 0.18), value: controller.snapshot.message)
    }

    /// Full round win/loss/draw banner shown during `.roundBreak` — previously the outcome only ever
    /// appeared as one line of the small top HUD caption for ~1.7-2.2s.
    private var roundResultOverlay: some View {
        let outcome = controller.snapshot.lastRoundOutcome
        let knockout = controller.snapshot.lastRoundWasKnockout
        let title: String
        let color: Color
        let titleColor: Color
        switch outcome {
        case .playerWin:
            title = knockout ? "K.O. WIN" : "ROUND WIN"
            color = Color(red: 0.035, green: 0.29, blue: 0.70)
            titleColor = Color(red: 0.20, green: 0.62, blue: 1.0)
        case .playerLoss:
            title = knockout ? "K.O. LOSS" : "ROUND LOSS"
            color = Color(red: 0.68, green: 0.035, blue: 0.11)
            titleColor = Color(red: 1.0, green: 0.20, blue: 0.26)
        case .draw:
            title = "DRAW"
            color = Color(red: 0.72, green: 0.50, blue: 0.02)
            titleColor = Color(red: 1.0, green: 0.78, blue: 0.12)
        }
        let snapshot = controller.snapshot
        let rivalRead = snapshot.rivalRead.cornerReport(for: loc.language)
        return VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(titleColor)
                Text("\(snapshot.playerScore) : \(snapshot.enemyScore)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 26) {
                    roundStatColumn(name: "ME", dodgeCount: snapshot.roundPlayerDodgeCount, topAttack: snapshot.roundPlayerTopAttack)
                    roundStatColumn(name: "RIVAL", dodgeCount: snapshot.roundEnemyDodgeCount, topAttack: snapshot.roundEnemyTopAttack)
                }
                .padding(.top, 2)
                if knockout, let finishingPunch = snapshot.roundFinishingPunch {
                    Text("\(loc.t(.roundStatsFinishingBlowLabel)) · \(snapshot.roundFinishingBlowByPlayer ? "ME" : "RIVAL") \(finishingPunch.label)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(titleColor.opacity(0.9))
                        .padding(.top, 2)
                }
                if let rivalRead {
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(titleColor.opacity(0.45))
                            .frame(width: 28, height: 2)
                        Text(loc.t(.roundStatsRivalCornerLabel))
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(titleColor.opacity(0.9))
                        Text(rivalRead)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: 280)
                    }
                    .padding(.top, 3)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(title), 스코어 \(snapshot.playerScore) 대 \(snapshot.enemyScore), "
                + "ME 회피 성공 \(snapshot.roundPlayerDodgeCount)회, 주요 공격 \(snapshot.roundPlayerTopAttack?.label ?? loc.t(.roundStatsNoAttack)), "
                + "RIVAL 회피 성공 \(snapshot.roundEnemyDodgeCount)회, 주요 공격 \(snapshot.roundEnemyTopAttack?.label ?? loc.t(.roundStatsNoAttack))"
                + (knockout && snapshot.roundFinishingPunch != nil
                    ? ", 결정타 \(snapshot.roundFinishingBlowByPlayer ? "ME" : "RIVAL") \(snapshot.roundFinishingPunch!.label)"
                    : "")
                + (rivalRead.map { ", \(loc.t(.roundStatsRivalCornerLabel)) \($0)" } ?? "")
            )

            Button(loc.t(.nextRoundButton)) {
                controller.continueToNextRound()
            }
            .buttonStyle(FightButtonStyle())
            .disabled(!snapshot.canAdvanceRound)
            .opacity(snapshot.canAdvanceRound ? 1 : 0.45)
            .animation(.easeOut(duration: 0.2), value: snapshot.canAdvanceRound)
            .accessibilityLabel(loc.t(.nextRoundButton))
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 20)
        .glowPanel(accent: color)
    }

    private func roundStatColumn(name: String, dodgeCount: Int, topAttack: Punch?) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Text("\(loc.t(.roundStatsDodgeLabel)) \(dodgeCount)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
            Text("\(loc.t(.roundStatsTopAttackLabel)) \(topAttack?.label ?? loc.t(.roundStatsNoAttack))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(minWidth: 96)
    }

    private func controls(size: CGSize, safeAreaInsets: EdgeInsets) -> some View {
        let compact = size.height < 390 || size.width < 700
        let controlWidth: CGFloat = compact ? 50 : 58
        let controlHeight: CGFloat = compact ? 46 : 54
        let attackWidth: CGFloat = compact ? 76 : 90
        let attackHeight: CGFloat = compact ? 66 : 76

        return HStack(alignment: .bottom, spacing: 8) {
            combatPad(width: controlWidth, height: controlHeight)
            Spacer(minLength: 12)
            attackPad(width: attackWidth, height: attackHeight)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, max(12, safeAreaInsets.leading + 8))
        .padding(.trailing, max(12, safeAreaInsets.trailing + 8))
        .padding(.top, compact ? 10 : 16)
        .padding(.bottom, max(10, safeAreaInsets.bottom + 5))
    }

    private func combatPad(width: CGFloat, height: CGFloat) -> some View {
        let locked = controller.snapshot.playerLocked
        return VStack(spacing: 0) {
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    controlSpacer(width: width, height: height)
                    HoldButton(symbol: "arrow.up", label: "전진", width: width, height: height, locked: locked) { controller.move(x: 1, y: 0, active: $0) }
                    controlSpacer(width: width, height: height)
                }
                GridRow {
                    HoldButton(symbol: "arrow.left", label: "왼쪽 이동", width: width, height: height, locked: locked) { controller.move(x: 0, y: -1, active: $0) }
                    HoldButton(symbol: "shield.fill", label: "가드", accent: Color(red: 0.72, green: 0.50, blue: 0.02), width: width, height: height, locked: locked) {
                        controller.guardButton(active: $0)
                    }
                    HoldButton(symbol: "arrow.right", label: "오른쪽 이동", width: width, height: height, locked: locked) { controller.move(x: 0, y: 1, active: $0) }
                }
                GridRow {
                    HoldButton(text: "L\nDUCK", label: "왼쪽 더킹", accent: Color(red: 0.035, green: 0.29, blue: 0.70), width: width, height: height, locked: locked) {
                        controller.duckButton(direction: -1, active: $0)
                    }
                    HoldButton(symbol: "arrow.down", label: "후퇴", width: width, height: height, locked: locked) { controller.move(x: -1, y: 0, active: $0) }
                    HoldButton(text: "R\nDUCK", label: "오른쪽 더킹", accent: Color(red: 0.62, green: 0.03, blue: 0.28), width: width, height: height, locked: locked) {
                        controller.duckButton(direction: 1, active: $0)
                    }
                }
            }
        }
    }

    private func controlSpacer(width: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: height)
    }

    private func attackPad(width: CGFloat, height: CGFloat) -> some View {
        let locked = controller.snapshot.playerLocked
        return VStack(spacing: 6) {
            ActionButton(
                text: "BACKSTEP",
                symbol: "arrow.down.backward",
                color: Color(red: 0.72, green: 0.50, blue: 0.02),
                width: width * 2 + 8,
                height: 40,
                locked: locked,
                action: controller.backstep
            )
            .accessibilityLabel("백스텝")
            HStack(spacing: 7) {
                ActionButton(
                    text: "JAB",
                    color: Color(red: 0.035, green: 0.29, blue: 0.70),
                    width: width,
                    height: height,
                    locked: locked,
                    action: { controller.comboAttack(base: .jab) }
                )
                ActionButton(
                    text: "CROSS",
                    color: Color(red: 0.62, green: 0.03, blue: 0.28),
                    width: width,
                    height: height,
                    locked: locked,
                    action: { controller.comboAttack(base: .cross) }
                )
            }
        }
    }

    private var introOverlay: some View {
        VStack(spacing: 9) {
            Text("FIGHT NIGHT")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
            Text(loc.t(.tagline))
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(loc.t(.introSubtitle))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.67, green: 0.76, blue: 0.88))
            HStack(alignment: .top, spacing: 24) {
                instructionColumn(
                    title: loc.t(.moveDefenseTitle),
                    lines: L.moveDefenseLines(for: loc.language)
                )
                instructionColumn(
                    title: loc.t(.jabCrossTitle),
                    lines: L.jabCrossLines(for: loc.language)
                )
            }
            Button("FIGHT", action: controller.start)
                .buttonStyle(FightButtonStyle())
                .accessibilityLabel("경기 시작")
            Button(loc.t(.waitingRoomButton)) { showsWaitingRoom = true }
                .buttonStyle(ModalButtonStyle(accent: .white.opacity(0.26)))
                .accessibilityLabel("복싱 스타일 및 복장 선택")
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 14)
        .glowPanel(accent: Color(red: 0.035, green: 0.29, blue: 0.70))
    }

    private func instructionColumn(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: 175, alignment: .leading)
    }

    private var pauseOverlay: some View {
        VStack(spacing: 12) {
            Text(loc.t(.pausedTitle))
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Button(loc.t(.resumeButton), action: controller.pause)
                .buttonStyle(FightButtonStyle())
        }
        .padding(24)
        .glowPanel(accent: Color(red: 0.72, green: 0.50, blue: 0.02))
    }

    private func iconButton(_ symbol: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(accessibility)
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(.ultraThinMaterial))
            .background(Circle().fill(Color.black.opacity(configuration.isPressed ? 0.30 : 0.5)))
            .overlay(Circle().stroke(.white.opacity(configuration.isPressed ? 0.45 : 0.26), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct FighterMeter: View {
    let health: Int
    let stamina: Double
    let color: Color
    let reverse: Bool
    let displayName: String
    let accessibilityName: String

    var body: some View {
        VStack(alignment: reverse ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 4) {
                if reverse {
                    Text("HP \(health)")
                    Spacer(minLength: 0)
                    Text(displayName)
                } else {
                    Text(displayName)
                    Spacer(minLength: 0)
                    Text("HP \(health)")
                }
            }
            .font(.system(size: 8, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.82))
            meter(value: Double(health) / 100, color: color, height: 6)
            meter(value: stamina / 100, color: Color(red: 0.35, green: 0.92, blue: 0.52), height: 3)
        }
        .frame(maxWidth: 178)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityName) 체력 \(health), 스태미나 \(Int(stamina))")
    }

    private func meter(value: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(1, max(0, value))
            ZStack(alignment: reverse ? .trailing : .leading) {
                Capsule(style: .continuous).fill(Color(red: 0.07, green: 0.11, blue: 0.17))
                Capsule(style: .continuous).fill(color).frame(width: width)
            }
        }
        .frame(height: height)
    }
}

struct HoldButton: View {
    let symbol: String?
    let text: String?
    let label: String
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    let locked: Bool
    let onPress: (Bool) -> Void
    @State private var isPressed = false

    init(symbol: String, label: String, accent: Color = .white.opacity(0.28), width: CGFloat = 56, height: CGFloat = 50, locked: Bool = false, onPress: @escaping (Bool) -> Void) {
        self.symbol = symbol
        text = nil
        self.label = label
        self.accent = accent
        self.width = width
        self.height = height
        self.locked = locked
        self.onPress = onPress
    }

    init(text: String, label: String, accent: Color = .white.opacity(0.28), width: CGFloat = 56, height: CGFloat = 50, locked: Bool = false, onPress: @escaping (Bool) -> Void) {
        symbol = nil
        self.text = text
        self.label = label
        self.accent = accent
        self.width = width
        self.height = height
        self.locked = locked
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
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: UIStyleKit.combatControlCornerRadius, style: .continuous)
                .fill(
                    isPressed && !locked
                        ? accent.opacity(0.68)
                        : Color(red: 0.075, green: 0.085, blue: 0.105)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIStyleKit.combatControlCornerRadius, style: .continuous)
                .stroke(accent.opacity(isPressed && !locked ? 0.92 : 0.48), lineWidth: isPressed && !locked ? 2.2 : 1.2)
        )
        .shadow(color: isPressed && !locked ? accent.opacity(0.32) : .black.opacity(0.28), radius: isPressed && !locked ? 8 : 4, y: 2)
        .opacity(locked ? 0.4 : 1)
        .saturation(locked ? 0.3 : 1)
        .scaleEffect(isPressed && !locked ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 30, pressing: { pressing in
            isPressed = pressing
            onPress(pressing)
        }, perform: {})
        .accessibilityLabel(locked ? "\(label), 현재 입력 불가" : label)
        .accessibilityAddTraits(.isButton)
    }
}

struct ActionButton: View {
    let text: String
    let symbol: String?
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let locked: Bool
    let action: () -> Void

    init(text: String, symbol: String? = nil, color: Color, width: CGFloat = 60, height: CGFloat = 44, locked: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.symbol = symbol
        self.color = color
        self.width = width
        self.height = height
        self.locked = locked
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
                .font(.system(size: symbol == nil && height >= 60 ? 15 : 10, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(.white)
                .frame(width: width, height: height)
        }
        .buttonStyle(AttackButtonStyle(color: color, locked: locked))
        .accessibilityLabel(locked ? "\(text), 현재 입력 불가" : text)
    }
}

private struct AttackButtonStyle: ButtonStyle {
    let color: Color
    let locked: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !locked
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: UIStyleKit.combatControlCornerRadius, style: .continuous)
                    .fill(pressed ? color : color.opacity(0.76))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIStyleKit.combatControlCornerRadius, style: .continuous)
                    .stroke(.white.opacity(pressed ? 0.34 : 0.18), lineWidth: pressed ? 1.6 : 1)
            )
            .shadow(color: pressed ? color.opacity(0.42) : .black.opacity(0.34), radius: pressed ? 10 : 5, y: pressed ? 2 : 4)
            .opacity(locked ? 0.4 : 1)
            .saturation(locked ? 0.3 : 1)
            .scaleEffect(pressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct FightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let accent = Color(red: 0.035, green: 0.29, blue: 0.70)
        configuration.label
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 34)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: UIStyleKit.controlCornerRadius, style: .continuous)
                    .fill(accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIStyleKit.controlCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: accent.opacity(configuration.isPressed ? 0.15 : 0.3), radius: configuration.isPressed ? 4 : 10, y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

struct ModalButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 112, minHeight: 38)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: UIStyleKit.controlCornerRadius, style: .continuous)
                    .fill(accent.opacity(configuration.isPressed ? 0.42 : 0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIStyleKit.controlCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.15 : 0.3), radius: configuration.isPressed ? 3 : 8, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// The style/outfit selection screen. Reused both from the in-fight settings menu and directly from the
/// main menu (so players can gear up before ever starting a fight) — extracted out of `GameView` so both
/// call sites share one implementation instead of two copies.
struct WaitingRoomView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    let onClose: () -> Void

    // Decoupled from `controller.equippedOutfit` so tapping a LOCKED outfit can preview its look in the 3D
    // rig above without actually equipping it (equipping still requires the outfit to be unlocked).
    @State private var previewOutfit: OutfitID

    init(controller: GameController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        _previewOutfit = State(initialValue: controller.equippedOutfit)
    }

    var body: some View {
        ZStack {
            // Background alone bleeds under the notch/home-indicator; the content HStack below does NOT
            // ignore the safe area, so titles/buttons never get pushed off-screen or clipped at the edges.
            Color(red: 0.03, green: 0.065, blue: 0.125)
                .ignoresSafeArea()

            HStack(spacing: 16) {
                VStack(spacing: 18) {
                    Text(loc.t(.waitingRoomButton))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    StylePreviewView(style: controller.playerStyle, outfit: previewOutfit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: UIStyleKit.cardCornerRadius, style: .continuous).fill(Color.black))
                        .overlay(RoundedRectangle(cornerRadius: UIStyleKit.cardCornerRadius, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: UIStyleKit.cardCornerRadius, style: .continuous))
                        .accessibilityLabel("\(controller.playerStyle.label(for: loc.language)) 스타일 캐릭터 미리보기, 360도 회전 중")

                    VStack(spacing: 4) {
                        Text(controller.playerStyle.label(for: loc.language))
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(controller.playerStyle.summary(for: loc.language))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.67, green: 0.76, blue: 0.88))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 16) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(loc.t(.fightingStyleLabel))
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
                                VStack(spacing: 10) {
                                    ForEach(FightStyle.allCases, id: \.self) { style in
                                        styleButton(style)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text(loc.t(.outfitLabel))
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
                                VStack(spacing: 10) {
                                    ForEach(OutfitID.allCases, id: \.self) { outfit in
                                        outfitButton(outfit)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Button(loc.t(.close), action: onClose)
                        .buttonStyle(ModalButtonStyle(accent: .white.opacity(0.26)))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("대기실 닫기")
                }
                .padding(22)
                .frame(width: 280)
                .frame(maxHeight: .infinity)
                .glowPanel(accent: Color(red: 0.72, green: 0.50, blue: 0.02))
            }
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func styleButton(_ style: FightStyle) -> some View {
        let isSelected = controller.playerStyle == style
        return Button {
            controller.setPlayerStyle(style)
        } label: {
            VStack(spacing: 3) {
                Text(style.label(for: loc.language))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                Text(style.summary(for: loc.language))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .selectableChip(isSelected: isSelected, accent: Color(red: 0.035, green: 0.29, blue: 0.70))
        }
        .accessibilityLabel("\(style.label(for: loc.language)) 스타일 선택")
    }

    private func outfitButton(_ outfit: OutfitID) -> some View {
        let unlocked = outfit.isUnlocked(
            highestRound: controller.engine.highestRound,
            totalWins: controller.playerStats.totalWins,
            gymSeconds: controller.playerStats.gymSeconds,
            perfectRoundWins: controller.playerStats.perfectRoundWins,
            bestWinStreak: controller.playerStats.bestWinStreak,
            winsByStyle: controller.playerStats.winsByStyle
        )
        let isEquipped = controller.equippedOutfit == outfit
        let isPreviewing = previewOutfit == outfit
        return Button {
            // Always update the live 3D preview, even for a locked outfit -- only actually equip it
            // (persist as the outfit worn into real matches) once it's unlocked.
            previewOutfit = outfit
            if unlocked {
                controller.setEquippedOutfit(outfit)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                    }
                    Text(outfit.label(for: loc.language))
                        .font(.system(size: 11, weight: .black, design: .rounded))
                    if isEquipped {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
                    }
                    Spacer(minLength: 0)
                }
                if !unlocked {
                    Text(outfit.unlockDescription(for: loc.language))
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .foregroundStyle(unlocked ? .white : .white.opacity(0.4))
            .padding(.horizontal, 14)
            .padding(.vertical, unlocked ? 8 : 6)
            .frame(maxWidth: .infinity)
            .selectableChip(isSelected: isPreviewing, accent: Color(red: 0.72, green: 0.50, blue: 0.02))
        }
        .accessibilityLabel(
            unlocked
                ? "\(outfit.label(for: loc.language)) 복장 선택"
                : "\(outfit.label(for: loc.language)) 복장, 잠김, 미리보기 가능, \(outfit.unlockDescription(for: loc.language))"
        )
    }
}

/// The single consolidated settings surface: sound + haptics toggles everywhere, plus context-specific
/// extras — mid-fight (`onExitToMenu` provided) adds an exit-to-main-menu row; the main menu
/// (`showsLanguageRow: true`) adds a language picker instead. Deliberately narrow (exactly 3 rows in each
/// context) rather than one big shared menu with everything visible at once.
struct SettingsMenuView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var haptics = HapticsManager.shared
    var showsLanguageRow = false
    var onExitToMenu: (() -> Void)? = nil
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(loc.t(.settingsTitle))
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.bottom, 4)

            settingsRow(
                symbol: controller.isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                title: controller.isSoundMuted ? loc.t(.soundOff) : loc.t(.soundOn),
                accent: .white.opacity(0.20)
            ) {
                controller.setSoundMuted(!controller.isSoundMuted)
            }

            settingsRow(
                symbol: haptics.isEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash",
                title: haptics.isEnabled ? loc.t(.hapticsOn) : loc.t(.hapticsOff),
                accent: Color(red: 0.05, green: 0.55, blue: 0.12).opacity(0.28)
            ) {
                haptics.setEnabled(!haptics.isEnabled)
            }

            if showsLanguageRow {
                languageRow
            }

            if let onExitToMenu {
                settingsRow(
                    symbol: "rectangle.portrait.and.arrow.right",
                    title: loc.t(.exitToMenu),
                    accent: .white.opacity(0.12),
                    action: onExitToMenu
                )
            }

            Button(loc.t(.close), action: onClose)
                .buttonStyle(ModalButtonStyle(accent: .white.opacity(0.26)))
                .padding(.top, 4)
                .accessibilityLabel(loc.t(.close))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .glowPanel(accent: Color(red: 0.035, green: 0.29, blue: 0.70))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 18)
                Text(loc.t(.language))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            HStack(spacing: 8) {
                ForEach(AppLanguage.allCases, id: \.self) { candidate in
                    let isSelected = loc.language == candidate
                    Button {
                        loc.setLanguage(candidate)
                    } label: {
                        Text(candidate.nativeName)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .selectableChip(isSelected: isSelected, accent: Color(red: 0.035, green: 0.29, blue: 0.70))
                    }
                    .accessibilityLabel(candidate.nativeName)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 250)
    }

    private func settingsRow(symbol: String, title: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .frame(width: 250)
            .background(RoundedRectangle(cornerRadius: UIStyleKit.chipCornerRadius, style: .continuous).fill(accent))
            .overlay(RoundedRectangle(cornerRadius: UIStyleKit.chipCornerRadius, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 1))
        }
        .accessibilityLabel(title)
    }
}

/// The "reset rival learning" confirmation — shared by the main menu's "새로하기" flow (its own default
/// entry point; in-fight settings no longer offers a reset shortcut, so this is main-menu-only now).
struct LearningResetConfirmView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.70, blue: 0.10))
            Text(loc.t(.resetConfirmTitle))
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(loc.t(.resetConfirmBody))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(red: 0.72, green: 0.80, blue: 0.90))
                .frame(maxWidth: 330)
            HStack(spacing: 10) {
                Button(loc.t(.cancel), action: onCancel)
                    .buttonStyle(ModalButtonStyle(accent: .white.opacity(0.26)))
                    .accessibilityLabel("초기화 취소")
                Button(loc.t(.resetConfirmButton), action: onConfirm)
                    .buttonStyle(ModalButtonStyle(accent: Color(red: 0.68, green: 0.035, blue: 0.11)))
                    .accessibilityLabel("학습 초기화 후 라운드 1 재시작")
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .glowPanel(accent: Color(red: 0.68, green: 0.035, blue: 0.11))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
