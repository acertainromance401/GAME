import XCTest
import SceneKit
@testable import RIVAL

@MainActor
final class MotionPolishTests: XCTestCase {
    func testLiveJabDeliveryIsDirectWithoutMovingTheContactClock() throws {
        let spec = try XCTUnwrap(CombatData.attacks[.jab])
        let halfway = Float((spec.deliveryStart + spec.activeStart) * 0.5 / spec.duration)
        XCTAssertEqual(PunchMotion.sample(.jab, progress: halfway).reach, 0.375, accuracy: 0.00001)
        for punch in [Punch.jab, .cross] {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let contact = Float(spec.activeStart / spec.duration)
            XCTAssertEqual(PunchMotion.sample(punch, progress: contact).reach, 1, accuracy: 0.00001)
            XCTAssertEqual(PunchMotion.sample(punch, progress: 0), PunchMotion())
            XCTAssertEqual(PunchMotion.sample(punch, progress: 1), PunchMotion())
        }
        XCTAssertEqual(CombatData.attacks[.jab]?.activeStart, 0.08)
        XCTAssertEqual(CombatData.attacks[.cross]?.activeStart, 0.17)
    }

    func testLiveCrossRearFootDrivesBeforeHipAndChest() throws {
        let spec = try XCTUnwrap(CombatData.attacks[.cross])
        let motion = PunchMotion.sample(.cross, progress: Float(0.05 / spec.duration))
        XCTAssertGreaterThan(motion.footDrive, 0.90)
        XCTAssertGreaterThan(motion.hipDrive, 0.25)
        XCTAssertGreaterThan(motion.footDrive, motion.hipDrive)
        XCTAssertGreaterThan(motion.hipDrive, motion.torsoDrive)
        XCTAssertEqual(motion.reach, 0)
    }

    func testLiveStraightDeliveryFollowsFacingSpaceInsteadOfChestRotation() throws {
        for style in FightStyle.allCases {
            for punch in [Punch.jab, .cross] {
                let spec = try XCTUnwrap(CombatData.attacks[punch])
                let jab = punch == .jab
                let side: Float = jab ? 1 : -1
                var base = FightPose.neutral(stride: 0, style: style)
                base.applyGuard(style: style)
                base.resolveArmLengths()
                let guardPosition = base.facingPoint(jab ? base.leftGlove : base.rightGlove)
                let target = SIMD3<Float>(side * 0.10, 2.08, 1.0)
                for fraction in [0.25, 0.50, 0.75] {
                    let progress = Float((spec.deliveryStart + (spec.activeStart - spec.deliveryStart) * fraction) / spec.duration)
                    let motion = PunchMotion.sample(punch, progress: progress)
                    var pose = base
                    pose.applyAttack(punch, progress: progress, contactTarget: target)
                    let shoulder = jab ? pose.leftShoulder : pose.rightShoulder
                    let end = StraightPunchAnatomy.restingArm.solve(root: shoulder,
                        target: pose.torsoPoint(target), pole: jab ? base.leftElbow : base.rightElbow,
                        fallback: SIMD3<Float>(side * 0.25, -1, 0)).end
                    let chamber = guardPosition
                        + SIMD3<Float>(jab ? 0.012 : -0.008, jab ? -0.012 : -0.008, jab ? -0.018 : -0.025) * motion.load
                    let expected = chamber + (pose.facingPoint(end) - chamber) * motion.reach
                    let actual = pose.facingPoint(jab ? pose.leftGlove : pose.rightGlove)
                    XCTAssertLessThan(simd_distance(actual, expected), 0.00001)
                }
            }
        }
    }

    func testLiveStraightRecoveryReturnsUpAndInWithExistingReachOffset() throws {
        for punch in [Punch.jab, .cross] {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let progress = Float((spec.activeStart + spec.recoveryEnd) * 0.5 / spec.duration)
            for landed in [true, false] {
                let motion = PunchRecoveryMotion.sample(punch, progress: progress, landed: landed, reducedMotion: false)
                XCTAssertEqual(motion.handOffset.y, 0.075, accuracy: 0.00001)
                XCTAssertEqual(motion.handOffset.x, punch == .jab ? -0.035 : 0.035, accuracy: 0.00001)
                XCTAssertEqual(motion.handOffset.z, landed ? -0.065 : 0.040, accuracy: 0.00001)
                let reduced = PunchRecoveryMotion.sample(punch, progress: progress, landed: landed, reducedMotion: true)
                XCTAssertEqual(reduced.handOffset.y, motion.handOffset.y * 0.30, accuracy: 0.00001)
                for endpoint in [Float(spec.activeStart / spec.duration), Float(spec.recoveryEnd / spec.duration)] {
                    XCTAssertEqual(PunchRecoveryMotion.sample(punch, progress: endpoint,
                        landed: landed, reducedMotion: false).handOffset, .zero)
                }
            }
        }
    }

    func testLiveStraightPunchKeepsGuardEndpointsAndFixedLimbs() {
        for style in FightStyle.allCases {
            for duck in [Float(-1), 0, 1] {
                var base = FightPose.neutral(stride: 0, style: style)
                base.applyGuard(style: style)
                base.applyDuck(direction: duck, style: style)
                base.resolveArmLengths()
                for punch in [Punch.jab, .cross] {
                    for frame in 0...60 {
                        var pose = base
                        let progress = Float(frame) / 60
                        pose.applyAttack(punch, progress: progress, contactTarget: SIMD3<Float>(0.10, 2.08, 1.0))
                        if frame == 0 || frame == 60 {
                            XCTAssertEqual(pose.leftGlove, base.leftGlove)
                            XCTAssertEqual(pose.rightGlove, base.rightGlove)
                            XCTAssertEqual(pose.leftFoot, base.leftFoot)
                            XCTAssertEqual(pose.rightFoot, base.rightFoot)
                            XCTAssertEqual(pose.hipYaw, base.hipYaw)
                            XCTAssertEqual(pose.torsoYaw, base.torsoYaw)
                        }
                        pose.resolveContactSupport(rootPosition: .zero, rootRotation: simd_quatf())
                        for (shoulder, elbow, glove) in [(pose.leftShoulder, pose.leftElbow, pose.leftGlove),
                                                       (pose.rightShoulder, pose.rightElbow, pose.rightGlove)] {
                            XCTAssertEqual(simd_distance(shoulder, elbow), 0.40, accuracy: 0.0001)
                            XCTAssertEqual(simd_distance(elbow, glove), 0.58, accuracy: 0.0001)
                        }
                        XCTAssertEqual(pose.rootX, base.rootX)
                        XCTAssertEqual(pose.rootY, base.rootY)
                        XCTAssertEqual(pose.rootZ, base.rootZ)
                    }
                }
            }
        }
    }

    #if DEBUG
    func testCaptureLiveStraightPunchSequence() throws {
        let model = MotionLabModel()
        var outcomes: [[String: String]] = []
        for punch in MotionLabPunch.allCases {
            for distance in MotionLabDistance.allCases {
                for defense in MotionLabDefense.allCases {
                    model.configure(punch: punch, distance: distance, defense: defense)
                    model.seek(to: model.endFrame)
                    outcomes.append(["punch": punch.rawValue, "distance": distance.rawValue,
                        "defense": defense.rawValue, "result": model.result,
                        "hp": "\(model.run.engine.enemy.hp)",
                        "stamina": String(format: "%.6f", model.run.engine.player.stamina)])
                }
            }
            model.configure(punch: punch, distance: .middle, defense: .open)
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = model.run.scene
            let camera = model.run.inspectionCamera
            camera.simdPosition = SIMD3<Float>(0.15, 2.0, 4.7)
            camera.look(at: SCNVector3(0, 1.35, 0))
            renderer.pointOfView = camera
            for frame in stride(from: 0, through: model.endFrame, by: 2) {
                model.seek(to: frame)
                let image = renderer.snapshot(atTime: model.time, with: CGSize(width: 960, height: 540),
                    antialiasingMode: .multisampling4X)
                XCTAssertEqual(image.size, CGSize(width: 960, height: 540))
                let attachment = XCTAttachment(image: image)
                attachment.name = String(format: "motion-live-%@-%03d", punch.rawValue, frame)
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(outcomes), uniformTypeIdentifier: "public.json")
        attachment.name = "motion-live-outcomes"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMotionLabSeeksReproduceProductionStateAndRig() throws {
        let model = MotionLabModel()
        model.seek(to: model.contactFrame + 4)
        let frame = model.frame
        let hp = model.run.engine.enemy.hp
        let events = model.run.events
        let foot = try XCTUnwrap(model.run.scene.rootNode.childNode(withName: "playerLeftFoot", recursively: true))
        let position = foot.simdWorldPosition
        model.seek(to: 0)
        model.seek(to: frame)
        let replayedFoot = try XCTUnwrap(model.run.scene.rootNode.childNode(withName: "playerLeftFoot", recursively: true))
        XCTAssertEqual(model.run.engine.enemy.hp, hp)
        XCTAssertEqual(model.run.events, events)
        XCTAssertLessThan(simd_distance(replayedFoot.simdWorldPosition, position), 0.00001)
        XCTAssertNil(model.failure)
    }

    func testMotionLabPlaybackUsesFixedFramesAndPauses() {
        let model = MotionLabModel()
        model.speed = .quarter
        model.advance(realDeltaTime: 0.1)
        XCTAssertEqual(model.frame, 0)
        model.togglePlayback()
        for _ in 0..<4 { model.advance(realDeltaTime: 0.1) }
        XCTAssertEqual(model.frame, 6)
        model.pause()
        let remaining = model.run.engine.roundTime
        model.advance(realDeltaTime: 0.1)
        XCTAssertEqual(model.frame, 6)
        XCTAssertEqual(model.run.engine.roundTime, remaining)
        model.seek(to: -10)
        XCTAssertEqual(model.frame, 0)
        model.seek(to: 10_000)
        XCTAssertEqual(model.frame, model.endFrame)
    }

    func testMotionLabMatrixUsesRealEventsAndReturnsToGuardWithoutSaving() {
        func savedProgress() -> NSDictionary {
            NSDictionary(dictionary: UserDefaults.standard.dictionaryRepresentation().filter {
                $0.key.hasPrefix("pixelBoxing") || $0.key.hasPrefix("rival.story")
            })
        }
        let before = savedProgress()
        let model = MotionLabModel()
        for punch in MotionLabPunch.allCases {
            for distance in MotionLabDistance.allCases {
                for defense in MotionLabDefense.allCases {
                    model.configure(punch: punch, distance: distance, defense: defense)
                    model.seek(to: model.endFrame)
                    XCTAssertNil(model.failure)
                    XCTAssertNil(model.run.engine.enemy.attack)
                    XCTAssertNil(model.run.engine.player.attack)
                    XCTAssertTrue(model.run.engine.player.guarding)
                    XCTAssertGreaterThan(model.run.engine.player.guardAmount, 0.99)
                    XCTAssertTrue(model.run.events.contains(.attackStarted(fighter: .player)))
                    XCTAssertFalse(model.run.events.contains(.attackStarted(fighter: .rival)))
                    XCTAssertNotEqual(model.result, "PENDING")
                    XCTAssertTrue(model.run.targetMarker.simdPosition.x.isFinite)
                    if distance == .middle, defense == .open {
                        XCTAssertLessThan(model.run.engine.enemy.hp, model.run.engine.enemy.maximumHealth)
                    }
                    if distance == .middle, defense == .guardUp {
                        XCTAssertTrue(model.run.events.contains { event in
                            if case let .impact(impact) = event { return impact.guarded }
                            return false
                        })
                    }
                }
            }
        }
        XCTAssertEqual(savedProgress(), before)
    }

    func testMotionLabLoopAndSinglePlaybackBoundaries() {
        let model = MotionLabModel()
        model.loops = false
        model.seek(to: model.endFrame - 1)
        model.togglePlayback()
        model.advance(realDeltaTime: 0.1)
        XCTAssertEqual(model.frame, model.endFrame)
        XCTAssertFalse(model.isPlaying)
        model.loops = true
        model.togglePlayback()
        XCTAssertEqual(model.frame, 0)
        model.seek(to: model.endFrame - 1)
        model.togglePlayback()
        model.advance(realDeltaTime: 0.1)
        XCTAssertEqual(model.frame, 5)
        XCTAssertTrue(model.isPlaying)
        XCTAssertNil(model.failure)
    }
    #endif

    func testProductionMotionRegressionMatrix() {
        let result = MotionRegressionChecks.run()
        XCTAssertTrue(result.failures.isEmpty, result.failures.joined(separator: "\n"))
        XCTAssertGreaterThan(result.checks, 10_000)
    }

    func testSceneMotionNeverMutatesAttackOrDefenseTimersWhilePaused() throws {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.pause()
        let engine = controller.engine
        engine.player.attack = .rightHook
        engine.player.actionTime = 0.18
        engine.player.duckDirection = 1
        engine.player.hitReaction = 0.20
        let x = engine.player.x
        let y = engine.player.y
        let hp = engine.player.hp
        let scene = controller.scene3D
        scene.update(at: 1)
        let foot = try XCTUnwrap(scene.rootNode.childNode(withName: "playerLeftFoot", recursively: true))
        let position = foot.simdWorldPosition
        for i in 1...10 { scene.update(at: 1 + Double(i) / 60) }
        XCTAssertEqual(engine.player.x, x)
        XCTAssertEqual(engine.player.y, y)
        XCTAssertEqual(engine.player.hp, hp)
        XCTAssertEqual(engine.player.actionTime, 0.18)
        XCTAssertEqual(engine.player.hitReaction, 0.20)
        XCTAssertEqual(engine.player.duckDirection, 1)
        XCTAssertLessThan(simd_distance(foot.simdWorldPosition, position), 0.0001)
    }
}