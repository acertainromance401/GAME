import Foundation

/// One-shot, orthodox weave shared by the match and gym. Simulation seconds, never actionTime.
/// Not Codable: no long-term habit persistence, new RIVAL read category, or AI weave action in
/// this first slice. The engine observes only executed weaves, not the private hook buffer.
struct WeaveState: Equatable, Sendable {
    static let duration = 0.36
    static let inputGrace = 0.12
    static let hookStart = 0.23
    static let evadeStart = DuckMotion.entryDuration * Double(DuckMotion.minimumEvadeAmount)
    static let evadeEnd = 0.27
    static let stepDistance = 12.0
    static let staminaCost = 9.0

    private(set) var direction = 0
    private(set) var elapsed = 0.0
    private(set) var cooldownRemaining = 0.0
    private var strafeX = 0.0
    private var strafeY = 0.0
    private var pendingHook: Punch?
    private var hookConsumed = false

    var isActive: Bool { direction != 0 && elapsed < Self.duration }
    /// Remains available through the 0.12s recovery grace; zero after consumption/cancellation.
    var comboDirection: Int {
        direction != 0 && elapsed < Self.duration + Self.inputGrace && !hookConsumed ? direction : 0
    }

    static func hook(base: Punch, direction: Int) -> Punch? {
        switch (direction, base) {
        case (-1, .jab): .leftHook
        case (1, .cross): .rightHook
        default: nil
        }
    }

    @discardableResult
        mutating func start(_ dir: Int, facingX: Double = 1, facingY: Double = 0) -> Bool {
        guard dir == -1 || dir == 1, cooldownRemaining <= 0,
              facingX.isFinite, facingY.isFinite else { return false }
        let length = hypot(facingX, facingY)
        guard length > 0.001 else { return false }
        direction = dir
        elapsed = 0
        cooldownRemaining = Self.duration + Self.inputGrace
        strafeX = -facingY / length
        strafeY = facingX / length
        pendingHook = nil
        hookConsumed = false
        return true
    }

    /// Cumulative smoothstep differences prevent frame-rate-dependent travel and facing drift.
    /// Clipped displacement is spent, never saved up as momentum or applied after cancellation.
    @discardableResult
    mutating func advance(_ dt: Double) -> (x: Double, y: Double) {
        guard dt.isFinite, dt > 0 else { return (0, 0) }
        cooldownRemaining = max(0, cooldownRemaining - dt)
        if cooldownRemaining < 1e-12 { cooldownRemaining = 0 }
        guard direction != 0 else { return (0, 0) }
        let previous = elapsed
        elapsed = min(Self.duration + Self.inputGrace, elapsed + dt)
        // Snap only numerical roundoff at authored boundaries (e.g. 60fps at 0.30s).
        for boundary in [Self.evadeStart, Self.hookStart, Self.evadeEnd, Self.duration,
                         Self.duration + Self.inputGrace] where abs(elapsed - boundary) < 1e-12 {
            elapsed = boundary
        }
        let distance = Self.stepDistance * Double(direction) * (Self.travel(elapsed) - Self.travel(previous))
        let displacement = (x: strafeX * distance, y: strafeY * distance)
        if elapsed >= Self.duration + Self.inputGrace {
            direction = 0
            pendingHook = nil
        }
        return displacement
    }

    func evades(_ punch: Punch) -> Bool {
        isActive && elapsed >= Self.evadeStart && elapsed < Self.evadeEnd
            && CombatData.requiredDuck[punch] == direction
    }

    @discardableResult
    mutating func queueHook(base: Punch) -> Bool {
        guard pendingHook == nil, let punch = Self.hook(base: base, direction: comboDirection) else { return false }
        pendingHook = punch
        return true
    }

    /// Take once. If the fighter cannot execute now, the request is dropped rather than retried later.
    mutating func takeReadyHook() -> Punch? {
        guard elapsed >= Self.hookStart, comboDirection != 0, let punch = pendingHook else { return nil }
        pendingHook = nil
        hookConsumed = true
        return punch
    }

    /// A menu/hit/exhaustion stops all motion and grace, but cannot bypass the started cooldown.
    mutating func cancel() {
        direction = 0
        elapsed = 0
        strafeX = 0
        strafeY = 0
        pendingHook = nil
        hookConsumed = false
    }

    mutating func reset() { self = WeaveState() }

    private static func travel(_ time: Double) -> Double {
        let t = min(1, max(0, (time - evadeStart) / (hookStart - evadeStart)))
        return t * t * (3 - 2 * t)
    }
}

extension FighterModel {
    /// Match cost is style-independent; the gym opts out of both the affordability gate and debit.
    /// Spending exactly the remaining stamina is accepted, then exhaustion cancels the weave.
    /// Unlike a backstep's immediate displacement, no future weave movement/evasion is reserved.
    @discardableResult
    func beginWeave(direction: Int, spendsStamina: Bool = true) -> Bool {
        guard hp > 0, !knockedOut, attack == nil, stagger <= 0, exhausted <= 0,
              invulnerable <= 0, !backstep.isActive, (!spendsStamina || stamina >= WeaveState.staminaCost),
              weave.start(direction, facingX: facingX, facingY: facingY) else { return false }
          weaveOrigin = SIMD2(x, y)
        if spendsStamina { stamina = max(0, stamina - WeaveState.staminaCost) }
        guarding = false
        duckDirection = 0
        duckTime = 0
        pendingDodgeCounter = false
        return true
    }

    @discardableResult
    func queueWeaveHook(base: Punch) -> Bool {
        guard hp > 0, !knockedOut, attack == nil, stagger <= 0, exhausted <= 0,
              invulnerable <= 0, !backstep.isActive else { return false }
        return weave.queueHook(base: base)
    }

    func advanceWeave(_ dt: Double) -> (x: Double, y: Double) {
        if hp <= 0 || knockedOut || stagger > 0 || exhausted > 0 { weave.cancel() }
        return weave.advance(dt)
    }
}