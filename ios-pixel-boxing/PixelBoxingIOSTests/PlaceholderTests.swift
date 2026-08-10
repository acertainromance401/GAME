import XCTest
import SceneKit
@testable import RIVAL

@MainActor
final class CombatCoreTests: XCTestCase {
    func testTwoButtonCombosMatchDesktopControls() {
        XCTAssertEqual(CombatData.comboPunch(base: .jab, guarding: false, duckDirection: 0), .jab)
        XCTAssertEqual(CombatData.comboPunch(base: .cross, guarding: false, duckDirection: 0), .cross)
        XCTAssertEqual(CombatData.comboPunch(base: .jab, guarding: true, duckDirection: 0), .leftUppercut)
        XCTAssertEqual(CombatData.comboPunch(base: .cross, guarding: true, duckDirection: 0), .rightUppercut)
        XCTAssertEqual(CombatData.comboPunch(base: .jab, guarding: false, duckDirection: -1), .leftBody)
        XCTAssertEqual(CombatData.comboPunch(base: .cross, guarding: false, duckDirection: -1), .rightHook)
        XCTAssertEqual(CombatData.comboPunch(base: .jab, guarding: false, duckDirection: 1), .leftHook)
        XCTAssertEqual(CombatData.comboPunch(base: .cross, guarding: false, duckDirection: 1), .rightBody)
        XCTAssertEqual(CombatData.comboPunch(base: .leftHook, guarding: true, duckDirection: 0), .leftHook)
    }

    func testControllerUsesHeldDefenseForComboAttack() {
        let guardController = GameController()
        guardController.start()
        guardController.guardButton(active: true)
        guardController.comboAttack(base: .jab)
        XCTAssertEqual(guardController.engine.player.attack, .leftUppercut)

        let duckController = GameController()
        duckController.start()
        duckController.duckButton(direction: -1, active: true)
        duckController.comboAttack(base: .cross)
        XCTAssertEqual(duckController.engine.player.attack, .rightHook)
    }

    func testVisualJabUsesLeftHandAndCrossUsesRightHand() {
        var jabPose = FightPose.neutral(stride: 0)
        jabPose.applyAttack(.jab, progress: 0.54)
        XCTAssertGreaterThan(jabPose.leftGlove.x, 0)
        XCTAssertGreaterThan(jabPose.leftGlove.z, jabPose.rightGlove.z + 1)

        var crossPose = FightPose.neutral(stride: 0)
        crossPose.applyAttack(.cross, progress: 0.54)
        XCTAssertLessThan(crossPose.rightGlove.x, 0)
        XCTAssertGreaterThan(crossPose.rightGlove.z, crossPose.leftGlove.z + 0.8)
    }

    func testVisualDucksAreLowAndMoveInOppositeDirections() {
        let neutral = FightPose.neutral(stride: 0)
        var leftDuck = FightPose.neutral(stride: 0)
        leftDuck.applyDuck(direction: -1)
        var rightDuck = FightPose.neutral(stride: 0)
        rightDuck.applyDuck(direction: 1)

        XCTAssertEqual(leftDuck.rootY, 0, accuracy: 0.001)
        XCTAssertEqual(leftDuck.rootY, rightDuck.rootY, accuracy: 0.001)
        XCTAssertEqual(leftDuck.leftFoot.y, neutral.leftFoot.y, accuracy: 0.001)
        XCTAssertEqual(leftDuck.rightFoot.y, neutral.rightFoot.y, accuracy: 0.001)
        XCTAssertGreaterThan(leftDuck.bodyDrop, 0.4)
        XCTAssertLessThan(leftDuck.torsoY, neutral.torsoY - 0.35)
        XCTAssertLessThan(leftDuck.leftHip.y, neutral.leftHip.y - 0.25)
        XCTAssertGreaterThan(leftDuck.torsoLean, 0.2)
        XCTAssertLessThan(rightDuck.torsoLean, -0.2)
        XCTAssertGreaterThan(leftDuck.leftGlove.x, rightDuck.leftGlove.x)
    }

    func testMovementUsesFighterRelativeDesktopAxes() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        let startX = engine.player.x
        let startY = engine.player.y
        engine.setMove(x: 1, y: 0)
        engine.update(deltaTime: 0.05)
        XCTAssertEqual(engine.player.x, startX + 10.5, accuracy: 0.01)
        XCTAssertEqual(engine.player.y, startY, accuracy: 0.01)

        let strafeEngine = CombatEngine(persistHabits: false)
        strafeEngine.startSession()
        let strafeStartY = strafeEngine.player.y
        strafeEngine.setMove(x: 0, y: 1)
        strafeEngine.update(deltaTime: 0.05)
        XCTAssertEqual(strafeEngine.player.y, strafeStartY + 10.5, accuracy: 0.01)
    }

    func testControllerKeepsRemainingHeldMovement() {
        let controller = GameController()
        controller.start()
        controller.move(x: 1, y: 0, active: true)
        controller.move(x: 0, y: 1, active: true)
        controller.move(x: 1, y: 0, active: false)
        XCTAssertEqual(controller.engine.moveX, 0)
        XCTAssertEqual(controller.engine.moveY, 1)
    }

    func testHeldGuardReturnsAfterComboAttack() {
        let controller = GameController()
        controller.start()
        controller.guardButton(active: true)
        controller.comboAttack(base: .jab)
        XCTAssertFalse(controller.engine.player.guarding)

        for _ in 0..<10 { controller.engine.update(deltaTime: 0.05) }
        controller.synchronizeHeldControls()
        XCTAssertNil(controller.engine.player.attack)
        XCTAssertTrue(controller.engine.player.guarding)
    }

    func testReleasedDuckClearsAfterBodyShot() {
        let controller = GameController()
        controller.start()
        controller.duckButton(direction: -1, active: true)
        controller.comboAttack(base: .jab)
        XCTAssertEqual(controller.engine.player.attack, .leftBody)

        controller.duckButton(direction: -1, active: false)
        XCTAssertEqual(controller.engine.player.duckDirection, 0)
        for _ in 0..<10 {
            controller.synchronizeHeldControls()
            controller.engine.update(deltaTime: 0.05)
        }
        controller.synchronizeHeldControls()

        XCTAssertNil(controller.engine.player.attack)
        XCTAssertEqual(controller.engine.player.duckDirection, 0)
    }

    func testFightersCannotOverlapAndShortestAttackStillConnects() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        engine.enemy.stagger = 1
        engine.enemy.x = engine.player.x + CombatData.minimumFighterSeparation
        engine.enemy.y = engine.player.y
        engine.setMove(x: 1, y: 0)

        for _ in 0..<20 { engine.update(deltaTime: 0.05) }

        let separation = hypot(engine.enemy.x - engine.player.x, engine.enemy.y - engine.player.y)
        XCTAssertGreaterThanOrEqual(separation, CombatData.minimumFighterSeparation - 0.001)

        engine.setMove(x: 0, y: 0)
        engine.enemy.stagger = 1
        let hpBefore = engine.enemy.hp
        XCTAssertTrue(engine.startAttack(engine.player, punch: .leftUppercut))
        for _ in 0..<4 { engine.update(deltaTime: 0.05) }
        XCTAssertLessThan(engine.enemy.hp, hpBefore)
    }

    func testBackstepSpendsStaminaAndMovesAway() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        let startX = engine.player.x

        XCTAssertTrue(engine.backstep())

        XCTAssertEqual(engine.player.x, startX - 34, accuracy: 0.001)
        XCTAssertEqual(engine.player.stamina, 100 - CombatData.backstepStaminaCost, accuracy: 0.001)
        XCTAssertEqual(engine.player.invulnerable, 0.22, accuracy: 0.001)
        engine.player.stamina = CombatData.backstepStaminaCost - 1
        XCTAssertFalse(engine.backstep())
    }

    func testGuardCostsStaminaAndCanBreak() {
        let engine = closeRangeEngine()
        engine.player.stamina = 5
        engine.setGuarding(true)
        XCTAssertTrue(engine.startAttack(engine.enemy, punch: .jab))
        advanceToActiveFrame(engine)

        XCTAssertEqual(engine.player.hp, 98)
        XCTAssertEqual(engine.player.stamina, 0, accuracy: 0.001)
        XCTAssertFalse(engine.player.guarding)
        XCTAssertGreaterThan(engine.player.exhausted, 0)
    }

    func testHealthTieIsDrawAndOnlyWinAdvancesRound() {
        XCTAssertEqual(CombatData.roundOutcome(playerHP: 80, enemyHP: 80), .draw)
        XCTAssertEqual(CombatData.roundOutcome(playerHP: 81, enemyHP: 80), .playerWin)
        XCTAssertEqual(CombatData.roundOutcome(playerHP: 79, enemyHP: 80), .playerLoss)

        let drawEngine = CombatEngine(persistHabits: false)
        drawEngine.startSession()
        drawEngine.finishRound(outcome: .draw, knockout: false)
        for _ in 0..<40 { drawEngine.update(deltaTime: 0.05) }
        XCTAssertEqual(drawEngine.round, 1)
        XCTAssertEqual(drawEngine.playerScore, 0)
        XCTAssertEqual(drawEngine.enemyScore, 0)

        let lossEngine = CombatEngine(persistHabits: false)
        lossEngine.startSession()
        lossEngine.finishRound(outcome: .playerLoss, knockout: false)
        for _ in 0..<40 { lossEngine.update(deltaTime: 0.05) }
        XCTAssertEqual(lossEngine.round, 1)
        XCTAssertEqual(lossEngine.enemyScore, 1)

        let winEngine = CombatEngine(persistHabits: false)
        winEngine.startSession()
        winEngine.finishRound(outcome: .playerWin, knockout: false)
        for _ in 0..<40 { winEngine.update(deltaTime: 0.05) }
        XCTAssertEqual(winEngine.round, 2)
        XCTAssertEqual(winEngine.playerScore, 1)
    }

    func testPlayerLossRollsBackRoundHabitLearning() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        let initialAttacks = engine.habits.attackCounts[.jab, default: 0]
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))
        XCTAssertGreaterThan(engine.habits.attackCounts[.jab, default: 0], initialAttacks)

        engine.finishRound(outcome: .playerLoss, knockout: false)

        XCTAssertEqual(engine.habits.attackCounts[.jab, default: 0], initialAttacks)
    }

    func testLearningResetBecomesLossRollbackBaseline() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))
        engine.resetLearning()
        engine.player.attack = nil
        XCTAssertTrue(engine.startAttack(engine.player, punch: .cross, recordsHabit: true))

        engine.finishRound(outcome: .playerLoss, knockout: false)

        XCTAssertTrue(engine.habits.attackCounts.values.allSatisfy { $0 == 0 })
    }

    func testRemodeledGlovesHaveBoxingGloveParts() {
        let scene = Arena3DScene(engine: CombatEngine(persistHabits: false))
        let glove = scene.rootNode.childNode(withName: "playerLeftGlove", recursively: true)
        XCTAssertNotNil(glove?.childNode(withName: "glovePalm", recursively: false))
        XCTAssertNotNil(glove?.childNode(withName: "gloveKnuckles", recursively: false))
        XCTAssertNotNil(glove?.childNode(withName: "gloveThumb", recursively: false))
        XCTAssertNotNil(glove?.childNode(withName: "gloveCuff", recursively: false))
        XCTAssertNotNil(glove?.childNode(withName: "gloveCuffRim", recursively: false))
    }

    func testBoxersHaveCameraFacingIdentityLabels() throws {
        let scene = Arena3DScene(engine: CombatEngine(persistHabits: false))
        let playerLabel = try XCTUnwrap(scene.rootNode.childNode(withName: "playerIdentityLabel", recursively: true))
        let rivalLabel = try XCTUnwrap(scene.rootNode.childNode(withName: "rivalIdentityLabel", recursively: true))
        let playerText = try XCTUnwrap(playerLabel.childNode(withName: "identityText", recursively: false)?.geometry as? SCNText)
        let rivalText = try XCTUnwrap(rivalLabel.childNode(withName: "identityText", recursively: false)?.geometry as? SCNText)

        XCTAssertEqual(playerText.string as? String, "ME")
        XCTAssertEqual(rivalText.string as? String, "RIVAL")
        XCTAssertTrue(playerLabel.constraints?.first is SCNBillboardConstraint)
        XCTAssertTrue(rivalLabel.constraints?.first is SCNBillboardConstraint)
    }

    func testCameraHeadingCannotFlipOrSpinOnStrafe() {
        let forward = SIMD3<Float>(1, 0, 0)
        let opposite = SIMD3<Float>(-1, 0, 0)
        let overlapResult = stabilizedCameraForward(
            current: forward,
            desired: opposite,
            separation: 0.3,
            deltaTime: 0.05
        )
        XCTAssertEqual(overlapResult.x, 1, accuracy: 0.001)
        XCTAssertEqual(overlapResult.z, 0, accuracy: 0.001)

        let sideResult = stabilizedCameraForward(
            current: forward,
            desired: SIMD3<Float>(0, 0, 1),
            separation: 3,
            deltaTime: 0.05
        )
        let turn = atan2(sideResult.z, sideResult.x)
        XCTAssertGreaterThan(turn, 0)
        XCTAssertLessThanOrEqual(turn, 0.0626)
    }

    func testCommentaryExplainsTechniquesAndDefense() {
        XCTAssertTrue(CombatCommentary.attackCall(.jab, attacker: "PLAYER").contains("왼손 잽"))
        XCTAssertTrue(CombatCommentary.attackCall(.cross, attacker: "PLAYER").contains("오른손 크로스"))
        XCTAssertTrue(CombatCommentary.impact(.leftHook, attacker: "PLAYER").contains("훅"))
        XCTAssertTrue(CombatCommentary.impact(.rightUppercut, attacker: "PLAYER").contains("어퍼컷"))
        XCTAssertTrue(CombatCommentary.guardBlock(defender: "PLAYER").contains("가드"))
        XCTAssertTrue(CombatCommentary.duckEvade(defender: "PLAYER").contains("더킹"))
        XCTAssertTrue(CombatCommentary.whiff(attacker: "PLAYER").contains("카운터"))
        XCTAssertTrue(CombatCommentary.knockout(winner: "PLAYER").contains("K.O."))
    }

    func testCanonicalAttackSpecsMatchPythonMainline() {
        XCTAssertEqual(CombatData.attacks.count, 8)
        XCTAssertEqual(CombatData.attacks[.jab], AttackSpec(duration: 0.24, activeStart: 0.08, activeEnd: 0.15, damage: 6, range: 78, halfAngle: 26, staminaCost: 13, targetZone: .head, fistRadius: 5, family: .straight))
        XCTAssertEqual(CombatData.attacks[.rightUppercut]?.damage, 14)
        XCTAssertEqual(CombatData.attacks[.rightUppercut]?.staminaCost, 21)
    }

    func testCompleteDamageAndGuardCostTable() throws {
        let expected: [Punch: (damage: Int, guardedDamage: Int, guardStamina: Double)] = [
            .jab: (6, 2, 5.4),
            .cross: (11, 4, 9.9),
            .leftBody: (9, 4, 8.1),
            .rightBody: (10, 4, 9.0),
            .leftHook: (11, 4, 9.9),
            .rightHook: (12, 5, 10.8),
            .leftUppercut: (13, 5, 11.7),
            .rightUppercut: (14, 6, 12.6),
        ]

        for (punch, values) in expected {
            let damage = try XCTUnwrap(CombatData.attacks[punch]?.damage)
            XCTAssertEqual(damage, values.damage)
            XCTAssertEqual(max(1, Int((Double(damage) * CombatData.guardDamageMultiplier).rounded())), values.guardedDamage)
            XCTAssertEqual(
                max(CombatData.minimumGuardStaminaDamage, Double(damage) * CombatData.guardStaminaDamageMultiplier),
                values.guardStamina,
                accuracy: 0.001
            )
        }
        XCTAssertEqual(CombatData.minimumFighterSeparation, 50)
    }

    func testDirectionalDuckMappingMatchesPythonMainline() {
        XCTAssertEqual(CombatData.requiredDuck[.jab], 1)
        XCTAssertEqual(CombatData.requiredDuck[.leftHook], 1)
        XCTAssertEqual(CombatData.requiredDuck[.cross], -1)
        XCTAssertEqual(CombatData.requiredDuck[.rightUppercut], -1)
        XCTAssertNil(CombatData.requiredDuck[.leftBody])
    }

    func testStartingAttackSpendsStaminaAndTracksHabit() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))
        XCTAssertEqual(engine.player.stamina, 87)
        XCTAssertEqual(engine.habits.attackCounts[.jab], 1)
        XCTAssertEqual(engine.habits.snapshot.favoriteAttack, .jab)
    }

    func testAdaptationIncreasesWithSamplesAndRounds() {
        var habits = HabitMemory()
        let initial = habits.snapshot.adaptation(round: 1)
        habits.sample(deltaTime: 3, guarding: true, duckDirection: 0, backstep: false, forwardAxis: 0)
        XCTAssertGreaterThan(habits.snapshot.adaptation(round: 1), initial)
        XCTAssertGreaterThan(habits.snapshot.adaptation(round: 3), habits.snapshot.adaptation(round: 1))
    }

    func testGuardHeavyPlayerRaisesBodyShotWeight() {
        var habits = HabitMemory()
        habits.sample(deltaTime: 3, guarding: true, duckDirection: 0, backstep: false, forwardAxis: 0)
        let weights = habits.snapshot.enemyWeights(distance: 60, round: 3, playerExposed: false)
        XCTAssertGreaterThan(weights[Punch.rightBody.rawValue, default: 0], weights[Punch.jab.rawValue, default: 0])
    }

    func testCorrectDuckEvadesJabButWrongDuckDoesNot() {
        let correct = closeRangeEngine()
        correct.setDuck(1, active: true)
        XCTAssertTrue(correct.startAttack(correct.enemy, punch: .jab))
        advanceToActiveFrame(correct)
        XCTAssertEqual(correct.player.hp, 100)
        XCTAssertGreaterThan(correct.enemy.exposed, 0)
        XCTAssertEqual(correct.snapshot.successfulDodgeCount, 1)
        XCTAssertTrue(correct.snapshot.message.contains("카운터 타이밍"))

        let wrong = closeRangeEngine()
        wrong.setDuck(-1, active: true)
        XCTAssertTrue(wrong.startAttack(wrong.enemy, punch: .jab))
        advanceToActiveFrame(wrong)
        XCTAssertEqual(wrong.player.hp, 94)
    }

    func testDuckCounterBodyAndHookBonusesAreVisibleInDamageAndCommentary() {
        let bodyEngine = closeRangeEngine()
        bodyEngine.setDuck(-1, active: true)
        XCTAssertTrue(bodyEngine.startAttack(bodyEngine.enemy, punch: .cross))
        advance(bodyEngine, frames: 3)
        XCTAssertEqual(bodyEngine.player.hp, 100)
        advance(bodyEngine, frames: 2)
        XCTAssertTrue(bodyEngine.startAttack(bodyEngine.player, punch: .leftBody))
        advance(bodyEngine, frames: 3)
        XCTAssertEqual(bodyEngine.enemy.hp, 84)
        XCTAssertTrue(bodyEngine.message.contains("바디/훅 보너스 피해 16"))

        let hookEngine = closeRangeEngine()
        hookEngine.setDuck(1, active: true)
        XCTAssertTrue(hookEngine.startAttack(hookEngine.enemy, punch: .jab))
        advanceToActiveFrame(hookEngine)
        XCTAssertEqual(hookEngine.player.hp, 100)
        advance(hookEngine, frames: 2)
        XCTAssertTrue(hookEngine.startAttack(hookEngine.player, punch: .leftHook))
        advance(hookEngine, frames: 4)
        XCTAssertEqual(hookEngine.enemy.hp, 82)
        XCTAssertTrue(hookEngine.message.contains("바디/훅 보너스 피해 18"))
    }

    func testRivalExecutesDirectionalDuckAndEvadesMatchingPunch() {
        let engine = closeRangeEngine()
        XCTAssertTrue(engine.performEnemyDecision("dodge_right"))
        XCTAssertEqual(engine.enemy.duckDirection, 1)
        XCTAssertEqual(engine.enemy.stamina, 100 - CombatData.dodgeStaminaCost, accuracy: 0.001)

        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        advanceToActiveFrame(engine)

        XCTAssertEqual(engine.enemy.hp, 100)
        XCTAssertGreaterThan(engine.player.exposed, 0)
        XCTAssertTrue(engine.message.contains("RIVAL의 완벽한 더킹"))
    }

    func testLearningResetRestartsAtRoundOne() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        engine.finishRound(outcome: .playerWin, knockout: false)
        advance(engine, frames: 40)
        XCTAssertEqual(engine.round, 2)
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))

        engine.resetLearning()

        XCTAssertEqual(engine.round, 1)
        XCTAssertEqual(engine.playerScore, 0)
        XCTAssertEqual(engine.enemyScore, 0)
        XCTAssertEqual(engine.phase, .fight)
        XCTAssertTrue(engine.habits.attackCounts.values.allSatisfy { $0 == 0 })
        XCTAssertTrue(engine.message.contains("ROUND 1"))
    }

    func testGuardReducesJabDamage() {
        let engine = closeRangeEngine()
        engine.setGuarding(true)
        XCTAssertTrue(engine.startAttack(engine.enemy, punch: .jab))
        advanceToActiveFrame(engine)
        XCTAssertEqual(engine.player.hp, 98)
    }

    func testAttackPunishesExposedDefender() {
        let engine = closeRangeEngine()
        engine.enemy.exposed = 1
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        advanceToActiveFrame(engine)
        XCTAssertEqual(engine.enemy.hp, 92)
    }

    private func closeRangeEngine() -> CombatEngine {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        engine.player.x = 280
        engine.player.y = 295
        engine.enemy.x = 330
        engine.enemy.y = 295
        return engine
    }

    private func advanceToActiveFrame(_ engine: CombatEngine) {
        advance(engine, frames: 2)
    }

    private func advance(_ engine: CombatEngine, frames: Int) {
        for _ in 0..<frames { engine.update(deltaTime: 0.05) }
    }
}
