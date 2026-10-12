/*
 CombatPresentation.swift

 파일 설명:
 - 전투 중의 시각적 연출(Camera shakes, signature text, impact flashes, particle-like effects 등)을
     담당하는 프레젠테이션 레이어입니다. 게임 규칙 자체를 변경하지 않고, 유저에게 보여줄 정보와
     카메라/음향/햅틱 동기화를 관리합니다.

 사용 영향 및 주의사항:
 - 이 레이어는 시청각·촉각 효과와 타이밍을 관장하므로 접근성(모션 감소) 옵션을 존중해야 합니다.
 - 로직 자체는 게임 상태를 변경하지 않지만, 연출 때문에 입력 타이밍이 체감상 달라보일 수 있습니다.
*/
//   시각·카메라·사운드 트리거로 변환하는 역할만 수행합니다.
// - `CombatPresentation`은 컨트롤러가 전송한 이벤트를 받아 내부 타이밍을 업데이트하고,
//   `@Published` 프로퍼티로 뷰(예: `CombatSignatureView`)에 표시 정보를 제공합니다.
// - 메인 액터에서 동작하며, 프레젠테이션 전용이므로 영속성이나 게임 룰은 포함하지 않습니다.

import Combine
import Foundation

enum Combatant: Equatable, Sendable {
    case player
    case rival
}

/// Facts emitted at resolution time, not inferred later from differences between HUD snapshots.
struct CombatImpact: Equatable, Sendable {
    let attacker: Combatant
    let punch: Punch
    let damage: Int
    let guarded: Bool
    let guardBroken: Bool
    let counter: Bool
    let perfectCounter: Bool
    let knockout: Bool
    var contactPoint: SIMD3<Float>? = nil
    var incomingDirection: SIMD3<Float>? = nil

    var level: ImpactLevel {
        if knockout { return .knockout }
        if perfectCounter { return .perfectCounter }
        if guardBroken { return .guardBreak }
        if guarded { return .blocked }
        if counter { return .counter }
        return damage >= 10 ? .heavy : .light
    }
}

enum CombatEvent: Equatable, Sendable {
    case roundStarted
    case attackStarted(fighter: Combatant)
    case punchSwing(fighter: Combatant, punch: Punch)
    case dodge(fighter: Combatant, grade: DodgeGrade?)
    case impact(CombatImpact)
    case whiff(fighter: Combatant)
    case exhausted(fighter: Combatant)
    case roundEnded(outcome: RoundOutcome, knockout: Bool)
}

/// Presentation-only cue at the authored extension onset, not at button input or hit resolution.
/// Mirrors PunchMotion's hand extension and BodyShovelMotion's end of loading.
enum PunchSwingTiming {
    static func cueTime(spec: AttackSpec) -> Double {
        spec.deliveryStart
    }
}

enum ImpactLevel: Int, Sendable {
    case blocked, light, heavy, counter, guardBreak, perfectCounter, knockout

    var duration: Double {
        switch self {
        case .blocked, .light: 0.10
        case .heavy: 0.14
        case .counter, .guardBreak: 0.18
        case .perfectCounter: 0.24
        case .knockout: 0.34
        }
    }

    var cameraStrength: Float {
        switch self {
        case .blocked, .light: 0
        case .heavy: 0.35
        case .counter, .guardBreak: 0.50
        case .perfectCounter: 0.80
        case .knockout: 1.10
        }
    }
}

enum CombatSignature: String, Sendable {
    case counterWindow = "COUNTER"
    case perfectCounter = "PERFECT COUNTER"
    case knockout = "K.O."

    var priority: Int {
        switch self {
        case .counterWindow: 1
        case .perfectCounter: 2
        case .knockout: 3
        }
    }
}

enum CombatPresentationTiming {
    // Simulation seconds: the KO fall takes 0.9s and is slowed by the existing KO time scale.
    static let knockoutResultReveal = 0.95
    static let decisionResultReveal = 0.35
    // Real presentation seconds, independent of the engine's KO slow motion.
    static let knockoutClockDelay = 0.20
    static let knockoutClockDuration = 0.60
}

enum KnockoutClockPhase {
    case inactive, waiting, visible, finished
}

/// A bounded 80ms presentation pulse AFTER confirmed contact. Visual speed briefly reaches 0.92x,
/// catches up inside the same interval and has no accumulated delay. Never use for the engine clock,
/// pre-contact attack frames, invulnerability, input windows or a KO/dodge cinematic.
enum ImpactMotionBeat {
    static let duration = 0.08

    static func supports(_ impact: CombatImpact?) -> Bool {
        guard let impact else { return false }
        return impact.damage >= 10 && !impact.guarded && !impact.knockout && !impact.perfectCounter
    }

    static func elapsed(_ time: Double, impact: CombatImpact?, reducedMotion: Bool) -> Double {
        guard time.isFinite, time > 0, time < duration, !reducedMotion, supports(impact) else { return time }
        let phase = time / duration
        let lag = 0.08 * duration / (2 * Double.pi) * (1 - cos(2 * Double.pi * phase))
        return time - lag
    }
}

/// Transient presentation only. No damage, AI weights, input windows or persistence live here.
/// The controller sends the same event to this timeline and to sound/haptics on the resolving frame.
@MainActor
/// `CombatPresentation`
/// - 역할: 전투 이벤트를 받아 시그니처(예: COUNTER, K.O.)와 충격 레벨(ImpactLevel) 같은
///   표시용 상태를 관리합니다. 뷰는 이 객체를 관찰해서 애니메이션/카메라/텍스트를 렌더링합니다.
final class CombatPresentation: ObservableObject {
    @Published private(set) var signature: CombatSignature?
    @Published private(set) var knockoutClockPhase: KnockoutClockPhase = .inactive
    private var knockoutClockElapsed = 0.0
    private(set) var impactLevel: ImpactLevel?
    private(set) var impactTime = 0.0
    private(set) var impactElapsed = 0.0
    private var signatureTime = 0.0
    private(set) var playerHit: CombatImpact?
    private(set) var rivalHit: CombatImpact?
    private(set) var playerStrike: CombatImpact?
    private(set) var rivalStrike: CombatImpact?
    private(set) var playerContactTime = 0.0
    private(set) var rivalContactTime = 0.0

    var cameraImpulse: Float {
        guard let impactLevel else { return 0 }
        // Normalize against THIS effect's duration. A KO must not divide 0.34 by a jab's 0.17.
        let remaining = Float(min(1, max(0, impactTime / impactLevel.duration)))
        return impactLevel.cameraStrength * remaining * remaining
    }

    /// One/two display frames at 60fps. Separate from the smoothed camera position so it cannot drift.
    var cameraContactKick: Float {
        guard let impactLevel, impactLevel != .knockout, impactTime > 0 else { return 0 }
        let remaining = max(0, 1 - impactElapsed / (2.0 / 60.0))
        return impactLevel.cameraStrength * Float(remaining * remaining)
    }

    func receive(_ event: CombatEvent) {
        // 게임 로직(컨트롤러/엔진)으로부터 전달된 단일 전투 이벤트를 수신하여
        // 내부 프레젠테이션 상태(시그니처, 임팩트 레벨, 접촉 타이밍 등)를 갱신합니다.
        // 이 메서드는 UI 연출(카메라 임펄스, 텍스트 표시, 임팩트 가시화)에 필요한
        // '사실(fact)' 중심의 정보를 기록하며, 실제 게임 룰/데미지 변경은 수행하지 않습니다.
        // 처리 예시:
        // - .impact: 해당 수신자(player/rival)에 대한 최근 임팩트 저장, 화면 임팩트 레벨 우선순위 결정,
        //            카메라 임펄스용 duration/elapsed 설정
        // - .dodge: 정확한 회피(accurate/perfect)일 경우 카운터 윈도우 시그니처를 보여줌
        switch event {
        case .roundStarted:
            reset()
        case let .attackStarted(fighter):
            if fighter == .player {
                playerStrike = nil
                if signature == .counterWindow { clearSignature() }
            } else {
                rivalStrike = nil
            }
        case let .dodge(fighter: .player, grade: grade):
            if let grade, grade == .accurate || grade == .perfect {
                show(.counterWindow, duration: grade.counterWindow)
            }
        case let .impact(impact):
            // Per-recipient facts survive independently of the single highest-priority camera cue.
            let contactDuration = impact.level.rawValue >= ImpactLevel.heavy.rawValue ? 0.065 : 0.045
            if impact.attacker == .player {
                playerStrike = impact
                rivalHit = impact
                rivalContactTime = contactDuration
            } else {
                rivalStrike = impact
                playerHit = impact
                playerContactTime = contactDuration
            }
            if impactTime <= 0 || impact.level.rawValue >= (impactLevel?.rawValue ?? 0) {
                impactLevel = impact.level
                impactTime = impact.level.duration
                impactElapsed = 0
            }
            if impact.knockout {
                // Retain priority immediately, but keep the finishing motion free of a KO banner.
                show(.knockout, duration: CombatPresentationTiming.knockoutClockDelay
                     + CombatPresentationTiming.knockoutClockDuration)
                knockoutClockElapsed = 0
                knockoutClockPhase = .waiting
            } else if impact.perfectCounter {
                show(.perfectCounter, duration: 0.55)
            } else if signature == .counterWindow {
                clearSignature()
            }
        case .roundEnded(_, knockout: false):
            reset()
        default:
            break
        }
    }

    func advance(deltaTime: Double) {
        // 프레임 간격만큼 내부 카운터들을 전진시킵니다.
        // - impactTime/impactElapsed: 화면 임팩트(카메라/효과) 타이밍 관리
        // - playerContactTime/rivalContactTime: 피격자에게 표시되는 접촉(빨간 플래시 등) 지속시간
        // - signatureTime: 현재 보여지는 `CombatSignature`의 남은 시간
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        playerContactTime = max(0, playerContactTime - deltaTime)
        rivalContactTime = max(0, rivalContactTime - deltaTime)
        impactTime = max(0, impactTime - deltaTime)
        impactElapsed += deltaTime
        if impactTime == 0 { impactLevel = nil }
        if knockoutClockPhase == .waiting || knockoutClockPhase == .visible {
            knockoutClockElapsed += deltaTime
            let end = CombatPresentationTiming.knockoutClockDelay + CombatPresentationTiming.knockoutClockDuration
            let next: KnockoutClockPhase = knockoutClockElapsed >= end ? .finished
                : (knockoutClockElapsed >= CombatPresentationTiming.knockoutClockDelay ? .visible : .waiting)
            // Publish only transitions, not every frame of the presentation clock.
            if next != knockoutClockPhase { knockoutClockPhase = next }
        }
        signatureTime = max(0, signatureTime - deltaTime)
        if signatureTime == 0, signature != nil { clearSignature() }
    }

    private func show(_ next: CombatSignature, duration: Double) {
        // 우선순위가 현재보다 높거나 같을 때만 새 시그니처를 펼칩니다.
        // ex) KO(우선순위 3)는 counterWindow(1) 위에 올라타지만, counterWindow는 KO를 덮지 않습니다.
        guard next.priority >= (signature?.priority ?? 0) else { return }
        signature = next
        signatureTime = duration
    }

    private func clearSignature() {
        signature = nil
        signatureTime = 0
    }

    private func reset() {
        clearSignature()
        knockoutClockElapsed = 0
        knockoutClockPhase = .inactive
        impactLevel = nil
        impactTime = 0
        impactElapsed = 0
        playerHit = nil
        rivalHit = nil
        playerStrike = nil
        rivalStrike = nil
        playerContactTime = 0
        rivalContactTime = 0
    }
}

/// `CombatCameraFocus`
/// - 카메라의 푸시(전후 이동)와 FOV(화각) 조정값을 계산하는 유틸리티 구조체입니다.
/// - 회피 판정·KO 모먼트 등에 따라 화면 프레이밍을 변경해 연출 효과를 줍니다.
struct CombatCameraFocus: Equatable {
    var push: Float = 0
    var fieldOfView: Double = 50

    static func sample(
        dodgeGrade: DodgeGrade?, dodgeTime: Double, knockoutTime: Double, reducedMotion: Bool
    ) -> CombatCameraFocus {
        // Accessibility changes camera motion, never the player's counter opportunity or combat speed.
        guard !reducedMotion else { return CombatCameraFocus() }
        if knockoutTime > 0 {
            let amount = envelope(remaining: knockoutTime, duration: CombatData.koMomentDuration)
            return CombatCameraFocus(push: CombatData.koMomentCameraZoom * amount, fieldOfView: 50 - 8 * Double(amount))
        }
        guard let grade = dodgeGrade, dodgeTime > 0, grade.focusDuration > 0 else {
            return CombatCameraFocus()
        }
        let amount = envelope(remaining: dodgeTime, duration: grade.focusDuration)
        let lensPush: Double = grade == .perfect ? 6 : (grade == .accurate ? 4 : 0)
        return CombatCameraFocus(push: grade.cameraZoom * amount, fieldOfView: 50 - lensPush * Double(amount))
    }

    /// Quick ease-out push, readable hold, then a short return. Unlike a sine wave, most of the
    /// counter window is spent at the intended framing rather than only reaching it halfway through.
    static func envelope(remaining: Double, duration: Double) -> Float {
        guard remaining.isFinite, duration.isFinite, remaining > 0, duration > 0 else { return 0 }
        let elapsed = min(duration, max(0, duration - remaining))
        let attack = min(0.06, duration * 0.25)
        let release = min(0.18, duration * 0.35)
        if elapsed < attack {
            return Float(1 - pow(1 - elapsed / attack, 3))
        }
        if remaining < release {
            let t = remaining / release
            return Float(t * t * (3 - 2 * t))
        }
        return 1
    }
}