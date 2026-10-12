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
        let guardController = GameController(persistsProgress: false, feedbackEnabled: false)
        guardController.start()
        guardController.guardButton(active: true)
        guardController.comboAttack(base: .jab)
        XCTAssertEqual(guardController.engine.player.attack, .leftUppercut)

        let duckController = GameController(persistsProgress: false, feedbackEnabled: false)
        duckController.start()
        duckController.duckButton(direction: -1, active: true)
        duckController.comboAttack(base: .cross)
        XCTAssertEqual(duckController.engine.player.attack, .rightHook)
    }

    func testVisualJabUsesLeftHandAndCrossUsesRightHand() {
        var jabPose = FightPose.neutral(stride: 0)
        jabPose.applyAttack(.jab, progress: Float(0.08 / 0.24))
        XCTAssertGreaterThan(jabPose.leftGlove.x, 0)
        XCTAssertGreaterThan(jabPose.leftGlove.z, jabPose.rightGlove.z + 1)

        var crossPose = FightPose.neutral(stride: 0)
        crossPose.applyAttack(.cross, progress: Float(0.14 / 0.34))
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
        var guardPose = neutral
        guardPose.applyGuard()
        for (direction, pose) in [(Float(-1), leftDuck), (Float(1), rightDuck)] {
            XCTAssertEqual(pose.leftFoot, neutral.leftFoot)
            XCTAssertEqual(pose.rightFoot, neutral.rightFoot)
            XCTAssertEqual(pose.rootZ, neutral.rootZ)
            XCTAssertEqual(pose.bodyDrop, 0.40, accuracy: 0.00001)
            XCTAssertEqual(pose.defensiveCrouch, 0.40, accuracy: 0.00001)
            XCTAssertEqual(pose.torsoY, neutral.torsoY - 0.40, accuracy: 0.00001)
            XCTAssertEqual(pose.leftHip.y, neutral.leftHip.y - 0.288, accuracy: 0.00001)
            XCTAssertEqual(pose.rightHip.y, neutral.rightHip.y - 0.288, accuracy: 0.00001)
            XCTAssertEqual(pose.leftKnee.y, neutral.leftKnee.y - 0.08, accuracy: 0.00001)
            XCTAssertEqual(pose.rightKnee.y, neutral.rightKnee.y - 0.08, accuracy: 0.00001)
            XCTAssertEqual(pose.leftKnee.z, neutral.leftKnee.z + 0.18, accuracy: 0.00001)
            XCTAssertEqual(pose.rightKnee.z, neutral.rightKnee.z + 0.18, accuracy: 0.00001)
            XCTAssertEqual(pose.torsoYaw, -direction * 0.18, accuracy: 0.00001)
            XCTAssertEqual(pose.hipYaw, -direction * 0.081, accuracy: 0.00001)
            XCTAssertEqual(pose.torsoPitch, -0.14, accuracy: 0.00001)
            XCTAssertEqual(pose.torsoLean, direction * 0.025, accuracy: 0.00001)
            XCTAssertEqual(pose.rootX, -direction * 0.04, accuracy: 0.00001)
            XCTAssertLessThan(pose.headFacingPosition.y, neutral.headFacingPosition.y - 0.39)
            XCTAssertGreaterThan(pose.headFacingPosition.z, neutral.headFacingPosition.z)
            // Rendered offsets follow the chin; inverse torso rotation changes authored glove.x/y.
            let joints = [pose.leftGlove, pose.rightGlove, pose.leftElbow, pose.rightElbow]
            let guarded = [guardPose.leftGlove, guardPose.rightGlove, guardPose.leftElbow, guardPose.rightElbow]
            for (joint, target) in zip(joints, guarded) {
                let offset = pose.facingPoint(joint) - pose.headFacingPosition
                XCTAssertLessThan(simd_distance(offset, target - SIMD3<Float>(0, 2.28, 0.04)), 0.0001)
            }
        }
        XCTAssertGreaterThan(leftDuck.rootX + leftDuck.headFacingPosition.x,
                             rightDuck.rootX + rightDuck.headFacingPosition.x)
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
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.move(x: 1, y: 0, active: true)
        controller.move(x: 0, y: 1, active: true)
        controller.move(x: 1, y: 0, active: false)
        XCTAssertEqual(controller.engine.moveX, 0)
        XCTAssertEqual(controller.engine.moveY, 1)
    }

    func testHeldGuardReturnsAfterComboAttack() {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
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
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
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
        // Round advancement is no longer automatic once the round-break timer expires -- the player must
        // explicitly confirm via `requestNextRound()` (round-result overlay's "next round" button).
        winEngine.requestNextRound()
        XCTAssertEqual(winEngine.round, 2)
        XCTAssertEqual(winEngine.playerScore, 1)
    }

    func testPlayerLossPromotesRoundHabitLearning() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        let initialAttacks = engine.habits.attackCounts[.jab, default: 0]
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))
        XCTAssertEqual(engine.habits.attackCounts[.jab, default: 0], initialAttacks)

        engine.finishRound(outcome: .playerLoss, knockout: false)

        XCTAssertEqual(engine.habits.attackCounts[.jab, default: 0], initialAttacks + 1)
    }

    func testEveryCompletedRoundPromotesPersistentHabits() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))
        engine.player.attack = nil
        engine.finishRound(outcome: .draw, knockout: false)
        XCTAssertEqual(engine.habits.attackCounts[.jab, default: 0], 1)

        engine.startRound()
        XCTAssertTrue(engine.startAttack(engine.player, punch: .cross, recordsHabit: true))
        engine.finishRound(outcome: .playerWin, knockout: false)

        XCTAssertEqual(engine.habits.attackCounts[.jab, default: 0], 0.82, accuracy: 0.001)
        XCTAssertEqual(engine.habits.attackCounts[.cross, default: 0], 1)
    }

    func testNextRoundKeepsConfirmedProfileButClearsTacticalRead() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()

        for _ in 0..<4 {
            XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))
            engine.player.attack = nil
        }
        XCTAssertEqual(engine.snapshot.rivalRead, .jabPattern)

        engine.finishRound(outcome: .playerWin, knockout: false)
        for _ in 0..<40 { engine.update(deltaTime: 0.05) }
        engine.requestNextRound()

        XCTAssertEqual(engine.habits.attackCounts[.jab, default: 0], 4)
        XCTAssertEqual(engine.snapshot.rivalRead, .none)
    }

    func testRemodeledGlovesHaveBoxingGloveParts() {
        let scene = Arena3DScene(engine: CombatEngine(persistHabits: false))
        let glove = scene.rootNode.childNode(withName: "playerLeftGlove", recursively: true)
        XCTAssertNotNil(glove?.childNode(withName: "glovePalm", recursively: false))
        XCTAssertNotNil(glove?.childNode(withName: "gloveThumb", recursively: false))
        XCTAssertNotNil(glove?.childNode(withName: "gloveCuff", recursively: false))
        XCTAssertNotNil(glove?.childNode(withName: "gloveStrap", recursively: false))
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
        XCTAssertTrue(CombatCommentary.attackCall(.jab, attacker: "PLAYER", language: .korean).contains("왼손 잽"))
        XCTAssertTrue(CombatCommentary.attackCall(.cross, attacker: "PLAYER", language: .korean).contains("오른손 크로스"))
        XCTAssertTrue(CombatCommentary.impact(.leftHook, attacker: "PLAYER", language: .korean).contains("훅"))
        XCTAssertTrue(CombatCommentary.impact(.rightUppercut, attacker: "PLAYER", language: .korean).contains("어퍼컷"))
        XCTAssertTrue(CombatCommentary.guardBlock(defender: "PLAYER", language: .korean).contains("가드"))
        XCTAssertTrue(CombatCommentary.duckEvade(defender: "PLAYER", isPlayerDefender: true, language: .korean).contains("더킹"))
        XCTAssertTrue(CombatCommentary.whiff(attacker: "PLAYER", isPlayerAttacker: true, language: .korean).contains("반격"))
        XCTAssertTrue(CombatCommentary.knockout(winner: "PLAYER", language: .korean).contains("K.O."))
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
        // Default player style is `.standard`, which gets a 0.88x punch-stamina discount: 13 * 0.88 = 11.44.
        XCTAssertEqual(engine.player.stamina, 100 - 13 * FightStyle.standard.punchStaminaMultiplier, accuracy: 0.001)
        XCTAssertEqual(engine.habits.attackCounts[.jab], 0)
        engine.player.attack = nil
        engine.finishRound(outcome: .playerWin, knockout: false)
        XCTAssertEqual(engine.habits.attackCounts[.jab], 1)
        XCTAssertEqual(engine.habits.snapshot.favoriteAttack, .jab)
    }

    func testAdaptationDependsOnConfirmedProfileNotRoundNumber() {
        var habits = HabitMemory()
        let initial = habits.snapshot.adaptation()
        habits.sample(deltaTime: 3, guarding: true, duckDirection: 0, backstep: false, forwardAxis: 0)
        XCTAssertGreaterThan(habits.snapshot.adaptation(), initial)
    }

    func testGuardHeavyPlayerRaisesBodyShotWeight() {
        var habits = HabitMemory()
        habits.sample(deltaTime: 3, guarding: true, duckDirection: 0, backstep: false, forwardAxis: 0)
        let weights = habits.snapshot.enemyWeights(distance: 60, playerExposed: false)
        XCTAssertGreaterThan(weights[Punch.rightBody.rawValue, default: 0], weights[Punch.jab.rawValue, default: 0])
    }

    func testRetreatingProfileRaisesDistanceCutoffWeight() {
        var retreatingHabits = HabitMemory()
        retreatingHabits.sample(deltaTime: 3, guarding: false, duckDirection: 0, backstep: true, forwardAxis: -1)

        let baseline = HabitMemory().snapshot.enemyWeights(distance: 95, playerExposed: false)
        let adjusted = retreatingHabits.snapshot.enemyWeights(distance: 95, playerExposed: false)

        XCTAssertGreaterThan(adjusted["cut_off", default: 0], baseline["cut_off", default: 0])
        XCTAssertGreaterThan(adjusted["advance", default: 0], baseline["advance", default: 0])
    }

    func testRecentJabPatternAddsCounterWeights() {
        var habits = HabitMemory()
        for _ in 0..<4 { habits.noteAttack(.jab) }

        let read = habits.rivalRead
        XCTAssertEqual(read.kind, .jabPattern)
        XCTAssertGreaterThan(read.confidence, 0.6)

        let baseline = habits.snapshot.enemyWeights(distance: 85, playerExposed: false)
        let adjusted = habits.snapshot.enemyWeights(distance: 85, playerExposed: false, rivalRead: read)
        XCTAssertGreaterThan(adjusted[Punch.cross.rawValue, default: 0], baseline[Punch.cross.rawValue, default: 0])
        XCTAssertGreaterThan(adjusted[Punch.rightHook.rawValue, default: 0], baseline[Punch.rightHook.rawValue, default: 0])
    }

    func testCombatEnginePublishesConfirmedRoundRead() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()

        for _ in 0..<4 {
            XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))
            engine.player.attack = nil
        }

        XCTAssertEqual(engine.snapshot.rivalRead, .jabPattern)
        XCTAssertGreaterThan(engine.snapshot.rivalReadConfidence, 0.6)
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

    func testKnockoutBlowStartsDedicatedKoMomentSlowMotionAndZoom() {
        let engine = closeRangeEngine()
        engine.enemy.hp = 5
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        advanceToActiveFrame(engine)

        XCTAssertEqual(engine.enemy.hp, 0)
        XCTAssertTrue(engine.lastRoundWasKnockout)
        XCTAssertEqual(engine.koMomentTime, CombatData.koMomentDuration, accuracy: 0.001)

        // The KO beat decays in real seconds and forces the strongest available slow-motion scale,
        // overriding whatever dodge-focus scale (if any) was active, so the finishing blow always reads
        // as unmistakably dramatic. `update(deltaTime:)` clamps each call's raw delta to 0.05s, so a
        // single 0.1s call still only advances real time by 0.05s.
        engine.update(deltaTime: 0.1)
        XCTAssertEqual(engine.koMomentTime, CombatData.koMomentDuration - 0.05, accuracy: 0.001)
    }

    func testRivalMomentStartsAtPerfectPlayerDodgeBeforeCounterInput() {
        let playerDuck = closeRangeEngine()
        XCTAssertTrue(playerDuck.startAttack(playerDuck.enemy, punch: .cross))
        advance(playerDuck, frames: 1)
        playerDuck.setDuck(-1, active: true)
        advance(playerDuck, frames: 2)

        XCTAssertEqual(playerDuck.lastPlayerDodgeGrade, .perfect)
        XCTAssertEqual(playerDuck.rivalMomentGrade, .perfect)
        XCTAssertEqual(playerDuck.rivalMomentTime, DodgeGrade.perfect.focusDuration, accuracy: 0.001)
        XCTAssertGreaterThan(playerDuck.enemy.exposed, 0)
        XCTAssertNil(playerDuck.player.attack)
        playerDuck.update(deltaTime: 0.05)
        XCTAssertEqual(
            playerDuck.enemy.actionTime,
            0.15 + 0.05 * DodgeGrade.perfect.timeScale,
            accuracy: 0.001
        )
    }

    func testEarlyPlayerDuckIsNormalAndRivalDuckCannotStartRivalMoment() {
        let earlyDuck = closeRangeEngine()
        earlyDuck.setDuck(1, active: true)
        advance(earlyDuck, frames: 7)
        XCTAssertTrue(earlyDuck.startAttack(earlyDuck.enemy, punch: .jab))
        advanceToActiveFrame(earlyDuck)

        XCTAssertEqual(earlyDuck.lastPlayerDodgeGrade, .normal)
        XCTAssertEqual(earlyDuck.rivalMomentTime, 0, accuracy: 0.001)

        let rivalDuck = closeRangeEngine()
        XCTAssertTrue(rivalDuck.performEnemyDecision("dodge_right"))
        XCTAssertTrue(rivalDuck.startAttack(rivalDuck.player, punch: .jab))
        advanceToActiveFrame(rivalDuck)

        XCTAssertEqual(rivalDuck.rivalMomentTime, 0, accuracy: 0.001)
    }

    func testPerfectDodgeCounterUsesAttackInputCapturedInsideWindow() {
        let engine = closeRangeEngine()
        XCTAssertTrue(engine.startAttack(engine.enemy, punch: .cross))
        advance(engine, frames: 1)
        engine.setDuck(-1, active: true)
        advance(engine, frames: 2)
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        // The Perfect RIVAL MOMENT beat now slows engine time much more aggressively (bolder zoom +
        // slow-motion per design direction), so more real frames must pass before the jab's active frame
        // is reached -- the counter input itself is still captured instantly at attack-start time either way.
        advanceUntilPlayerAttackResolves(engine)

        XCTAssertEqual(engine.perfectCounterCount, 1)
        XCTAssertTrue(engine.message.contains("PERFECT COUNTER"))
    }

    func testDuckCounterBodyAndHookBonusesAreVisibleInDamageAndCommentary() {
        let bodyEngine = closeRangeEngine()
        bodyEngine.setDuck(-1, active: true)
        XCTAssertTrue(bodyEngine.startAttack(bodyEngine.enemy, punch: .cross))
        advance(bodyEngine, frames: 3)
        XCTAssertEqual(bodyEngine.player.hp, 100)
        advance(bodyEngine, frames: 2)
        XCTAssertTrue(bodyEngine.startAttack(bodyEngine.player, punch: .leftBody))
        // This setup is Accurate; wait for resolution instead of assuming a particular time scale.
        advanceUntilPlayerAttackResolves(bodyEngine)
        XCTAssertEqual(bodyEngine.enemy.hp, 84)
        XCTAssertTrue(bodyEngine.message.contains("바디/훅 보너스 피해 16"))

        let hookEngine = closeRangeEngine()
        hookEngine.setDuck(1, active: true)
        // A small extra gap before the jab starts keeps this dodge graded Accurate rather than Perfect
        // (jab's active frame arrives very early), so this stays a plain countered-hit assertion instead
        // of tripping the separate PERFECT COUNTER message override (covered by its own dedicated test).
        advance(hookEngine, frames: 1)
        XCTAssertTrue(hookEngine.startAttack(hookEngine.enemy, punch: .jab))
        advanceToActiveFrame(hookEngine)
        XCTAssertEqual(hookEngine.player.hp, 100)
        advance(hookEngine, frames: 2)
        XCTAssertTrue(hookEngine.startAttack(hookEngine.player, punch: .leftHook))
        advanceUntilPlayerAttackResolves(hookEngine)
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
        // Commentary is now asymmetric: when the AI (not the player) is the one who ducks, the message warns
        // the player they're exposed rather than praising "완벽한 더킹" (that phrasing is player-duck-only).
        XCTAssertTrue(engine.message.contains("완벽하게 피했습니다"))
    }

    func testRivalCircleDecisionMovesLaterally() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        engine.enemy.x = 330
        engine.enemy.y = 295

        XCTAssertTrue(engine.performEnemyDecision("circle_left"))
        engine.update(deltaTime: 0.05)

        XCTAssertNotEqual(engine.enemy.y, 295)
    }

    func testLearningResetRestartsAtRoundOne() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        engine.finishRound(outcome: .playerWin, knockout: false)
        advance(engine, frames: 40)
        // Round advancement is no longer automatic once the round-break timer expires -- the player must
        // explicitly confirm via `requestNextRound()` (round-result overlay's "next round" button).
        engine.requestNextRound()
        XCTAssertEqual(engine.round, 2)
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))

        engine.resetLearning()

        XCTAssertEqual(engine.round, 1)
        XCTAssertEqual(engine.playerScore, 0)
        XCTAssertEqual(engine.enemyScore, 0)
        XCTAssertEqual(engine.phase, .fight)
        XCTAssertTrue(engine.habits.attackCounts.values.allSatisfy { $0 == 0 })
        // `resetLearning()`'s message is now the localized "학습 초기화"-style string (`learningResetMessage`),
        // not a hardcoded "ROUND 1" -- just confirm it's non-empty rather than asserting exact copy here.
        XCTAssertFalse(engine.message.isEmpty)
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

    func testCounterWindowExpiresAndLateAttackIsNotCounter() {
        let engine = closeRangeEngine()
        XCTAssertTrue(engine.startAttack(engine.enemy, punch: .cross))
        advance(engine, frames: 1)
        engine.setDuck(-1, active: true)
        advance(engine, frames: 2)
        XCTAssertEqual(engine.lastPlayerDodgeGrade, .perfect)

        // Wait past both the dodge-captured counter window and exposed time.
        advance(engine, frames: 25)

        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        advanceUntilPlayerAttackResolves(engine)

        XCTAssertEqual(engine.perfectCounterCount, 0)
        XCTAssertEqual(engine.enemy.hp, 94)
        XCTAssertFalse(engine.message.contains("PERFECT COUNTER"))
    }

    func testExhaustionLocksActionsThenRecovers() {
        let engine = closeRangeEngine()
        engine.player.stamina = CombatData.backstepStaminaCost

        XCTAssertTrue(engine.backstep())
        XCTAssertEqual(engine.player.stamina, 0, accuracy: 0.001)
        XCTAssertGreaterThan(engine.player.exhausted, 0)

        let lockedX = engine.player.x
        engine.setMove(x: 1, y: 0)
        engine.setGuarding(true)
        engine.setDuck(1, active: true)

        XCTAssertFalse(engine.startAttack(engine.player, punch: .jab))
        XCTAssertFalse(engine.backstep())

        engine.update(deltaTime: 0.05)
        XCTAssertEqual(engine.player.x, lockedX, accuracy: 0.001)
        XCTAssertFalse(engine.player.guarding)
        XCTAssertEqual(engine.player.duckDirection, 0)

        advance(engine, frames: 20)
        XCTAssertEqual(engine.player.exhausted, 0, accuracy: 0.0001)

        engine.setGuarding(true)
        XCTAssertTrue(engine.player.guarding)
    }

    func testWhiffSetsExposedThenClearsByTimer() {
        let engine = CombatEngine(persistHabits: false)
        engine.startRound()

        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        advance(engine, frames: 10)

        XCTAssertNil(engine.player.attack)
        XCTAssertGreaterThan(engine.player.exposed, 0)
        XCTAssertTrue(engine.message.contains("조심하세요"))

        advance(engine, frames: 30)
        XCTAssertEqual(engine.player.exposed, 0, accuracy: 0.0001)
    }

    func testDuckEvadeMessageMatchesWhoIsActuallyExposed() {
        let playerDodges = closeRangeEngine()
        XCTAssertTrue(playerDodges.startAttack(playerDodges.enemy, punch: .cross))
        advance(playerDodges, frames: 1)
        playerDodges.setDuck(-1, active: true)
        advanceToActiveFrame(playerDodges)
        XCTAssertTrue(playerDodges.message.contains("카운터 타이밍"))

        let rivalDodges = closeRangeEngine()
        XCTAssertTrue(rivalDodges.performEnemyDecision("dodge_right"))
        XCTAssertTrue(rivalDodges.startAttack(rivalDodges.player, punch: .jab))
        advanceToActiveFrame(rivalDodges)
        XCTAssertTrue(rivalDodges.message.contains("당신이 노출"))
    }

    func testTwentyMinuteSessionRemainsStableAndResponsive() {
        let engine = CombatEngine(persistHabits: false)
        engine.startSession()
        let frames = Int((20.0 * 60.0) / 0.05)

        for frame in 0..<frames {
            if engine.snapshot.canAdvanceRound {
                engine.requestNextRound()
            }

            if frame % 120 == 0 {
                switch (frame / 120) % 4 {
                case 0: engine.setMove(x: 1, y: 0)
                case 1: engine.setMove(x: 0, y: 1)
                case 2: engine.setMove(x: -1, y: 0)
                default: engine.setMove(x: 0, y: -1)
                }
            }
            if frame % 90 == 0 {
                engine.setGuarding((frame / 90) % 2 == 0)
            }
            if frame % 110 == 0 {
                let direction = ((frame / 110) % 2 == 0) ? -1 : 1
                engine.setDuck(direction, active: true)
            }
            if frame % 110 == 25 {
                engine.setDuck(0, active: false)
            }
            if frame % 75 == 0 {
                _ = engine.startAttack(engine.player, punch: .jab, recordsHabit: true)
            }
            if frame % 150 == 0 {
                _ = engine.backstep()
            }

            engine.update(deltaTime: 0.05)
            assertFighterStateStable(engine.player)
            assertFighterStateStable(engine.enemy)

            if frame % 300 == 0 {
                let snapshot = engine.snapshot
                XCTAssertTrue(snapshot.time.isFinite)
                XCTAssertFalse(snapshot.message.isEmpty)
            }
        }

        engine.setMove(x: 0, y: 0)
        engine.setGuarding(false)
        engine.setDuck(0, active: false)
        engine.update(deltaTime: 0.05)

        XCTAssertEqual(engine.moveX, 0, accuracy: 0.0001)
        XCTAssertEqual(engine.moveY, 0, accuracy: 0.0001)
        XCTAssertEqual(engine.player.duckDirection, 0)
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

    /// Stop at hit resolution, whiff completion or round end; do not wait through unrelated recovery.
    private func advanceUntilPlayerAttackResolves(_ engine: CombatEngine, maxFrames: Int = 200) {
        var frames = 0
        while engine.phase == .fight, engine.player.attack != nil, !engine.player.acted, frames < maxFrames {
            engine.update(deltaTime: 0.05)
            frames += 1
        }
        XCTAssertLessThan(frames, maxFrames, "Player attack never resolved")
    }

    private func assertFighterStateStable(_ fighter: FighterModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(fighter.x.isFinite, file: file, line: line)
        XCTAssertTrue(fighter.y.isFinite, file: file, line: line)
        XCTAssertTrue(fighter.facingX.isFinite, file: file, line: line)
        XCTAssertTrue(fighter.facingY.isFinite, file: file, line: line)
        XCTAssertTrue(fighter.stamina.isFinite, file: file, line: line)
        XCTAssertTrue(fighter.actionTime.isFinite, file: file, line: line)
        XCTAssertTrue(fighter.exposed.isFinite, file: file, line: line)
        XCTAssertTrue(fighter.exhausted.isFinite, file: file, line: line)
        XCTAssertTrue(fighter.hitReaction.isFinite, file: file, line: line)
        XCTAssertGreaterThanOrEqual(fighter.hp, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(fighter.hp, 100, file: file, line: line)
        XCTAssertGreaterThanOrEqual(fighter.stamina, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(fighter.stamina, 100, file: file, line: line)
    }
}
