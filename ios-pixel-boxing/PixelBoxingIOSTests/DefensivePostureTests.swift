import SceneKit
import XCTest
@testable import RIVAL

private enum DuckTransition: String, CaseIterable {
    case enterLeft, enterRight, leftToRight, rightToLeft, releaseLeft, releaseRight

    var initial: Int {
        switch self {
        case .enterLeft, .enterRight: 0
        case .leftToRight, .releaseLeft: -1
        case .rightToLeft, .releaseRight: 1
        }
    }

    var requested: Int {
        switch self {
        case .enterLeft, .rightToLeft: -1
        case .enterRight, .leftToRight: 1
        case .releaseLeft, .releaseRight: 0
        }
    }
}

@MainActor
final class DefensivePostureTests: XCTestCase {
    func testDirectionAndEvadeClockRemainLinearAtEveryFrameRate() {
        XCTAssertEqual(DuckMotion.entryDuration, 0.09)
        XCTAssertEqual(DuckMotion.releaseDuration, 0.12)
        XCTAssertEqual(DuckMotion.minimumEvadeAmount, 0.70)
        for fps in [30.0, 60, 120] {
            var motion = DuckMotion()
            var reference: Float = 0
            for (requested, seconds) in [(1, 0.09), (-1, 0.18), (0, 0.12), (-1, 0.045), (1, 0.09), (0, 0.12)] {
                var remaining = seconds
                while remaining > 1e-10 {
                    let dt = min(1 / fps, remaining)
                    let target = Float(requested)
                    let step = Float(dt / (requested == 0 ? 0.12 : 0.09))
                    reference += min(step, max(-step, target - reference))
                    motion.advance(direction: requested, deltaTime: dt)
                    XCTAssertEqual(motion.direction, reference, accuracy: 0.000001)
                    for punch in Punch.allCases {
                        let eligible = CombatData.requiredDuck[punch].map { reference * Float($0) >= 0.70 } ?? false
                        XCTAssertEqual(motion.evades(punch), eligible)
                    }
                    remaining -= dt
                }
            }
        }
    }

    func testReversalStaysCompactWithoutGrantingNeutralDirectionEvasion() {
        for direction in [-1, 1] {
            var motion = DuckMotion()
            motion.advance(direction: direction, deltaTime: 0.09)
            XCTAssertEqual(motion.postureAmount, 1)
            motion.advance(direction: -direction, deltaTime: 0.09)
            XCTAssertEqual(motion.direction, 0, accuracy: 0.000001)
            XCTAssertGreaterThanOrEqual(motion.postureAmount, 0.24)
            XCTAssertLessThanOrEqual(motion.postureAmount, 0.26)
            var pose = FightPose.neutral(stride: 0)
            pose.applyDuck(direction: motion.direction, postureAmount: motion.postureAmount)
            XCTAssertEqual(pose.bodyDrop, 0.10, accuracy: 0.000001)
            for punch in Punch.allCases { XCTAssertFalse(motion.evades(punch)) }
            motion.advance(direction: 0, deltaTime: 0.12)
            XCTAssertEqual(motion, DuckMotion())
            motion.advance(direction: direction, deltaTime: 0.02)
            let shallow = motion.postureAmount
            motion.advance(direction: -direction, deltaTime: 0.02)
            XCTAssertLessThan(motion.postureAmount, shallow)
        }
    }

    func testLegsLeadWaistAndGuardWithUnchangedHeightAndFullPosture() {
        var motion = DuckMotion()
        motion.advance(direction: 1, deltaTime: 0.018)
        XCTAssertEqual(motion.postureAmount, 0.20, accuracy: 0.000001)
        let ready = FightPose.neutral(stride: 0)
        var early = ready
        early.applyDuck(direction: motion.direction, postureAmount: motion.postureAmount)
        XCTAssertEqual(early.bodyDrop, 0.08, accuracy: 0.000001)
        let upperBody = DuckMotion.upperBodyAmount(0.20)
        XCTAssertEqual(early.torsoPitch,
            ready.torsoPitch - (0.18 + max(0, ready.torsoPitch)) * upperBody, accuracy: 0.000001)
        motion.advance(direction: 1, deltaTime: 0.072)
        XCTAssertEqual(motion.postureAmount, 1)
        motion.advance(direction: 0, deltaTime: 0.001)
        XCTAssertEqual(motion.postureAmount, Float(1 - 0.001 / 0.12), accuracy: 0.000001)
        motion.advance(direction: 0, deltaTime: 0.119)
        XCTAssertEqual(motion.postureAmount, 0)
        for style in FightStyle.allCases {
            for direction in [Float(-1), 1] {
                let ready = FightPose.neutral(stride: 0, style: style)
                var pose = ready
                pose.applyDuck(direction: direction, style: style)
                XCTAssertEqual(pose.bodyDrop, 0.40, accuracy: 0.000001)
                XCTAssertEqual(pose.leftHip.y, ready.leftHip.y - 0.288, accuracy: 0.000001)
                XCTAssertEqual(pose.torsoYaw, ready.torsoYaw - 0.276 * direction, accuracy: 0.000001)
                XCTAssertEqual(pose.hipYaw, ready.hipYaw - 0.108 * direction, accuracy: 0.000001)
                XCTAssertEqual(pose.rootX, -0.055 * direction, accuracy: 0.000001)
            }
        }
    }

    func testPostureKeepsFixedAnatomySupportAndChinGuard() {
        for style in FightStyle.allCases {
            var motion = DuckMotion()
            for (requested, frames) in [(-1, 18), (1, 24), (-1, 24), (0, 16)] {
                for _ in 0..<frames {
                    motion.advance(direction: requested, deltaTime: 1.0 / 120)
                    let base = FightPose.neutral(stride: 0, style: style, stanceWidth: style.stanceWidth,
                        leanBias: style.leanBias, pitchBias: style.pitchBias)
                    var pose = base
                    pose.applyDuck(direction: motion.direction, postureAmount: motion.postureAmount, style: style)
                    XCTAssertGreaterThanOrEqual(pose.bodyDrop, 0)
                    XCTAssertLessThanOrEqual(pose.bodyDrop, 0.400001)
                    XCTAssertEqual(pose.leftFoot, base.leftFoot)
                    XCTAssertEqual(pose.rightFoot, base.rightFoot)
                    XCTAssertEqual(pose.rootY, base.rootY)
                    XCTAssertEqual(pose.rootZ, base.rootZ)
                    if motion.postureAmount > 0.5 {
                        for glove in [pose.leftGlove, pose.rightGlove] {
                            XCTAssertLessThan(abs(pose.facingPoint(glove).y - pose.headFacingPosition.y), 0.65)
                        }
                    }
                    let root = FighterPoseRoot(pose: pose, reaction: FighterImpactMotion())
                    let contacts = pose.resolveContactSupport(rootPosition: root.position, rootRotation: root.rotation)
                    for (shoulder, elbow, glove) in [
                        (pose.leftShoulder, pose.leftElbow, pose.leftGlove),
                        (pose.rightShoulder, pose.rightElbow, pose.rightGlove)
                    ] {
                        XCTAssertEqual(simd_distance(shoulder, elbow), 0.40, accuracy: 0.00001)
                        XCTAssertEqual(simd_distance(elbow, glove), 0.58, accuracy: 0.00001)
                    }
                    let anatomy = StraightPunchAnatomy(pose: base)
                    let pivot = SIMD3<Float>(0, 0.86, 0)
                    let hips = simd_quatf(angle: pose.hipYaw, axis: SIMD3<Float>(0, 1, 0))
                    for (hip, knee, foot, limb) in [
                        (pose.leftHip, pose.leftKnee, contacts.left, anatomy.leftLeg),
                        (pose.rightHip, pose.rightKnee, contacts.right, anatomy.rightLeg)
                    ] {
                        XCTAssertEqual(simd_distance(hips.act(hip - pivot) + pivot, knee), limb.upper, accuracy: 0.0001)
                        XCTAssertEqual(simd_distance(knee, foot + SIMD3<Float>(0, 0.16, 0)), limb.lower, accuracy: 0.0001)
                    }
                }
            }
        }
    }

    func testRendererAndContactShareReversalAndReleaseHeight() throws {
        for style in FightStyle.allCases {
            let fixture = DefensivePunchFixture(punch: .jab, style: style, distanceFraction: 0.85, renders: true)
            let head = try XCTUnwrap(fixture.scene.rootNode.childNode(withName: "playerHead", recursively: true))
            for frame in 0..<84 {
                if frame == 12 { fixture.engine.setDuck(-1, active: true) }
                if frame == 30 { fixture.engine.setDuck(1, active: true) }
                if frame == 48 { fixture.engine.setDuck(0, active: false) }
                fixture.advance(1.0 / 60)
                XCTAssertEqual(head.simdWorldPosition.y,
                    PunchContactGeometry.target(fixture.engine.player, zone: .head).y + 0.13, accuracy: 0.015,
                    "\(style)/\(frame)")
            }
        }
    }

    func testRapidChangesInvalidDeltasAndGymStayConsistent() {
        let fixture = DefensivePunchFixture(punch: .jab, style: .standard, distanceFraction: 0.85)
        let practice = PracticeEngine()
        for request in [-1, 1, 0, 1, -1, 0, -1, 1] {
            fixture.engine.setDuck(request, active: request != 0)
            practice.setDuck(request, active: request != 0)
            for _ in 0..<13 {
                fixture.advance(1.0 / 240)
                practice.update(deltaTime: 1.0 / 240)
                let motion = fixture.engine.player.duckMotion
                XCTAssertEqual(motion, practice.player.duckMotion)
                XCTAssertTrue(motion.postureAmount.isFinite)
                XCTAssertGreaterThanOrEqual(motion.postureAmount, 0)
                XCTAssertLessThanOrEqual(motion.postureAmount, 1)
            }
        }
        var motion = fixture.engine.player.duckMotion
        let before = motion
        for dt in [Double.nan, .infinity, -1, 0] {
            motion.advance(direction: 1, deltaTime: dt)
            XCTAssertEqual(motion, before)
        }
        motion.advance(direction: 0, deltaTime: 0.12)
        XCTAssertEqual(motion, DuckMotion())
    }

    func testReversalHasNoVerticalVelocityCuspAtNeutral() {
        var motion = DuckMotion()
        motion.advance(direction: 1, deltaTime: 0.09)
        var previous = motion.postureAmount
        var centerSamples = 0
        for _ in 0..<108 {
            motion.advance(direction: -1, deltaTime: 1.0 / 600)
            if abs(motion.direction) < 0.03 {
                XCTAssertLessThan(abs(motion.postureAmount - previous) * 0.40, 0.002)
                centerSamples += 1
            }
            previous = motion.postureAmount
        }
        XCTAssertGreaterThan(centerSamples, 0)
    }

    func testHeldControlReversalAndReleasingOneSideRestoreTheOther() {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.engine.enemy.stagger = 1_000
        controller.duckButton(direction: -1, active: true)
        for _ in 0..<24 { controller.engine.update(deltaTime: 1.0 / 120) }
        let leftSelection = controller.selectedPunch(base: .jab)
        controller.duckButton(direction: 1, active: true)
        XCTAssertNotEqual(controller.selectedPunch(base: .jab), leftSelection)
        for _ in 0..<12 { controller.engine.update(deltaTime: 1.0 / 120) }
        XCTAssertLessThan(abs(controller.engine.player.duckMotion.direction), 0.12)
        XCTAssertGreaterThan(controller.engine.player.duckMotion.postureAmount, 0.24)
        XCTAssertLessThan(controller.engine.player.duckMotion.postureAmount, 0.30)
        controller.duckButton(direction: 1, active: false)
        XCTAssertEqual(controller.selectedPunch(base: .jab), leftSelection)
        for _ in 0..<24 { controller.engine.update(deltaTime: 1.0 / 120) }
        XCTAssertEqual(controller.engine.player.duckMotion.direction, -1)
        XCTAssertEqual(controller.engine.player.duckMotion.postureAmount, 1)
        controller.releaseHeldControls()
        for _ in 0..<18 { controller.engine.update(deltaTime: 1.0 / 120) }
        XCTAssertEqual(controller.engine.player.duckMotion, DuckMotion())
    }

    func testDuckToWeaveDoesNotAddTravelOrLeavePostureAfterCancel() {
        for direction in [-1, 1] {
            let fixture = DefensivePunchFixture(punch: .jab, style: .standard, distanceFraction: 0.85)
            fixture.engine.setDuck(-direction, active: true)
            for _ in 0..<18 { fixture.advance(1.0 / 120) }
            let x = fixture.engine.player.x, y = fixture.engine.player.y
            XCTAssertTrue(fixture.engine.weave(direction: direction))
            for _ in 0..<72 { fixture.advance(1.0 / 120) }
            XCTAssertEqual(fixture.engine.player.x, x, accuracy: 0.000001)
            XCTAssertEqual(fixture.engine.player.y, y + Double(direction) * 12, accuracy: 0.000001)
            XCTAssertEqual(fixture.engine.player.duckMotion, DuckMotion())
            XCTAssertFalse(fixture.engine.player.weave.isActive)
            XCTAssertTrue(fixture.engine.weave(direction: -direction))
            for _ in 0..<12 { fixture.advance(1.0 / 120) }
            fixture.engine.cancelWeaveInput()
            let stopped = SIMD2(fixture.engine.player.x, fixture.engine.player.y)
            for _ in 0..<60 { fixture.advance(1.0 / 120) }
            XCTAssertEqual(SIMD2(fixture.engine.player.x, fixture.engine.player.y), stopped)
            XCTAssertEqual(fixture.engine.player.duckMotion, DuckMotion())
            XCTAssertEqual(PunchContactGeometry.stance(fixture.engine.player).defensiveCrouch, 0)
        }
    }

    func testIncomingContactsKeepTransitionHitsAndCorrectDirectionDodges() throws {
        let cases: [(Punch, DuckTransition, Double, String, Int, Int)] = [
            (.jab, .leftToRight, 0.02, "hit:6:false", 94, 0),
            (.jab, .leftToRight, 0.14, "hit:6:false", 94, 0),
            (.cross, .rightToLeft, 0.02, "hit:11:false", 89, 0),
            (.cross, .rightToLeft, 0.14, "hit:11:false", 89, 0),
            (.leftBody, .enterLeft, 0.02, "hit:9:false", 91, 0),
            (.rightBody, .releaseRight, 0.02, "hit:10:false", 90, 0),
            (.jab, .rightToLeft, 0.02, "dodged", 100, 1),
            (.cross, .leftToRight, 0.02, "dodged", 100, 1),
        ]
        for (punch, transition, offset, expected, hp, dodges) in cases {
            let result = try incomingResult(style: .standard, punch: punch, transition: transition,
                offset: offset, distance: 0.65)
            let context = "\(punch)/\(transition)/\(offset)"
            XCTAssertEqual(result["result"], expected, context)
            XCTAssertEqual(result["hp"], "\(hp)", context)
            XCTAssertEqual(result["dodges"], "\(dodges)", context)
        }
    }

    private func incomingResult(style: FightStyle, punch: Punch, transition: DuckTransition,
                                offset: Double, distance: Double) throws -> [String: String] {
        let spec = try XCTUnwrap(CombatData.attacks[punch])
        let fixture = DefensivePunchFixture(punch: punch, style: .standard, distanceFraction: distance)
        fixture.engine.player.style = style
        fixture.engine.setDuck(transition.initial, active: transition.initial != 0)
        let attackTime = 0.30 + offset - spec.activeStart
        var started = false
        var switched = false
        while fixture.elapsed < 1.2 - 1e-10 {
            if !switched, fixture.elapsed >= 0.30 - 1e-10 {
                fixture.engine.setDuck(transition.requested, active: transition.requested != 0)
                switched = true
            }
            if !started, fixture.elapsed >= attackTime - 1e-10 {
                fixture.engine.enemy.stagger = 0
                XCTAssertTrue(fixture.engine.startAttack(fixture.engine.enemy, punch: punch))
                fixture.engine.enemy.stagger = 1_000
                started = true
            }
            let boundary = min(started ? 1.2 : attackTime, switched ? 1.2 : 0.30)
            fixture.advance(min(1.0 / 120, boundary - fixture.elapsed))
        }
        XCTAssertNotEqual(fixture.result, "unresolved", "\(style)/\(punch)/\(transition)/\(offset)/\(distance)")
        return ["style": style.rawValue, "punch": punch.rawValue, "transition": transition.rawValue,
            "offset": "\(offset)", "distance": "\(distance)", "result": fixture.result,
            "hp": "\(fixture.engine.player.hp)", "dodges": "\(fixture.engine.roundPlayerDodgeCount)"]
    }

    func testCaptureDefensivePostureAndIncomingContacts() throws {
        var outcomes: [[String: String]] = []
        for style in FightStyle.allCases {
            for punch in Punch.allCases {
                for transition in DuckTransition.allCases {
                    for offset in [0.02, 0.08, 0.14, 0.20] {
                        for distance in [0.65, 0.85] {
                            outcomes.append(try incomingResult(style: style, punch: punch, transition: transition,
                                offset: offset, distance: distance))
                        }
                    }
                }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let outcomeAttachment = XCTAttachment(data: try encoder.encode(outcomes), uniformTypeIdentifier: "public.json")
        outcomeAttachment.name = "defensive-posture-incoming-outcomes"
        outcomeAttachment.lifetime = .keepAlways
        add(outcomeAttachment)

        for name in ["duck-reversal", "duck-quick-release", "duck-to-weave"] {
            let fixture = DefensivePunchFixture(punch: .jab, style: .standard, distanceFraction: 0.85, renders: true)
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = fixture.scene
            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 42
            camera.simdPosition = SIMD3<Float>(0.15, 2.0, 4.7)
            camera.look(at: SCNVector3(0, 1.35, 0))
            fixture.scene.rootNode.addChildNode(camera)
            renderer.pointOfView = camera
            var heights: [[String: Float]] = []
            let head = try XCTUnwrap(fixture.scene.rootNode.childNode(withName: "playerHead", recursively: true))
            for frame in 0..<126 {
                switch name {
                case "duck-reversal":
                    if frame == 12 { fixture.engine.setDuck(-1, active: true) }
                    if frame == 42 { fixture.engine.setDuck(1, active: true) }
                    if frame == 72 { fixture.engine.setDuck(-1, active: true) }
                    if frame == 102 { fixture.engine.setDuck(0, active: false) }
                case "duck-quick-release":
                    if frame == 12 { fixture.engine.setDuck(-1, active: true) }
                    if frame == 18 { fixture.engine.setDuck(1, active: true) }
                    if frame == 21 { fixture.engine.setDuck(0, active: false) }
                    if frame == 30 { fixture.engine.setDuck(1, active: true) }
                    if frame == 40 { fixture.engine.setDuck(-1, active: true) }
                    if frame == 45 { fixture.engine.setDuck(0, active: false) }
                default:
                    if frame == 12 { fixture.engine.setDuck(-1, active: true) }
                    if frame == 40 { XCTAssertTrue(fixture.engine.weave(direction: -1)) }
                    if frame == 80 { XCTAssertTrue(fixture.engine.weave(direction: 1)) }
                }
                fixture.advance(1.0 / 60)
                heights.append(["frame": Float(frame), "direction": fixture.engine.player.duckMotion.direction,
                    "headY": head.simdWorldPosition.y])
                if frame.isMultiple(of: 2) {
                    let image = renderer.snapshot(atTime: fixture.elapsed, with: CGSize(width: 960, height: 540),
                        antialiasingMode: .multisampling4X)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = String(format: "posture-%@-%03d", name, frame)
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            let attachment = XCTAttachment(data: try encoder.encode(heights), uniformTypeIdentifier: "public.json")
            attachment.name = "posture-\(name)-heights"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
