import Foundation

/// Render-only orthodox weave: dip, stay low during the engine's lateral step, rise on the exit.
/// No FighterModel/CombatData dependency, movement integration, input queue or hit timing here.
/// Direction +1 is RIGHT/exit toward local -X; -1 is LEFT/exit toward local +X.
struct WeaveMotion: Equatable {
    static let duration = WeaveState.duration
    static let lateralStart = WeaveState.evadeStart
    static let lateralEnd = WeaveState.hookStart

    /// 0...1 defensive envelope. Retain it when a hook starts; do NOT multiply by attack recovery.
    var amount: Float = 0
    var crouch: Float = 0
    /// Signed exit-side weight, not a distance. Its sign is input space, opposite local X.
    var side: Float = 0
    var yaw: Float = 0
    var pitch: Float = 0
    var roll: Float = 0
    /// Optional, bounded LOCAL pose shift. Never add the engine's 12 game units here again.
    var rootX: Float = 0
    /// Informational progress while active (resets when inactive), never world-position deltas.
    var lateralProgress: Float = 0
    var riseProgress: Float = 0

    static func sample(direction: Int, elapsed: Double, reducedMotion: Bool = false) -> WeaveMotion {
        guard direction != 0, elapsed.isFinite, elapsed > 0, elapsed < duration else {
            return WeaveMotion()
        }
        let sign: Float = direction > 0 ? 1 : -1
        let dip = smoothStep(elapsed / lateralStart)
        let lateral = smoothStep((elapsed - lateralStart) / (lateralEnd - lateralStart))
        let rise = smoothStep((elapsed - lateralEnd) / (duration - lateralEnd))
        let amount = dip * (1 - rise)
        let side = sign * amount
        let underArc = sin(.pi * lateral)
        return WeaveMotion(
            amount: amount, crouch: (0.34 + 0.06 * underArc) * amount, side: side,
            yaw: -0.22 * side * (0.25 + 0.75 * lateral),
            pitch: -(0.12 + 0.10 * underArc) * amount,
            roll: reducedMotion ? 0 : 0.045 * side * (1 - 2 * lateral),
            rootX: -0.055 * side * lateral,
            lateralProgress: lateral, riseProgress: rise
        )
    }

    private static func smoothStep(_ value: Double) -> Float {
        let t = min(1, max(0, value))
        return Float(t * t * (3 - 2 * t))
    }

    /// A hook keeps the exit posture until contact, then releases it during its OWN recovery.
    /// This changes only the pose: evasion/travel still end on the engine's original weave clock.
    func carryingHook(progress: Float, contactProgress: Float) -> WeaveMotion {
      guard progress.isFinite, contactProgress.isFinite, progress < 1 else { return WeaveMotion() }
      let release = Self.smoothStep(Double((progress - contactProgress) / max(0.001, 1 - contactProgress)))
      let weight = 1 - release
      var result = self
      result.amount *= weight
      result.crouch *= weight
      result.side *= weight
      result.yaw *= weight
      result.pitch *= weight
      result.roll *= weight
      result.rootX *= weight
      return result
    }
}
