import SceneKit
import XCTest
@testable import RIVAL

@MainActor
final class RecoveryMotionTests: XCTestCase {
    func testOutcomeDetailsRespectContactWindowRecoveryDeadlineAndReducedMotion() throws {
        for punch in Punch.allCases {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let activeEnd = Float(spec.activeEnd / spec.duration)
            let end = Float(spec.recoveryEnd / spec.duration)
            for outcome in [RivalAttackOutcome.hit, .guarded, .missed(.contact), .evaded(.duck)] {
                for clock in [Float(0), Float(spec.activeStart / spec.duration), activeEnd, end, 1] {
                    let motion = PunchRecoveryMotion.sample(punch, progress: clock, landed: outcome.landed,
                        reducedMotion: false, outcome: outcome, clockProgress: clock)
                    XCTAssertEqual(motion.elbowOffset, .zero)
                    XCTAssertEqual(motion.offhandGuard, 0)
                }
                let clock = (activeEnd + end) / 2
                let motion = PunchRecoveryMotion.sample(punch, progress: clock, landed: outcome.landed,
                    reducedMotion: false, outcome: outcome, clockProgress: clock)
                let reduced = PunchRecoveryMotion.sample(punch, progress: clock, landed: outcome.landed,
                    reducedMotion: true, outcome: outcome, clockProgress: clock)
                XCTAssertGreaterThan(motion.offhandGuard, 0.17)
                XCTAssertGreaterThan(simd_length(motion.elbowOffset), 0.025)
                XCTAssertLessThan(simd_length(reduced.elbowOffset - motion.elbowOffset * 0.30), 0.00001)
                XCTAssertEqual(reduced.offhandGuard, motion.offhandGuard * 0.30, accuracy: 0.00001)
            }
            let middle = (activeEnd + end) / 2
            let hit = PunchRecoveryMotion.sample(punch, progress: middle, landed: true, reducedMotion: false,
                outcome: .hit, clockProgress: middle)
            let blocked = PunchRecoveryMotion.sample(punch, progress: middle, landed: true, reducedMotion: false,
                outcome: .guarded, clockProgress: middle)
            XCTAssertGreaterThan(simd_distance(hit.handOffset, blocked.handOffset), 0.04)
            XCTAssertGreaterThan(simd_distance(hit.elbowOffset, blocked.elbowOffset), 0.035)
        }
    }

    func testRecoveryKeepsFixedAnatomyPlantedFeetAndContinuousEndpoints() throws {
        let rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        for style in FightStyle.allCases {
            for punch in Punch.allCases {
                let spec = try XCTUnwrap(CombatData.attacks[punch])
                for outcome in [RivalAttackOutcome.hit, .guarded, .missed(.distance)] {
                    var previous: SIMD3<Float>?
                    for frame in 0...120 {
                        let clock = Float(frame) / 120
                        let progress = PunchRecoveryMotion.progress(punch, progress: clock, landed: outcome.landed)
                        var pose = FightPose.neutral(stride: 0, style: style)
                        let base = pose
                        pose.applyAttack(punch, progress: progress)
                        pose.applyPunchRecovery(punch, progress: progress, landed: outcome.landed,
                            reducedMotion: false, outcome: outcome, clockProgress: clock)
                        XCTAssertEqual(pose.leftFoot, base.leftFoot)
                        XCTAssertEqual(pose.rightFoot, base.rightFoot)
                        pose.resolveContactSupport(rootPosition: .zero, rootRotation: rotation)
                        for (root, joint, end) in [(pose.leftShoulder, pose.leftElbow, pose.leftGlove),
                                                  (pose.rightShoulder, pose.rightElbow, pose.rightGlove)] {
                            XCTAssertEqual(simd_distance(root, joint), 0.40, accuracy: 0.0001)
                            XCTAssertEqual(simd_distance(joint, end), 0.58, accuracy: 0.0001)
                        }

                        let leading = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
                        let hand = pose.facingPoint(leading ? pose.leftGlove : pose.rightGlove)
                        if let previous, Double(clock) * spec.duration > spec.activeEnd + spec.duration / 120 {
                            XCTAssertLessThan(simd_distance(hand, previous), 0.13, "\(style)/\(punch)/\(frame)")
                        }
                        previous = hand
                    }
                }
            }
        }
    }

    func testRecoveryDetailsDoNotMoveTheOffhandDuringContact() throws {
        for punch in Punch.allCases {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let leading = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
            for landed in [false, true] {
                for frame in 0...60 {
                    let clock = Float(spec.activeEnd / spec.duration) * Float(frame) / 60
                    let progress = PunchRecoveryMotion.progress(punch, progress: clock, landed: landed)
                    var pose = FightPose.neutral(stride: 0)
                    pose.applyAttack(punch, progress: progress)
                    let offhand = leading ? pose.rightGlove : pose.leftGlove
                    let elbow = leading ? pose.rightElbow : pose.leftElbow
                    pose.applyPunchRecovery(punch, progress: progress, landed: landed,
                        reducedMotion: false, outcome: landed ? .guarded : .missed(.contact),
                        clockProgress: clock)
                    XCTAssertEqual(leading ? pose.rightGlove : pose.leftGlove, offhand)
                    XCTAssertEqual(leading ? pose.rightElbow : pose.leftElbow, elbow)
                }
            }
        }
    }

    private func impact(_ punch: Punch, guarded: Bool = false, knockout: Bool = false) -> CombatImpact {
        CombatImpact(attacker: .rival, punch: punch, damage: 11, guarded: guarded,
            guardBroken: false, counter: false, perfectCounter: false, knockout: knockout)
    }

    func testImpactGuardTracksHeadAndSettlesWithoutChangingHeadOrBodyClocks() {
        for punch in Punch.allCases {
            for remaining in [0.24, 0.20, 0.12, 0.06, 0.001] {
                let hit = impact(punch)
                let motion = FighterImpactMotion.sample(hit, remaining: remaining, reducedMotion: false,
                    allowsContactBeat: false)
                XCTAssertEqual(motion.guardTracking, 1)
                XCTAssertGreaterThan(simd_length(motion.guardOffset), 0)
                let base = FightPose.neutral(stride: 0)
                var legacy = motion
                legacy.guardOffset = .zero
                legacy.guardTracking = 0
                var oldPose = base, pose = base
                oldPose.applyImpact(legacy)
                pose.applyImpact(motion)
                XCTAssertEqual(pose.headFacingPosition, oldPose.headFacingPosition)
                XCTAssertEqual(pose.bodyDrop, oldPose.bodyDrop)
                XCTAssertEqual(pose.leftFoot, oldPose.leftFoot)
                XCTAssertGreaterThan(simd_distance(pose.leftGlove, oldPose.leftGlove), 0)
                for reduced in [false, true] {
                    let expired = FighterImpactMotion.sample(hit, remaining: 0, reducedMotion: reduced)
                    XCTAssertEqual(expired, FighterImpactMotion())
                }
            }
            XCTAssertEqual(FighterImpactMotion.sample(impact(punch), remaining: 0.12,
                reducedMotion: true).guardTracking, 0)
            XCTAssertEqual(FighterImpactMotion.sample(impact(punch, knockout: true), remaining: 0.12,
                reducedMotion: false).guardTracking, 0)
        }
    }

    func testBlockedElbowsSettleAfterGlovesWithoutHeadSnapOrOvershoot() {
        let hit = impact(.cross, guarded: true)
        let peak = FighterImpactMotion.sample(hit, remaining: 0.24, reducedMotion: false)
        XCTAssertEqual(peak.elbowLag, 0, accuracy: 0.00001)
        var previousCompression = peak.guardCompression
        var previousElbow = peak.guardCompression * 0.4
        for frame in 1...240 {
            let remaining = 0.24 * (1 - Double(frame) / 240)
            let motion = FighterImpactMotion.sample(hit, remaining: remaining, reducedMotion: false,
                allowsContactBeat: false)
            let elbow = motion.guardCompression * 0.4 + motion.elbowLag
            XCTAssertGreaterThanOrEqual(motion.elbowLag, 0)
            XCTAssertLessThanOrEqual(motion.guardCompression, previousCompression + 0.000001)
            XCTAssertLessThanOrEqual(elbow, previousElbow + 0.000001)
            XCTAssertEqual(motion.headOffset, .zero)
            XCTAssertEqual(motion.recoil, 0)
            if frame < 240 { XCTAssertGreaterThan(motion.elbowLag, 0) }
            previousCompression = motion.guardCompression
            previousElbow = elbow
        }
    }

    func testGuardTransitionKeepsHeadAndEndpointsWhileElbowsFollowHands() {
        for style in FightStyle.allCases {
            let base = FightPose.neutral(stride: 0, style: style)
            var full = base
            full.applyGuard(style: style)
            for frame in 0...120 {
                let amount = Float(frame) / 120
                var pose = base
                pose.applyGuard(style: style, amount: amount)
                XCTAssertEqual(pose.torsoLean, base.torsoLean - 0.015 * amount, accuracy: 0.00001)
                XCTAssertEqual(pose.leftFoot, base.leftFoot)
                XCTAssertEqual(pose.rightFoot, base.rightFoot)
                let elbowAmount = amount * amount * (3 - 2 * amount)
                XCTAssertLessThan(simd_distance(pose.leftElbow,
                    base.leftElbow + (full.leftElbow - base.leftElbow) * elbowAmount), 0.000001)
                if frame == 0 {
                    XCTAssertLessThan(simd_distance(pose.leftGlove, base.leftGlove), 0.000001)
                }
                if frame == 120 {
                    XCTAssertEqual(pose.leftGlove, full.leftGlove)
                    XCTAssertEqual(pose.rightGlove, full.rightGlove)
                }
            }
        }
    }

    private struct Frame: Encodable {
        let time: Double
        let points: [String: [Float]]
    }

    private func attach<T: Encodable>(_ value: T, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(value), uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func run(punch: Punch, style: FightStyle, distance: Double, defense: String,
                     incoming: Bool = false, capture: String? = nil) throws -> [String: String] {
        let fixture = DefensivePunchFixture(punch: punch, style: style,
            distanceFraction: distance, renders: capture != nil)
        let defender = incoming ? fixture.engine.player : fixture.engine.enemy
        defender.guarding = defense == "guard"
        defender.duckDirection = defense == "left" ? -1 : (defense == "right" ? 1 : 0)
        fixture.advance(0)
        for _ in 0..<18 { fixture.advance(1.0 / 120) }
        let attacker = incoming ? fixture.engine.enemy : fixture.engine.player
        if incoming { attacker.stagger = 0 }
        XCTAssertTrue(fixture.engine.startAttack(attacker, punch: punch))
        if incoming { attacker.stagger = 1_000 }
        let renderer: SCNRenderer?
        if capture != nil {
            let view = SCNRenderer(device: nil, options: nil)
            view.scene = fixture.scene
            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 42
            camera.simdPosition = SIMD3(0.15, 2.0, 5.7)
            camera.look(at: SCNVector3(0, 1.35, 0))
            fixture.scene.rootNode.addChildNode(camera)
            view.pointOfView = camera
            renderer = view
        } else {
            renderer = nil
        }
        var frames: [Frame] = []
        for frame in 0..<90 {
            fixture.advance(capture == nil ? 1.0 / 120 : 1.0 / 60)
            if let capture, let renderer {
                var points: [String: [Float]] = [:]
                for prefix in ["player", "rival"] {
                    for part in ["Head", "Torso", "Pelvis", "LeftGlove", "RightGlove", "LeftFoot", "RightFoot"] {
                        let node = try XCTUnwrap(fixture.scene.rootNode.childNode(
                            withName: prefix + part, recursively: true))
                        let p = node.simdWorldPosition
                        points[prefix + part] = [p.x, p.y, p.z]
                    }
                    let fighter = prefix == "player" ? fixture.engine.player : fixture.engine.enemy
                    let sharedHead = PunchContactGeometry.target(fighter, zone: .head)
                    let renderedHead = try XCTUnwrap(points[prefix + "Head"])
                    XCTAssertLessThan(abs(renderedHead[1] - sharedHead.y - 0.13), 0.015,
                        "\(capture)/\(prefix)/\(frame)")
                }
                frames.append(Frame(time: fixture.elapsed, points: points))
                if frame.isMultiple(of: 3) {
                    let image = renderer.snapshot(atTime: fixture.elapsed, with: CGSize(width: 960, height: 540),
                        antialiasingMode: .multisampling4X)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = String(format: "recovery-%@-%03d", capture, frame)
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        if let capture { try attach(frames, name: "recovery-\(capture)-points") }
        XCTAssertNotEqual(fixture.result, "unresolved")
        return ["punch": punch.rawValue, "style": style.rawValue, "distance": "\(distance)",
            "defense": defense, "incoming": "\(incoming)", "result": fixture.result,
            "hp": "\(defender.hp)", "stamina": "\(attacker.stamina)",
            "x": "\(attacker.x)", "y": "\(attacker.y)"]
    }

    func testCaptureRecoveryAndCombatOutcomes() throws {
        var outcomes: [[String: String]] = []
        for style in FightStyle.allCases {
            for punch in Punch.allCases {
                for distance in [0.65, 0.85, 1.05] {
                    for defense in ["none", "guard", "left", "right"] {
                        outcomes.append(try run(punch: punch, style: style, distance: distance, defense: defense))
                    }
                }
            }
        }
        try attach(outcomes, name: "recovery-combat-outcomes")
        for (name, punch, distance, defense, incoming) in [
            ("hit", Punch.leftHook, 0.65, "none", false),
            ("block", .leftHook, 0.65, "guard", false),
            ("miss", .leftHook, 1.10, "none", false),
            ("receive-head", .cross, 0.65, "none", true),
            ("receive-body", .leftBody, 0.65, "none", true),
            ("receive-block", .cross, 0.65, "guard", true),
        ] {
            let result = try run(punch: punch, style: .standard, distance: distance,
                defense: defense, incoming: incoming, capture: name)
            let expected = name == "miss" ? "miss"
                : (defense == "guard" ? ":true" : ":false")
            XCTAssertTrue(try XCTUnwrap(result["result"]).hasSuffix(expected), "\(name)/\(result)")
        }
    }
}
