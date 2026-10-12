import Foundation
import simd
#if canImport(RIVAL)
@testable import RIVAL
#endif

/// Runs against the same production sources on macOS and inside iPhone XCTest. No renderer,
/// save data, audio, device automation or alternate implementation of the animation math.
enum MotionRegressionChecks {
    @MainActor
    static func run() -> (checks: Int, failures: [String]) {
        var count = 0
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            count += 1
            if !condition, failures.count < 30 { failures.append(message) }
        }
        func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool { simd_distance(a, b) < 0.0001 }
        func hit(_ punch: Punch, blocked: Bool = false, knockout: Bool = false) -> CombatImpact {
            CombatImpact(attacker: .player, punch: punch, damage: CombatData.attacks[punch]!.damage,
                         guarded: blocked, guardBroken: false, counter: false,
                         perfectCounter: false, knockout: knockout)
        }

        for style in FightStyle.allCases {
            var ready = FightPose.neutral(stride: 0, style: style, stanceWidth: style.stanceWidth,
                                         leanBias: style.leanBias, pitchBias: style.pitchBias)
            let original = ready
            ready.applyReadiness(motion: BoxingIdleMotion())
            check(ready.torsoPitch < 0 && ready.torsoPitch >= -0.10, "Readiness faces forward: \(style)")
            check(near(ready.leftFoot, original.leftFoot) && near(ready.rightFoot, original.rightFoot), "Readiness plants feet")
            if style == .infighting {
                check(near(ready.leftGlove, original.leftGlove), "Slugger low/wide guard preserved")
            }
            if style == .outboxing {
                check(ready.leftGlove.y < ready.rightGlove.y, "Outboxer shell preserved")
            }
            for direction in [-1, 0, 1] {
                var base = ready
                if direction != 0 { base.applyDuck(direction: Float(direction), style: style) }
                check(base.leftFoot == ready.leftFoot && base.rightFoot == ready.rightFoot, "Duck never translates either foot")
                if direction != 0 {
                    var guardPose = FightPose.neutral(stride: 0, style: style)
                    guardPose.applyGuard(style: style)
                    for (joint, target) in zip(guardJoints(base), guardJoints(guardPose)) {
                        check(near(base.facingPoint(joint) - base.headFacingPosition,
                                   target - SIMD3<Float>(0, 2.28, 0.04)),
                              "Duck gloves/elbows keep style guard offset from actual chin: \(style)/\(direction)")
                    }
                    check(base.headFacingPosition.y < ready.headFacingPosition.y - 0.39, "Duck lowers actual head")
                    check(base.leftShoulder.x == ready.leftShoulder.x, "Duck shoulder stays attached")
                }
                for punch in Punch.allCases {
                    let spec = CombatData.attacks[punch]!
                    let contact = Float(spec.activeStart / spec.duration)
                    let leading = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
                    check(abs(PunchMotion.sample(punch, progress: contact).reach - 1) < 0.00001,
                          "Contact timing \(punch)")
                    check(PunchMotion.sample(punch, progress: 0) == PunchMotion(), "Neutral attack start")
                    check(PunchMotion.sample(punch, progress: 1) == PunchMotion(), "Neutral attack end")
                    var contactPose = base
                    contactPose.applyAttack(punch, progress: contact, opponentDistance: 1.25,
                                            reachMultiplier: Float(style.reachMultiplier))
                    let pivot = SIMD3<Float>(0, contactPose.torsoY, 0)
                    let glove = leading ? contactPose.leftGlove : contactPose.rightGlove
                    let rendered = contactPose.torsoOrientation.act(glove - pivot) + pivot
                    check(abs(rendered.z - 0.91) < 0.0001, "Facing-space target preserved: \(punch)/\(style)/\(direction)")
                    let peakHeight: Float = spec.family == .body ? 1.35 : (spec.family == .uppercut ? 2.13 : 2.08)
                    check(abs(rendered.y - peakHeight) < 0.0001, "Contact zone height preserved")
                    for i in 0...60 {
                        var pose = base
                        pose.applyAttack(punch, progress: Float(i) / 60)
                        for point in [pose.leftGlove, pose.rightGlove, pose.leftElbow, pose.rightElbow,
                                      pose.leftFoot, pose.rightFoot] {
                            check(point.x.isFinite && point.y.isFinite && point.z.isFinite, "Finite pose: \(punch)")
                        }
                        checkOffhand(pose, base: base, punch: punch, progress: Float(i) / 60,
                                     label: "\(punch)/\(style)/\(direction)/\(i)", check: check)
                        if i == 0 || i == 60 {
                            check(near(pose.leftGlove, base.leftGlove) && near(pose.rightGlove, base.rightGlove), "Return to existing guard")
                            check(near(pose.leftElbow, base.leftElbow) && near(pose.rightElbow, base.rightElbow), "Elbow recovery")
                            check(near(pose.leftFoot, base.leftFoot) && near(pose.rightFoot, base.rightFoot), "Foot pivot recovery")
                            checkSamePose(pose, base, label: "Exact attack endpoint \(punch)/\(style)/\(direction)", check: check)
                        }
                    }
                    let early = PunchMotion.sample(punch, progress: contact * 0.12)
                    check(early.hipLoad > early.torsoLoad && early.reach < 0.01, "Pelvis loads before thorax/hand")
                }
            }
        }

        checkDefensiveGeometry(check)
        checkWeaveGeometry(check)
        checkBodyShovelsAndContactContract(check)

        check(BoxingIdleMotion.sample(at: 3.5, activity: 0, reducedMotion: true) == BoxingIdleMotion(), "Reduced idle is static")
        var guardValue: Float = 0
        var duckValue: Float = 0
        for _ in 0..<8 {
            guardValue = DefensiveMotion.guardBlend(current: guardValue, raised: true, deltaTime: 1.0 / 60, reducedMotion: false)
            duckValue = DefensiveMotion.duckBlend(current: duckValue, direction: 1, deltaTime: 1.0 / 60, reducedMotion: false)
            check((0...1).contains(guardValue) && (0...1).contains(duckValue), "Bounded defense transition")
        }
        check(guardValue > 0.95 && duckValue > 0.95, "Defense settles in about 0.13s")
        let frozenDuck = DefensiveMotion.duckBlend(current: duckValue, direction: -1, deltaTime: 0, reducedMotion: false)
        check(frozenDuck == duckValue, "Paused duck freezes")
        check(DefensiveMotion.duckBlend(current: duckValue, direction: -1, deltaTime: 0.01, reducedMotion: true) == -1, "Reduced duck immediate")
        for _ in 0..<60 {
            duckValue = DefensiveMotion.duckBlend(current: duckValue, direction: -1, deltaTime: 1.0 / 60, reducedMotion: false)
            check((-1...1).contains(duckValue), "Duck reversal does not overshoot")
        }

        let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        for style in FightStyle.allCases {
            let pose = FightPose.neutral(stride: 0, style: style, stanceWidth: style.stanceWidth)
            for direction in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, 0, -1)] {
                for fps in [30, 60, 120] {
                    var feet = FootPlantMotion()
                    var root = SIMD3<Float>.zero
                    var previous = feet.sample(rootPosition: root, rootRotation: identity,
                                               left: pose.leftFoot, right: pose.rightFoot, deltaTime: 0, moving: false)
                    var previousWorldLeft = previous.left
                    var previousWorldRight = previous.right
                    var checkedFirstStep = false
                    for frame in 0..<(fps * 2) {
                        let moving = frame < fps
                        if moving { root += direction * (5.25 / Float(fps)) }
                        let next = feet.sample(rootPosition: root, rootRotation: identity,
                                               left: pose.leftFoot, right: pose.rightFoot,
                                               deltaTime: 1.0 / Double(fps), moving: moving)
                        let worldLeft = root + next.left
                        let worldRight = root + next.right
                        let leftStep = simd_length(SIMD2<Float>(worldLeft.x - previousWorldLeft.x, worldLeft.z - previousWorldLeft.z))
                        let rightStep = simd_length(SIMD2<Float>(worldRight.x - previousWorldRight.x, worldRight.z - previousWorldRight.z))
                        check(min(leftStep, rightStep) < 0.0001, "One world support foot: \(style)/\(direction)/\(fps)/\(frame)")
                        check(next.left.x > next.right.x, "No crossing feet: \(style)/\(direction)/\(fps)/\(frame)")
                        check(simd_distance(next.left, pose.leftFoot) < 0.95 && simd_distance(next.right, pose.rightFoot) < 0.95,
                              "Foot reach bounded: \(style)/\(direction)/\(fps)/\(frame)")
                        if !checkedFirstStep, direction.x != 0, max(leftStep, rightStep) > 0.0001 {
                            check(direction.x > 0 ? leftStep > 0 && rightStep < 0.0001 : rightStep > 0 && leftStep < 0.0001,
                                  "Direction-side foot leads")
                            checkedFirstStep = true
                        }
                        previous = next
                        previousWorldLeft = worldLeft
                        previousWorldRight = worldRight
                    }
                    check(simd_distance(previous.left, pose.leftFoot) < 0.03 && simd_distance(previous.right, pose.rightFoot) < 0.03,
                          "Feet settle after stopping: \(style)/\(direction)/\(fps)")
                    let paused = feet.sample(rootPosition: root, rootRotation: identity, left: pose.leftFoot,
                                             right: pose.rightFoot, deltaTime: 0, moving: false)
                    check(near(paused.left, previous.left) && near(paused.right, previous.right), "Pause preserves feet")
                    let rebased = feet.sample(rootPosition: root + SIMD3<Float>(5, 0, 0), rootRotation: identity,
                                              left: pose.leftFoot, right: pose.rightFoot, deltaTime: 0.02, moving: false)
                    check(near(rebased.left, pose.leftFoot) && near(rebased.right, pose.rightFoot), "Teleport rebases feet")
                }
            }
        }

        var turningFeet = FootPlantMotion()
        let restPose = FightPose.neutral(stride: 0)
        var previousTurn = turningFeet.sample(rootPosition: .zero, rootRotation: identity,
                                             left: restPose.leftFoot, right: restPose.rightFoot,
                                             deltaTime: 0, moving: false)
        for frame in 1...300 {
            let rotation = simd_quatf(angle: Float(frame) * 0.02, axis: SIMD3<Float>(0, 1, 0))
            let feet = turningFeet.sample(rootPosition: .zero, rootRotation: rotation,
                                         left: restPose.leftFoot, right: restPose.rightFoot,
                                         deltaTime: 1.0 / 60, moving: false)
            let world = FootPlantMotion.Feet(left: rotation.act(feet.left), right: rotation.act(feet.right))
            let leftTravel = simd_length(SIMD2<Float>(world.left.x - previousTurn.left.x, world.left.z - previousTurn.left.z))
            let rightTravel = simd_length(SIMD2<Float>(world.right.x - previousTurn.right.x, world.right.z - previousTurn.right.z))
            check(min(leftTravel, rightTravel) < 0.0001, "Facing turn retains one planted foot")
            check(feet.left.x > feet.right.x, "Facing turn avoids crossing feet")
            previousTurn = world
        }

        for punch in Punch.allCases {
            let impact = hit(punch)
            let peak = FighterImpactMotion.sample(impact, remaining: 0.24, reducedMotion: false)
            var previous = peak.recoil
            for frame in 0...120 {
                let remaining = 0.24 * (1 - Double(frame) / 120)
                let reaction = FighterImpactMotion.sample(impact, remaining: remaining, reducedMotion: false)
                check(reaction.recoil >= 0 && reaction.recoil <= previous + 0.00001, "Bounded two-stage recoil")
                previous = reaction.recoil
            }
            check(FighterImpactMotion.sample(impact, remaining: 0, reducedMotion: false) == FighterImpactMotion(), "Impact expires at same time")
            check(FighterImpactMotion.sample(hit(punch, blocked: true), remaining: 0.24, reducedMotion: false).shoulderYaw == 0,
                  "Blocked hit compresses guard, not head")
        }
        let leftHook = FighterImpactMotion.sample(hit(.leftHook), remaining: 0.24, reducedMotion: false)
        let rightHook = FighterImpactMotion.sample(hit(.rightHook), remaining: 0.24, reducedMotion: false)
        check(leftHook.headOffset.x * rightHook.headOffset.x < 0 && leftHook.shoulderYaw * rightHook.shoulderYaw < 0,
              "Opposite hooks turn head and shoulders in opposite directions")
        for elapsed in [0.0, 0.02, 0.04, 0.06, 0.08, 0.1] {
            let time = ImpactMotionBeat.elapsed(elapsed, impact: hit(.cross), reducedMotion: false)
            check(time <= elapsed && time >= elapsed - 0.0021, "Contact pulse has at most 2.1ms visual lag")
            check(ImpactMotionBeat.elapsed(elapsed, impact: hit(.jab), reducedMotion: false) == elapsed, "Light hits do not pulse")
            check(ImpactMotionBeat.elapsed(elapsed, impact: hit(.cross, blocked: true), reducedMotion: false) == elapsed, "Blocks do not pulse")
            check(ImpactMotionBeat.elapsed(elapsed, impact: hit(.cross, knockout: true), reducedMotion: false) == elapsed, "KO owns its clock")
            check(ImpactMotionBeat.elapsed(elapsed, impact: hit(.cross), reducedMotion: true) == elapsed, "Reduced pulse disabled")
        }
        check(ImpactMotionBeat.elapsed(0.08, impact: hit(.cross), reducedMotion: false) == 0.08, "No accumulated time drift")
        let presentation = CombatPresentation()
        presentation.receive(.impact(hit(.cross)))
        check(presentation.cameraContactKick > 0 && presentation.playerStrike != nil, "Contact event drives presentation")
        presentation.advance(deltaTime: 2.0 / 60)
        check(presentation.cameraContactKick == 0, "Camera kick lasts no more than two 60fps frames")
        presentation.receive(.attackStarted(fighter: .player))
        check(presentation.playerStrike == nil && presentation.rivalHit != nil, "New punch clears only its own strike")
        presentation.receive(.roundStarted)
        check(presentation.rivalHit == nil && presentation.cameraContactKick == 0, "Round reset clears contact state")
          presentation.receive(.impact(hit(.cross, knockout: true)))
          check(presentation.knockoutClockPhase == .waiting && presentation.signature == .knockout,
              "KO priority is immediate, clock label is delayed")
          presentation.advance(deltaTime: 0.19)
          check(presentation.knockoutClockPhase == .waiting, "First 0.2 seconds remain free of KO label")
          presentation.advance(deltaTime: 0.011)
          check(presentation.knockoutClockPhase == .visible, "KO appears in the clock after delay")
          presentation.advance(deltaTime: 0)
          check(presentation.knockoutClockPhase == .visible, "Paused clock holds its phase")
          presentation.advance(deltaTime: 0.58)
          check(presentation.knockoutClockPhase == .visible, "KO remains visible for 0.6 seconds")
          presentation.advance(deltaTime: 0.02)
          check(presentation.knockoutClockPhase == .finished && presentation.signature == nil, "KO clock expires")
          presentation.receive(.roundStarted)
          check(presentation.knockoutClockPhase == .inactive, "Next round restores numeric clock")
          presentation.receive(.impact(hit(.cross, knockout: true)))
          presentation.advance(deltaTime: 0.1)
          presentation.receive(.roundStarted)
          presentation.advance(deltaTime: 0.3)
          check(presentation.knockoutClockPhase == .inactive, "Reset cancels a pending KO label")
          presentation.receive(.dodge(fighter: .player, grade: .perfect))
          check(presentation.signature == .counterWindow && presentation.knockoutClockPhase == .inactive,
              "Counter banner behavior is unchanged")
          check(CombatPresentationTiming.knockoutResultReveal == 0.95
              && CombatPresentationTiming.decisionResultReveal == 0.35, "Result reveal timing is unchanged")
        return (count, failures)
    }

    private static func guardJoints(_ pose: FightPose) -> [SIMD3<Float>] {
        [pose.leftGlove, pose.rightGlove, pose.leftElbow, pose.rightElbow]
    }

    private static func joints(_ pose: FightPose) -> [SIMD3<Float>] {
        [pose.leftShoulder, pose.rightShoulder, pose.leftElbow, pose.rightElbow,
         pose.leftGlove, pose.rightGlove, pose.leftHip, pose.rightHip,
         pose.leftKnee, pose.rightKnee, pose.leftFoot, pose.rightFoot]
    }

    private static func scalars(_ pose: FightPose) -> [Float] {
        [pose.rootX, pose.rootY, pose.rootZ, pose.bodyDrop, pose.headBob, pose.defensiveCrouch,
         pose.torsoY, pose.torsoLean, pose.torsoPitch, pose.torsoYaw, pose.hipYaw,
         pose.leftFootYaw, pose.rightFootPitch, pose.rightFootYaw]
    }

    private static func checkSamePose(_ pose: FightPose, _ base: FightPose, label: String,
                                      check: (Bool, String) -> Void) {
        check(joints(pose) == joints(base), "\(label): all joints unchanged")
        check(scalars(pose) == scalars(base), "\(label): all scalars retain baseline, including hipYaw/rootX/bodyDrop")
        check(pose.separatesTorsoRotation == base.separatesTorsoRotation, "\(label): rotation mode unchanged")
    }

    private static func checkFinite(_ pose: FightPose, label: String, check: (Bool, String) -> Void) {
        check(scalars(pose).allSatisfy(\.isFinite), "\(label): finite scalar pose")
        check((joints(pose) + [pose.headFacingPosition]).allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        }, "\(label): finite joints/head")
    }

    private static func readyPose(_ style: FightStyle) -> FightPose {
        var pose = FightPose.neutral(stride: 0, style: style, stanceWidth: style.stanceWidth,
                                     leanBias: style.leanBias, pitchBias: style.pitchBias)
        // Nonzero idle head height catches guards anchored to a stale y=2.28 instead of the head.
        pose.applyReadiness(motion: BoxingIdleMotion(breath: 0.006, weightShift: 0.003, guardLift: 0.002))
        return pose
    }

    private static func checkDefenseGuard(_ pose: FightPose, base: FightPose, style: FightStyle,
                                          amount: Float, label: String, check: (Bool, String) -> Void) {
        var guarded = FightPose.neutral(stride: 0, style: style)
        guarded.applyGuard(style: style)
        for (index, entries) in zip(zip(guardJoints(pose), guardJoints(base)), guardJoints(guarded)).enumerated() {
            let ((joint, original), target) = entries
            let oldOffset = base.facingPoint(original) - base.headFacingPosition
            let targetOffset = target - SIMD3<Float>(0, 2.28, 0.04)
            let expected = oldOffset + (targetOffset - oldOffset) * amount
            check(simd_distance(pose.facingPoint(joint) - pose.headFacingPosition, expected) < 0.0001,
                  "\(label): chin-relative guard joint \(index)")
        }
    }

    private static func checkOffhand(_ pose: FightPose, base: FightPose, punch: Punch,
                                    progress: Float, label: String, check: (Bool, String) -> Void) {
        let leading = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
        let side: Float = leading ? -1 : 1
        let amount = PunchMotion.sample(punch, progress: progress).torsoDrive
            * ((punch == .jab || punch == .cross) ? 0.85 : 0.80)
        let old = [leading ? base.rightGlove : base.leftGlove, leading ? base.rightElbow : base.leftElbow]
        let current = [leading ? pose.rightGlove : pose.leftGlove, leading ? pose.rightElbow : pose.leftElbow]
        let targets = [SIMD3<Float>(side * 0.23, -0.16, 0.34), SIMD3<Float>(side * 0.35, -0.58, 0.18)]
        for index in 0..<2 {
            let offset = base.facingPoint(old[index]) - base.headFacingPosition
            let expected = offset + (targets[index] - offset) * amount
            check(simd_distance(pose.facingPoint(current[index]) - pose.headFacingPosition, expected) < 0.0001,
                  "Offhand follows chin, not fixed world height: \(label)/\(index)")
        }
    }

    private static func checkDefensiveGeometry(_ check: (Bool, String) -> Void) {
        for style in FightStyle.allCases {
            let ready = readyPose(style)
            for direction in [-1, 1] {
                for step in 0...20 {
                    let amount = Float(step) / 20
                    let side = Float(direction) * amount
                    var pose = ready
                    pose.applyDuck(direction: side, style: style)
                    let label = "Duck \(style)/\(direction)/\(step)"
                    check(abs(pose.bodyDrop - ready.bodyDrop - 0.40 * amount) < 0.00001, "\(label): .40 knee/hip dip")
                    check(abs(pose.torsoYaw - ready.torsoYaw + 0.207 * side) < 0.00001, "\(label): shoulder/chest yaw increased by 15 percent")
                    check(abs(pose.hipYaw - ready.hipYaw + 0.081 * side) < 0.00001, "\(label): pelvis follows yaw")
                    check(abs(pose.torsoPitch - ready.torsoPitch + 0.14 * amount) < 0.00001, "\(label): forward pitch preserved")
                    check(abs(pose.torsoLean - (ready.torsoLean * (1 - amount) + 0.025 * side)) < 0.00001,
                          "\(label): small roll, not lateral fold")
                    check(abs(pose.rootX + 0.04 * side) < 0.00001, "\(label): bounded local visual shift")
                    check(pose.rootY == ready.rootY && pose.rootZ == ready.rootZ, "\(label): no root bob/forward displacement")
                    check(pose.leftFoot == ready.leftFoot && pose.rightFoot == ready.rightFoot, "\(label): complete foot positions fixed")
                    check(abs(pose.leftHip.y - ready.leftHip.y + 0.288 * amount) < 0.00001
                        && abs(pose.rightHip.y - ready.rightHip.y + 0.288 * amount) < 0.00001, "\(label): both hips lower")
                    check(abs(pose.leftKnee.y - ready.leftKnee.y + 0.08 * amount) < 0.00001
                        && abs(pose.rightKnee.z - ready.rightKnee.z - 0.18 * amount) < 0.00001, "\(label): knees flex, feet stay down")
                    checkDefenseGuard(pose, base: ready, style: style, amount: amount, label: label, check: check)
                    checkFinite(pose, label: label, check: check)
                }
            }
            for invalid in [Float(0), .nan, .infinity, -.infinity] {
                var pose = ready
                pose.applyDuck(direction: invalid, style: style)
                checkSamePose(pose, ready, label: "Zero/nonfinite duck \(style)/\(invalid)", check: check)
            }
            for direction in [Float(-2), 2] {
                var clamped = ready, full = ready
                clamped.applyDuck(direction: direction, style: style)
                full.applyDuck(direction: direction < 0 ? -1 : 1, style: style)
                checkSamePose(clamped, full, label: "Duck clamps to full commitment", check: check)
            }
            // The primitive must move all connected joints, not the root or feet, for a dip OR rise.
            for drop in [Float(0), 0.40, -0.055] {
                var pose = ready
                pose.rootX = 0.017; pose.rootY = 0.021; pose.rootZ = -0.031
                let base = pose
                pose.lowerBody(by: drop)
                let expectedDeltas = [SIMD3<Float>(0, -drop, 0), SIMD3<Float>(0, -drop, 0),
                                      SIMD3<Float>(0, -drop, 0), SIMD3<Float>(0, -drop, 0),
                                      SIMD3<Float>(0, -drop, 0), SIMD3<Float>(0, -drop, 0),
                                      SIMD3<Float>(0, -drop * 0.72, 0), SIMD3<Float>(0, -drop * 0.72, 0),
                                      SIMD3<Float>(0, -drop * 0.20, drop * 0.45), SIMD3<Float>(0, -drop * 0.20, drop * 0.45),
                                      SIMD3<Float>.zero, SIMD3<Float>.zero]
                for (index, pair) in zip(joints(pose), joints(base)).enumerated() {
                    check(simd_distance(pair.0 - pair.1, expectedDeltas[index]) < 0.00001,
                          "lowerBody connected joint \(style)/\(drop)/\(index)")
                }
                check(pose.rootX == base.rootX && pose.rootY == base.rootY && pose.rootZ == base.rootZ,
                      "lowerBody preserves all root coordinates")
                check(abs(pose.bodyDrop - base.bodyDrop - drop) < 0.00001
                    && abs(pose.torsoY - base.torsoY + drop) < 0.00001, "lowerBody changes body/head and torso consistently")
                check(pose.defensiveCrouch == base.defensiveCrouch && pose.hipYaw == base.hipYaw
                    && pose.torsoYaw == base.torsoYaw && pose.headBob == base.headBob, "lowerBody does not overwrite other layers")
            }
        }
    }

    private static func checkWeaveGeometry(_ check: (Bool, String) -> Void) {
        for direction in [-1, 1] {
            let entry = WeaveMotion.sample(direction: direction, elapsed: 0.22)
            let hook: Punch = direction < 0 ? .leftHook : .rightHook
            let spec = CombatData.attacks[hook]!
            let contact = Float(spec.activeStart / spec.duration)
            check(entry.carryingHook(progress: 0, contactProgress: contact) == entry, "Hook begins in weave exit pose")
            check(entry.carryingHook(progress: contact, contactProgress: contact).crouch == entry.crouch,
                  "Weave hook stays loaded until contact, even after evasion ends")
            var previous = entry.crouch
            for i in 0...60 {
                let pose = entry.carryingHook(progress: Float(i) / 60, contactProgress: contact)
                check(pose.crouch <= previous + 0.00001 && pose.crouch >= 0, "Carried hook lowers no second time")
                previous = pose.crouch
            }
            check(entry.carryingHook(progress: 1, contactProgress: contact) == WeaveMotion(), "Hook recovery releases entry pose")
        }
        check(WeaveMotion.duration == 0.36 && WeaveState.duration == 0.36, "Weave visual/engine finish exactly .36s")
        check(WeaveMotion.lateralStart == 0.06 && WeaveState.evadeStart == 0.06, "Weave dip ends at .06s")
        check(WeaveMotion.lateralEnd == 0.22 && WeaveState.hookStart == 0.22, "Hook starts at lateral finish .22s")
        for reduced in [false, true] {
            for direction in [-1, 1] {
                for invalid in [Double(-1), 0, .nan, .infinity, -.infinity, 0.36, 0.40, 0.48, 1] {
                    check(WeaveMotion.sample(direction: direction, elapsed: invalid, reducedMotion: reduced) == WeaveMotion(),
                          "Inactive weave time is neutral, grace is not animation: \(invalid)/\(reduced)")
                }
                check(WeaveMotion.sample(direction: 0, elapsed: 0.14, reducedMotion: reduced) == WeaveMotion(), "Zero weave direction is neutral")
                let dip = WeaveMotion.sample(direction: direction, elapsed: 0.06, reducedMotion: reduced)
                let exit = WeaveMotion.sample(direction: direction, elapsed: 0.22, reducedMotion: reduced)
                check(dip.amount == 1 && exit.amount == 1 && dip.crouch == 0.38 && exit.crouch == 0.38, "Full .38 crouch spans low traverse")
                check(dip.lateralProgress == 0 && exit.lateralProgress == 1 && exit.riseProgress == 0, "Exact lateral/rise boundary phases")
                check(abs(exit.yaw + Float(direction) * 0.18 * (reduced ? 0.45 : 1)) < 0.00001, "Exit yaw magnitude/direction")
            }
        }
        for style in FightStyle.allCases {
            let ready = readyPose(style)
            for reduced in [false, true] {
                for direction in [-1, 1] {
                    let sign = Float(direction)
                    var state = WeaveState()
                    check(state.start(direction, facingX: 0, facingY: 1), "Weave U fixture starts facing local +Z")
                    var worldX: Float = 0
                    var previousTime = 0.0
                    var previousHead = ready.headFacingPosition
                    var lowHeadY: Float = 0
                    for frame in 0...72 { // 5ms samples; bounded to one .36s action.
                        let time = Double(frame) * 0.005
                        let step = state.advance(time - previousTime)
                        worldX += Float(step.x * 0.025)
                        previousTime = time
                        let motion = WeaveMotion.sample(direction: direction, elapsed: time, reducedMotion: reduced)
                        let opposite = WeaveMotion.sample(direction: -direction, elapsed: time, reducedMotion: reduced)
                        let full = WeaveMotion.sample(direction: direction, elapsed: time)
                        var pose = ready
                        pose.applyWeave(motion, style: style)
                        let head = pose.headFacingPosition + SIMD3<Float>(worldX + pose.rootX, pose.rootY, pose.rootZ)
                        let label = "Weave \(style)/\(direction)/\(reduced)/\(frame)"
                        let fields = [motion.amount, motion.crouch, motion.side, motion.yaw, motion.pitch,
                                      motion.roll, motion.rootX, motion.lateralProgress, motion.riseProgress]
                        check(fields.allSatisfy(\.isFinite), "\(label): finite sampler")
                        check((0...1).contains(motion.amount) && (0...0.380001).contains(motion.crouch), "\(label): bounded .38 dip")
                        check(abs(motion.rootX) <= 0.040001 && abs(motion.yaw) <= 0.180001 && abs(motion.roll) <= 0.025001,
                              "\(label): bounded turn/visual offset")
                        check(motion.crouch == opposite.crouch && motion.pitch == opposite.pitch
                            && motion.side == -opposite.side && motion.yaw == -opposite.yaw
                            && motion.rootX == -opposite.rootX && motion.roll == -opposite.roll, "\(label): directions mirror")
                        check(motion.amount == full.amount && motion.crouch == full.crouch
                            && motion.lateralProgress == full.lateralProgress && motion.riseProgress == full.riseProgress,
                              "\(label): Reduced Motion retains timing and dip")
                        if reduced {
                            check(motion.rootX == 0 && motion.roll == 0
                                && abs(motion.yaw - full.yaw * 0.45) < 0.00001
                                && abs(motion.pitch - full.pitch * 0.65) < 0.00001, "\(label): Reduced Motion suppresses decorative movement only")
                        }
                        check(abs(pose.bodyDrop - ready.bodyDrop - motion.crouch) < 0.00001, "\(label): pelvis-generated dip, not head-only U")
                        check(abs(pose.torsoYaw - ready.torsoYaw - motion.yaw * 1.15) < 0.00001,
                            "\(label): shoulder/chest yaw increased by 15 percent")
                        check(abs(pose.hipYaw - ready.hipYaw - motion.yaw * 0.45) < 0.00001,
                            "\(label): pelvis rotation unchanged")
                        check(abs(pose.leftHip.y - ready.leftHip.y + motion.crouch * 0.72) < 0.00001
                            && abs(pose.rightKnee.z - ready.rightKnee.z - motion.crouch * 0.45) < 0.00001, "\(label): connected hip/knee flexion")
                        check(pose.leftFoot == ready.leftFoot && pose.rightFoot == ready.rightFoot
                            && pose.rootY == ready.rootY && pose.rootZ == ready.rootZ, "\(label): feet/rootY/rootZ unchanged")
                        check(abs(worldX + pose.rootX) <= 0.340001, "\(label): engine step is not added to visual root twice")
                        checkDefenseGuard(pose, base: ready, style: style, amount: motion.amount, label: label, check: check)
                        checkFinite(pose, label: label, check: check)
                        if frame > 0 && frame <= 12 { check(head.y < previousHead.y, "\(label): U descends before traversal") }
                        if frame >= 12 && frame <= 44 {
                            check(head.y < ready.headFacingPosition.y - 0.35, "\(label): U stays low while crossing")
                            if frame > 12 { check((head.x - previousHead.x) * sign < 0, "\(label): U crosses toward exit side") }
                        }
                        if frame == 44 { lowHeadY = head.y }
                        if frame > 44 { check(head.y > previousHead.y, "\(label): U rises after traversal") }
                        if frame == 72 {
                            check(head.y > lowHeadY + 0.35, "\(label): final head rises out of U")
                            check(abs(head.x - ready.headFacingPosition.x + sign * 0.30) < 0.00001, "\(label): only the real 12-unit step remains")
                            checkSamePose(pose, ready, label: "Weave finish returns to exact baseline", check: check)
                        }
                        previousHead = head
                    }
                    // The renderer's duck fade must not double the defensive crouch or drop tiny inputs.
                    for time in [0.0001, 0.03, 0.06, 0.14, 0.22, 0.30, 0.3599, 0.36] {
                        let motion = WeaveMotion.sample(direction: direction, elapsed: time, reducedMotion: reduced)
                        for heldDuck in [Float(-1), 1] {
                            var pose = ready
                            pose.applyDuck(direction: heldDuck * (1 - motion.amount), style: style)
                            pose.applyWeave(motion, style: style)
                            check(abs(pose.bodyDrop - (0.40 * (1 - motion.amount) + motion.crouch)) < 0.00001,
                                  "Scaled duck + weave shares bounded lowering without threshold snap")
                            check(pose.defensiveCrouch <= 0.420001 && abs(pose.rootX) <= 0.060001, "Combined defense remains bounded")
                            check(pose.leftFoot == ready.leftFoot && pose.rightFoot == ready.rightFoot, "Combined defense plants both feet")
                        }
                    }
                    for boundary in [0.06, 0.22, 0.36] {
                        var before = ready, after = ready
                        before.applyWeave(.sample(direction: direction, elapsed: boundary - 0.000001, reducedMotion: reduced), style: style)
                        after.applyWeave(.sample(direction: direction, elapsed: boundary + 0.000001, reducedMotion: reduced), style: style)
                        check(zip(joints(before), joints(after)).allSatisfy { simd_distance($0.0, $0.1) < 0.0001 }
                            && simd_distance(before.headFacingPosition, after.headFacingPosition) < 0.0001,
                              "Weave joins continuously at \(boundary)/\(style)/\(direction)/\(reduced)")
                    }
                    checkWeaveHook(ready: ready, style: style, direction: direction, reduced: reduced, check: check)
                }
            }
            for invalid in [WeaveMotion(), WeaveMotion(amount: .nan), WeaveMotion(amount: 1, crouch: .nan),
                            WeaveMotion(amount: 1, yaw: .infinity), WeaveMotion(amount: 1, pitch: .nan),
                            WeaveMotion(amount: 1, roll: .nan), WeaveMotion(amount: 1, rootX: .infinity)] {
                var pose = ready
                pose.applyWeave(invalid, style: style)
                checkSamePose(pose, ready, label: "Zero/nonfinite defensive layer is a no-op", check: check)
            }
        }
    }

    private static func checkWeaveHook(ready: FightPose, style: FightStyle, direction: Int,
                                       reduced: Bool, check: (Bool, String) -> Void) {
        let hook: Punch = direction < 0 ? .leftHook : .rightHook
        let key: Punch = direction < 0 ? .jab : .cross
        let spec = CombatData.attacks[hook]!
        var state = WeaveState()
        check(state.start(direction) && state.queueHook(base: key), "Same-side weave/hook fixture queues")
        state.advance(0.22)
        check(state.takeReadyHook() == hook && state.elapsed == 0.22 && state.isActive,
              "Taking hook at .22 never resets active weave")
        var startBase = ready
        startBase.applyWeave(.sample(direction: direction, elapsed: state.elapsed, reducedMotion: reduced), style: style)
        var started = startBase
        started.applyAttack(hook, progress: 0)
        checkSamePose(started, startBase, label: "Hook starts from exact .22 weave base", check: check)
        check(abs(started.bodyDrop - 0.38) < 0.00001, "Hook starts lowered, not standing")

        for frame in 0...28 {
            let time = frame == 28 ? 0.36 : 0.22 + Double(frame) * 0.005
            let progress = Float((time - 0.22) / spec.duration)
            var base = ready
            base.applyWeave(.sample(direction: direction, elapsed: time, reducedMotion: reduced), style: style)
            var pose = base
            pose.applyAttack(hook, progress: progress, opponentDistance: 1.25, reachMultiplier: Float(style.reachMultiplier))
            let expectedRise = min(Float(0.055), base.defensiveCrouch * 0.15) * PunchMotion.sample(hook, progress: progress).torsoDrive
            check(abs(pose.bodyDrop - base.bodyDrop + expectedRise) < 0.00001, "Weave/hook keeps current base and only bounded .055 rise")
            if frame < 28 { check(pose.bodyDrop > 0, "Active hook does not cut off weave recovery before .36") }
            checkOffhand(pose, base: base, punch: hook, progress: progress, label: "Weave hook \(style)/\(direction)/\(reduced)/\(frame)", check: check)
            check(pose.leftFoot.x == base.leftFoot.x && pose.leftFoot.z == base.leftFoot.z
                && pose.rightFoot.x == base.rightFoot.x && pose.rightFoot.z == base.rightFoot.z, "Hook pivot adds no horizontal foot teleport")
            checkFinite(pose, label: "Weave hook", check: check)
            if frame == 28 {
                var withoutWeave = ready
                withoutWeave.applyAttack(hook, progress: progress, opponentDistance: 1.25, reachMultiplier: Float(style.reachMultiplier))
                checkSamePose(pose, withoutWeave, label: "At .36 weave ends while original hook continues", check: check)
            }
        }
        let contact = Float(spec.activeStart / spec.duration)
        var contactPose = ready
        contactPose.applyWeave(.sample(direction: direction, elapsed: 0.22 + spec.activeStart, reducedMotion: reduced), style: style)
        contactPose.applyAttack(hook, progress: contact, opponentDistance: 1.25, reachMultiplier: Float(style.reachMultiplier))
        let glove = contactPose.facingPoint(direction < 0 ? contactPose.leftGlove : contactPose.rightGlove)
        check(simd_distance(glove, SIMD3<Float>(direction < 0 ? 0.16 : -0.16, 2.08, 0.91)) < 0.0001,
              "Queued hook contact stays .22 + original activeStart at original target")
        var finished = ready
        finished.applyWeave(.sample(direction: direction, elapsed: 0.22 + spec.duration, reducedMotion: reduced), style: style)
        finished.applyAttack(hook, progress: 1)
        checkSamePose(finished, ready, label: "Hook completes without residual defensive offset", check: check)
    }

    private static func checkBodyShovelsAndContactContract(_ check: (Bool, String) -> Void) {
        // Literal pre-weave combat contract: changes to timing/damage/range/cost must not hide
        // behind tests that derive both their inputs and expectations from a modified spec.
        let expected: [Punch: AttackSpec] = [
            .jab: AttackSpec(duration: 0.24, activeStart: 0.08, activeEnd: 0.15, damage: 6, range: 78, halfAngle: 26, staminaCost: 13, targetZone: .head, fistRadius: 5, family: .straight),
            .cross: AttackSpec(duration: 0.34, activeStart: 0.14, activeEnd: 0.24, damage: 11, range: 60, halfAngle: 20, staminaCost: 18, targetZone: .head, fistRadius: 5.4, family: .straight),
            .leftBody: AttackSpec(duration: 0.32, activeStart: 0.12, activeEnd: 0.22, damage: 9, range: 54, halfAngle: 40, staminaCost: 16, targetZone: .body, fistRadius: 5.2, family: .body),
            .rightBody: AttackSpec(duration: 0.35, activeStart: 0.14, activeEnd: 0.24, damage: 10, range: 56, halfAngle: 38, staminaCost: 17, targetZone: .body, fistRadius: 5.4, family: .body),
            .leftHook: AttackSpec(duration: 0.36, activeStart: 0.16, activeEnd: 0.26, damage: 11, range: 50, halfAngle: 56, staminaCost: 18, targetZone: .head, fistRadius: 5.6, family: .hook),
            .rightHook: AttackSpec(duration: 0.38, activeStart: 0.17, activeEnd: 0.28, damage: 12, range: 52, halfAngle: 50, staminaCost: 19, targetZone: .head, fistRadius: 5.8, family: .hook),
            .leftUppercut: AttackSpec(duration: 0.40, activeStart: 0.18, activeEnd: 0.30, damage: 13, range: 44, halfAngle: 26, staminaCost: 20, targetZone: .head, fistRadius: 5.4, family: .uppercut),
            .rightUppercut: AttackSpec(duration: 0.42, activeStart: 0.19, activeEnd: 0.31, damage: 14, range: 46, halfAngle: 24, staminaCost: 21, targetZone: .head, fistRadius: 5.8, family: .uppercut)
        ]
        check(CombatData.attacks == expected, "All eight original AttackSpecs are unchanged")
        check(BodyShovelMotion.loadHeight == 1.08 && BodyShovelMotion.loadFraction == 0.40
            && BodyShovelMotion.recoveryEnd == 0.88, "Body shovel retains authored load/recovery landmarks")
        let reaches: [(distance: Float?, radius: Float)] = [(nil, 0.34), (0.4, 0.34), (1.25, 0.24), (3.5, 0.46)]
        for style in FightStyle.allCases {
            let ready = readyPose(style)
            var bases: [(name: String, pose: FightPose)] = [("ready", ready)]
            for direction in [-1, 1] {
                var duck = ready, weave = ready
                duck.applyDuck(direction: Float(direction), style: style)
                weave.applyWeave(.sample(direction: direction, elapsed: 0.22), style: style)
                bases.append(("duck\(direction)", duck))
                bases.append(("weave\(direction)", weave))
            }
            for (name, base) in bases {
                for punch in Punch.allCases {
                    let spec = expected[punch]!
                    let lead = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
                    let side: Float = lead ? 1 : -1
                    let contactProgress = Float(spec.activeStart / spec.duration)
                    for progress in [Float(0), 1, -1, 2, .nan, .infinity, -.infinity] {
                        check(PunchMotion.sample(punch, progress: progress) == PunchMotion(), "Invalid/endpoint punch has no animation deltas")
                        var pose = base
                        pose.applyAttack(punch, progress: progress)
                        checkSamePose(pose, base, label: "\(punch)/\(style)/\(name)/\(progress) no-op", check: check)
                    }
                    for reach in reaches {
                        let label = "\(punch)/\(style)/\(name)/\(String(describing: reach.distance))/\(reach.radius)"
                        let maximum = Float((spec.range * style.reachMultiplier + 17) * 0.025) - reach.radius
                        let expectedReach = reach.distance.map { min(maximum, max(0.62, $0 - reach.radius)) } ?? maximum
                        check(abs(PunchMotion.contactReach(punch, opponentDistance: reach.distance,
                                                          reachMultiplier: Float(style.reachMultiplier), targetRadius: reach.radius) - expectedReach) < 0.0001,
                              "Original visual reach clamp: \(label)")
                        check(abs(PunchMotion.contactReach(punch, opponentDistance: .nan,
                                                          reachMultiplier: Float(style.reachMultiplier), targetRadius: reach.radius) - maximum) < 0.0001,
                              "Nonfinite distance falls back to original maximum: \(label)")
                        func sample(_ progress: Float) -> FightPose {
                            var pose = base
                            pose.applyAttack(punch, progress: progress, opponentDistance: reach.distance,
                                             reachMultiplier: Float(style.reachMultiplier), targetRadius: reach.radius)
                            return pose
                        }
                        func glove(_ progress: Float) -> SIMD3<Float> {
                            let pose = sample(progress)
                            return pose.facingPoint(lead ? pose.leftGlove : pose.rightGlove)
                        }
                        let height: Float = spec.family == .body ? 1.35 : (spec.family == .uppercut ? 2.13 : 2.08)
                        let target = SIMD3<Float>(side * (spec.family == .hook ? 0.16 : 0.10), height, expectedReach)
                        check(simd_distance(glove(contactProgress), target) < 0.0001, "Exact activeStart contact x/y/z: \(label)")
                        check(PunchMotion.sample(punch, progress: contactProgress).reach == 1
                            && PunchMotion.sample(punch, progress: contactProgress).followThrough == 0, "One contact, no premature follow-through")
                        check(PunchMotion.sample(punch, progress: contactProgress - 0.005).reach < 1
                            && PunchMotion.sample(punch, progress: contactProgress + 0.005).reach < 1, "Reach peak is at activeStart, not adjacent samples")
                        guard spec.family == .body else { continue }
                        let load = contactProgress * 0.40
                        let follow = contactProgress + 0.09
                        check(abs(glove(load).y - 1.08) < 0.0001, "Body load is exactly 1.08 at .40*activeStart: \(label)")
                        check(abs(glove(follow).y - 1.41) < 0.0001, "Body follows upward .06 after contact: \(label)")
                        var previousY = glove(load).y
                        for step in 1...48 {
                            let progress = load + (follow - load) * Float(step) / 48
                            let point = glove(progress)
                            check(point.y > previousY, "Body strictly ascends from load through follow: \(label)/\(step)")
                            check(point.z <= expectedReach + 0.0001, "Body ascending arc cannot add forward reach: \(label)/\(step)")
                            previousY = point.y
                        }
                        let epsilon: Float = 0.0001
                        let before = glove(contactProgress - epsilon), at = glove(contactProgress), after = glove(contactProgress + epsilon)
                        check(before.y < at.y && at.y < after.y, "Body is ascending on BOTH sides of contact: \(label)")
                        let incomingSlope = (at.y - before.y) / epsilon
                        let outgoingSlope = (after.y - at.y) / epsilon
                        check(incomingSlope > 0 && outgoingSlope > 0 && abs(incomingSlope - outgoingSlope) < 0.02,
                              "Body contact has continuous positive vertical slope: \(label)")
                        for step in 0...60 {
                            let progress = Float(step) / 60
                            let pose = sample(progress)
                            let point = pose.facingPoint(lead ? pose.leftGlove : pose.rightGlove)
                            check(point.z <= expectedReach + 0.0001, "Entire body motion stays within original reach: \(label)/\(step)")
                            checkFinite(pose, label: "Body \(label)/\(step)", check: check)
                            checkOffhand(pose, base: base, punch: punch, progress: progress, label: label, check: check)
                        }
                        let pose = sample(contactProgress)
                        let shoulder = pose.facingPoint(lead ? pose.leftShoulder : pose.rightShoulder)
                        let elbow = pose.facingPoint(lead ? pose.leftElbow : pose.rightElbow)
                        let upper = shoulder - elbow, forearm = at - elbow
                        let cosine = simd_dot(simd_normalize(upper), simd_normalize(forearm))
                        let angle = acos(min(1, max(-1, cosine))) * 180 / Float.pi
                        check(angle > 95 && angle < 97, "Body elbow remains compact ~96 degrees, not straight: \(label)")
                        check(abs(simd_length(upper) - simd_length(forearm)) < 0.0001, "Body elbow keeps balanced segments: \(label)")
                        check(abs(simd_distance(elbow, (shoulder + at) * 0.5) - simd_distance(shoulder, at) * 0.45) < 0.0001,
                              "Body elbow bend stays bounded to chord: \(label)")
                        check(elbow.y < at.y, "Body elbow stays below rising fist: \(label)")
                    }
                }
            }
        }
        let guardPosition = SIMD3<Float>(0.2, 2.16, 0.30)
        let target = SIMD3<Float>(0.1, 1.35, 0.91)
        for progress in [Float(0), -1, 0.88, 1, .nan, .infinity, -.infinity] {
            check(BodyShovelMotion.glove(progress: progress, contactProgress: 0.375,
                                         guardPosition: guardPosition, contact: target, side: 1) == guardPosition,
                  "Body helper returns exact guard for inactive/nonfinite progress")
        }
        for contact in [Float(0), -1, .nan] {
            check(BodyShovelMotion.glove(progress: 0.15, contactProgress: contact,
                                         guardPosition: guardPosition, contact: target, side: 1) == guardPosition,
                  "Body helper handles zero/invalid contact without division by zero")
        }
        for side in [Float(-1), 1] {
            check(BodyShovelMotion.elbow(shoulder: guardPosition, glove: guardPosition, side: side) == guardPosition,
                  "Zero-length body arm has finite coincident elbow")
            let glove = guardPosition + SIMD3<Float>(side * 0.18, -1, 0)
            let elbow = BodyShovelMotion.elbow(shoulder: guardPosition, glove: glove, side: side)
            check(elbow.x.isFinite && elbow.y.isFinite && elbow.z.isFinite, "Collinear bend axis uses finite fallback")
        }
    }
}