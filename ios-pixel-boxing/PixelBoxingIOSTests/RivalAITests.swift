import XCTest
@testable import RIVAL

@MainActor
final class RivalAITests: XCTestCase {
    func testExperienceGrowsBeyondEarlySampleSaturationWithoutStatBuffs() {
        let rounds = [1, 5, 20, 50, 100, 200, 1_000]
        var previous = RivalDifficulty(round: 1)
        for round in rounds {
            let skill = RivalDifficulty(round: round)
            XCTAssertGreaterThanOrEqual(skill.experience, previous.experience)
            XCTAssertLessThanOrEqual(skill.decisionInterval, previous.decisionInterval)
            XCTAssertGreaterThanOrEqual(skill.learningWeight, previous.learningWeight)
            XCTAssertLessThan(skill.movementEffort, 1)
            XCTAssertLessThan(skill.reactionChance, 1)
            XCTAssertGreaterThan(skill.reactionDelay, 0.05)
            let engine = CombatEngine(persistHabits: false, initialRound: round, randomSeed: 1)
            engine.resumeSession()
            XCTAssertEqual(engine.round, round)
            XCTAssertEqual(engine.player.hp, 100)
            XCTAssertEqual(engine.enemy.hp, 100)
            XCTAssertEqual(engine.enemy.style.damageMultiplier, engine.player.style.damageMultiplier)
            previous = skill
        }
        XCTAssertEqual(CombatData.attacks[.jab]?.damage, 6)
        XCTAssertEqual(CombatData.attacks[.cross]?.activeStart, 0.14)
    }

    func testNewGameReturnsToBeginnerExecution() {
        let engine = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 1)
        engine.resumeSession()
        XCTAssertGreaterThan(engine.rivalDifficulty.experience, 0.9)
        engine.resetLearning()
        XCTAssertEqual(engine.round, 1)
        XCTAssertEqual(engine.rivalDifficulty.experience, 0)
    }

    func testForwardLearningIsIndependentOfFacingAndBlockedMovementIsExcluded() {
        for offset in [(100.0, 0.0), (-100.0, 0.0), (0.0, 100.0), (0.0, -100.0)] {
            for guarding in [false, true] {
                let engine = CombatEngine(persistHabits: false, randomSeed: 2)
                engine.startSession()
                engine.player.x = 295; engine.player.y = 295
                engine.enemy.x = 295 + offset.0; engine.enemy.y = 295 + offset.1
                engine.enemy.stagger = 100
                engine.setMove(x: 1, y: 0)
                engine.setGuarding(guarding)
                for _ in 0..<5 { engine.update(deltaTime: 0.05) }
                engine.finishRound(outcome: .draw, knockout: false)
                XCTAssertEqual(engine.habits.snapshot.pressureRatio, guarding ? 0 : 1, accuracy: 0.00001)
                XCTAssertEqual(engine.habits.snapshot.retreatRatio, 0)
            }
        }
    }

    func testActionMaskUsesActualStyleReachAndStamina() throws {
        let engine = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 5)
        engine.resumeSession()
        for style in FightStyle.allCases {
            engine.enemy.style = style
            for stamina in [0.0, 12.0, 100.0] {
                engine.enemy.stamina = stamina
                for distance in [50.0, 80.0, 120.0] {
                    let weights = engine.enemyActionWeights(distance: distance)
                    for punch in Punch.allCases {
                        let spec = try XCTUnwrap(CombatData.attacks[punch])
                        let legal = stamina >= spec.staminaCost * style.punchStaminaMultiplier && distance <= spec.range * style.reachMultiplier + 17
                        XCTAssertEqual(weights[punch.rawValue, default: 0] > 0, legal)
                    }
                }
            }
        }
    }

    func testRivalClosesDeadZoneAndCirclesAtFightingDistance() {
        for distance in [70.0, 100.0, 110.0] {
            let engine = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 3)
            engine.resumeSession()
            engine.player.x = 250; engine.enemy.x = 250 + distance
            let oldX = engine.enemy.x
            let oldY = engine.enemy.y
            engine.update(deltaTime: 0.05)
            if distance >= 100 { XCTAssertLessThan(engine.enemy.x, oldX) }
            if distance == 70 { XCTAssertNotEqual(engine.enemy.y, oldY) }
            XCTAssertEqual(engine.player.hp, 100)
        }
    }

    func testRivalCannotActThroughStaggerOrExhaustionAndBackstepUsesSharedCost() {
        let engine = CombatEngine(persistHabits: false, randomSeed: 8)
        engine.resumeSession()
        for exhausted in [false, true] {
            engine.enemy.stagger = exhausted ? 0 : 1
            engine.enemy.exhausted = exhausted ? 1 : 0
            for action in ["guard", "dodge_left", "dodge_back", "advance", Punch.jab.rawValue] {
                XCTAssertFalse(engine.performEnemyDecision(action))
            }
            XCTAssertEqual(engine.enemy.stamina, 100)
        }
        engine.enemy.exhausted = 0
        engine.enemy.stagger = 0
        XCTAssertTrue(engine.performEnemyDecision("dodge_back"))
        XCTAssertEqual(engine.enemy.stamina, 100 - CombatData.backstepStaminaCost * engine.enemy.style.backstepStaminaMultiplier)
        XCTAssertEqual(engine.enemy.invulnerable, CombatData.backstepDuration)
    }

    func testSeedReproducesOpponentMovementAndDecisions() {
        let first = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 99)
        let second = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 99)
        first.resumeSession(); second.resumeSession()
        for _ in 0..<600 {
            first.update(deltaTime: 1.0 / 60)
            second.update(deltaTime: 1.0 / 60)
            XCTAssertEqual(first.enemy.x, second.enemy.x)
            XCTAssertEqual(first.enemy.y, second.enemy.y)
            XCTAssertEqual(first.enemy.attack, second.enemy.attack)
            XCTAssertEqual(first.player.hp, second.player.hp)
        }
    }

    func testRepeatedPunchesHaveDistinctObservationIdentity() {
        let engine = CombatEngine(persistHabits: false, randomSeed: 2)
        engine.resumeSession()
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        let first = engine.player.attackSerial
        engine.player.attack = nil
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        XCTAssertEqual(engine.player.attackSerial, first + 1)
    }
}