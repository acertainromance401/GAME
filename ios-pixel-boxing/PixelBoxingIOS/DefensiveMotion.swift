import Foundation
import simd

struct DuckMotion: Equatable, Sendable {
    static let entryDuration = 0.09
    static let releaseDuration = 0.12
    static let minimumEvadeAmount: Float = 0.70
    private(set) var direction: Float = 0

    mutating func advance(direction requested: Int, deltaTime: Double) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let target = Float(min(1, max(-1, requested)))
        let duration = target == 0 ? Self.releaseDuration : Self.entryDuration
        let step = Float(deltaTime / duration)
        direction += min(step, max(-step, target - direction))
    }

    func evades(_ punch: Punch) -> Bool {
        guard let required = CombatData.requiredDuck[punch] else { return false }
        return direction * Float(required) >= Self.minimumEvadeAmount
    }
}

struct BackstepState: Equatable, Sendable {
    static let travelDuration = 0.18
    static let evadeStart = 0.035
    static let evadeEnd = 0.18
    private(set) var elapsed = CombatData.backstepDuration
    private var travelX = 0.0
    private var travelY = 0.0

    var isActive: Bool { elapsed < CombatData.backstepDuration }
    var isEvading: Bool { isActive && elapsed >= Self.evadeStart && elapsed < Self.evadeEnd }

    mutating func start(facingX: Double, facingY: Double) {
        elapsed = 0
        travelX = -facingX * CombatData.backstepDistance
        travelY = -facingY * CombatData.backstepDistance
    }

    mutating func advance(_ deltaTime: Double) -> (x: Double, y: Double) {
        guard isActive, deltaTime.isFinite, deltaTime > 0 else { return (0, 0) }
        func travel(_ time: Double) -> Double {
            let amount = min(1, max(0, time / Self.travelDuration))
            return amount * amount * (3 - 2 * amount)
        }
        let previous = elapsed
        elapsed = min(CombatData.backstepDuration, elapsed + deltaTime)
        let amount = travel(elapsed) - travel(previous)
        return (travelX * amount, travelY * amount)
    }

    mutating func cancel() { self = BackstepState() }
}

struct BackstepMotion: Equatable {
    static let duration = BackstepState.travelDuration
    var positionLag: Float = 0
    var rearLift: Float = 0
    var frontLift: Float = 0
    var crouch: Float = 0

    static func sample(elapsed: Double) -> BackstepMotion {
        guard elapsed.isFinite, elapsed >= 0, elapsed < duration else { return BackstepMotion() }
        let t = Float(elapsed / duration)
        func step(_ start: Float, _ end: Float) -> Float {
            guard t > start, t < end else { return 0 }
            return sin(.pi * (t - start) / (end - start))
        }
        return BackstepMotion(positionLag: pow(1 - t, 3), rearLift: step(0, 0.65) * 0.080,
                      frontLift: step(0.30, 1) * 0.060, crouch: sin(.pi * t) * 0.075)
    }
}

enum DefensiveMotion {
    static func guardBlend(current: Float, raised: Bool, deltaTime: Double, reducedMotion: Bool) -> Float {
        let target: Float = raised ? 1 : 0
        if reducedMotion { return target }
        guard deltaTime.isFinite, deltaTime > 0 else { return current }
        let amount = Float(1 - exp(-min(0.05, deltaTime) * (raised ? 34 : 24)))
        let next = current + (target - current) * amount
        return abs(target - next) < 0.002 ? target : min(1, max(0, next))
    }

    /// Visual commitment only; the engine still accepts/evaluates the direction immediately.
    static func duckBlend(current: Float, direction: Int, deltaTime: Double, reducedMotion: Bool) -> Float {
        let target = Float(min(1, max(-1, direction)))
        if reducedMotion { return target }
        guard deltaTime.isFinite, deltaTime > 0 else { return current }
        let rate: Double = direction == 0 ? 22 : 32
        let next = current + (target - current) * Float(1 - exp(-min(0.05, deltaTime) * rate))
        return abs(target - next) < 0.002 ? target : min(1, max(-1, next))
    }

    /// Undo only the pose-root lean/translation for the contact foot. The fighter's actual movement
    /// and facing still apply; KO uses its dedicated full-body transform instead of this compensation.
    static func plantedFoot(_ point: SIMD3<Float>, posePosition: SIMD3<Float>, poseRotation: simd_quatf) -> SIMD3<Float> {
        poseRotation.inverse.act(point - posePosition)
    }

    static func pivotedFoot(_ point: SIMD3<Float>, restYaw: Float, yaw: Float, pitch: Float) -> SIMD3<Float> {
        let pivot = SIMD3<Float>(0, -0.1475, 0.335)
        let rest = simd_quatf(angle: restYaw, axis: SIMD3<Float>(0, 1, 0))
        let rotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        return point + rest.act(pivot) - rotation.act(pivot)
    }
}

/// Alternating contact feet in scene coordinates, independent of upper-body actions.
/// One support foot stays still while the other steps. Teleports/backsteps/KO explicitly rebase it;
/// the state is transient, never written into FighterModel or the saved profile.
struct FootPlantMotion {
    struct Feet {
        var left: SIMD3<Float>
        var right: SIMD3<Float>
    }

    private var leftWorld: SIMD3<Float>?
    private var rightWorld: SIMD3<Float>?
    private var previousRoot: SIMD3<Float>?
    private var swingLeft: Bool?
    private var swingStart = SIMD3<Float>.zero
    private var swingLead = SIMD3<Float>.zero
    private var swingTime: Double = 0
    private var swingDuration: Double = 0.12
    private var nextLeft = true
    private var lift: Float = 0

    mutating func sample(
        rootPosition: SIMD3<Float>, rootRotation: simd_quatf,
        left: SIMD3<Float>, right: SIMD3<Float>, deltaTime: Double,
        moving: Bool, reset: Bool = false, reducedMotion: Bool = false
    ) -> Feet {
        let leftTarget = rootPosition + rootRotation.act(SIMD3<Float>(left.x, 0.14, left.z))
        let rightTarget = rootPosition + rootRotation.act(SIMD3<Float>(right.x, 0.14, right.z))
        let displacement = previousRoot.map { rootPosition - $0 } ?? .zero
        let teleport = simd_length(displacement) > 1.0
        if reset || teleport || leftWorld == nil || rightWorld == nil {
            leftWorld = leftTarget
            rightWorld = rightTarget
            previousRoot = rootPosition
            swingLeft = nil
            swingTime = 0
            lift = 0
            nextLeft = true
            return Feet(left: left, right: right)
        }
        let dt = deltaTime.isFinite ? min(0.05, max(0, deltaTime)) : 0
        if dt > 0 {
            previousRoot = rootPosition
            var velocity = displacement / Float(dt)
            velocity.y = 0
            let speed = simd_length(velocity)
            if speed > 6.5 { velocity *= 6.5 / speed }
            let leftError = simd_distance(leftWorld!, leftTarget)
            let rightError = simd_distance(rightWorld!, rightTarget)
            if swingLeft == nil, max(leftError, rightError) > (moving ? 0.045 : 0.025) {
                // Larger error catches up first; ties alternate rather than crossing the feet.
                let localVelocity = rootRotation.inverse.act(velocity)
                let directionFirst: Bool
                if abs(localVelocity.x) > abs(localVelocity.z), abs(localVelocity.x) > 0.01 {
                    directionFirst = localVelocity.x > 0
                } else if abs(localVelocity.z) > 0.01 {
                    directionFirst = localVelocity.z > 0
                } else {
                    directionFirst = nextLeft
                }
                let chooseLeft = abs(leftError - rightError) > 0.025 ? leftError > rightError : directionFirst
                swingLeft = chooseLeft
                swingStart = chooseLeft ? leftWorld! : rightWorld!
                swingTime = 0
                swingDuration = moving ? max(0.08, 0.15 - Double(min(6.5, speed)) * 0.011) : 0.10
                var lead = localVelocity * (moving ? 0.035 : 0)
                lead.x = min(0.10, max(-0.10, lead.x))
                swingLead = rootRotation.act(lead)
            }
            if let swingLeft {
                swingTime = min(swingDuration, swingTime + dt)
                let t = Float(swingTime / swingDuration)
                let eased = t * t * (3 - 2 * t)
                // A short lead avoids dragging the recovery foot behind fast lateral movement.
                // Cap lateral anticipation to preserve each style's stance width.
                // Retain this step's lead if an attack stops locomotion mid-step; do not yank it back.
                var targetLocal = rootRotation.inverse.act(
                    (swingLeft ? leftTarget : rightTarget) + swingLead - rootPosition)
                let supportLocal = rootRotation.inverse.act((swingLeft ? rightWorld! : leftWorld!) - rootPosition)
                targetLocal.x = swingLeft ? max(targetLocal.x, supportLocal.x + 0.26)
                    : min(targetLocal.x, supportLocal.x - 0.26)
                let target = rootPosition + rootRotation.act(targetLocal)
                let position = swingStart + (target - swingStart) * eased
                if swingLeft { leftWorld = position } else { rightWorld = position }
                lift = sin(.pi * t) * (reducedMotion ? 0.025 : 0.065)
                if t >= 1 {
                    self.swingLeft = nil
                    nextLeft = !swingLeft
                    lift = 0
                }
            }
        }
        var localLeft = rootRotation.inverse.act(leftWorld! - rootPosition)
        var localRight = rootRotation.inverse.act(rightWorld! - rootPosition)
        // Preserve attack heel lift and the existing shoe-ground height.
        localLeft.y = left.y + (swingLeft == true ? lift : 0)
        localRight.y = right.y + (swingLeft == false ? lift : 0)
        return Feet(left: localLeft, right: localRight)
    }
}