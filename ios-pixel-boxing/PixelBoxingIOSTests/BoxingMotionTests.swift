import SceneKit
import UIKit
import XCTest
@testable import RIVAL

@MainActor
final class BoxingMotionTests: XCTestCase {
    func testStraightExtensionPeaksAtExistingHitFrame() throws {
        for punch in [Punch.jab, .cross] {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let contact = Float(spec.activeStart / spec.duration)
            XCTAssertEqual(StraightPunchMotion.sample(punch, progress: contact).reach, 1, accuracy: 0.00001)
            XCTAssertLessThan(StraightPunchMotion.sample(punch, progress: contact - 0.05).reach, 1)
            XCTAssertLessThan(StraightPunchMotion.sample(punch, progress: contact + 0.05).reach, 1)
            XCTAssertEqual(StraightPunchMotion.sample(punch, progress: 0).reach, 0)
            XCTAssertEqual(StraightPunchMotion.sample(punch, progress: 1).reach, 0)
        }
        XCTAssertEqual(CombatData.attacks[.jab]?.activeStart, 0.08)
        XCTAssertEqual(CombatData.attacks[.cross]?.activeStart, 0.14)
    }

    func testCrossStartsWithLowerBodyAndJabRetractsEarlier() {
        let cross = StraightPunchMotion.sample(.cross, progress: 0.08)
        XCTAssertGreaterThan(cross.hipDrive, cross.torsoDrive)
        XCTAssertGreaterThan(cross.torsoDrive, cross.reach)
        XCTAssertEqual(cross.reach, 0)
        XCTAssertLessThan(StraightPunchMotion.sample(.jab, progress: 0.65).reach,
                          StraightPunchMotion.sample(.cross, progress: 0.65).reach)
        var jabPose = FightPose.neutral(stride: 0)
        var crossPose = jabPose
        jabPose.applyAttack(.jab, progress: Float(0.08 / 0.24))
        crossPose.applyAttack(.cross, progress: Float(0.14 / 0.34))
        XCTAssertGreaterThan(abs(crossPose.hipYaw), abs(jabPose.hipYaw) * 3)
        XCTAssertGreaterThan(crossPose.rightFootYaw, 0.2)
        XCTAssertGreaterThan(crossPose.rightFoot.y, jabPose.rightFoot.y)
    }

    func testEveryStyleAndDuckPoseReturnsToOriginalGuard() {
        for style in FightStyle.allCases {
            for duck in [-1, 0, 1] {
                var base = FightPose.neutral(stride: 0, style: style)
                if duck != 0 { base.applyDuck(direction: Float(duck), style: style) }
                for punch in Punch.allCases {
                    for progress in [Float(0), Float(1)] {
                        var pose = base
                        pose.applyAttack(punch, progress: progress)
                        assertNear(pose.leftGlove, base.leftGlove)
                        assertNear(pose.rightGlove, base.rightGlove)
                        assertNear(pose.leftElbow, base.leftElbow)
                        assertNear(pose.rightElbow, base.rightElbow)
                        assertNear(pose.leftFoot, base.leftFoot)
                        assertNear(pose.rightFoot, base.rightFoot)
                        // A duck/weave is the attack's baseline, not an instruction to stand up.
                        XCTAssertEqual(pose.hipYaw, base.hipYaw)
                        XCTAssertEqual(pose.torsoYaw, base.torsoYaw)
                        XCTAssertEqual(pose.torsoPitch, base.torsoPitch)
                        XCTAssertEqual(pose.torsoLean, base.torsoLean)
                        XCTAssertEqual(pose.torsoY, base.torsoY)
                        XCTAssertEqual(pose.bodyDrop, base.bodyDrop)
                        XCTAssertEqual(pose.defensiveCrouch, base.defensiveCrouch)
                        XCTAssertEqual(pose.rootX, base.rootX)
                        XCTAssertEqual(pose.rootY, base.rootY)
                        XCTAssertEqual(pose.rootZ, base.rootZ)
                    }
                }
            }
        }
    }

    func testContactAimDoesNotSwingSidewaysWithTorsoRotation() throws {
        for style in FightStyle.allCases {
            for distance in [Float(1.25), Float(1.8), Float(3.5)] {
                for punch in [Punch.jab, .cross] {
                    let spec = try XCTUnwrap(CombatData.attacks[punch])
                    var pose = FightPose.neutral(stride: 0, style: style)
                    pose.applyAttack(punch, progress: Float(spec.activeStart / spec.duration),
                                     opponentDistance: distance, reachMultiplier: Float(style.reachMultiplier))
                    let authored = punch == .jab ? pose.leftGlove : pose.rightGlove
                    let pivot = SIMD3<Float>(0, pose.torsoY, 0)
                    let rendered = pose.torsoOrientation.act(authored - pivot) + pivot
                    XCTAssertEqual(rendered.x, punch == .jab ? 0.1 : -0.1, accuracy: 0.0001)
                    XCTAssertEqual(rendered.y, 2.08, accuracy: 0.0001)
                    XCTAssertEqual(rendered.z,
                                   StraightPunchMotion.contactReach(punch, opponentDistance: distance,
                                                                    reachMultiplier: Float(style.reachMultiplier)), accuracy: 0.0001)
                    XCTAssertLessThanOrEqual(rendered.z, distance)
                }
            }
        }
    }

    func testNonStraightPunchesUseSharedContactTimingAndDistance() throws {
        for punch in Punch.allCases where punch != .jab && punch != .cross {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let contact = Float(spec.activeStart / spec.duration)
            XCTAssertEqual(PunchMotion.sample(punch, progress: contact).reach, 1, accuracy: 0.00001)
            XCTAssertEqual(PunchMotion.sample(punch, progress: contact).followThrough, 0)
            XCTAssertGreaterThan(PunchMotion.sample(punch, progress: contact + 0.09).followThrough, 0.99)
            XCTAssertEqual(PunchMotion.sample(punch, progress: 0), PunchMotion())
            XCTAssertEqual(PunchMotion.sample(punch, progress: 1), PunchMotion())
            var normal = FightPose.neutral(stride: 0)
            var nearby = normal
            normal.applyAttack(punch, progress: contact)
            nearby.applyAttack(punch, progress: contact, opponentDistance: 1.25, reachMultiplier: 1.2)
            XCTAssertTrue(normal.separatesTorsoRotation)
            XCTAssertNotEqual(normal.hipYaw, 0)
            let lead = [.leftBody, .leftHook, .leftUppercut].contains(punch)
            let pivot = SIMD3<Float>(0, nearby.torsoY, 0)
            let glove = lead ? nearby.leftGlove : nearby.rightGlove
            let rendered = nearby.torsoOrientation.act(glove - pivot) + pivot
            XCTAssertEqual(rendered.z, 1.25 - 0.34, accuracy: 0.0001)
        }
    }

    func testPlantedFrontFootDoesNotInheritCrossTorsoYaw() throws {
        let controller = isolatedController()
        let scene = controller.scene3D
        controller.pause()
        scene.update(at: 1)
        let leftFoot = try XCTUnwrap(scene.rootNode.childNode(withName: "playerLeftFoot", recursively: true))
        let rightFoot = try XCTUnwrap(scene.rootNode.childNode(withName: "playerRightFoot", recursively: true))
        let initialLeft = leftFoot.simdWorldPosition
        let initialRight = rightFoot.simdWorldPosition
        controller.engine.player.attack = .cross
        controller.engine.player.actionTime = 0.14
        scene.update(at: 1.05)
        assertNear(leftFoot.simdWorldPosition, initialLeft)
        XCTAssertGreaterThan(rightFoot.simdWorldPosition.y, initialRight.y)
        let torso = try XCTUnwrap(scene.rootNode.childNode(withName: "playerTorso", recursively: true))
        let pelvis = try XCTUnwrap(scene.rootNode.childNode(withName: "playerPelvis", recursively: true))
        XCTAssertGreaterThan(torso.simdOrientation.angle, pelvis.simdOrientation.angle)
    }

    func testHeadBodyAndGuardHitsHaveDifferentResponses() {
        let head = FighterImpactMotion.sample(hit(.cross), remaining: 0.24, reducedMotion: false)
        let body = FighterImpactMotion.sample(hit(.leftBody), remaining: 0.24, reducedMotion: false)
        let block = FighterImpactMotion.sample(hit(.cross, guarded: true), remaining: 0.24, reducedMotion: false)
        XCTAssertLessThan(head.headOffset.z, 0)
        XCTAssertLessThan(head.fold, 0)
        XCTAssertGreaterThan(body.fold, 0)
        XCTAssertLessThan(body.headOffset.y, 0)
        XCTAssertGreaterThan(block.guardCompression, 0)
        XCTAssertEqual(block.headOffset, .zero)
        XCTAssertEqual(block.recoil, 0)
    }

    func testReducedMotionKeepsSmallerReactionAndExpiredHitIsNeutral() {
        let normal = FighterImpactMotion.sample(hit(.cross), remaining: 0.24, reducedMotion: false)
        let reduced = FighterImpactMotion.sample(hit(.cross), remaining: 0.24, reducedMotion: true)
        XCTAssertGreaterThan(reduced.recoil, 0)
        XCTAssertLessThan(reduced.recoil, normal.recoil)
        XCTAssertEqual(FighterImpactMotion.sample(hit(.cross), remaining: 0, reducedMotion: false), FighterImpactMotion())
        XCTAssertEqual(FighterImpactMotion.sample(nil, remaining: 0.24, reducedMotion: false), FighterImpactMotion())
    }

    func testNormalHitsGainEighteenPercentWhileReducedMotionKeepsPreviousAmplitude() {
        for punch in Punch.allCases {
            let impact = hit(punch)
            let strength = min(1, 0.28 + Float(impact.damage) / 20)
            let oldRecoil: Float = CombatData.attacks[punch]?.targetZone == .body ? 0.045 : (punch == .jab ? 0.055 : 0.105)
            let normal = FighterImpactMotion.sample(impact, remaining: 0.24, reducedMotion: false)
            let reduced = FighterImpactMotion.sample(impact, remaining: 0.24, reducedMotion: true)

            XCTAssertEqual(normal.recoil, oldRecoil * strength * 1.18, accuracy: 0.00001)
            XCTAssertEqual(reduced.recoil, oldRecoil * strength * 0.4, accuracy: 0.00001)
            XCTAssertEqual(normal.fold, reduced.fold * (1.18 / 0.4), accuracy: 0.00001)
            assertNear(normal.headOffset, reduced.headOffset * (1.18 / 0.4))
            XCTAssertEqual(normal.roll, reduced.roll * (1.18 / 0.4), accuracy: 0.00001)
        }
    }

    func testGuardCompressionGetsOnlySmallBoostAndKnockoutKeepsPreviousScale() {
        for punch in Punch.allCases {
            let impact = hit(punch, guarded: true)
            let strength = min(1, 0.28 + Float(impact.damage) / 20)
            let guarded = FighterImpactMotion.sample(impact, remaining: 0.24, reducedMotion: false)
            let reduced = FighterImpactMotion.sample(impact, remaining: 0.24, reducedMotion: true)
            XCTAssertEqual(guarded.guardCompression, 0.17 * strength * 1.06, accuracy: 0.00001)
            XCTAssertEqual(reduced.guardCompression, 0.17 * strength * 0.4, accuracy: 0.00001)
            XCTAssertEqual(guarded.recoil, 0)
            XCTAssertEqual(guarded.headOffset, .zero)

            let knockout = CombatImpact(attacker: .player, punch: punch, damage: 20, guarded: false,
                                        guardBroken: false, counter: true, perfectCounter: true, knockout: true)
            let koMotion = FighterImpactMotion.sample(knockout, remaining: 0.24, reducedMotion: false)
            let oldRecoil: Float = CombatData.attacks[punch]?.targetZone == .body ? 0.045 : (punch == .jab ? 0.055 : 0.105)
            XCTAssertEqual(koMotion.recoil, oldRecoil, accuracy: 0.00001)
        }
    }

    func testStrongerRecoilStaysBoundedAndExpiresWithoutExtraRecoveryTime() {
        for punch in Punch.allCases {
            let impact = hit(punch)
            let peak = FighterImpactMotion.sample(impact, remaining: 0.24, reducedMotion: false)
            XCTAssertEqual(FighterImpactMotion.sample(impact, remaining: 10, reducedMotion: false), peak)
            var previousRecoil = peak.recoil
            for remaining in [0.24, 0.20, 0.12, 0.06, 0.001, 0] {
                let motion = FighterImpactMotion.sample(impact, remaining: remaining, reducedMotion: false)
                XCTAssertGreaterThanOrEqual(motion.recoil, 0)
                XCTAssertLessThanOrEqual(motion.recoil, previousRecoil)
                XCTAssertLessThanOrEqual(abs(motion.fold), abs(peak.fold))
                XCTAssertLessThanOrEqual(simd_length(motion.headOffset), simd_length(peak.headOffset))
                previousRecoil = motion.recoil
            }
            for remaining in [0, -0.1, Double.nan, Double.infinity] {
                XCTAssertEqual(FighterImpactMotion.sample(impact, remaining: remaining, reducedMotion: false), FighterImpactMotion())
            }
        }
    }

    func testPerFighterContactMetadataAndRealTimeExpiry() {
        let presentation = CombatPresentation()
        presentation.receive(.impact(hit(.cross)))
        let reply = CombatImpact(attacker: .rival, punch: .jab, damage: 6, guarded: false,
                                 guardBroken: false, counter: false, perfectCounter: false, knockout: false)
        presentation.receive(.impact(reply))
        XCTAssertEqual(presentation.rivalHit?.punch, .cross)
        XCTAssertEqual(presentation.playerHit?.punch, .jab)
        presentation.advance(deltaTime: 0.05)
        XCTAssertEqual(presentation.playerContactTime, 0)
        XCTAssertGreaterThan(presentation.rivalContactTime, 0)
        presentation.advance(deltaTime: 0.02)
        XCTAssertEqual(presentation.rivalContactTime, 0)
        presentation.receive(.roundStarted)
        XCTAssertNil(presentation.playerHit)
        XCTAssertNil(presentation.rivalHit)
    }

    func testContactMarkComesFromResolvedHitAndHonorsReducedMotion() throws {
        let controller = isolatedController()
        let scene = controller.scene3D
        let mark = try XCTUnwrap(scene.rootNode.childNode(withName: "rivalImpactMark", recursively: true))
        XCTAssertTrue(controller.engine.startAttack(controller.engine.player, punch: .jab))
        controller.engine.update(deltaTime: 0.05)
        scene.update(at: 1) // Still before 0.08s.
        XCTAssertTrue(mark.isHidden)
        scene.update(at: 1.02)
        XCTAssertFalse(mark.isHidden)
        XCTAssertEqual(controller.engine.enemy.hp, 94)
        scene.setReducedMotion(true)
        scene.update(at: 1.03)
        XCTAssertTrue(mark.isHidden)
    }

    func testReducedMotionStopsLockerTurntable() throws {
        let scene = StylePreviewScene()
        scene.configure()
        scene.setReducedMotion(true)
        scene.update(at: 1)
        let root = try XCTUnwrap(scene.rootNode.childNode(withName: "playerBoxer", recursively: true))
        let first = root.simdTransform
        scene.update(at: 9)
        XCTAssertEqual(root.simdTransform, first)
    }

    func testRoundLossCopyDoesNotClaimUnimplementedRollback() {
        for language in AppLanguage.allCases {
            let text = L.roundLostMessage.text(for: language)
            switch language {
            case .korean: XCTAssertTrue(text.contains("재도전"))
            case .english: XCTAssertTrue(text.contains("Retry this round"))
            case .japanese: XCTAssertTrue(text.contains("再挑戦"))
            }
            XCTAssertFalse(text.contains("롤백"))
            XCTAssertFalse(text.contains("rolled back"))
            XCTAssertFalse(text.contains("ロールバック"))
        }
    }

    func testCaptureStraightPunchFramesOnDevice() throws {
        let controller = isolatedController()
        controller.engine.player.x = 263
        controller.engine.enemy.x = 327
        controller.pause()
        let scene = controller.scene3D
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.cameraNode
        var time = 1.0
        for punch in [Punch.jab, .cross] {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            for (name, elapsed) in [("load", spec.activeStart * 0.35), ("contact", spec.activeStart), ("recovery", spec.duration * 0.88)] {
                controller.presentation.receive(.roundStarted)
                controller.engine.player.attack = punch
                controller.engine.player.actionTime = elapsed
                controller.engine.enemy.hitReaction = name == "contact" ? 0.24 : 0
                if name == "contact" { controller.presentation.receive(.impact(hit(punch))) }
                scene.update(at: time)
                time += 0.02
                // Diagnostic courtside angle; the actual in-game camera is not changed by this test.
                scene.cameraNode.position = SCNVector3(0.2, 2.1, 5.5)
                scene.cameraNode.look(at: SCNVector3(0, 1.25, 0))
                let image = renderer.snapshot(atTime: time, with: CGSize(width: 1200, height: 675), antialiasingMode: .multisampling4X)
                XCTAssertEqual(image.size.width, 1200)
                let attachment = XCTAttachment(image: image)
                attachment.name = "RIVAL \(punch.label) \(name) - device pose render"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func hit(_ punch: Punch, guarded: Bool = false) -> CombatImpact {
        CombatImpact(attacker: .player, punch: punch, damage: CombatData.attacks[punch]?.damage ?? 0,
                     guarded: guarded, guardBroken: false, counter: false, perfectCounter: false, knockout: false)
    }

    private func isolatedController() -> GameController {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.engine.player.x = 280
        controller.engine.enemy.x = 330
        controller.engine.enemy.stagger = 1000
        return controller
    }

    private func assertNear(_ value: SIMD3<Float>, _ expected: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_distance(value, expected), 0.0001, file: file, line: line)
    }
}