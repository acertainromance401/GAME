/*
 RivalMenuComponents.swift

 파일 설명:
 - 라이벌 선택/대결 관련 메뉴 컴포넌트(초상화, 카드, 요약 패널 등)를 모아둔 UI 헬퍼 파일입니다.
 - 재사용 가능한 뷰 조각들을 정의해 메인 메뉴와 상대 선택 화면에서 공유합니다.

 사용 영향 및 주의사항:
 - 이 파일의 변경은 메뉴 표시와 유저 흐름에 영향을 줄 수 있으니 UI 연결을 함께 점검하세요.
*/
import SwiftUI

enum PreparationPalette {
    static let paper = Color(red: 0.925, green: 0.918, blue: 0.886)
    static let surface = Color(red: 0.96, green: 0.953, blue: 0.929)
    static let ink = Color(red: 0.06, green: 0.075, blue: 0.082)
    static let secondary = Color(red: 0.35, green: 0.38, blue: 0.38)
    static let selected = Color(red: 0.855, green: 0.84, blue: 0.808)
    static let rule = ink.opacity(0.18)
    static let player = Color(red: 0.13, green: 0.31, blue: 0.43)
    static let rival = Color(red: 0.55, green: 0.22, blue: 0.20)
}

struct RivalWordmark: View {
    let width: CGFloat
    var color = MainMenuPalette.paper

    var body: some View {
        Image("RivalWordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width * 300 / 1064)
            .foregroundStyle(color)
            .accessibilityLabel("RIVAL")
    }
}

/// Shared editorial header; content stays inside the safe area while only the background bleeds out.
struct RivalScreenHeader: View {
    let kicker: String
    let title: String
    let closeTitle: String
    let closeID: String
    let onClose: () -> Void
    var onPaper = false
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(onPaper ? PreparationPalette.secondary : MainMenuPalette.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: min(42, titleSize), weight: .semibold))
                    .foregroundStyle(onPaper ? PreparationPalette.ink : MainMenuPalette.paper)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Label(closeTitle, systemImage: "arrow.left")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(RivalMenuButtonStyle(onPaper: onPaper))
            .accessibilityLabel(closeTitle)
            .accessibilityIdentifier(closeID)
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(onPaper ? PreparationPalette.rule : MainMenuPalette.rule).frame(height: 1)
        }
    }
}

struct RivalMenuButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false
    var onPaper = false
    @ScaledMetric(relativeTo: .subheadline) private var textSize: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: textSize, weight: .semibold))
            .foregroundStyle(destructive ? MainMenuPalette.paper :
                primary ? (onPaper ? PreparationPalette.paper : MainMenuPalette.background) :
                    (onPaper ? PreparationPalette.ink : MainMenuPalette.paper))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: primary ? 48 : 44)
            .background(destructive ? MainMenuPalette.rival :
                primary ? (onPaper ? PreparationPalette.ink : MainMenuPalette.paper) :
                    (onPaper ? PreparationPalette.surface : MainMenuPalette.surface),
                        in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(onPaper ? PreparationPalette.rule : MainMenuPalette.rule, lineWidth: 1))
            .rivalPressFeedback(isPressed: configuration.isPressed)
    }
}

private struct RivalSelectionFeedback: ViewModifier {
    let isSelected: Bool
    let onPaper: Bool
    @RivalReducedMotion private var reducedMotion

    func body(content: Content) -> some View {
        content
            .background(onPaper ? (isSelected ? PreparationPalette.selected : PreparationPalette.surface) :
                (isSelected ? MainMenuPalette.paper.opacity(0.09) : MainMenuPalette.surface),
                        in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(onPaper ? (isSelected ? PreparationPalette.ink : PreparationPalette.rule) :
                    (isSelected ? MainMenuPalette.paper.opacity(0.8) : MainMenuPalette.rule), lineWidth: 1))
            .animation(reducedMotion ? nil : .easeOut(duration: UIStyleKit.fastDuration), value: isSelected)
    }
}

extension View {
    func rivalPaperSurface() -> some View {
        background(PreparationPalette.paper, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(PreparationPalette.ink)
    }

    func rivalSelection(isSelected: Bool, onPaper: Bool = false) -> some View {
        modifier(RivalSelectionFeedback(isSelected: isSelected, onPaper: onPaper))
    }

}

struct RoundRecordTable: View {
    let snapshot: CombatSnapshot
    var opponentName = "RIVAL"
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text(loc.t(.leaderboardYouLabel)).foregroundStyle(PreparationPalette.player)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(opponentName).foregroundStyle(PreparationPalette.rival)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline.weight(.bold))
            GridRow {
                Text(loc.t(.roundStatsDodgeLabel)).foregroundStyle(PreparationPalette.secondary)
                    .accessibilityIdentifier("roundRecordDodges")
                Text("\(snapshot.roundPlayerDodgeCount)")
                    .accessibilityIdentifier("roundRecordPlayerDodges")
                Text("\(snapshot.roundEnemyDodgeCount)")
                    .accessibilityIdentifier("roundRecordEnemyDodges")
            }
            GridRow {
                Text(loc.t(.roundStatsTopAttackLabel)).foregroundStyle(PreparationPalette.secondary)
                    .accessibilityIdentifier("roundRecordTopAttack")
                Text(snapshot.roundPlayerTopAttack?.localizedName(for: loc.language) ?? loc.t(.roundStatsNoAttack))
                Text(snapshot.roundEnemyTopAttack?.localizedName(for: loc.language) ?? loc.t(.roundStatsNoAttack))
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(PreparationPalette.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roundRecordTable")
    }
}