import XCTest
import simd
@testable import RIVAL

@MainActor
final class ControlAndDefenseTests: XCTestCase {
    func testWeaveHoldStartsOnceAndReleaseClearsPendingHook() {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.engine.enemy.stagger = 100
        controller.weaveButton(direction: -1, active: true)
        XCTAssertEqual(controller.selectedPunch(base: .jab), .leftHook)
        XCTAssertEqual(controller.engine.player.stamina, 88)
        controller.weaveButton(direction: -1, active: true)
        XCTAssertEqual(controller.engine.player.stamina, 88)
        controller.comboAttack(base: .jab)
        controller.releaseHeldControls()
        for _ in 0..<40 { controller.engine.update(deltaTime: 1.0 / 60) }
        XCTAssertNil(controller.engine.player.attack)
        XCTAssertEqual(controller.engine.player.weave.comboDirection, 0)
        XCTAssertTrue(controller.engine.roundPlayerPunchCounts.isEmpty)
        controller.weaveButton(direction: -1, active: true)
        XCTAssertTrue(controller.engine.player.weave.isActive)
    }

    func testOppositeAttackWorksNormallyAfterWeaveButNotDuringIt() {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.engine.enemy.stagger = 100
        controller.weaveButton(direction: -1, active: true)
        controller.comboAttack(base: .cross)
        XCTAssertNil(controller.engine.player.attack)
        for _ in 0..<36 { controller.engine.update(deltaTime: 0.01) }
        controller.comboAttack(base: .cross)
        XCTAssertEqual(controller.engine.player.attack, .cross)
        XCTAssertEqual(controller.engine.player.weave.comboDirection, 0)
    }

    func testHeldCombosMatchExistingMappingAndGuardHasPriority() {
        var controls = CombatModifiers()
        XCTAssertEqual(controls.punch(base: .jab), .jab)
        XCTAssertEqual(controls.punch(base: .cross), .cross)
        controls.setDuck(-1, active: true)
        XCTAssertEqual(controls.punch(base: .jab), .leftBody)
        XCTAssertEqual(controls.punch(base: .cross), .rightHook)
        controls.setDuck(1, active: true)
        XCTAssertEqual(controls.punch(base: .jab), .leftHook)
        XCTAssertEqual(controls.punch(base: .cross), .rightBody)
        controls.guarding = true
        XCTAssertEqual(controls.punch(base: .jab), .leftUppercut)
        XCTAssertEqual(controls.punch(base: .cross), .rightUppercut)
        controls.guarding = false
        controls.setDuck(1, active: false)
        XCTAssertEqual(controls.duckDirection, -1)
        controls.setDuck(-1, active: false)
        XCTAssertEqual(controls.duckDirection, 0)
    }

    func testRepeatedHoldCallbackDoesNotStealMostRecentDuckAndResetReleasesAll() {
        var controls = CombatModifiers()
        controls.setDuck(-1, active: true)
        controls.setDuck(1, active: true)
        controls.setDuck(-1, active: true)
        XCTAssertEqual(controls.duckDirection, 1)
        controls.guarding = true
        controls.reset()
        XCTAssertEqual(controls, CombatModifiers())
    }

    func testControllerUsesSameModifierForDisplayAndAttack() {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.duckButton(direction: -1, active: true)
        let displayed = controller.selectedPunch(base: .cross)
        controller.comboAttack(base: .cross)
        XCTAssertEqual(controller.engine.player.attack, displayed)
        controller.releaseHeldControls()
        XCTAssertEqual(controller.modifiers, CombatModifiers())
        for language in AppLanguage.allCases {
            for punch in Punch.allCases { XCTAssertFalse(punch.controlLabel(for: language).isEmpty) }
        }
    }

    func testBackstepMovesRearFootFirstThenFrontFootAndSettles() {
        let early = BackstepMotion.sample(elapsed: 0.03)
        let late = BackstepMotion.sample(elapsed: 0.15)
        XCTAssertGreaterThan(early.rearLift, 0)
        XCTAssertEqual(early.frontLift, 0)
        XCTAssertEqual(late.rearLift, 0)
        XCTAssertGreaterThan(late.frontLift, 0)
        XCTAssertLessThan(late.positionLag, early.positionLag)
        XCTAssertEqual(BackstepMotion.sample(elapsed: BackstepMotion.duration), BackstepMotion())
        XCTAssertEqual(BackstepMotion.sample(elapsed: .nan), BackstepMotion())
        XCTAssertLessThan(BackstepMotion.duration, CombatData.backstepDuration)
    }

    func testFootCompensationCancelsPoseTranslationAndRotationOnly() {
        let contact = SIMD3<Float>(0.31, 0.14, 0.29)
        let position = SIMD3<Float>(-0.26, 0.035, -0.20)
        let rotation = simd_quatf(angle: 0.18, axis: SIMD3<Float>(0, 0, 1))
            * simd_quatf(angle: 0.15, axis: SIMD3<Float>(0, 1, 0))
        let local = DefensiveMotion.plantedFoot(contact, posePosition: position, poseRotation: rotation)
        XCTAssertLessThan(simd_distance(rotation.act(local) + position, contact), 0.00001)
    }

    func testGuardBlendIsBoundedAndReducedMotionIsImmediate() {
        let raised = DefensiveMotion.guardBlend(current: 0, raised: true, deltaTime: 1.0 / 60, reducedMotion: false)
        XCTAssertGreaterThan(raised, 0)
        XCTAssertLessThan(raised, 1)
        let lowered = DefensiveMotion.guardBlend(current: raised, raised: false, deltaTime: 1.0 / 60, reducedMotion: false)
        XCTAssertGreaterThanOrEqual(lowered, 0)
        XCTAssertLessThan(lowered, raised)
        XCTAssertEqual(DefensiveMotion.guardBlend(current: 0, raised: true, deltaTime: 1.0 / 60, reducedMotion: true), 1)
    }

    func testFootworkFollowsTravelDirectionAndZeroGuardBlendKeepsStance() {
        for style in FightStyle.allCases {
            var forward = FightPose.neutral(stride: 0, style: style)
            let base = forward
            var lateral = base
            forward.applyFootwork(forward: 1, strafe: 0, strideCycle: 0.7)
            lateral.applyFootwork(forward: 0, strafe: 1, strideCycle: 0.7)
            XCTAssertGreaterThan(forward.leftFoot.z, base.leftFoot.z)
            XCTAssertEqual(forward.leftFoot.x, base.leftFoot.x)
            XCTAssertGreaterThan(lateral.leftFoot.x, base.leftFoot.x)
            XCTAssertEqual(lateral.leftFoot.z, base.leftFoot.z)
            var unraised = base
            unraised.applyGuard(style: style, amount: 0)
            XCTAssertEqual(unraised.leftGlove, base.leftGlove)
            XCTAssertEqual(unraised.rightGlove, base.rightGlove)
        }
    }
}