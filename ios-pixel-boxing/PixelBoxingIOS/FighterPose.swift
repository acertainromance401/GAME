import Foundation
import simd

struct FightPose: Sendable {
    private(set) var style: FightStyle = .standard
    /// Facing-local visual offset only. BoxerRig must use this instead of -duckVisual * 0.26;
    /// FighterModel owns world displacement, including the weave's real lateral step.
    var rootX: Float = 0
    var rootY: Float = 0
    var rootZ: Float = 0
    var bodyDrop: Float = 0
    var headBob: Float = 0
    private(set) var defensiveCrouch: Float = 0
    var torsoY: Float = 1.55
    /// Hip-driven chest displacement shared by the torso, head and attached arms.
    var torsoOffset = SIMD3<Float>.zero
    var straightPunchConstraint: StraightPunchConstraint?
    var torsoLean: Float = 0
    var torsoPitch: Float = 0
    var torsoYaw: Float = 0
    var separatesTorsoRotation = false
    var hipYaw: Float = 0
    var leftFootYaw: Float = 0
    var leftFootPitch: Float = 0
    var rightFootPitch: Float = 0
    var rightFootYaw: Float = 0
    var leftShoulder = SIMD3<Float>(0.39, 1.82, 0)
    var rightShoulder = SIMD3<Float>(-0.39, 1.82, 0)
    var leftElbow = SIMD3<Float>(0.50, 1.52, 0.25)
    var rightElbow = SIMD3<Float>(-0.50, 1.52, 0.25)
    var leftGlove = SIMD3<Float>(0.25, 1.82, 0.48)
    var rightGlove = SIMD3<Float>(-0.25, 1.78, 0.44)
    var leftHip = SIMD3<Float>(0.22, 0.86, 0)
    var rightHip = SIMD3<Float>(-0.22, 0.86, 0)
    var leftKnee = SIMD3<Float>(0.29, 0.46, 0.14)
    var rightKnee = SIMD3<Float>(-0.30, 0.46, -0.12)
    var leftFoot = SIMD3<Float>(0.31, 0.14, 0.29)
    var rightFoot = SIMD3<Float>(-0.32, 0.14, -0.22)

    private static let baseStances = Dictionary(uniqueKeysWithValues: FightStyle.allCases.map { style in
        (style, makeNeutral(style: style))
    })
    private static let styledStances = Dictionary(uniqueKeysWithValues: FightStyle.allCases.map { style in
        (style, makeNeutral(style: style, stanceWidth: style.stanceWidth,
                            leanBias: style.leanBias, pitchBias: style.pitchBias))
    })

    static func neutral(
        stride: Float, style: FightStyle = .standard, stanceWidth: Float = 0,
        leanBias: Float = 0, pitchBias: Float = 0
    ) -> FightPose {
        if stride == 0 {
            if stanceWidth == 0, leanBias == 0, pitchBias == 0, let pose = baseStances[style] {
                return pose
            }
            if stanceWidth == style.stanceWidth, leanBias == style.leanBias, pitchBias == style.pitchBias,
               let pose = styledStances[style] {
                return pose
            }
        }
        return makeNeutral(stride: stride, style: style, stanceWidth: stanceWidth,
                           leanBias: leanBias, pitchBias: pitchBias)
    }

    private static func makeNeutral(
        stride: Float = 0, style: FightStyle, stanceWidth: Float = 0,
        leanBias: Float = 0, pitchBias: Float = 0
    ) -> FightPose {
        var pose = FightPose()
        pose.leftKnee.z += stride
        pose.rightKnee.z -= stride
        pose.leftFoot.z += stride
        pose.rightFoot.z -= stride
        pose.leftKnee.x += stanceWidth
        pose.rightKnee.x -= stanceWidth
        pose.leftFoot.x += stanceWidth
        pose.rightFoot.x -= stanceWidth
        pose.applyStance(style)
        // Style identity is principally a bladed stance, not a sideways/backward waist bend.
        pose.torsoLean += leanBias * 0.2
        pose.torsoPitch += min(0, pitchBias) * 0.15
        return pose
    }

    /// Orthodox +Z-facing stance: negative yaw brings the left shoulder forward. Feet have
    /// separate toe angles and an actual fore/aft stagger; neither is rotated by chest yaw.
    mutating func applyStance(_ style: FightStyle) {
        self.style = style
        separatesTorsoRotation = true
        let leftHand: SIMD3<Float>
        let rightHand: SIMD3<Float>
        let leftArm: SIMD3<Float>
        let rightArm: SIMD3<Float>
        switch style {
        case .standard:
            torsoYaw = -0.40
            hipYaw = -0.30
            torsoPitch = -0.06
            leftFootYaw = -0.18
            rightFootYaw = -0.72
            leftFoot.z += 0.03
            rightFoot.z -= 0.06
            leftHand = SIMD3<Float>(0.22, 2.00, 0.48)
            rightHand = SIMD3<Float>(-0.22, 2.03, 0.34)
            leftArm = SIMD3<Float>(0.43, 1.51, 0.26)
            rightArm = SIMD3<Float>(-0.43, 1.52, 0.12)
        case .outboxing:
            // More side-on, longer stance, low lead shield and high rear hand. The shoulder,
            // not an attack-time arm scale, supplies the Outboxer's longer lead-hand reach.
            torsoYaw = -0.62
            hipYaw = -0.46
            torsoPitch = -0.03
            leftFootYaw = -0.30
            rightFootYaw = -0.90
            leftFoot.z += 0.08
            rightFoot.z -= 0.12
            leftHand = SIMD3<Float>(0.10, 1.61, 0.52)
            rightHand = SIMD3<Float>(-0.18, 2.10, 0.33)
            leftArm = SIMD3<Float>(0.38, 1.38, 0.36)
            rightArm = SIMD3<Float>(-0.34, 1.67, 0.10)
        case .infighting:
            // Slugger keeps the broad, low guard and a less bladed, compact power stance.
            torsoYaw = -0.26
            hipYaw = -0.20
            torsoPitch = -0.08
            leftFootYaw = -0.14
            rightFootYaw = -0.62
            leftFoot.z -= 0.02
            rightFoot.z -= 0.02
            leftShoulder.x = 0.43
            rightShoulder.x = -0.43
            leftHand = SIMD3<Float>(0.44, 1.69, 0.39)
            rightHand = SIMD3<Float>(-0.44, 1.68, 0.22)
            leftArm = SIMD3<Float>(0.50, 1.46, 0.18)
            rightArm = SIMD3<Float>(-0.50, 1.46, -0.03)
        }
        // Author hands toward the opponent, then express them in the rotated chest frame.
        // Otherwise a bladed torso would rotate the high rear hand away from the chin.
        leftGlove = torsoPoint(leftHand)
        rightGlove = torsoPoint(rightHand)
        leftElbow = torsoPoint(leftArm)
        rightElbow = torsoPoint(rightArm)
        let hips = simd_quatf(angle: hipYaw, axis: SIMD3<Float>(0, 1, 0))
        let pivot = SIMD3<Float>(0, 0.86, 0)
        let leftHipPosition = hips.act(leftHip - pivot) + pivot
        let rightHipPosition = hips.act(rightHip - pivot) + pivot
        leftKnee = (leftHipPosition + leftFoot + SIMD3<Float>(0, 0.16, 0)) * 0.5
            + simd_quatf(angle: leftFootYaw, axis: SIMD3<Float>(0, 1, 0)).act(SIMD3<Float>(0, -0.07, 0.12))
        rightKnee = (rightHipPosition + rightFoot + SIMD3<Float>(0, 0.16, 0)) * 0.5
            + simd_quatf(angle: rightFootYaw, axis: SIMD3<Float>(0, 1, 0)).act(SIMD3<Float>(0, -0.07, 0.12))
    }

    mutating func applyFootwork(forward: Float, strafe: Float, strideCycle: Float) {
        let step = SIMD3<Float>(strafe * 0.11, 0, forward * 0.13) * strideCycle
        leftFoot += step
        rightFoot -= step
        leftKnee += step * 0.7
        rightKnee -= step * 0.7
        let leftLift = max(0, strideCycle) * 0.04
        let rightLift = max(0, -strideCycle) * 0.04
        leftFoot.y += leftLift
        rightFoot.y += rightLift
        leftKnee.y += leftLift * 0.6
        rightKnee.y += rightLift * 0.6
    }

    mutating func applyBackstep(_ motion: BackstepMotion) {
        lowerBody(by: motion.crouch)
        torsoPitch -= motion.crouch * 0.90
        leftFoot.y += motion.frontLift
        rightFoot.y += motion.rearLift
        leftFootPitch += motion.frontLift * 1.8
        rightFootPitch += motion.rearLift * 1.8
        leftKnee.y += motion.frontLift * 0.6
        rightKnee.y += motion.rearLift * 0.6
    }

    mutating func applyGuard(style: FightStyle = .standard, amount: Float = 1) {
        let original = self
        let head = headFacingPosition
        switch style {
        case .standard:
            leftElbow = torsoPoint(head + SIMD3<Float>(0.40, -0.66, 0.20))
            rightElbow = torsoPoint(head + SIMD3<Float>(-0.40, -0.66, 0.12))
            leftGlove = torsoPoint(head + SIMD3<Float>(0.20, -0.10, 0.34))
            rightGlove = torsoPoint(head + SIMD3<Float>(-0.20, -0.10, 0.32))
        case .outboxing:
            rightElbow = torsoPoint(head + SIMD3<Float>(-0.34, -0.56, 0.14))
            rightGlove = torsoPoint(head + SIMD3<Float>(-0.20, -0.10, 0.33))
            leftElbow = torsoPoint(head + SIMD3<Float>(0.38, -0.72, 0.33))
            leftGlove = torsoPoint(head + SIMD3<Float>(0.10, -0.34, 0.44))
        case .infighting:
            // Raise the low guard without collapsing the wide elbows into the chest.
            leftElbow = torsoPoint(head + SIMD3<Float>(0.50, -0.70, 0.16))
            rightElbow = torsoPoint(head + SIMD3<Float>(-0.50, -0.70, 0.08))
            leftGlove = torsoPoint(head + SIMD3<Float>(0.29, -0.20, 0.36))
            rightGlove = torsoPoint(head + SIMD3<Float>(-0.29, -0.20, 0.32))
        }
        torsoLean -= 0.015
        let blend = min(1, max(0, amount))
        leftElbow = original.leftElbow + (leftElbow - original.leftElbow) * blend
        rightElbow = original.rightElbow + (rightElbow - original.rightElbow) * blend
        leftGlove = original.leftGlove + (leftGlove - original.leftGlove) * blend
        rightGlove = original.rightGlove + (rightGlove - original.rightGlove) * blend
        torsoLean = original.torsoLean + (torsoLean - original.torsoLean) * blend
    }

    /// Knee/hip lowering leads; yaw faces INTO the duck, with forward pitch and only a small roll.
    /// +1 means the fighter's right (local -X), so yaw is negative, not a root-facing rotation.
    mutating func applyDuck(direction: Float, style: FightStyle = .standard) {
        guard direction.isFinite else { return }
        let side = min(1, max(-1, direction))
        let amount = abs(side)
        let turnProgress = min(1, max(0, (amount - 0.20) / 0.80))
        let turn = side * turnProgress * turnProgress * (3 - 2 * turnProgress)
        applyDefensiveLowering(amount: amount, crouch: 0.40 * amount,
                       yaw: -0.24 * turn, pitch: -0.18 * amount,
                       roll: 0.035 * turn, lateralShift: -0.055 * turn, style: style)
    }

    /// Apply BEFORE applyAttack, including the overlap when a queued hook is active.
    /// For a fading held duck, first applyDuck(direction: duckVisual * (1 - motion.amount)).
    /// Both layers then share one bounded lowering mechanism rather than resetting to standing guard.
    mutating func applyWeave(_ motion: WeaveMotion, style: FightStyle) {
        applyDefensiveLowering(amount: motion.amount, crouch: motion.crouch,
                               yaw: motion.yaw, pitch: motion.pitch, roll: motion.roll,
                               lateralShift: motion.rootX, style: style)
    }

    /// Matches BoxerRig's partial head/neck rotation. headBob is the SAME idle value used by the
    /// renderer, not a second oscillator. Use this anchor for non-striking guards after any body turn.
    var headFacingPosition: SIMD3<Float> {
        let pivot = SIMD3<Float>(0, torsoY, 0)
        let rotation = simd_slerp(simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), torsoOrientation, 0.55)
        return rotation.act(SIMD3<Float>(0, 2.28 + headBob - bodyDrop, 0.04) - pivot) + pivot + torsoOffset
    }

    func facingPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let pivot = SIMD3<Float>(0, torsoY, 0)
        return torsoOrientation.act(point - pivot) + pivot + torsoOffset
    }

    func torsoPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let pivot = SIMD3<Float>(0, torsoY, 0)
        return torsoOrientation.inverse.act(point - pivot - torsoOffset) + pivot
    }

    /// Positive is a dip, negative is a small rise from an already-loaded hook stance.
    /// Feet and rootY/rootZ never move: the pelvis, knees and connected upper body do the work.
    mutating func lowerBody(by drop: Float) {
        bodyDrop += drop
        torsoY -= drop
        leftShoulder.y -= drop
        rightShoulder.y -= drop
        leftElbow.y -= drop
        rightElbow.y -= drop
        leftGlove.y -= drop
        rightGlove.y -= drop
        leftHip.y -= drop * 0.72
        rightHip.y -= drop * 0.72
        leftKnee.y -= drop * 0.20
        rightKnee.y -= drop * 0.20
        leftKnee.z += drop * 0.45
        rightKnee.z += drop * 0.45
    }

    private mutating func applyDefensiveLowering(
        amount: Float, crouch: Float, yaw: Float, pitch: Float, roll: Float,
        lateralShift: Float, style: FightStyle
    ) {
        guard amount.isFinite, amount > 0, crouch.isFinite, yaw.isFinite,
              pitch.isFinite, roll.isFinite, lateralShift.isFinite else { return }
        let weight = min(1, amount)
        let original = self
        let oldHead = original.headFacingPosition
        // Sample the style's guard without overwriting this pose's existing lowered hand positions.
        var guardPose = FightPose.neutral(stride: 0, style: style)
        guardPose.applyGuard(style: style)
        let guardHead = guardPose.headFacingPosition

        separatesTorsoRotation = true
        let drop = min(max(0, crouch), max(0, 0.42 - defensiveCrouch))
        defensiveCrouch += drop
        lowerBody(by: drop)
        // Slightly stronger shoulder/chest twist; keep the pelvis rotation unchanged.
        torsoYaw += yaw * 1.15
        hipYaw += yaw * 0.45
        // Remove backward style pitch while entering; preserve forward readiness pitch.
        torsoPitch += pitch - max(0, torsoPitch) * weight
        torsoLean = torsoLean * (1 - weight) + roll
        rootX = min(0.06, max(-0.06, rootX + lateralShift))

        let head = headFacingPosition
        func guardedPoint(_ current: SIMD3<Float>, _ target: SIMD3<Float>) -> SIMD3<Float> {
            let offset = original.facingPoint(current) - oldHead
            let guardOffset = guardPose.facingPoint(target) - guardHead
            return torsoPoint(head + offset + (guardOffset - offset) * weight)
        }
        // Elbows and gloves follow the actual partially-rotated head, not a fixed world Y or
        // an independent sideways hand shove. Shoulders remain attached to the rotated torso.
        leftGlove = guardedPoint(original.leftGlove, guardPose.leftGlove)
        rightGlove = guardedPoint(original.rightGlove, guardPose.rightGlove)
        leftElbow = guardedPoint(original.leftElbow, guardPose.leftElbow)
        rightElbow = guardedPoint(original.rightElbow, guardPose.rightElbow)
    }

    mutating func blendStraightPunchEntry(_ entry: FightPose, punch: Punch, progress: Float) {
        guard punch == .jab || punch == .cross else { return }
        blendAttackEntry(entry, punch: punch, progress: progress)
    }

    mutating func blendAttackEntry(_ entry: FightPose, punch: Punch, progress: Float) {
        guard entry.style == style, progress.isFinite,
              let spec = CombatData.attacks[punch] else { return }
        let contact = Float(spec.activeStart / spec.duration)
        let recovery = min(1, max(0, (progress - contact) / (1 - contact)))
        let weight = 1 - recovery * recovery * (3 - 2 * recovery)
        blend(from: entry, amount: weight, includesFootAngles: false)
    }

    mutating func blend(from entry: FightPose, amount: Float, includesFootAngles: Bool = true) {
        guard entry.style == style, amount.isFinite else { return }
        let weight = min(1, max(0, amount))
        rootX += (entry.rootX - rootX) * weight
        rootY += (entry.rootY - rootY) * weight
        rootZ += (entry.rootZ - rootZ) * weight
        bodyDrop += (entry.bodyDrop - bodyDrop) * weight
        defensiveCrouch += (entry.defensiveCrouch - defensiveCrouch) * weight
        headBob += (entry.headBob - headBob) * weight
        torsoY += (entry.torsoY - torsoY) * weight
        torsoOffset += (entry.torsoOffset - torsoOffset) * weight
        torsoLean += (entry.torsoLean - torsoLean) * weight
        torsoPitch += (entry.torsoPitch - torsoPitch) * weight
        torsoYaw += (entry.torsoYaw - torsoYaw) * weight
        hipYaw += (entry.hipYaw - hipYaw) * weight
        leftShoulder += (entry.leftShoulder - leftShoulder) * weight
        rightShoulder += (entry.rightShoulder - rightShoulder) * weight
        leftElbow += (entry.leftElbow - leftElbow) * weight
        rightElbow += (entry.rightElbow - rightElbow) * weight
        leftGlove += (entry.leftGlove - leftGlove) * weight
        rightGlove += (entry.rightGlove - rightGlove) * weight
        leftHip += (entry.leftHip - leftHip) * weight
        rightHip += (entry.rightHip - rightHip) * weight
        leftKnee += (entry.leftKnee - leftKnee) * weight
        rightKnee += (entry.rightKnee - rightKnee) * weight
        if includesFootAngles {
            leftFootYaw += (entry.leftFootYaw - leftFootYaw) * weight
            rightFootYaw += (entry.rightFootYaw - rightFootYaw) * weight
            leftFootPitch += (entry.leftFootPitch - leftFootPitch) * weight
            rightFootPitch += (entry.rightFootPitch - rightFootPitch) * weight
        }
    }

    mutating func applyAttack(_ punch: Punch, progress: Float, opponentDistance: Float? = nil, reachMultiplier: Float = 1, targetRadius: Float = 0.34, straightAnatomy: StraightPunchAnatomy? = nil, contactTarget: SIMD3<Float>? = nil) {
        if punch == .jab || punch == .cross {
            applyStraightPunch(punch, progress: progress, opponentDistance: opponentDistance,
                               reachMultiplier: reachMultiplier, targetRadius: targetRadius, anatomy: straightAnatomy,
                               contactTarget: contactTarget)
        } else {
            applyPowerPunch(punch, progress: progress, opponentDistance: opponentDistance,
                            reachMultiplier: reachMultiplier, targetRadius: targetRadius, anatomy: straightAnatomy,
                            contactTarget: contactTarget)
        }
    }
}

struct FighterPoseTransition {
    static let duration = 0.10
    let source: FightPose
    let facingAngle: Float
    private(set) var remaining = FighterPoseTransition.duration

    var isActive: Bool { remaining > 0 }

    mutating func advance(_ deltaTime: Double) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        remaining = max(0, remaining - deltaTime)
    }

    func apply(to pose: inout FightPose, facingAngle currentAngle: Float) {
        guard isActive else { return }
        let difference = facingAngle - currentAngle
        let turn = atan2(sin(difference), cos(difference))
        let rotation = simd_quatf(angle: turn, axis: SIMD3<Float>(0, 1, 0))
        var entry = source
        let root = rotation.act(SIMD3<Float>(entry.rootX, entry.rootY, entry.rootZ))
        entry.rootX = root.x
        entry.rootY = root.y
        entry.rootZ = root.z
        entry.torsoOffset = rotation.act(entry.torsoOffset)
        entry.torsoYaw += turn
        entry.hipYaw += turn
        entry.leftKnee = rotation.act(entry.leftKnee)
        entry.rightKnee = rotation.act(entry.rightKnee)
        entry.leftFootYaw += turn
        entry.rightFootYaw += turn
        let weight = Float(remaining / Self.duration)
        pose.blend(from: entry, amount: weight * weight * (3 - 2 * weight))
    }
}