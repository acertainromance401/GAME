/*
 UIStyleKit.swift

 파일 설명:
 - 앱 전반에서 사용하는 UI 스타일 상수(색상, 폰트 크기, 모서리 반경, 애니메이션 지속시간 등)와
     공용 View modifier들을 정의합니다.
 - 접근성 옵션(`RivalReducedMotion`)을 처리해 모션 감속(감소 모션) 사용 시 애니메이션을 억제합니다.

 사용 영향 및 주의사항:
 - 이 파일은 시각적 스타일을 정의하는 헬퍼 모음이며, 런타임 로직(게임 규칙)을 변경하지 않습니다.
 - 주석만 추가되었으므로 컴파일/런타임에는 영향이 없습니다.
*/
// - `glowPanel` 등의 View extension은 공통 패널/칩 스타일을 통일합니다.

import SwiftUI
private enum ReducedMotionOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var rivalReducedMotionOverride: Bool {
        get { self[ReducedMotionOverrideKey.self] }
        set { self[ReducedMotionOverrideKey.self] = newValue }
    }
}

/// The system accessibility value is read-only. A separate override supports isolated UI tests
/// without changing the user's device settings or disabling a system-requested reduction.
@propertyWrapper
struct RivalReducedMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemValue
    @Environment(\.rivalReducedMotionOverride) private var overrideValue

    var wrappedValue: Bool { systemValue || overrideValue }
}

/// Matte surfaces and restrained borders. Shared controls respond quickly without elastic overshoot.
enum UIStyleKit {
    static let cardCornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 6
    static let combatControlCornerRadius: CGFloat = 8
    static let microDuration = 0.12
    static let fastDuration = 0.20
    static let transitionDuration = 0.30
}

private struct GlowPanelBackground: ViewModifier {
    let accent: Color
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(Color(red: 0.035, green: 0.039, blue: 0.047)))
            .overlay(shape.stroke(accent.opacity(0.42), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
    }
}

extension View {
    /// Legacy API name retained for existing callers; renders a solid matte panel, not glass or glow.
    func glowPanel(accent: Color, cornerRadius: CGFloat = UIStyleKit.cardCornerRadius) -> some View {
        modifier(GlowPanelBackground(accent: accent, cornerRadius: cornerRadius))
    }

}
