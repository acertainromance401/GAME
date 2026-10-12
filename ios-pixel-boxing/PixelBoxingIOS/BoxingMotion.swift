/*
 BoxingMotion.swift

 파일 설명:
 - 전투 애니메이션과 관련된 수학/보간 유틸리티를 제공합니다. 펀치 궤적, 임팩트 반응, 스무딩 함수,
     보간계수 계산 등이 포함됩니다.

 사용 영향 및 주의사항:
 - 이 모듈의 수치 변경은 애니메이션 타이밍과 타격의 시각적 체감에 직접적 영향을 줍니다.
 - 디버깅 시 실제 프레임 단위 변화를 확인하세요.
*/
// - 이 파일의 값들은 물리/데미지에 영향을 주지 않으며, 오직 렌더 연출용입니다.

import Foundation
import simd

/// A shared visual clock for every punch. Contact is the existing activeStart, never a second hit timer.
/// The lower body leads the torso; the hand returns before the existing attack duration expires.
struct PunchMotion: Equatable {
    var reach: Float = 0
    var hipDrive: Float = 0
    var torsoDrive: Float = 0
    var footDrive: Float = 0
    var shoulderDrive: Float = 0
    var load: Float = 0
    var hipLoad: Float = 0
    var torsoLoad: Float = 0
    var followThrough: Float = 0

    static func contactReach(_ punch: Punch, opponentDistance: Float?, reachMultiplier: Float = 1, targetRadius: Float = 0.34) -> Float {
        guard let spec = CombatData.attacks[punch] else { return 0 }
        // Same root-to-glove reach as the match/practice hit check, excluding target surface radius.
        let maximum = Float((spec.range * Double(reachMultiplier) + CombatData.punchReachExtension) * CombatData.sceneScale)
        guard let distance = opponentDistance, distance.isFinite else { return maximum }
        return min(maximum, max(0.20, distance - targetRadius))
    }

    /// Supply only the part beyond the old reach. Close punches keep their existing posture;
    /// at the range edge, chest and hand share the additional travel at contact.
    static func chestAdvance(_ punch: Punch, opponentDistance: Float?, reachMultiplier: Float, targetRadius: Float) -> Float {
        guard let spec = CombatData.attacks[punch] else { return 0 }
        let baseReach = Float(spec.range * Double(reachMultiplier) * CombatData.sceneScale)
        let target = contactReach(punch, opponentDistance: opponentDistance,
                                  reachMultiplier: reachMultiplier, targetRadius: targetRadius)
        let maximum = Float(CombatData.punchReachExtension * CombatData.sceneScale)
        return min(maximum, max(0, target - baseReach))
    }

    static func sample(_ punch: Punch, progress: Float) -> PunchMotion {
        guard progress.isFinite, let spec = CombatData.attacks[punch] else { return PunchMotion() }
        let t = min(1, max(0, progress))
        let contact = Float(spec.activeStart / spec.duration)
        let start = Float(spec.deliveryStart / spec.duration)
        let followEnd = Float(spec.followThroughEnd / spec.duration)
        let recoveryEnd = Float(spec.recoveryEnd / spec.duration)
        let reach: Float
        if spec.family == .straight || spec.family == .hook {
            let delivery = min(1, max(0, (t - start) / max(0.001, contact - start)))
            reach = t <= contact ? delivery * delivery
                : 1 - ease((t - followEnd) / max(0.001, recoveryEnd - followEnd))
        } else {
            reach = pulse(t, start: start, peak: contact,
                          release: contact, end: recoveryEnd)
        }
        if punch == .cross {
            return PunchMotion(
                reach: reach,
                hipDrive: pulse(t, start: start * 0.25, peak: start + (contact - start) * 0.62,
                                release: followEnd, end: recoveryEnd),
                torsoDrive: pulse(t, start: start * 0.70, peak: contact * 0.92,
                                  release: followEnd, end: 1),
                footDrive: pulse(t, start: 0, peak: start + (contact - start) * 0.30,
                                 release: followEnd, end: recoveryEnd),
                shoulderDrive: pulse(t, start: start, peak: contact,
                                     release: followEnd, end: recoveryEnd),
                load: pulse(t, start: 0, peak: start, release: start, end: contact),
                hipLoad: pulse(t, start: 0, peak: start * 0.55,
                               release: start * 0.55, end: start * 1.40),
                torsoLoad: pulse(t, start: start * 0.20, peak: start,
                                 release: start, end: contact * 0.80),
                followThrough: pulse(t, start: contact, peak: followEnd,
                                     release: followEnd, end: recoveryEnd)
            )
        }
        if punch == .jab {
            return PunchMotion(
                reach: reach,
                hipDrive: pulse(t, start: 0, peak: contact * 0.60,
                                release: contact, end: recoveryEnd),
                torsoDrive: pulse(t, start: 0, peak: contact * 0.82,
                                  release: contact, end: recoveryEnd),
                footDrive: pulse(t, start: 0, peak: contact * 0.45,
                                 release: contact, end: recoveryEnd),
                shoulderDrive: pulse(t, start: start, peak: contact,
                                     release: contact, end: recoveryEnd),
                load: pulse(t, start: 0, peak: start, release: start, end: contact) * 0.25,
                hipLoad: pulse(t, start: 0, peak: start, release: start, end: contact * 0.50) * 0.25,
                torsoLoad: pulse(t, start: 0, peak: start, release: start, end: contact * 0.60) * 0.25
            )
        }
        let leading = punch == .leftBody || punch == .leftHook || punch == .leftUppercut
        let footPeak: Float
        let hipPeak: Float
        let torsoPeak: Float
        let loadRelease: Float
        switch spec.family {
        case .hook:
            footPeak = 0.62
            hipPeak = leading ? 0.82 : 0.86
            torsoPeak = 1
            loadRelease = start * 0.65
        case .uppercut:
            footPeak = 0.35
            hipPeak = leading ? 0.62 : 0.70
            torsoPeak = 0.94
            loadRelease = start
        case .body:
            footPeak = 0.25
            hipPeak = leading ? 0.50 : 0.60
            torsoPeak = 0.90
            loadRelease = start
        case .straight:
            return PunchMotion()
        }
        let deliverySpan = contact - start
        return PunchMotion(
            reach: reach,
            hipDrive: pulse(t, start: start * 0.35, peak: start + deliverySpan * hipPeak,
                            release: followEnd, end: recoveryEnd),
            torsoDrive: pulse(t, start: start * 0.75, peak: start + deliverySpan * torsoPeak,
                              release: followEnd, end: 1),
            footDrive: pulse(t, start: start * 0.10, peak: start + deliverySpan * footPeak,
                             release: followEnd, end: recoveryEnd),
            shoulderDrive: pulse(t, start: start, peak: contact,
                                 release: followEnd, end: recoveryEnd),
            load: pulse(t, start: 0, peak: start, release: start, end: contact),
            hipLoad: pulse(t, start: 0, peak: start * 0.55,
                                                     release: loadRelease, end: start + deliverySpan * (spec.family == .hook ? 0.35 : 0.75)),
            torsoLoad: pulse(t, start: start * 0.25, peak: start,
                                                         release: start, end: start + deliverySpan * (spec.family == .hook ? 0.45 : 0.85)),
            followThrough: pulse(t, start: contact, peak: followEnd,
                                 release: followEnd, end: recoveryEnd)
        )
    }

    private static func pulse(_ t: Float, start: Float, peak: Float, release: Float, end: Float) -> Float {
        if t <= peak { return ease((t - start) / max(0.001, peak - start)) }
        return 1 - ease((t - release) / max(0.001, end - release))
    }

    private static func ease(_ value: Float) -> Float {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}

/// Kept for the earlier straight-punch call sites/tests; all attacks now use the same timing model.
typealias StraightPunchMotion = PunchMotion

struct PunchRecoveryMotion {
    var handOffset = SIMD3<Float>.zero
    var torsoTurn: Float = 0
    var hipTurn: Float = 0
    var chestAdvance: Float = 0

    static func progress(_ punch: Punch, progress: Float, landed: Bool) -> Float {
        guard progress.isFinite, let spec = CombatData.attacks[punch] else { return progress }
        let contact = Float(spec.activeStart / spec.duration)
        let end = Float(spec.recoveryEnd / spec.duration)
        guard progress > contact, progress < end else { return progress }
        let phase = (progress - contact) / (end - contact)
        let pulse = sin(.pi * phase)
        return progress + (landed ? 0.16 : -0.12) * (end - contact) * pulse * pulse
    }

    static func sample(_ punch: Punch, progress: Float, landed: Bool, reducedMotion: Bool) -> PunchRecoveryMotion {
        guard progress.isFinite, let spec = CombatData.attacks[punch] else { return PunchRecoveryMotion() }
        let contact = Float(spec.activeStart / spec.duration)
        let end = Float(spec.recoveryEnd / spec.duration)
        guard progress > contact, progress < end else { return PunchRecoveryMotion() }
        let phase = (progress - contact) / (end - contact)
        let pulse = sin(.pi * phase)
        let weight = pulse * pulse * (reducedMotion ? 0.30 : 1)
        let side: Float = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch) ? 1 : -1
        var motion = PunchRecoveryMotion()
        switch spec.family {
        case .straight:
            motion.handOffset = SIMD3<Float>(0, 0, landed ? -0.065 : 0.040)
        case .hook:
            motion.handOffset = landed ? SIMD3<Float>(side * 0.015, -0.010, -0.040)
                : SIMD3<Float>(-side * 0.045, -0.015, -0.010)
        case .uppercut:
            motion.handOffset = landed ? SIMD3<Float>(0, -0.040, -0.030)
                : SIMD3<Float>(side * 0.015, 0.065, -0.010)
        case .body:
            motion.handOffset = landed ? SIMD3<Float>(0, -0.010, -0.050)
                : SIMD3<Float>(side * 0.025, 0.030, 0.020)
        }
        motion.handOffset *= weight
        if !landed {
            motion.torsoTurn = -side * (spec.family == .hook ? 0.10 : 0.055) * weight
            motion.hipTurn = -side * 0.035 * weight
            motion.chestAdvance = 0.015 * weight
        }
        return motion
    }
}

struct FighterPoseRoot: Sendable {
    let position: SIMD3<Float>
    let rotation: simd_quatf

    init(pose: FightPose, reaction: FighterImpactMotion, legacyAmount: Float = 0, legacyDirection: Float = 1) {
        position = SIMD3<Float>(pose.rootX, pose.rootY, pose.rootZ - legacyAmount * 0.26 - reaction.recoil)
        let yaw = (pose.separatesTorsoRotation ? 0 : pose.torsoYaw) - legacyAmount * 0.22
        let roll = legacyAmount * legacyDirection * 0.16 + reaction.roll
        rotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
    }

    func point(_ local: SIMD3<Float>) -> SIMD3<Float> { rotation.act(local) + position }
}

struct FighterDefenseFrame: Sendable {
    let invulnerable: Double
    let exhausted: Double
    let attacking: Bool
    let guarding: Bool
    let guardAmount: Float
    let duckDirection: Int
    let duck: DuckMotion
    let backstep: BackstepState
    let weave: WeaveState

    func advanced(toward other: Self, deltaTime: Double, frameDuration: Double) -> Self {
        var duck = duck
        duck.advance(direction: other.duckDirection, deltaTime: deltaTime)
        var backstep = backstep
        if !backstep.isActive, other.backstep.isActive {
            backstep.start(facingX: 0, facingY: 1)
            _ = backstep.advance(max(0, other.backstep.elapsed - (frameDuration - deltaTime)))
        } else if backstep.isActive, !other.backstep.isActive,
                  backstep.elapsed + frameDuration < CombatData.backstepDuration - 0.000000001 {
            backstep.cancel()
        } else {
            _ = backstep.advance(deltaTime)
        }
        var weave = weave
        if other.weave.direction != 0,
           weave.direction != other.weave.direction || other.weave.elapsed < weave.elapsed {
            weave = WeaveState()
            _ = weave.start(other.weave.direction)
            _ = weave.advance(max(0, other.weave.elapsed - (frameDuration - deltaTime)))
        } else if other.weave.direction == 0, weave.direction != 0,
                  weave.elapsed + frameDuration < WeaveState.duration + WeaveState.inputGrace - 0.000000001 {
            weave.cancel()
        } else {
            _ = weave.advance(deltaTime)
        }
        return Self(invulnerable: max(0, invulnerable - deltaTime),
            exhausted: max(0, exhausted - deltaTime), attacking: other.attacking,
            guarding: other.guarding,
            guardAmount: DefensiveMotion.guardBlend(current: guardAmount, raised: other.guarding,
                deltaTime: deltaTime, reducedMotion: false),
            duckDirection: other.duckDirection, duck: duck, backstep: backstep, weave: weave)
    }
}

struct PunchContactFrame: Sendable {
    let time: Double
    var glove: SIMD3<Float>
    let target: SIMD3<Float>
    var standingTarget: SIMD3<Float>
    let attackerPosition: SIMD3<Float>
    var rootDelta: SIMD2<Float>
    let defense: FighterDefenseFrame

    func blended(with other: Self, amount: Float) -> Self {
        Self(time: time + (other.time - time) * Double(amount),
            glove: glove + (other.glove - glove) * amount,
            target: target + (other.target - target) * amount,
            standingTarget: standingTarget + (other.standingTarget - standingTarget) * amount,
            attackerPosition: attackerPosition + (other.attackerPosition - attackerPosition) * amount,
            rootDelta: rootDelta + (other.rootDelta - rootDelta) * amount,
            defense: defense.advanced(toward: other.defense,
                deltaTime: (other.time - time) * Double(amount), frameDuration: other.time - time))
    }
}

enum PunchContactGeometry {
    static func stance(_ fighter: FighterModel, defended: Bool = true) -> FightPose {
        var pose = FightPose.neutral(stride: 0, style: fighter.style,
            stanceWidth: fighter.style.stanceWidth, leanBias: fighter.style.leanBias,
            pitchBias: fighter.style.pitchBias)
        if defended {
            pose.applyGuard(style: fighter.style, amount: fighter.guardAmount)
            let weave = WeaveMotion.sample(direction: fighter.weave.direction, elapsed: fighter.weave.elapsed)
            pose.applyDuck(direction: fighter.duckMotion.direction * (1 - weave.amount), style: fighter.style)
            pose.applyWeave(weave, style: fighter.style)
            pose.applyBackstep(BackstepMotion.sample(elapsed: fighter.backstep.elapsed))
        }
        pose.resolveArmLengths()
        return pose
    }

    static func worldPoint(_ local: SIMD3<Float>, fighter: FighterModel) -> SIMD3<Float> {
        let scale = Float(CombatData.sceneScale)
        return SIMD3<Float>(Float(fighter.x) * scale + Float(fighter.facingY) * local.x + Float(fighter.facingX) * local.z,
                            local.y,
                            Float(fighter.y) * scale - Float(fighter.facingX) * local.x + Float(fighter.facingY) * local.z)
    }

    static func localPoint(_ world: SIMD3<Float>, fighter: FighterModel) -> SIMD3<Float> {
        let scale = Float(CombatData.sceneScale)
        let delta = world - SIMD3<Float>(Float(fighter.x) * scale, 0, Float(fighter.y) * scale)
        return SIMD3<Float>(Float(fighter.facingY) * delta.x - Float(fighter.facingX) * delta.z,
                            delta.y,
                            Float(fighter.facingX) * delta.x + Float(fighter.facingY) * delta.z)
    }

    static func samplePose(_ fighter: FighterModel, punch forcedPunch: Punch? = nil,
                           progress clockProgress: Float? = nil, aimWorld: SIMD3<Float>? = nil,
                           entryPose: FightPose? = nil) -> FightPose {
        var pose = stance(fighter)
        if let punch = forcedPunch ?? fighter.attack, let spec = CombatData.attacks[punch] {
            let landed = fighter.attack == punch && fighter.acted
            let progress = PunchRecoveryMotion.progress(punch,
                progress: clockProgress ?? Float(min(1, fighter.actionTime / spec.duration)), landed: landed)
            if let entry = entryPose ?? (aimWorld == nil ? fighter.attackEntryPose : nil) {
                pose.blendAttackEntry(entry, punch: punch, progress: progress)
            }
            pose.applyAttack(punch, progress: progress, reachMultiplier: Float(fighter.reachMultiplier(for: punch)),
                             contactTarget: aim(fighter, punch: punch, world: aimWorld))
            pose.applyPunchRecovery(punch, progress: progress, landed: landed, reducedMotion: false)
        }
        fighter.poseTransition?.apply(to: &pose, facingAngle: Float(atan2(fighter.facingX, fighter.facingY)))
        return pose
    }

    static func target(_ fighter: FighterModel, zone: TargetZone, defended: Bool = true) -> SIMD3<Float> {
        var pose = defended ? samplePose(fighter) : stance(fighter, defended: false)
        let reaction = defended ? FighterImpactMotion.sample(fighter.lastImpact, remaining: fighter.hitReaction,
            reducedMotion: false, allowsContactBeat: false) : FighterImpactMotion()
        pose.applyImpact(reaction)
        let root = FighterPoseRoot(pose: pose, reaction: reaction)
        pose.resolveContactSupport(rootPosition: root.position, rootRotation: root.rotation)
        let point = zone == .head ? pose.headFacingPosition
            : pose.facingPoint(SIMD3<Float>(0, pose.torsoY - 0.15, 0.08))
        return worldPoint(root.point(point + (zone == .head ? reaction.headOffset : .zero)), fighter: fighter)
    }

    static func radius(_ zone: TargetZone) -> Float {
        zone == .head ? 0.28 : Float(CombatData.fighterContactRadius)
    }

    static func contactFrame(_ fighter: FighterModel, defender: FighterModel, punch: Punch,
                             spec: AttackSpec, time: Double) -> PunchContactFrame {
        PunchContactFrame(time: time,
            glove: glove(fighter, punch: punch, progress: Float(min(1, time / spec.duration))),
            target: target(defender, zone: spec.targetZone),
            standingTarget: target(defender, zone: spec.targetZone, defended: false),
            attackerPosition: worldPoint(.zero, fighter: fighter),
            rootDelta: SIMD2<Float>(Float(defender.x - fighter.x), Float(defender.y - fighter.y)),
            defense: FighterDefenseFrame(invulnerable: defender.invulnerable, exhausted: defender.exhausted,
                attacking: defender.attack != nil, guarding: defender.guarding, guardAmount: defender.guardAmount,
                duckDirection: defender.duckDirection, duck: defender.duckMotion,
                backstep: defender.backstep, weave: defender.weave))
    }

    static func sweptContact(_ fighter: FighterModel, punch: Punch, from previous: PunchContactFrame,
                         to current: PunchContactFrame, defended: Bool = true,
                         defense: RivalDefense? = nil) -> PunchContactFrame? {
          guard let spec = CombatData.attacks[punch], current.time > previous.time,
              current.defense.invulnerable <= 0 else { return nil }
          let startTime = max(spec.activeStart, previous.time + previous.defense.invulnerable)
        let endTime = min(spec.activeEnd, current.time)
        guard startTime <= endTime else { return nil }
        let frameDuration = current.time - previous.time
        func sample(at time: Double) -> PunchContactFrame {
            let fraction = Float(min(1, max(0, (time - previous.time) / frameDuration)))
            var frame = previous.blended(with: current, amount: fraction)
            if time > previous.time, time < current.time {
                frame.glove = glove(fighter, punch: punch, progress: Float(time / spec.duration))
                    + frame.attackerPosition - current.attackerPosition
            }
            return frame
        }
        let allowance = radius(spec.targetZone) + Float(spec.fistRadius * CombatData.sceneScale)
        let range = Float(fighter.hitRange(punch))
        let facing = SIMD2<Float>(Float(fighter.facingX), Float(fighter.facingY))
        let slope = Float(tan(spec.halfAngle * .pi / 180))
        var start = sample(at: startTime)
        for index in 1...4 {
            let time = startTime + (endTime - startTime) * Double(index) / 4
            let end = sample(at: time)
            let startTarget = defended ? start.target : start.standingTarget
            let endTarget = defended ? end.target : end.standingTarget
            if let contactInterval = overlapInterval(from: start.glove - startTarget,
                                                      to: end.glove - endTarget, radius: allowance),
               let rangeInterval = overlapInterval(from: SIMD3<Float>(start.rootDelta.x, 0, start.rootDelta.y),
                    to: SIMD3<Float>(end.rootDelta.x, 0, end.rootDelta.y), radius: range) {
                let lower = max(contactInterval.lowerBound, rangeInterval.lowerBound)
                let upper = min(contactInterval.upperBound, rangeInterval.upperBound)
                if lower <= upper {
                    let startForward = simd_dot(start.rootDelta, facing)
                    let endForward = simd_dot(end.rootDelta, facing)
                    let startLateral = start.rootDelta.x * facing.y - start.rootDelta.y * facing.x
                    let endLateral = end.rootDelta.x * facing.y - end.rootDelta.y * facing.x
                    if let left = clip(lower...upper, start: startForward * slope - startLateral,
                                       end: endForward * slope - endLateral),
                       let right = clip(left, start: startForward * slope + startLateral,
                                        end: endForward * slope + endLateral),
                       let valid = defenseInterval(right, from: start.defense, to: end.defense,
                                                   punch: punch, defense: defense) {
                        return start.blended(with: end, amount: valid.lowerBound)
                    }
                }
            }
            start = end
        }
        return nil
    }

    private static func defenseInterval(_ interval: ClosedRange<Float>, from start: FighterDefenseFrame,
                                        to end: FighterDefenseFrame, punch: Punch,
                                        defense: RivalDefense?) -> ClosedRange<Float>? {
        guard let defense else { return interval }
        if defense == .backstep {
            guard start.backstep.isActive || end.backstep.isActive,
                  let entry = clip(interval, start: Float(start.backstep.elapsed - BackstepState.evadeStart),
                    end: Float(end.backstep.elapsed - BackstepState.evadeStart)) else { return nil }
            return clip(entry, start: Float(BackstepState.evadeEnd).nextDown - Float(start.backstep.elapsed),
                end: Float(BackstepState.evadeEnd).nextDown - Float(end.backstep.elapsed))
        }
        guard !end.attacking, let required = CombatData.requiredDuck[punch],
              let available = clip(interval, start: -Float(start.exhausted), end: -Float(end.exhausted)) else { return nil }
        if defense == .duck {
            return clip(available, start: start.duck.direction * Float(required) - DuckMotion.minimumEvadeAmount,
                end: end.duck.direction * Float(required) - DuckMotion.minimumEvadeAmount)
        }
        guard start.weave.direction == required || end.weave.direction == required,
              let entry = clip(available, start: Float(start.weave.elapsed - WeaveState.evadeStart),
                end: Float(end.weave.elapsed - WeaveState.evadeStart)) else { return nil }
        return clip(entry, start: Float(WeaveState.evadeEnd).nextDown - Float(start.weave.elapsed),
            end: Float(WeaveState.evadeEnd).nextDown - Float(end.weave.elapsed))
    }

    private static func overlapInterval(from start: SIMD3<Float>, to end: SIMD3<Float>,
                                        radius: Float) -> ClosedRange<Float>? {
        let movement = end - start
        let lengthSquared = simd_length_squared(movement)
        let constant = simd_length_squared(start) - radius * radius
        guard lengthSquared.isFinite, constant.isFinite else { return nil }
        if lengthSquared < 0.00000001 { return constant <= 0 ? 0...1 : nil }
        let halfLinear = simd_dot(start, movement)
        let discriminant = halfLinear * halfLinear - lengthSquared * constant
        guard discriminant >= 0 else { return nil }
        let root = sqrt(discriminant)
        let lower = max(0, (-halfLinear - root) / lengthSquared)
        let upper = min(1, (-halfLinear + root) / lengthSquared)
        return lower <= upper ? lower...upper : nil
    }

    private static func clip(_ interval: ClosedRange<Float>, start: Float, end: Float) -> ClosedRange<Float>? {
        guard start >= 0 || end >= 0 else { return nil }
        var lower = interval.lowerBound
        var upper = interval.upperBound
        if start < 0 { lower = max(lower, -start / (end - start)) }
        if end < 0 { upper = min(upper, start / (start - end)) }
        return lower <= upper ? lower...upper : nil
    }

    private static func surface(_ target: SIMD3<Float>, fighter: FighterModel, radius: Float) -> SIMD3<Float> {
        let origin = worldPoint(.zero, fighter: fighter)
        let horizontal = SIMD3<Float>(target.x - origin.x, 0, target.z - origin.z)
        let distance = simd_length(horizontal)
        let toward = distance > 0.0001 ? horizontal / distance : SIMD3<Float>(0, 0, 1)
        return target - toward * radius
    }

    static func begin(_ fighter: FighterModel, target: SIMD3<Float>, radius: Float) {
        fighter.attackAim = surface(target, fighter: fighter, radius: radius)
        fighter.attackEntryPose = stance(fighter)
    }

    static func alignCrossWindup(_ fighter: FighterModel, target: SIMD3<Float>, radius: Float) {
        guard fighter.isAligningCross else { return }
        fighter.attackAim = surface(target, fighter: fighter, radius: radius)
    }

    static func aim(_ fighter: FighterModel, punch: Punch, world: SIMD3<Float>? = nil) -> SIMD3<Float>? {
        guard let world = world ?? fighter.attackAim, let spec = CombatData.attacks[punch] else { return nil }
        var local = localPoint(world, fighter: fighter)
        let maximum = Float((spec.range * fighter.reachMultiplier(for: punch) + CombatData.punchReachExtension) * CombatData.sceneScale)
        let horizontal = hypot(local.x, local.z)
        if horizontal > maximum {
            local.x *= maximum / horizontal
            local.z *= maximum / horizontal
        }
        return local
    }

    static func glove(_ fighter: FighterModel, punch: Punch, progress: Float? = nil,
                      aimWorld: SIMD3<Float>? = nil, entryPose: FightPose? = nil) -> SIMD3<Float> {
        guard let spec = CombatData.attacks[punch] else { return worldPoint(.zero, fighter: fighter) }
        var pose = samplePose(fighter, punch: punch, progress: progress ?? Float(spec.activeStart / spec.duration),
            aimWorld: aimWorld, entryPose: entryPose)
        let reaction = FighterImpactMotion.sample(fighter.lastImpact, remaining: fighter.hitReaction,
            reducedMotion: false, allowsContactBeat: false)
        pose.applyImpact(reaction)
        let root = FighterPoseRoot(pose: pose, reaction: reaction)
        pose.resolveContactSupport(rootPosition: root.position, rootRotation: root.rotation)
        let leading = punch == .jab || punch == .leftBody || punch == .leftHook || punch == .leftUppercut
        let hand = pose.facingPoint(leading ? pose.leftGlove : pose.rightGlove)
        return worldPoint(root.point(hand), fighter: fighter)
    }

    static func direction(_ fighter: FighterModel, punch: Punch, contact: SIMD3<Float>? = nil,
                          progress: Float? = nil) -> SIMD3<Float> {
        guard let spec = CombatData.attacks[punch] else { return SIMD3<Float>(0, 0, 1) }
        let progress = progress ?? Float(spec.activeStart / spec.duration)
        let entry = fighter.attackEntryPose ?? stance(fighter)
        let current = contact ?? glove(fighter, punch: punch, progress: progress, entryPose: entry)
        let previous = glove(fighter, punch: punch, progress: max(0, progress - 0.01), entryPose: entry)
        let delta = current - previous
        return simd_length_squared(delta) > 0.000001 ? simd_normalize(delta)
            : SIMD3<Float>(Float(fighter.facingX), 0, Float(fighter.facingY))
    }

    static func touches(_ fighter: FighterModel, punch: Punch, target: SIMD3<Float>, radius: Float,
                        contact: SIMD3<Float>? = nil) -> Bool {
        guard let spec = CombatData.attacks[punch] else { return false }
        let allowance = radius + Float(spec.fistRadius * CombatData.sceneScale)
        return simd_distance(contact ?? glove(fighter, punch: punch), target) <= allowance
    }

    static func threatens(_ fighter: FighterModel, punch: Punch, target: SIMD3<Float>, radius: Float,
                          contact: SIMD3<Float>? = nil) -> Bool {
        guard let spec = CombatData.attacks[punch] else { return false }
        guard spec.targetZone == .head else {
            return touches(fighter, punch: punch, target: target, radius: radius, contact: contact)
        }
        let allowance = radius + Float(spec.fistRadius * CombatData.sceneScale)
        let start = Float(max(spec.deliveryStart, spec.activeStart - 0.04) / spec.duration)
        let end = Float(max(spec.activeStart, spec.followThroughEnd) / spec.duration)
        let entry = fighter.attackEntryPose ?? stance(fighter)
        var previous = glove(fighter, punch: punch, progress: start, entryPose: entry)
        for index in 1...4 {
            let progress = start + (end - start) * Float(index) / 4
            let current = glove(fighter, punch: punch, progress: progress, entryPose: entry)
            let segment = current - previous
            let lengthSquared = simd_length_squared(segment)
            let fraction = lengthSquared > 0.000001
                ? min(1, max(0, simd_dot(target - previous, segment) / lengthSquared)) : 0
            let nearest = previous + segment * fraction
            if simd_length_squared(nearest - target) <= allowance * allowance { return true }
            previous = current
        }
        return false
    }

    static func canReach(_ fighter: FighterModel, defender: FighterModel, punch: Punch,
                         targetCenter: SIMD3<Float>? = nil, entryPose: FightPose? = nil) -> Bool {
        guard let spec = CombatData.attacks[punch] else { return false }
        let center = targetCenter ?? target(defender, zone: spec.targetZone, defended: false)
        let targetRadius = radius(spec.targetZone)
        let aimSurface = surface(center, fighter: fighter, radius: targetRadius)
        let hand = glove(fighter, punch: punch, aimWorld: aimSurface, entryPose: entryPose)
        return simd_distance(hand, center) <= targetRadius + Float(spec.fistRadius * CombatData.sceneScale)
    }
}

/// Fixed two-segment IK. A distant target is clamped, never satisfied by scaling a limb.
struct TwoBoneLimb: Sendable {
    let upper: Float
    let lower: Float

    var maximumReach: Float { upper + lower - 0.0001 }

    func solve(root: SIMD3<Float>, target: SIMD3<Float>, pole: SIMD3<Float>, fallback: SIMD3<Float>)
        -> (joint: SIMD3<Float>, end: SIMD3<Float>) {
        let delta = target - root
        let distance = simd_length(delta)
        let axis = distance > 0.0001 ? delta / distance : SIMD3<Float>(0, 0, 1)
        let reach = min(maximumReach, max(abs(upper - lower) + 0.0001, distance))
        let along = (upper * upper - lower * lower + reach * reach) / (2 * reach)
        let height = sqrt(max(0, upper * upper - along * along))
        let hint = pole - root
        var bend = hint - axis * simd_dot(hint, axis)
        if simd_length_squared(bend) < 0.000001 {
            bend = fallback - axis * simd_dot(fallback, axis)
        }
        if simd_length_squared(bend) < 0.000001 {
            let reference = abs(axis.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            bend = reference - axis * simd_dot(reference, axis)
        }
        return (root + axis * along + simd_normalize(bend) * height, root + axis * reach)
    }
}

/// Shared by all punches. Keep the earlier type name for existing pose callers.
/// A guard is a joint arrangement, not a new anatomical arm length.
struct StraightPunchAnatomy: Sendable {
    static let cuffOffset: Float = 0.29
    // Forearm includes the rigid glove cuff; visible skin remains .29, even on the Slugger.
    static let restingArm = TwoBoneLimb(upper: 0.40, lower: 0.58)
    let arm: TwoBoneLimb
    let leftLeg: TwoBoneLimb
    let rightLeg: TwoBoneLimb

    private static let restingAnatomies = Dictionary(uniqueKeysWithValues: FightStyle.allCases.map { style in
        let pose = FightPose.neutral(stride: 0, style: style, stanceWidth: style.stanceWidth,
                                    leanBias: style.leanBias, pitchBias: style.pitchBias)
        return (style, StraightPunchAnatomy(rest: pose))
    })

    init(pose: FightPose) {
        self = Self.restingAnatomies[pose.style] ?? Self(rest: FightPose.neutral(stride: 0,
            style: pose.style, stanceWidth: pose.style.stanceWidth,
            leanBias: pose.style.leanBias, pitchBias: pose.style.pitchBias))
    }

    private init(rest: FightPose) {
        // Style limbRadiusScale is thickness only. Never derive length from the current guard,
        // a duck transition or an attack, which previously made reach depend on entry posture.
        arm = Self.restingArm
        let pivot = SIMD3<Float>(0, 0.86, 0)
        let hips = simd_quatf(angle: rest.hipYaw, axis: SIMD3<Float>(0, 1, 0))
        leftLeg = TwoBoneLimb(upper: simd_distance(hips.act(rest.leftHip - pivot) + pivot, rest.leftKnee),
                      lower: simd_distance(rest.leftKnee, rest.leftFoot + SIMD3<Float>(0, 0.16, 0)))
        rightLeg = TwoBoneLimb(upper: simd_distance(hips.act(rest.rightHip - pivot) + pivot, rest.rightKnee),
                       lower: simd_distance(rest.rightKnee, rest.rightFoot + SIMD3<Float>(0, 0.16, 0)))
    }
}

struct StraightPunchConstraint: Sendable {
    let anatomy: StraightPunchAnatomy
    let leading: Bool
}

/// Curved delivery for hooks/uppercuts, in fighter-facing coordinates. Contact stays at activeStart.
enum CurvedPunchMotion {
    static func glove(punch: Punch, progress: Float, contactProgress: Float,
                      guardPosition: SIMD3<Float>, shoulder: SIMD3<Float>, contact: SIMD3<Float>,
                      side: Float) -> SIMD3<Float> {
                guard let spec = CombatData.attacks[punch] else { return guardPosition }
                let hook = spec.family == .hook
                let end = Float(spec.recoveryEnd / spec.duration)
                guard progress.isFinite, contactProgress.isFinite,
              progress > 0, progress < end, contactProgress > 0 else { return guardPosition }
                let loadEnd = Float(spec.deliveryStart / spec.duration)
                let followEnd = Float(spec.followThroughEnd / spec.duration)
                let hookAngle: Float = 0.96
        func ease(_ value: Float) -> Float {
            let t = min(1, max(0, value))
            return t * t * (3 - 2 * t)
        }
        let load: SIMD3<Float>
        let follow: SIMD3<Float>
        if hook {
            // An arc about the moving shoulder, not a straight diagonal across the opponent.
            load = shoulder + simd_quatf(angle: side * hookAngle, axis: SIMD3<Float>(0, 1, 0)).act(contact - shoulder)
            var through = shoulder + simd_quatf(angle: -side * 0.18, axis: SIMD3<Float>(0, 1, 0)).act(contact - shoulder)
            through.z = min(contact.z, through.z)
            follow = through
        } else {
            // Compact rib-height chamber; don't swing the fist down toward the hip first.
            load = SIMD3<Float>(side * 0.22, min(1.50, contact.y - 0.50), min(0.32, contact.z * 0.45))
            follow = contact + SIMD3<Float>(side * 0.015, 0.10, -0.05)
        }
        if progress <= loadEnd {
            return guardPosition + (load - guardPosition) * ease(progress / loadEnd)
        }
        if progress <= contactProgress {
            let delivery = min(1, max(0, (progress - loadEnd) / (contactProgress - loadEnd)))
            let u = hook ? delivery * delivery : delivery
            if hook {
                return shoulder + simd_quatf(angle: side * hookAngle * (1 - u), axis: SIMD3<Float>(0, 1, 0)).act(contact - shoulder)
            }
            // Cubic delivery turns upward before contact; it is not a long diagonal straight.
            let c1 = load + SIMD3<Float>(0, 0.015, (contact.z - load.z) * 0.75)
            let c2 = contact - SIMD3<Float>(0, 0.32, 0.02)
            let v = 1 - u
            return load * (v * v * v) + c1 * (3 * v * v * u)
                + c2 * (3 * v * u * u) + contact * (u * u * u)
        }
        if progress <= followEnd {
            let followProgress = (progress - contactProgress) / (followEnd - contactProgress)
            var point = contact + (follow - contact) * ease(followProgress)
            if !hook {
                let tangent = 0.96 * (followEnd - contactProgress) / (contactProgress - loadEnd)
                point.y += tangent * followProgress * (1 - followProgress) * (1 - followProgress)
            }
            return point
        }
        let recovery = min(1, max(0, (progress - followEnd) / (end - followEnd)))
        let returnArc = hook ? SIMD3<Float>(side * 0.06, -0.045, -0.035) * sin(.pi * recovery) : .zero
        return follow + (guardPosition - follow) * ease(recovery) + returnArc
    }
}

/// A short shovel/body uppercut, not a straight punch aimed lower. All points are in facing
/// space so defensive pitch/yaw cannot turn the final ascending segment into a descending one.
/// Uses the existing body's contact progress and recovery end; adds no reach or combat clock.
enum BodyShovelMotion {
    static let loadHeight: Float = 1.08
    static let loadFraction: Float = 0.40
    static let recoveryEnd: Float = 0.88

    static func glove(
        progress: Float, contactProgress: Float, guardPosition: SIMD3<Float>,
        contact: SIMD3<Float>, side: Float, spec: AttackSpec? = nil
    ) -> SIMD3<Float> {
        let returnEnd = spec.map { Float($0.recoveryEnd / $0.duration) } ?? recoveryEnd
        guard progress.isFinite, contactProgress > 0, progress > 0, progress < returnEnd else {
            return guardPosition
        }
        let loadEnd = spec.map { Float($0.deliveryStart / $0.duration) } ?? contactProgress * loadFraction
        let followEnd = spec.map { Float($0.followThroughEnd / $0.duration) } ?? contactProgress + 0.09
        let load = SIMD3<Float>(side * 0.38, loadHeight, min(0.46, contact.z * 0.42))
        let follow = SIMD3<Float>(contact.x + side * 0.035, contact.y + 0.06,
                                  max(load.z, contact.z - 0.12))
        if progress <= loadEnd {
            return guardPosition + (load - guardPosition) * ease(progress / loadEnd)
        }
        if progress <= contactProgress {
            let u = (progress - loadEnd) / (contactProgress - loadEnd)
            var point = load + (contact - load) * ease(u)
            // h(u)=u²(2-u), h'(u)=u(4-3u)>0 for 0<u<=1. Y is 1.08 -> 1.35,
            // with a POSITIVE slope at activeStart, while Z has zero slope at max reach.
            point.y = load.y + (contact.y - load.y) * u * u * (2 - u)
            return point
        }
        if progress <= followEnd {
            let u = (progress - contactProgress) / (followEnd - contactProgress)
            var point = contact + (follow - contact) * ease(u)
            // Cubic Hermite: carry the SAME incoming Y slope through contact, then flatten.
            // Left/right m=.108/.10125 for deltaY=.06. With 0<m<3*deltaY,
            // dy/du=(1-u)[m+(6*deltaY-3*m)u]>0 throughout 0<=u<1.
            // Thus contact-epsilon < 1.35 < contact+epsilon, even from a low shell guard.
            let tangent = (contact.y - load.y) * (followEnd - contactProgress)
                / (contactProgress - loadEnd)
            point.y += tangent * u * (1 - u) * (1 - u)
            return point
        }
        return follow + (guardPosition - follow) * ease((progress - followEnd) / (returnEnd - followEnd))
    }

    /// Body-only elbow pole hint for the shared fixed-length solver. The down/out bias
    /// keeps the elbow below the rising glove; the hint never sets a new bone length.
    static func elbow(shoulder: SIMD3<Float>, glove: SIMD3<Float>, side: Float) -> SIMD3<Float> {
        let span = glove - shoulder
        let length = simd_length(span)
        guard length > 0.0001 else { return shoulder }
        let axis = span / length
        let down = SIMD3<Float>(side * 0.18, -1, 0)
        var bend = down - axis * simd_dot(down, axis)
        if simd_length_squared(bend) < 0.0001 {
            let forward = SIMD3<Float>(0, 0, 1)
            bend = forward - axis * simd_dot(forward, axis)
        }
        return (shoulder + glove) * 0.5 + simd_normalize(bend) * (length * 0.45)
    }

    private static func ease(_ value: Float) -> Float {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}

/// Quiet whole-body readiness, not a second movement input. Decorative cycles stop in Reduce Motion.
struct BoxingIdleMotion: Equatable {
    var breath: Float = 0
    var weightShift: Float = 0
    var guardLift: Float = 0

    static func sample(at time: Double, activity: Float, reducedMotion: Bool) -> BoxingIdleMotion {
        guard time.isFinite, !reducedMotion else { return BoxingIdleMotion() }
        let amount = 1 - min(1, max(0, activity)) * 0.8
        return BoxingIdleMotion(breath: Float(sin(time * 2.8)) * 0.010 * amount,
                                weightShift: Float(sin(time * 1.65)) * 0.014 * amount,
                                guardLift: Float(sin(time * 2.1 + 0.7)) * 0.008 * amount)
    }
}

/// Contact location determines the physical response. Reduced Motion keeps the information with
/// smaller displacement; it does not change a hit, stamina cost, stagger or counter window.
struct FighterImpactMotion: Equatable {
    var recoil: Float = 0
    var fold: Float = 0
    var headOffset = SIMD3<Float>.zero
    var guardCompression: Float = 0
    var roll: Float = 0
    var shoulderYaw: Float = 0
    var brace: Float = 0
    var headPitch: Float = 0
    var headYaw: Float = 0
    var headRoll: Float = 0

    static func sample(_ impact: CombatImpact?, remaining: Double, reducedMotion: Bool,
                       allowsContactBeat: Bool = true) -> FighterImpactMotion {
        guard let impact, remaining.isFinite, remaining > 0 else { return FighterImpactMotion() }
        let elapsed = max(0, 0.24 - remaining)
        let visualElapsed = ImpactMotionBeat.elapsed(elapsed, impact: allowsContactBeat ? impact : nil,
                                                    reducedMotion: reducedMotion)
        let life = Float(min(1, max(0, (0.24 - visualElapsed) / 0.24)))
        let strength = impact.knockout || impact.perfectCounter ? 1 : min(1, 0.28 + Float(impact.damage) / 20)
        // Immediate compression plus a slower critically-damped settling component. Normalize at
        // 0.24s so the pose returns exactly to neutral without adding recovery time or a second hit.
        let legacyEnvelope: Float = life > 0.78 ? 0.90 + 0.10 * ((life - 0.78) / 0.22) : pow(life / 0.78, 2) * 0.90
        let t = 1 - life
        func spring(_ rate: Float) -> Float {
            let end = (1 + rate) * exp(-rate)
            return max(0, ((1 + rate * t) * exp(-rate * t) - end) / (1 - end))
        }
        let envelope = reducedMotion || impact.knockout ? legacyEnvelope : 0.72 * spring(9) + 0.28 * spring(4)
        let blocked = impact.guarded && !impact.guardBroken
        // Slightly stronger received-hit poses, not world-space knockback. Keep the original KO
        // and Reduced Motion amplitudes; a block compresses the gloves without snapping the head.
        let responseGain: Float = reducedMotion || impact.knockout ? 1 : (blocked ? 1.06 : 1.18)
        let amount = envelope * strength * (reducedMotion ? 0.4 : 1) * responseGain
        if blocked {
            return FighterImpactMotion(guardCompression: 0.18 * amount, brace: 0.025 * amount)
        }
        let authoredSide: Float = [.jab, .leftBody, .leftHook, .leftUppercut].contains(impact.punch) ? -1 : 1
        let lateral = impact.incomingDirection?.x ?? 0
        let side: Float = abs(lateral) > 0.12 ? (lateral < 0 ? -1 : 1) : authoredSide
        if CombatData.attacks[impact.punch]?.targetZone == .body {
            return FighterImpactMotion(recoil: 0.045 * amount, fold: 0.30 * amount,
                                       headOffset: SIMD3<Float>(side * 0.012, -0.065, 0.045) * amount,
                                       shoulderYaw: side * 0.045 * amount,
                                       brace: 0.08 * amount, headPitch: -0.08 * amount)
        }
        let hook = CombatData.attacks[impact.punch]?.family == .hook
        let uppercut = CombatData.attacks[impact.punch]?.family == .uppercut
        return FighterImpactMotion(recoil: (impact.punch == .jab ? 0.055 : 0.105) * amount,
                                   fold: (uppercut ? -0.13 : -0.095) * amount,
                                   headOffset: SIMD3<Float>(side * (hook ? 0.14 : 0.016), uppercut ? 0.09 : 0.012, -0.11) * amount,
                                   roll: hook ? side * 0.07 * amount : 0,
                                   shoulderYaw: side * (hook ? 0.085 : 0.025) * amount,
                                   headPitch: (uppercut ? 0.20 : 0.10) * amount,
                                   headYaw: hook ? side * 0.16 * amount : 0,
                                   headRoll: hook ? side * 0.10 * amount : 0)
    }
}

struct FighterKnockdownMotion {
    var collapse: Float = 0
    var fall: Float = 0
    var armRelease: Float = 0
    var roll: Float = 0
    var forwardFold: Float = 0

    static func sample(progress: Float, reducedMotion: Bool, impact: CombatImpact? = nil) -> FighterKnockdownMotion {
        guard progress.isFinite else { return FighterKnockdownMotion() }
        let time = min(1, max(0, progress))
        func phase(_ start: Float, _ end: Float) -> Float {
            let amount = min(1, max(0, (time - start) / (end - start)))
            return amount * amount * (3 - 2 * amount)
        }
        let fall = reducedMotion ? phase(0, 1) : phase(0.14, 0.92)
        return FighterKnockdownMotion(
            collapse: (reducedMotion ? 0.08 : 0.24) * phase(0, 0.24) * (1 - fall),
            fall: fall,
            armRelease: reducedMotion ? fall : phase(0.18, 0.74),
            roll: reducedMotion ? 0 : min(1, max(-1, impact?.incomingDirection?.x ?? 0)) * 0.08 * sin(.pi * fall)
        )
    }

    static func sampleRecovery(progress: Float, reducedMotion: Bool) -> FighterKnockdownMotion {
        guard progress.isFinite else { return FighterKnockdownMotion(fall: 1, armRelease: 1) }
        let time = min(1, max(0, progress))
        func phase(_ start: Float, _ end: Float) -> Float {
            let amount = min(1, max(0, (time - start) / (end - start)))
            return amount * amount * (3 - 2 * amount)
        }
        let collapse: Float = (reducedMotion ? 0.12 : 0.34) * phase(0.06, 0.42) * (1 - phase(0.50, 1))
        return FighterKnockdownMotion(
            collapse: collapse,
            fall: 1 - (reducedMotion ? phase(0, 1) : phase(0.04, 0.60)),
            armRelease: 1 - phase(0.42, 0.95),
            forwardFold: collapse * 1.30
        )
    }
}

extension FightPose {
    /// Add breathing without replacing each style's authored shoulder lead or resting guard.
    mutating func applyReadiness(motion: BoxingIdleMotion) {
        separatesTorsoRotation = true
        headBob = motion.breath
        // The stance already owns its forward pitch and shoulder lead. Idle is additive only.
        torsoY += motion.breath
        torsoLean += motion.weightShift
        leftShoulder.y += motion.breath
        rightShoulder.y += motion.breath
        leftElbow.y += motion.breath * 0.7
        rightElbow.y += motion.breath * 0.7
        leftGlove.y += motion.breath + motion.guardLift
        rightGlove.y += motion.breath - motion.guardLift
        leftHip.y -= max(0, motion.weightShift) * 0.4
        rightHip.y -= max(0, -motion.weightShift) * 0.4
        leftKnee.z += 0.018
        rightKnee.z += 0.018
    }

    var torsoOrientation: simd_quatf {
        simd_quatf(angle: torsoLean, axis: SIMD3<Float>(0, 0, 1))
            * simd_quatf(angle: separatesTorsoRotation ? torsoYaw : 0, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: torsoPitch, axis: SIMD3<Float>(1, 0, 0))
    }

    mutating func applyStraightPunch(_ punch: Punch, progress: Float, opponentDistance: Float? = nil, reachMultiplier: Float = 1, targetRadius: Float = 0.34, anatomy: StraightPunchAnatomy? = nil, contactTarget: SIMD3<Float>? = nil) {
        let motion = StraightPunchMotion.sample(punch, progress: progress)
        guard motion != PunchMotion() else { return }
        let jab = punch == .jab
        let side: Float = jab ? 1 : -1
        let base = self
        let anatomy = anatomy ?? StraightPunchAnatomy(pose: base)
        straightPunchConstraint = StraightPunchConstraint(anatomy: anatomy, leading: jab)

        // Load the support legs before the pelvis/chest/shoulder turn. No world step is added.
        lowerBody(by: max(0, (jab ? 0.035 : 0.055) - defensiveCrouch) * motion.hipLoad)
        separatesTorsoRotation = true
        hipYaw += side * (jab ? 0.018 : 0.075) * motion.hipLoad
            - side * (jab ? 0.10 : (style == .outboxing ? 0.68 : 0.60)) * motion.hipDrive
        torsoYaw += side * (jab ? 0.025 : 0.10) * motion.torsoLoad
            - side * (jab ? 0.20 : (style == .outboxing ? 0.95 : 0.80)) * motion.torsoDrive
        let lean: Float = jab ? (style == .outboxing ? 0.13 : 0.10) : 0.15
        driveChest(forwardLean: lean * motion.torsoDrive)
        extendChestForPunch(punch, motion: motion, opponentDistance: opponentDistance,
                    reachMultiplier: reachMultiplier, targetRadius: targetRadius, contactTarget: contactTarget)
        // Small scapular travel; the shoulder remains overlapped with the chest surface.
        let shoulderAdvance = (jab ? Float(0.055) : 0.075) * motion.shoulderDrive
        if jab { leftShoulder.z += shoulderAdvance } else { rightShoulder.z += shoulderAdvance }

        let shoulder = jab ? leftShoulder : rightShoulder
        let baseGlove = jab ? leftGlove : rightGlove
        let baseElbow = jab ? leftElbow : rightElbow
        let chamber: SIMD3<Float>
        if jab {
            chamber = baseGlove + SIMD3<Float>(0.012, -0.012, -0.018) * motion.load
        } else {
            chamber = torsoPoint(base.facingPoint(baseGlove)
                + SIMD3<Float>(-0.008, -0.008, -0.025) * motion.load)
        }
        // Account for the advanced chest/shoulder before spending the arm's fixed reach.
        // The extension is carried by the upper body, not a longer arm or enlarged glove.
        let contactTarget = (contactTarget ?? SIMD3<Float>(
            side * 0.10, 2.08,
            PunchMotion.contactReach(punch, opponentDistance: opponentDistance, reachMultiplier: reachMultiplier, targetRadius: targetRadius)
        )) - SIMD3<Float>(rootX, rootY, rootZ)
        let target = anatomy.arm.solve(root: shoulder, target: torsoPoint(contactTarget), pole: baseElbow,
                                       fallback: SIMD3<Float>(side * 0.25, -1, 0)).end
        let glove = chamber + (target - chamber) * motion.reach
        let elbow: SIMD3<Float>
        if jab {
            let extendedElbow = (shoulder + glove) * 0.5 + SIMD3<Float>(0.07, -0.045, 0)
            elbow = baseElbow + (extendedElbow - baseElbow) * motion.reach
        } else {
            let guardedElbow = base.facingPoint(baseElbow)
            let extendedElbow = (facingPoint(shoulder) + facingPoint(glove)) * 0.5
                + SIMD3<Float>(-0.025, -0.085, 0)
            elbow = torsoPoint(guardedElbow + (extendedElbow - guardedElbow) * motion.reach)
        }
        let guardAmount = motion.torsoDrive * 0.85
        if jab {
            leftGlove = glove
            leftElbow = elbow
            leftKnee.z += 0.025 * motion.footDrive
            leftFootYaw -= 0.04 * motion.footDrive
        } else {
            rightGlove = glove
            rightElbow = elbow
            rightKnee.x += 0.035 * motion.footDrive
            rightKnee.z += 0.025 * motion.footDrive
            rightFootPitch += 0.20 * motion.footDrive
            rightFootYaw += min(0.70, max(0, -base.rightFootYaw - 0.12)) * motion.footDrive
        }
        protectChin(side: -side, base: base, amount: guardAmount)
    }

    /// Rotation about the supported hip advances the whole chest/head/shoulder assembly together.
    private mutating func driveChest(forwardLean: Float) {
        let spine = SIMD3<Float>(0, max(0.35, torsoY - (leftHip.y + rightHip.y) * 0.5), 0)
        torsoOffset += simd_quatf(angle: forwardLean, axis: SIMD3<Float>(1, 0, 0)).act(spine) - spine
        torsoPitch += forwardLean
    }

    /// Small forward weight shift over the existing support legs. The torso, head and both
    /// shoulders share this translation; feet and FighterModel position remain unchanged.
    /// torsoDrive is one at activeStart and zero at both endpoints, including weave-hook entries.
    private mutating func extendChestForPunch(_ punch: Punch, motion: PunchMotion, opponentDistance: Float?,
                                              reachMultiplier: Float, targetRadius: Float,
                                              contactTarget: SIMD3<Float>? = nil) {
        let advance: Float
        if let contactTarget, let spec = CombatData.attacks[punch] {
            let baseReach = Float(spec.range * Double(reachMultiplier) * CombatData.sceneScale)
            advance = min(Float(CombatData.punchReachExtension * CombatData.sceneScale),
                          max(0, hypot(contactTarget.x, contactTarget.z) - baseReach))
        } else {
            advance = PunchMotion.chestAdvance(punch, opponentDistance: opponentDistance,
                                               reachMultiplier: reachMultiplier, targetRadius: targetRadius)
        }
        torsoOffset.z += advance * motion.torsoDrive
    }

    /// Fixed anatomy in idle, guard, defense and every punch; no length pop when an attack starts.
    mutating func resolveArmLengths() {
        let arm = StraightPunchAnatomy.restingArm
        let left = arm.solve(root: leftShoulder, target: leftGlove, pole: leftElbow,
                             fallback: SIMD3<Float>(0.35, -1, 0.15))
        let right = arm.solve(root: rightShoulder, target: rightGlove, pole: rightElbow,
                              fallback: SIMD3<Float>(-0.35, -1, 0.15))
        leftGlove = left.end
        leftElbow = left.joint
        rightGlove = right.end
        rightElbow = right.joint
    }

    /// Run once after impact and world-foot compensation, before rendering body parts.
    /// Contacts are poseRoot-local shoe centers; torsoOffset applies to the chest, not the hips/feet.
    @discardableResult
    mutating func resolveContactSupport(rootPosition: SIMD3<Float>, rootRotation: simd_quatf)
        -> (left: SIMD3<Float>, right: SIMD3<Float>) {
        let rest = FightPose.neutral(stride: 0, style: style)
        let leftPivot = DefensiveMotion.pivotedFoot(leftFoot, restYaw: rest.leftFootYaw,
            yaw: leftFootYaw, pitch: leftFootPitch)
        let rightPivot = DefensiveMotion.pivotedFoot(rightFoot, restYaw: rest.rightFootYaw,
            yaw: rightFootYaw, pitch: rightFootPitch)
        let left = DefensiveMotion.plantedFoot(leftPivot, posePosition: rootPosition, poseRotation: rootRotation)
        let right = DefensiveMotion.plantedFoot(rightPivot, posePosition: rootPosition, poseRotation: rootRotation)
        resolveStraightPunch(leftContact: left, rightContact: right)
        return (left: left, right: right)
    }

    mutating func resolveStraightPunch(leftContact: SIMD3<Float>, rightContact: SIMD3<Float>) {
        let constraint = straightPunchConstraint
        let anatomy = constraint?.anatomy ?? StraightPunchAnatomy(pose: self)
        let strikingTarget = constraint.map { facingPoint($0.leading ? leftGlove : rightGlove) }
        let hipPivot = SIMD3<Float>(0, 0.86, 0)
        let hipRotation = simd_quatf(angle: hipYaw, axis: SIMD3<Float>(0, 1, 0))
        let leftAnkle = leftContact + SIMD3<Float>(0, 0.16, 0)
        let rightAnkle = rightContact + SIMD3<Float>(0, 0.16, 0)
        func hipPoint(_ hip: SIMD3<Float>) -> SIMD3<Float> { hipRotation.act(hip - hipPivot) + hipPivot }
        func supportDrop(hip: SIMD3<Float>, ankle: SIMD3<Float>, limb: TwoBoneLimb) -> Float {
            let delta = hip - ankle
            let horizontal = delta.x * delta.x + delta.z * delta.z
            // Do not move an ongoing locomotion step to make the punch layer fit.
            guard horizontal < limb.maximumReach * limb.maximumReach else { return 0 }
            return max(0, delta.y - sqrt(max(0, limb.maximumReach * limb.maximumReach - horizontal)))
        }
        let drop = max(supportDrop(hip: hipPoint(leftHip), ankle: leftAnkle, limb: anatomy.leftLeg),
                   supportDrop(hip: hipPoint(rightHip), ankle: rightAnkle, limb: anatomy.rightLeg))
        // Small knee flexion, never a large squat/lunge to chase a distant hand target.
        lowerBody(by: min(0.08, drop / 0.72))
        func knee(hip: SIMD3<Float>, current: SIMD3<Float>, ankle: SIMD3<Float>, limb: TwoBoneLimb,
                  yaw: Float) -> SIMD3<Float> {
            guard simd_distance(hip, ankle) <= limb.maximumReach + 0.0001 else { return current }
            let bend = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)).act(SIMD3<Float>(0, 0, 1))
            return limb.solve(root: hip, target: ankle, pole: current, fallback: bend).joint
        }
        leftKnee = knee(hip: hipPoint(leftHip), current: leftKnee, ankle: leftAnkle,
                       limb: anatomy.leftLeg, yaw: leftFootYaw)
        rightKnee = knee(hip: hipPoint(rightHip), current: rightKnee, ankle: rightAnkle,
                        limb: anatomy.rightLeg, yaw: rightFootYaw)

        // Support-leg flexion lowers the chest, not the intended contact point.
        if let constraint, let strikingTarget {
            let glove = torsoPoint(strikingTarget)
            if constraint.leading {
                leftGlove = glove
            } else {
                rightGlove = glove
            }
        }
        resolveArmLengths()
    }

    mutating func applyPowerPunch(_ punch: Punch, progress: Float, opponentDistance: Float?, reachMultiplier: Float, targetRadius: Float, anatomy: StraightPunchAnatomy? = nil, contactTarget: SIMD3<Float>? = nil) {
        guard let spec = CombatData.attacks[punch], spec.family != .straight else { return }
        let motion = PunchMotion.sample(punch, progress: progress)
        guard motion != PunchMotion() else { return }
        let lead = [.leftBody, .leftHook, .leftUppercut].contains(punch)
        let side: Float = lead ? 1 : -1
        let hook = spec.family == .hook
        let body = spec.family == .body
        let uppercut = spec.family == .uppercut
        let base = self
        let anatomy = anatomy ?? StraightPunchAnatomy(pose: base)
        straightPunchConstraint = StraightPunchConstraint(anatomy: anatomy, leading: lead)

        separatesTorsoRotation = true
        if hook {
            hipYaw += side * 0.12 * motion.hipLoad
                - side * ((lead ? 0.50 : 0.60) * motion.hipDrive + 0.04 * motion.followThrough)
            torsoYaw += side * 0.20 * motion.torsoLoad
                - side * ((lead ? 0.68 : (style == .outboxing ? 0.98 : 0.88)) * motion.torsoDrive
                          + 0.08 * motion.followThrough)
        } else {
            let hipTurn: Float = body ? (lead ? 0.30 : 0.44) : (lead ? 0.24 : 0.36)
            let chestTurn: Float = body ? (lead ? 0.44 : (style == .outboxing ? 0.72 : 0.62))
                : (lead ? 0.34 : (style == .outboxing ? 0.64 : 0.56))
            hipYaw += side * 0.08 * motion.hipLoad - side * hipTurn * motion.hipDrive
            torsoYaw += side * 0.12 * motion.torsoLoad - side * chestTurn * motion.torsoDrive
        }
        torsoLean += side * (hook ? 0.045 : 0.025) * motion.torsoDrive

        // Reuse an existing duck/weave load instead of crouching twice or resetting upright.
        // A hook may rise at most .055 from that posture; every delta is zero at attack endpoints.
        let bodyDip = body ? max(0, 0.18 - defensiveCrouch)
            * max(motion.hipLoad, motion.torsoDrive * 0.65) : 0
        let upperDip = uppercut ? max(0, 0.16 - defensiveCrouch) * motion.hipLoad : 0
        let upperRise = uppercut ? min(0.045, defensiveCrouch * 0.10) * motion.torsoDrive : 0
        let hookDip = hook ? max(0, 0.045 - defensiveCrouch) * motion.hipLoad : 0
        let hookRise = hook ? min(0.055, defensiveCrouch * 0.15) * motion.torsoDrive : 0
        lowerBody(by: bodyDip + upperDip + hookDip - hookRise - upperRise)
        driveChest(forwardLean: (body ? 0.18 : (hook ? 0.08 : 0.04)) * motion.torsoDrive)
        if uppercut { torsoPitch += 0.03 * motion.torsoDrive }
        extendChestForPunch(punch, motion: motion, opponentDistance: opponentDistance,
                    reachMultiplier: reachMultiplier, targetRadius: targetRadius, contactTarget: contactTarget)

        let shoulderAdvance = (body ? Float(0.035) : (uppercut ? 0.025 : 0.015)) * motion.shoulderDrive
        if lead {
            leftShoulder.z += shoulderAdvance
        } else {
            rightShoulder.z += shoulderAdvance
        }

        let shoulder = lead ? leftShoulder : rightShoulder
        let contact = (contactTarget ?? SIMD3<Float>(
            side * (hook ? 0.16 : 0.10), body ? 1.35 : (uppercut ? 2.13 : 2.08),
            PunchMotion.contactReach(punch, opponentDistance: opponentDistance, reachMultiplier: reachMultiplier, targetRadius: targetRadius)
        )) - SIMD3<Float>(rootX, rootY, rootZ)
        let guardPosition = base.facingPoint(lead ? base.leftGlove : base.rightGlove)
        let glove: SIMD3<Float>
        let elbow: SIMD3<Float>
        if body {
            let facingGlove = BodyShovelMotion.glove(
                progress: progress, contactProgress: Float(spec.activeStart / spec.duration),
                guardPosition: guardPosition,
                contact: contact, side: side, spec: spec
            )
            glove = torsoPoint(facingGlove)
            let compactElbow = BodyShovelMotion.elbow(shoulder: facingPoint(shoulder), glove: facingGlove, side: side)
            let restingElbow = base.facingPoint(lead ? base.leftElbow : base.rightElbow)
            let armBlend = min(1, motion.load + max(motion.reach, motion.followThrough))
            elbow = torsoPoint(restingElbow + (compactElbow - restingElbow) * armBlend)
        } else {
            let shoulderPosition = facingPoint(shoulder)
            let facingGlove = CurvedPunchMotion.glove(punch: punch, progress: progress,
                contactProgress: Float(spec.activeStart / spec.duration), guardPosition: guardPosition,
                shoulder: shoulderPosition, contact: contact, side: side)
            glove = torsoPoint(facingGlove)
            let oldElbow = base.facingPoint(lead ? base.leftElbow : base.rightElbow)
            let pole = (shoulderPosition + facingGlove) * 0.5
                + (hook ? SIMD3<Float>(side * 0.42, 0.025, -0.12) : SIMD3<Float>(side * 0.10, -0.46, -0.08))
            elbow = torsoPoint(oldElbow + (pole - oldElbow)
                * min(1, motion.load + max(motion.reach, motion.followThrough)))
        }
        let guardAmount = motion.torsoDrive * 0.80

        if lead {
            leftGlove = glove
            leftElbow = elbow
            leftFootYaw += (hook ? -0.45 : (body ? -0.18 : -0.14)) * motion.footDrive
            leftKnee.x -= (hook ? 0.030 : 0.018) * motion.footDrive
            if hook {
                leftFootPitch += 0.09 * motion.footDrive
                leftKnee.z += 0.025 * motion.footDrive
            }
            if uppercut {
                leftFootPitch += 0.12 * motion.footDrive
                leftKnee.z += 0.040 * motion.footDrive
            }
        } else {
            rightGlove = glove
            rightElbow = elbow
            rightFootYaw += (hook ? 0.50 : 0.30) * motion.footDrive
            rightFootPitch = (uppercut ? 0.18 : (hook ? 0.14 : 0.10)) * motion.footDrive
            rightKnee.x += 0.030 * motion.footDrive
            rightKnee.z += (uppercut ? 0.055 : 0.020) * motion.footDrive
        }
        protectChin(side: -side, base: base, amount: guardAmount)
    }

    mutating func applyPunchRecovery(_ punch: Punch, progress: Float, landed: Bool, reducedMotion: Bool) {
        let motion = PunchRecoveryMotion.sample(punch, progress: progress, landed: landed,
                                                reducedMotion: reducedMotion)
        torsoYaw += motion.torsoTurn
        hipYaw += motion.hipTurn
        torsoOffset.z += motion.chestAdvance
        if [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch) {
            leftGlove = torsoPoint(facingPoint(leftGlove) + motion.handOffset)
            leftElbow.z += motion.handOffset.z * 0.35
        } else {
            rightGlove = torsoPoint(facingPoint(rightGlove) + motion.handOffset)
            rightElbow.z += motion.handOffset.z * 0.35
        }
    }

    /// Keep the offhand beside the actual lowered/partially-rotated head throughout the punch.
    /// Transport its old head-relative offset, then tighten it; never snap to a fixed y=2.1 guard.
    private mutating func protectChin(side: Float, base: FightPose, amount: Float) {
        let head = headFacingPosition
        let oldHead = base.headFacingPosition
        let oldGlove = side > 0 ? base.leftGlove : base.rightGlove
        let oldElbow = side > 0 ? base.leftElbow : base.rightElbow
        let gloveOffset = base.facingPoint(oldGlove) - oldHead
        let elbowOffset = base.facingPoint(oldElbow) - oldHead
        let glove = torsoPoint(head + gloveOffset
            + (SIMD3<Float>(side * 0.23, -0.16, 0.34) - gloveOffset) * amount)
        let elbow = torsoPoint(head + elbowOffset
            + (SIMD3<Float>(side * 0.35, -0.58, 0.18) - elbowOffset) * amount)
        if side > 0 {
            leftGlove = glove
            leftElbow = elbow
        } else {
            rightGlove = glove
            rightElbow = elbow
        }
    }

    mutating func applyImpact(_ motion: FighterImpactMotion) {
        separatesTorsoRotation = true
        lowerBody(by: motion.brace)
        torsoYaw += motion.shoulderYaw
        torsoPitch -= motion.fold
        let dip = max(0, motion.fold) * 0.3
        torsoY -= dip
        bodyDrop += dip
        leftShoulder.y -= dip
        rightShoulder.y -= dip
        leftElbow.y -= dip * 0.5
        rightElbow.y -= dip * 0.5
        let gloveRetraction = SIMD3<Float>(0, 0, motion.guardCompression)
        leftGlove = torsoPoint(facingPoint(leftGlove) - gloveRetraction)
        rightGlove = torsoPoint(facingPoint(rightGlove) - gloveRetraction)
        leftElbow = torsoPoint(facingPoint(leftElbow) - gloveRetraction * 0.4)
        rightElbow = torsoPoint(facingPoint(rightElbow) - gloveRetraction * 0.4)
    }

    mutating func applyKnockdown(_ motion: FighterKnockdownMotion) {
        straightPunchConstraint = nil
        lowerBody(by: motion.collapse)
        torsoPitch += motion.forwardFold - motion.collapse * 0.65
        torsoYaw *= 1 - motion.armRelease * 0.55
        hipYaw *= 1 - motion.armRelease * 0.75
        leftKnee.z += motion.collapse * 0.35
        rightKnee.z += motion.collapse * 0.35
        let leftHand = torsoPoint(SIMD3<Float>(0.48, 0.96 - bodyDrop, 0.18))
        let rightHand = torsoPoint(SIMD3<Float>(-0.48, 0.90 - bodyDrop, 0.16))
        let leftArm = torsoPoint(SIMD3<Float>(0.56, 1.30 - bodyDrop, 0.08))
        let rightArm = torsoPoint(SIMD3<Float>(-0.56, 1.26 - bodyDrop, 0.06))
        leftGlove += (leftHand - leftGlove) * motion.armRelease
        rightGlove += (rightHand - rightGlove) * motion.armRelease
        leftElbow += (leftArm - leftElbow) * motion.armRelease
        rightElbow += (rightArm - rightElbow) * motion.armRelease
        leftFoot.z += (0.10 - leftFoot.z) * motion.fall
        rightFoot.z += (0.10 - rightFoot.z) * motion.fall
        resolveArmLengths()
    }
}