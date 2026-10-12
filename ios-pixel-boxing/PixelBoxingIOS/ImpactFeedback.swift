/// Shared by live match and gym feedback. Haptic values are a small increase over the previous
/// live values; audio texture/volume and event priority are preserved. No gameplay values live here.
struct ImpactFeedback: Equatable, Sendable {
    enum Texture: Equatable, Sendable { case jab, cross, body, hook, uppercut, blocked, guardBreak, knockout }
    enum Haptic: Equatable, Sendable { case light, medium, heavy, soft, rigid }

    let texture: Texture
    let haptic: Haptic
    let intensity: Double
    let volume: Float

    static func sample(_ impact: CombatImpact) -> ImpactFeedback {
        if impact.knockout { return ImpactFeedback(texture: .knockout, haptic: .heavy, intensity: 1, volume: 0.95) }
        if impact.guardBroken { return ImpactFeedback(texture: .guardBreak, haptic: .rigid, intensity: 0.90, volume: 0.85) }
        if impact.guarded { return ImpactFeedback(texture: .blocked, haptic: .soft, intensity: 0.30, volume: 0.48) }

        let texture: Texture
        let haptic: Haptic
        let intensity: Double
        let volume: Float
        switch CombatData.attacks[impact.punch]?.family {
        case .body:
            texture = .body; haptic = .medium; intensity = 0.59; volume = 0.72
        case .hook:
            texture = .hook; haptic = .heavy; intensity = 0.75; volume = 0.80
        case .uppercut:
            texture = .uppercut; haptic = .heavy; intensity = 0.83; volume = 0.84
        default:
            texture = impact.punch == .jab ? .jab : .cross
            haptic = impact.punch == .jab ? .light : .heavy
            intensity = impact.punch == .jab ? 0.38 : 0.69
            volume = impact.punch == .jab ? 0.62 : 0.76
        }
        // Preserve the existing live family styles even for counters. The former, unused profile's
        // extra counter gain must not turn this modest increase into a second, much larger boost.
        return ImpactFeedback(
            texture: texture, haptic: haptic, intensity: intensity, volume: volume
        )
    }
}
