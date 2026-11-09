import SceneKit
import XCTest
@testable import RIVAL

enum DefensivePunchEntry: String, CaseIterable {
    case standing, duck, weave
}

@MainActor
final class DefensivePunchFixture {
    let engine = CombatEngine(persistHabits: false, randomSeed: 11)
    let presentation = CombatPresentation()
    private(set) var events: [CombatEvent] = []
    private(set) var elapsed = 0.0
    private let renders: Bool
    lazy var scene = Arena3DScene(engine: engine, presentation: presentation)

    init(punch: Punch, style: FightStyle, distanceFraction: Double, renders: Bool = false) {
        self.renders = renders
        engine.startSession()
        engine.player.style = style
        let spec = CombatData.attacks[punch]!
        let range = spec.range * engine.player.reachMultiplier(for: punch)
            + CombatData.punchReachExtension + CombatData.fighterContactRadius / CombatData.sceneScale
        let distance = range * distanceFraction
        engine.player.x = 295 - distance / 2
        engine.enemy.x = 295 + distance / 2
        engine.player.facingX = 1
        engine.player.facingY = 0
        engine.enemy.facingX = -1
        engine.enemy.facingY = 0
        engine.enemy.stagger = 1_000
        engine.onCombatEvent = { [weak self] event in
            self?.events.append(event)
            self?.presentation.receive(event)
        }
    }

    func advance(_ dt: Double) {
        elapsed += dt
        if renders {
            scene.update(at: 1 + elapsed)
        } else {
            presentation.advance(deltaTime: dt)
            engine.update(deltaTime: dt)
        }
    }

    func enter(_ entry: DefensivePunchEntry, punch: Punch) {
        let left = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
        switch entry {
        case .standing: break
        case .duck:
            let body = CombatData.attacks[punch]?.family == .body
            engine.setDuck(left == body ? -1 : 1, active: true)
        case .weave:
            XCTAssertTrue(engine.weave(direction: left ? -1 : 1))
            XCTAssertTrue(engine.requestWeaveHook(base: left ? .jab : .cross))
        }
    }

    func trigger(_ punch: Punch, entry: DefensivePunchEntry) {
        if entry != .weave { XCTAssertTrue(engine.startAttack(engine.player, punch: punch)) }
    }

    var result: String {
        for event in events {
            if case let .impact(impact) = event { return "hit:\(impact.damage):\(impact.guarded)" }
            if case .dodge = event { return "dodged" }
            if case .whiff = event { return "miss" }
        }
        return "unresolved"
    }
}

@MainActor
final class DefensivePunchMotionTests: XCTestCase {
    func testLoadedHeadPunchRisesBeforeGloveDeliveryAndKeepsBodyShotsLow() throws {
        for style in FightStyle.allCases {
            for direction in [Float(-1), 1] {
                var base = FightPose.neutral(stride: 0, style: style, stanceWidth: style.stanceWidth,
                    leanBias: style.leanBias, pitchBias: style.pitchBias)
                base.applyDuck(direction: direction, style: style)
                for punch in [Punch.leftHook, .rightHook, .leftUppercut, .rightUppercut] {
                    let spec = try XCTUnwrap(CombatData.attacks[punch])
                    let driveTime = spec.deliveryStart + (spec.activeStart - spec.deliveryStart) * 0.82
                    let motion = PunchMotion.sample(punch, progress: Float(driveTime / spec.duration))
                    XCTAssertEqual(motion.defensiveRise, 1, accuracy: 0.00001)
                    XCTAssertLessThan(motion.reach, 0.95)
                    var pose = base
                    pose.applyAttack(punch, progress: Float(spec.activeStart / spec.duration))
                    let rise = base.bodyDrop - pose.bodyDrop
                    XCTAssertGreaterThanOrEqual(rise, 0.27)
                    XCTAssertLessThanOrEqual(rise, 0.30001)
                    XCTAssertGreaterThanOrEqual(pose.bodyDrop, 0.09999)
                    XCTAssertEqual(pose.defensiveCrouch, base.defensiveCrouch - rise, accuracy: 0.00001)
                    XCTAssertGreaterThan(pose.leftHip.y - base.leftHip.y, 0.19)
                    XCTAssertGreaterThan(pose.leftShoulder.y - base.leftShoulder.y, 0.27)
                    XCTAssertGreaterThan(pose.headFacingPosition.y - base.headFacingPosition.y, 0.25)
                    XCTAssertGreaterThan(pose.torsoPitch - base.torsoPitch, 0.10)
                    XCTAssertEqual(pose.leftFoot, base.leftFoot)
                    XCTAssertEqual(pose.rightFoot, base.rightFoot)
                    XCTAssertEqual(pose.rootY, base.rootY)
                    XCTAssertEqual(pose.rootZ, base.rootZ)
                }
                for punch in [Punch.leftBody, .rightBody] {
                    let spec = try XCTUnwrap(CombatData.attacks[punch])
                    var pose = base
                    pose.applyAttack(punch, progress: Float(spec.activeStart / spec.duration))
                    XCTAssertEqual(pose.bodyDrop, base.bodyDrop)
                    XCTAssertEqual(pose.defensiveCrouch, base.defensiveCrouch)
                }
            }
        }
    }

    func testDefensiveRiseHasContinuousLoadContactAndRecoveryBoundaries() throws {
        for punch in Punch.allCases {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let headPower = spec.family == .hook || spec.family == .uppercut
            for time in [0, spec.deliveryStart, spec.duration] {
                XCTAssertEqual(PunchMotion.sample(punch, progress: Float(time / spec.duration)).defensiveRise, 0)
            }
            XCTAssertEqual(PunchMotion.sample(punch, progress: Float(spec.activeStart / spec.duration)).defensiveRise,
                headPower ? 1 : 0)
            var previous: Float = 0
            for frame in 0...240 {
                let rise = PunchMotion.sample(punch, progress: Float(frame) / 240).defensiveRise
                XCTAssertTrue(rise.isFinite)
                XCTAssertGreaterThanOrEqual(rise, 0)
                XCTAssertLessThanOrEqual(rise, 1)
                XCTAssertLessThan(abs(rise - previous), 0.07)
                previous = rise
            }
        }
    }

    func testDefensiveHeadPunchEndpointsAnatomyAndOffhand() throws {
        for style in FightStyle.allCases {
            for direction in [-1, 1] {
                for weave in [false, true] {
                    var base = FightPose.neutral(stride: 0, style: style)
                    if weave {
                        base.applyWeave(.sample(direction: direction, elapsed: WeaveState.hookStart), style: style)
                    } else {
                        base.applyDuck(direction: Float(direction), style: style)
                    }
                    base.resolveArmLengths()
                    for punch in [Punch.leftHook, .rightHook, .leftUppercut, .rightUppercut] {
                        for frame in 0...60 {
                            let progress = Float(frame) / 60
                            var pose = base
                            pose.applyAttack(punch, progress: progress,
                                contactTarget: SIMD3<Float>(0.10, 2.20, 0.8))
                            if frame == 0 || frame == 60 {
                                XCTAssertEqual(pose.bodyDrop, base.bodyDrop)
                                XCTAssertEqual(pose.defensiveCrouch, base.defensiveCrouch)
                                XCTAssertEqual(pose.torsoPitch, base.torsoPitch)
                                XCTAssertEqual(pose.leftGlove, base.leftGlove)
                                XCTAssertEqual(pose.rightGlove, base.rightGlove)
                            }
                            XCTAssertEqual(pose.leftFoot, base.leftFoot)
                            XCTAssertEqual(pose.rightFoot, base.rightFoot)
                            let head = pose.headFacingPosition
                            let left = punch == .leftHook || punch == .leftUppercut
                            let offhand = pose.facingPoint(left ? pose.rightGlove : pose.leftGlove)
                            XCTAssertLessThan(abs(head.y - offhand.y), 0.48)
                            pose.resolveArmLengths()
                            for (shoulder, elbow, glove) in [
                                (pose.leftShoulder, pose.leftElbow, pose.leftGlove),
                                (pose.rightShoulder, pose.rightElbow, pose.rightGlove)
                            ] {
                                XCTAssertEqual(simd_distance(shoulder, elbow), 0.40, accuracy: 0.00001)
                                XCTAssertEqual(simd_distance(elbow, glove), 0.58, accuracy: 0.00001)
                            }
                            let root = FighterPoseRoot(pose: pose, reaction: FighterImpactMotion())
                            let contacts = pose.resolveContactSupport(rootPosition: root.position, rootRotation: root.rotation)
                            let anatomy = StraightPunchAnatomy(pose: base)
                            let pivot = SIMD3<Float>(0, 0.86, 0)
                            let hips = simd_quatf(angle: pose.hipYaw, axis: SIMD3<Float>(0, 1, 0))
                            for (hip, knee, foot, limb) in [
                                (pose.leftHip, pose.leftKnee, contacts.left, anatomy.leftLeg),
                                (pose.rightHip, pose.rightKnee, contacts.right, anatomy.rightLeg)
                            ] {
                                XCTAssertEqual(simd_distance(hips.act(hip - pivot) + pivot, knee),
                                    limb.upper, accuracy: 0.0001)
                                XCTAssertEqual(simd_distance(knee, foot + SIMD3<Float>(0, 0.16, 0)),
                                    limb.lower, accuracy: 0.0001)
                            }
                        }
                    }
                }
            }
        }
    }

    func testWeaveHookRenderingTracksSharedHeadGeometryThroughRecovery() throws {
        for style in FightStyle.allCases {
            for punch in [Punch.leftHook, .rightHook] {
                let fixture = DefensivePunchFixture(punch: punch, style: style, distanceFraction: 1.8, renders: true)
                let head = try XCTUnwrap(fixture.scene.rootNode.childNode(withName: "playerHead", recursively: true))
                fixture.enter(.weave, punch: punch)
                for _ in 0..<72 {
                    fixture.advance(1.0 / 60)
                    // The launch frame may still be completing a planted weave step.
                    guard fixture.engine.player.attack != nil,
                          fixture.engine.player.actionTime >= CombatData.attacks[punch]!.activeStart else { continue }
                    let expected = PunchContactGeometry.target(fixture.engine.player, zone: .head)
                    XCTAssertEqual(head.simdWorldPosition.y, expected.y + 0.13, accuracy: 0.025,
                        "\(style)/\(punch)/\(fixture.engine.player.actionTime)")
                }
                XCTAssertNil(fixture.engine.player.attack)
                XCTAssertFalse(fixture.engine.player.weave.isActive)
                XCTAssertEqual(fixture.result, "miss")
            }
        }
    }

    func testWeaveHookLaunchCostAndFreeGymRemainUnchanged() throws {
        for direction in [-1, 1] {
            let punch: Punch = direction < 0 ? .leftHook : .rightHook
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let fixture = DefensivePunchFixture(punch: punch, style: .standard, distanceFraction: 0.85)
            let practice = PracticeEngine()
            XCTAssertTrue(practice.weave(direction: direction))
            XCTAssertTrue(practice.requestWeaveHook(base: direction < 0 ? .jab : .cross))
            fixture.enter(.weave, punch: punch)
            XCTAssertEqual(fixture.engine.player.stamina, 91)
            XCTAssertEqual(practice.player.stamina, 100)
            for _ in 0..<27 {
                fixture.advance(1.0 / 120)
                practice.update(deltaTime: 1.0 / 120)
                XCTAssertNil(fixture.engine.player.attack)
                XCTAssertNil(practice.player.attack)
            }
            let before = fixture.engine.player.stamina
            fixture.advance(1.0 / 120)
            practice.update(deltaTime: 1.0 / 120)
            XCTAssertEqual(fixture.engine.player.attack, punch)
            XCTAssertEqual(practice.player.attack, punch)
            XCTAssertEqual(fixture.engine.player.actionTime, 0)
            XCTAssertEqual(practice.player.actionTime, 0)
            XCTAssertEqual(fixture.engine.player.stamina,
                before - spec.staminaCost * fixture.engine.player.style.punchStaminaMultiplier, accuracy: 0.001)
            XCTAssertEqual(practice.player.stamina, 100)
            for _ in 0..<120 {
                fixture.advance(1.0 / 120)
                practice.update(deltaTime: 1.0 / 120)
            }
            XCTAssertEqual(fixture.events.filter { if case .impact = $0 { return true }; return false }.count, 1)
            XCTAssertEqual(fixture.engine.enemy.hp, 100 - spec.damage)
            XCTAssertNil(fixture.engine.player.attack)
            XCTAssertEqual(practice.player.stamina, 100)
        }
    }

    func testAttackingDoesNotKeepDuckOrWeaveEvasion() throws {
        let spec = try XCTUnwrap(CombatData.attacks[.jab])
        for weave in [false, true] {
            for attacks in [false, true] {
                let punch: Punch = weave ? .rightHook : .leftHook
                let fixture = DefensivePunchFixture(punch: punch, style: .standard, distanceFraction: 0.65)
                if weave {
                    XCTAssertTrue(fixture.engine.weave(direction: 1))
                    if attacks { XCTAssertTrue(fixture.engine.requestWeaveHook(base: .cross)) }
                } else {
                    fixture.enter(.duck, punch: punch)
                }
                for _ in 0..<28 { fixture.advance(1.0 / 120) }
                if attacks, !weave { fixture.trigger(punch, entry: .duck) }
                fixture.engine.enemy.stagger = 0
                XCTAssertTrue(fixture.engine.startAttack(fixture.engine.enemy, punch: .jab))
                var frame = PunchContactGeometry.contactFrame(fixture.engine.enemy, defender: fixture.engine.player,
                    punch: .jab, spec: spec, time: spec.activeStart)
                // Isolate defense eligibility from a legitimate miss against a still-low head.
                frame.glove = frame.standingTarget
                var next = PunchContactGeometry.contactFrame(fixture.engine.enemy, defender: fixture.engine.player,
                    punch: .jab, spec: spec, time: spec.activeStart + 1.0 / 120)
                next.glove = next.standingTarget
                let evasion = PunchContactGeometry.sweptContact(fixture.engine.enemy, punch: .jab,
                    from: frame, to: next, defended: false, defense: weave ? .weave : .duck)
                if attacks {
                    XCTAssertNotNil(fixture.engine.player.attack)
                    XCTAssertNil(evasion)
                } else {
                    XCTAssertNil(fixture.engine.player.attack)
                    XCTAssertNotNil(evasion)
                }
            }
        }
    }

    func testCaptureDefensivePunchSequenceAndCombatOutcomes() throws {
        var outcomes: [[String: String]] = []
        for style in FightStyle.allCases {
            for punch in Punch.allCases {
                for entry in DefensivePunchEntry.allCases {
                    if entry == .weave, CombatData.attacks[punch]?.family != .hook { continue }
                    for fraction in [0.65, 0.85, 1.06] {
                        let fixture = DefensivePunchFixture(punch: punch, style: style, distanceFraction: fraction)
                        var minimumStamina = 100.0
                        for frame in 0..<180 {
                            if frame == 30 { fixture.enter(entry, punch: punch) }
                            if frame == 54 { fixture.trigger(punch, entry: entry) }
                            fixture.advance(1.0 / 120)
                            minimumStamina = min(minimumStamina, fixture.engine.player.stamina)
                        }
                        XCTAssertNotEqual(fixture.result, "unresolved")
                        if fraction > 1 { XCTAssertEqual(fixture.result, "miss") }
                        outcomes.append(["style": style.rawValue, "punch": punch.rawValue, "entry": entry.rawValue,
                            "distance": "\(fraction)", "result": fixture.result,
                            "hp": "\(fixture.engine.enemy.hp)",
                            "minimumStamina": String(format: "%.6f", minimumStamina)])
                    }
                }
            }
        }
        let captures: [(String, Punch, DefensivePunchEntry)] = [
            ("duck-left-hook", .leftHook, .duck),
            ("weave-right-hook", .rightHook, .weave),
            ("duck-left-uppercut", .leftUppercut, .duck)
        ]
        for (name, punch, entry) in captures {
            let fixture = DefensivePunchFixture(punch: punch, style: .standard, distanceFraction: 0.85, renders: true)
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = fixture.scene
            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 42
            camera.simdPosition = SIMD3<Float>(0.15, 2.0, 4.7)
            camera.look(at: SCNVector3(0, 1.35, 0))
            fixture.scene.rootNode.addChildNode(camera)
            renderer.pointOfView = camera
            for frame in 0..<90 {
                if frame == 15 { fixture.enter(entry, punch: punch) }
                if frame == 27 { fixture.trigger(punch, entry: entry) }
                if frame == 66 { fixture.engine.setDuck(0, active: false) }
                fixture.advance(1.0 / 60)
                if frame.isMultiple(of: 3) {
                    let image = renderer.snapshot(atTime: fixture.elapsed, with: CGSize(width: 960, height: 540),
                        antialiasingMode: .multisampling4X)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = String(format: "defensive-%@-%03d", name, frame)
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(outcomes), uniformTypeIdentifier: "public.json")
        attachment.name = "defensive-punch-outcomes"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
