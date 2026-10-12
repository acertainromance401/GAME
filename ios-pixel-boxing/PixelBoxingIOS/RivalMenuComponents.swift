/*
 RivalMenuComponents.swift

 파일 설명:
 - 라이벌 선택/대결 관련 메뉴 컴포넌트(초상화, 카드, 요약 패널 등)를 모아둔 UI 헬퍼 파일입니다.
 - 재사용 가능한 뷰 조각들을 정의해 메인 메뉴와 상대 선택 화면에서 공유합니다.

 사용 영향 및 주의사항:
 - 이 파일의 변경은 메뉴 표시와 유저 흐름에 영향을 줄 수 있으니 UI 연결을 함께 점검하세요.
*/
import SwiftUI

/// Shared editorial header; content stays inside the safe area while only the background bleeds out.
struct RivalScreenHeader: View {
    let kicker: String
    let title: String
    let closeTitle: String
    let closeID: String
    let onClose: () -> Void
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(MainMenuPalette.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: min(42, titleSize), weight: .black))
                    .fontWidth(.condensed)
                    .foregroundStyle(MainMenuPalette.paper)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Label(closeTitle, systemImage: "arrow.left")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(RivalMenuButtonStyle())
            .accessibilityLabel(closeTitle)
            .accessibilityIdentifier(closeID)
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(MainMenuPalette.rule).frame(height: 1) }
    }
}

struct RivalMenuButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false
    @RivalReducedMotion private var reducedMotion
    @ScaledMetric(relativeTo: .subheadline) private var textSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: textSize, weight: .semibold))
            .foregroundStyle(primary && !destructive ? MainMenuPalette.background : MainMenuPalette.paper)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(destructive ? MainMenuPalette.rival : (primary ? MainMenuPalette.paper : MainMenuPalette.surface),
                        in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MainMenuPalette.rule, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.98 : 1)
            .animation(.easeOut(duration: UIStyleKit.microDuration), value: configuration.isPressed)
    }
}

extension View {
    func rivalSelection(isSelected: Bool) -> some View {
        self
            .background(isSelected ? MainMenuPalette.paper.opacity(0.09) : MainMenuPalette.surface,
                        in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? MainMenuPalette.paper.opacity(0.8) : MainMenuPalette.rule, lineWidth: 1))
    }
}