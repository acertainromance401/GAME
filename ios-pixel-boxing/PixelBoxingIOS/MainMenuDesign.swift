/*
 MainMenuDesign.swift

 파일 설명:
 - 메인 메뉴의 아트 디렉션(색상 팔레트, 타이포그래피 스케일, 카드 레이아웃 규칙 등)을 정의합니다.
 - 디자인 관련 상수/유틸리티를 여기서 관리해 UI 전반의 비주얼 일관성을 확보합니다.

 사용 영향 및 주의사항:
 - 디자인 상수는 전역적으로 쓰이므로 변경 시 UI 전반의 일관성에 영향을 줄 수 있습니다.
*/
import SwiftUI

/// Shared menu art direction. Combat retains its established team colors and information hierarchy.
enum MainMenuPalette {
    static let background = Color(red: 0.028, green: 0.032, blue: 0.040)
    static let surface = Color(red: 0.055, green: 0.061, blue: 0.073)
    static let paper = Color(red: 0.95, green: 0.94, blue: 0.90)
    static let secondary = Color(red: 0.67, green: 0.69, blue: 0.73)
    static let rival = Color(red: 0.72, green: 0.045, blue: 0.09)
    static let story = Color(red: 0.86, green: 0.69, blue: 0.34)
    static let rule = Color.white.opacity(0.15)
}

struct MainMenuLayout {
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 14
    let menuWidth: CGFloat
    let heroWidth: CGFloat
    let contentHeight: CGFloat
    let gutter: CGFloat
    let displaySize: CGFloat

    /// The supplied size is already inside SwiftUI's safe area. The menu column can scroll at large
    /// text sizes; the hero never competes with the controls for their minimum usable width.
    init(size: CGSize) {
        let width = max(0, size.width - Self.horizontalPadding * 2)
        contentHeight = max(0, size.height - Self.verticalPadding * 2)
        gutter = width < 680 ? 22 : 34
        menuWidth = min(360, max(252, (width - gutter) * 0.44))
        heroWidth = max(0, width - gutter - menuWidth)
        displaySize = contentHeight < 340 ? 48 : (contentHeight < 390 ? 60 : 76)
    }
}

/// Independent, low-amplitude rhythms rather than replaying attacks on a live fighter. Only the
/// menu portrait consumes these offsets; neither physics nor the combat pose timeline is affected.
struct MenuIdleMotion: Equatable, Sendable {
    var breath: Float = 0
    var weightShift: Float = 0
    var leftGuard: Float = 0
    var rightGuard: Float = 0
    var headSway: Float = 0

    static func sample(at time: Double, reducedMotion: Bool) -> MenuIdleMotion {
        guard time.isFinite, !reducedMotion else { return MenuIdleMotion() }
        return MenuIdleMotion(
            breath: Float(sin(time * 2 * .pi / 4.8)) * 0.018,
            weightShift: Float(sin(time * 2 * .pi / 6.7 + 0.6)) * 0.028,
            leftGuard: Float(sin(time * 2 * .pi / 3.9)) * 0.032,
            rightGuard: Float(sin(time * 2 * .pi / 5.3 + 0.9)) * 0.027,
            headSway: Float(sin(time * 2 * .pi / 7.4 + 0.4)) * 0.014
        )
    }
}