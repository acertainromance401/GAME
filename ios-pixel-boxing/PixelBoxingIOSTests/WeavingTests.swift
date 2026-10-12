import Foundation
import XCTest
#if !WEAVING_PROBE
@testable import RIVAL
#endif

@MainActor
private func match(distance: Double = 60) -> CombatEngine {
    let engine = CombatEngine(persistHabits: false, randomSeed: 7)
    engine.startSession()
    engine.player.x = 250
    engine.player.y = 295
    engine.enemy.x = 250 + distance
    engine.enemy.y = 295
    engine.enemy.stagger = 100 // Freeze AI, not the attack resolution code under test.
    return engine
}

@MainActor
private func gym(radius: Double = 60) -> PracticeEngine {
    let engine = PracticeEngine()
    engine.player.x = PracticeEngine.bagX - radius
    engine.player.y = PracticeEngine.bagY
    return engine
}

@MainActor
private func advance(_ seconds: Double, fps: Double = 120, update: (Double) -> Void) {
    var remaining = seconds
    while remaining > 1e-10 {
        let dt = min(remaining, 1 / fps)
        update(dt)
        remaining -= dt
    }
}

@MainActor
private func incoming(_ punch: Punch, to engine: CombatEngine) {
    engine.enemy.stagger = 0
    XCTAssertTrue(engine.startAttack(engine.enemy, punch: punch))
    engine.enemy.stagger = 100
    engine.enemy.actionTime = CombatData.attacks[punch]!.activeStart - 0.005
}

/// The same XCTest bodies run against the actual app sources in check_weaving.sh, without UI.
/// MainActor.assumeIsolated avoids actor-qualified XCTest discovery thunks on the native runner.
/// Helpers are free functions, so closures never transfer a non-Sendable XCTestCase across actors.
final class WeavingTests: XCTestCase {
    func testRivalWeaveHasNoOrdinaryMovementEvenOnFinalTick() {
        MainActor.assumeIsolated {
            for fps in [30.0, 60, 120] {
                for direction in [-1, 1] {
                    let engine = match()
                    engine.enemy.stagger = 0
                    engine.enemy.facingX = -1
                    XCTAssertTrue(engine.enemy.beginWeave(direction: direction))
                    let x = engine.enemy.x, y = engine.enemy.y
                    advance(0.36, fps: fps, update: engine.update)
                    XCTAssertEqual(engine.enemy.x, x, accuracy: 1e-8)
                    XCTAssertEqual(engine.enemy.y, y - Double(direction) * 12, accuracy: 1e-8)
                    XCTAssertFalse(engine.enemy.weave.isActive)
                    XCTAssertNil(engine.enemy.attack)
                }
            }
        }
    }

    func testRivalCannotReadBufferedHookBeforeVisibleAttackStarts() {
        MainActor.assumeIsolated {
            let plain = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 19)
            let buffered = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 19)
            for engine in [plain, buffered] {
                engine.resumeSession()
                engine.player.x = 250; engine.enemy.x = 305
                XCTAssertTrue(engine.weave(direction: -1))
            }
            XCTAssertTrue(buffered.requestWeaveHook(base: .jab))
            advance(0.21) { dt in
                plain.update(deltaTime: dt); buffered.update(deltaTime: dt)
                XCTAssertEqual(plain.enemy.x, buffered.enemy.x)
                XCTAssertEqual(plain.enemy.y, buffered.enemy.y)
                XCTAssertEqual(plain.enemy.attack, buffered.enemy.attack)
                XCTAssertEqual(plain.enemy.duckDirection, buffered.enemy.duckDirection)
                XCTAssertEqual(plain.enemy.guarding, buffered.enemy.guarding)
                XCTAssertEqual(plain.enemyActionWeights(distance: 55), buffered.enemyActionWeights(distance: 55))
            }
            XCTAssertEqual(buffered.player.attackSerial, 0)
            XCTAssertTrue(buffered.roundPlayerPunchCounts.isEmpty)
        }
    }

    func testStateBoundariesAndStrictHookMapping() {
        for direction in [-1, 1] {
            for elapsed in [0.0, 0.059, 0.06, 0.219, 0.22, 0.239, 0.24, 0.359, 0.36, 0.479, 0.48] {
                var state = WeaveState()
                XCTAssertTrue(state.start(direction))
                state.advance(elapsed)
                XCTAssertEqual(state.isActive, elapsed < 0.36)
                XCTAssertEqual(state.comboDirection, elapsed < 0.48 ? direction : 0)
                for punch in Punch.allCases {
                    XCTAssertEqual(state.evades(punch), elapsed >= 0.06 && elapsed < 0.24
                                   && CombatData.requiredDuck[punch] == direction)
                    let expected: Punch? = direction == -1 && punch == .jab ? .leftHook
                        : (direction == 1 && punch == .cross ? .rightHook : nil)
                    XCTAssertEqual(WeaveState.hook(base: punch, direction: direction), expected)
                }
            }
        }
        var state = WeaveState()
        for direction in [-2, 0, 2] { XCTAssertFalse(state.start(direction)) }
        XCTAssertFalse(state.start(1, facingX: .nan))
        XCTAssertFalse(state.start(1, facingX: 0, facingY: 0))
        XCTAssertTrue(state.start(1))
        let unchanged = state
        for dt in [Double.nan, .infinity, -1, 0] { state.advance(dt) }
        XCTAssertEqual(state, unchanged)
        XCTAssertTrue(state.queueHook(base: .cross))
        XCTAssertFalse(state.queueHook(base: .cross))
        state.advance(0.219)
        XCTAssertNil(state.takeReadyHook())
        state.advance(0.001)
        XCTAssertEqual(state.takeReadyHook(), .rightHook)
        XCTAssertNil(state.takeReadyHook())
        XCTAssertEqual(state.comboDirection, 0)
        XCTAssertTrue(state.isActive) // Pose continues; attack presence disables evasion.
        state.cancel()
        XCTAssertFalse(state.start(-1)) // Cancellation cannot reset cooldown.
        XCTAssertEqual(state.advance(0.26).x, 0)
        XCTAssertTrue(state.start(-1))
        state.reset()
        XCTAssertEqual(state, WeaveState())
    }

    func testCumulativeTravelAt30_60_120FPSAndFrozenBasis() {
        for fps in [30.0, 60, 120] {
            for direction in [-1, 1] {
                for facing in [(1.0, 0.0), (0.0, -1.0), (-0.6, 0.8)] {
                    var state = WeaveState()
                    XCTAssertTrue(state.start(direction, facingX: facing.0, facingY: facing.1))
                    var x = 0.0, y = 0.0, path = 0.0
                    for _ in 0..<Int(fps) {
                        let step = state.advance(1 / fps)
                        x += step.x; y += step.y; path += hypot(step.x, step.y)
                        XCTAssertLessThanOrEqual(path, 12 + 1e-10)
                        if state.elapsed <= 0.06 { XCTAssertEqual(path, 0) }
                    }
                    XCTAssertEqual(x, -facing.1 * Double(direction) * 12, accuracy: 1e-9)
                    XCTAssertEqual(y, facing.0 * Double(direction) * 12, accuracy: 1e-9)
                    XCTAssertEqual(path, 12, accuracy: 1e-9)
                }
            }
        }
        MainActor.assumeIsolated {
            let engine = match()
            XCTAssertTrue(engine.weave(direction: 1))
            // Rotate the actual target mid-weave; the step stays on the original +Y basis.
            engine.enemy.x = 400; engine.enemy.y = 450
            advance(0.36, update: engine.update)
            XCTAssertEqual(engine.player.x, 250, accuracy: 1e-9)
            XCTAssertEqual(engine.player.y, 307, accuracy: 1e-9)
            XCTAssertNotEqual(engine.player.facingY, 0)
            XCTAssertEqual(engine.player.actionTime, 0)
        }
    }

    func testRealMovementHasNoExtraOrdinaryStepAndStaysInsideClamps() {
        MainActor.assumeIsolated {
            for fps in [30.0, 60, 120] {
                for direction in [-1, 1] {
                    let engine = match()
                    let practice = gym()
                    engine.setMove(x: 1, y: 1)
                    practice.setMove(x: 1, y: 1)
                    XCTAssertTrue(engine.weave(direction: direction))
                    XCTAssertTrue(practice.weave(direction: direction))
                    advance(0.36, fps: fps) { dt in
                        engine.update(deltaTime: dt); practice.update(deltaTime: dt)
                    }
                    XCTAssertEqual(engine.player.x, 250, accuracy: 1e-8)
                    XCTAssertEqual(engine.player.y, 295 + 12 * Double(direction), accuracy: 1e-8)
                    XCTAssertEqual(practice.player.x, 235, accuracy: 1e-8)
                    XCTAssertEqual(practice.player.y, engine.player.y, accuracy: 1e-8)
                    XCTAssertEqual(practice.player.weave, engine.player.weave)
                }
            }
            for direction in [-1, 1] {
                for corner in [(104.0, 104.0), (104.0, 486.0), (486.0, 104.0), (486.0, 486.0)] {
                    let engine = match()
                    engine.player.x = corner.0; engine.player.y = corner.1
                    engine.enemy.x = 295; engine.enemy.y = 295
                    XCTAssertTrue(engine.weave(direction: direction))
                    advance(0.36) { dt in
                        engine.update(deltaTime: dt)
                        XCTAssertTrue((104...486).contains(engine.player.x))
                        XCTAssertTrue((104...486).contains(engine.player.y))
                        XCTAssertLessThanOrEqual(hypot(engine.player.x - corner.0, engine.player.y - corner.1), 12 + 1e-8)
                    }
                }
                for radius in [54.0, 185.0] {
                    let practice = gym(radius: radius)
                    let x = practice.player.x, y = practice.player.y
                    XCTAssertTrue(practice.weave(direction: direction))
                    advance(0.36) { dt in
                        practice.update(deltaTime: dt)
                        let distance = hypot(practice.player.x - 295, practice.player.y - 295)
                        XCTAssertGreaterThanOrEqual(distance, 54 - 1e-8)
                        XCTAssertLessThanOrEqual(distance, 185 + 1e-8)
                        XCTAssertLessThanOrEqual(hypot(practice.player.x - x, practice.player.y - y), 12 + 1e-8)
                    }
                }
            }
            let collision = match()
            XCTAssertTrue(collision.weave(direction: 1))
            collision.enemy.x = 250; collision.enemy.y = 345
            advance(0.36) { dt in
                collision.update(deltaTime: dt)
                XCTAssertGreaterThanOrEqual(hypot(collision.player.x - collision.enemy.x,
                                                 collision.player.y - collision.enemy.y), 50 - 1e-8)
            }
        }
    }

    func testMatchPaysAndGymIsFreeWithSameCooldownAndActionGates() {
        MainActor.assumeIsolated {
            for direction in [-1, 1] {
                for style in FightStyle.allCases {
                    let engine = match()
                    let practice = gym()
                    engine.player.style = style; practice.player.style = style
                    XCTAssertTrue(engine.weave(direction: direction))
                    XCTAssertTrue(practice.weave(direction: direction))
                    for _ in 0..<20 {
                        XCTAssertFalse(engine.weave(direction: -direction))
                        XCTAssertFalse(practice.weave(direction: -direction))
                    }
                    XCTAssertEqual(engine.player.stamina, 88)
                    XCTAssertEqual(practice.player.stamina, 100)
                    XCTAssertEqual(practice.player.exhausted, 0)
                    XCTAssertFalse(engine.backstep()); XCTAssertFalse(practice.backstep())
                    XCTAssertFalse(engine.startAttack(engine.player, punch: .jab))
                    XCTAssertFalse(practice.startAttack(.jab))
                    engine.setGuarding(true); practice.setGuarding(true)
                    engine.setDuck(-direction, active: true); practice.setDuck(-direction, active: true)
                    XCTAssertFalse(engine.player.guarding); XCTAssertFalse(practice.player.guarding)
                    XCTAssertEqual(engine.player.duckDirection, 0); XCTAssertEqual(practice.player.duckDirection, 0)
                    advance(0.36) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                    XCTAssertFalse(engine.player.weave.isActive)
                    XCTAssertFalse(engine.weave(direction: direction)); XCTAssertFalse(practice.weave(direction: direction))
                    advance(0.119) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                    XCTAssertFalse(engine.weave(direction: direction)); XCTAssertFalse(practice.weave(direction: direction))
                    advance(0.001) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                    XCTAssertTrue(engine.weave(direction: direction)); XCTAssertTrue(practice.weave(direction: direction))
                }
            }
        }
    }

    func testSharedStartGatesButOnlyMatchRequiresStamina() {
        MainActor.assumeIsolated {
            // Artificial locks verify the shared predicate; gym actions never create exhaustion.
            for blocked in ["attack", "stagger", "exhausted", "ko", "hp", "backstep"] {
                let engine = match()
                let practice = gym()
                for player in [engine.player, practice.player] {
                    switch blocked {
                    case "attack": player.attack = .jab
                    case "stagger": player.stagger = 1
                    case "exhausted": player.exhausted = 1
                    case "ko": player.knockedOut = true
                    case "hp": player.hp = 0
                    default: player.invulnerable = 0.1
                    }
                }
                let costBefore = engine.player.stamina
                XCTAssertFalse(engine.weave(direction: 1), blocked)
                XCTAssertFalse(practice.weave(direction: 1), blocked)
                XCTAssertEqual(engine.player.stamina, costBefore)
                XCTAssertEqual(practice.player.stamina, costBefore)
            }
            for stamina in [0.0, 11.99] {
                for direction in [-1, 1] {
                    let engine = match(), practice = gym()
                    engine.player.stamina = stamina; practice.player.stamina = stamina
                    XCTAssertFalse(engine.weave(direction: direction))
                    XCTAssertTrue(practice.weave(direction: direction))
                    XCTAssertEqual(engine.player.stamina, stamina)
                    XCTAssertEqual(practice.player.stamina, stamina) // Opt-out never debits.
                    XCTAssertEqual(practice.player.exhausted, 0)
                    practice.update(deltaTime: 0.01)
                    XCTAssertEqual(practice.player.stamina, 100)
                    XCTAssertEqual(practice.player.exhausted, 0)
                }
            }
            let intro = CombatEngine(persistHabits: false)
            XCTAssertFalse(intro.weave(direction: 1))
        }
    }

    func testExactZeroMatchWeaveExhaustsAndReservesNoMovementOrEvasion() {
        MainActor.assumeIsolated {
            for fps in [30.0, 60, 120] {
                for direction in [-1, 1] {
                    let engine = match(), practice = gym()
                    engine.player.stamina = 12; practice.player.stamina = 12
                    XCTAssertTrue(engine.weave(direction: direction)); XCTAssertTrue(practice.weave(direction: direction))
                    XCTAssertEqual(engine.exhaustionCount, 1)
                    XCTAssertEqual(engine.player.stamina, 0)
                    XCTAssertEqual(engine.player.exhausted, CombatData.exhaustionDuration)
                    XCTAssertEqual(engine.player.exposed, CombatData.exhaustionExposed)
                    XCTAssertFalse(engine.player.weave.isActive)
                    XCTAssertEqual(engine.player.weave.comboDirection, 0)
                    XCTAssertEqual(engine.player.weave.cooldownRemaining, WeaveState.duration + WeaveState.inputGrace)
                    XCTAssertEqual(practice.player.stamina, 12)
                    XCTAssertEqual(practice.player.exhausted, 0)
                    XCTAssertTrue(practice.player.weave.isActive)
                    let base: Punch = direction < 0 ? .jab : .cross
                    XCTAssertFalse(engine.requestWeaveHook(base: base))
                    // No immediate step was made: exhaustion cancels all future weave travel.
                    advance(0.36, fps: fps) { dt in
                        engine.update(deltaTime: dt); practice.update(deltaTime: dt)
                        XCTAssertEqual(engine.player.x, 250)
                        XCTAssertEqual(engine.player.y, 295)
                        XCTAssertEqual(engine.player.invulnerable, 0)
                        XCTAssertFalse(engine.player.weave.isActive)
                        for punch in Punch.allCases { XCTAssertFalse(engine.player.weave.evades(punch)) }
                        XCTAssertEqual(practice.player.stamina, 100)
                        XCTAssertEqual(practice.player.exhausted, 0)
                    }
                    XCTAssertEqual(practice.player.y, 295 + Double(direction) * 12, accuracy: 1e-8)
                    XCTAssertEqual(engine.player.stamina, 0)
                    advance(0.8, fps: fps) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                    XCTAssertGreaterThan(engine.player.stamina, 0)
                    XCTAssertEqual(engine.player.x, 250); XCTAssertEqual(engine.player.y, 295)
                    XCTAssertEqual(engine.player.weave.comboDirection, 0)
                    XCTAssertNil(engine.player.attack)
                    XCTAssertEqual(practice.player.stamina, 100)
                }
            }
            // Matching head attacks still land throughout what would have been the evade window.
            for punch in Punch.allCases {
                guard let direction = CombatData.requiredDuck[punch] else { continue }
                for elapsed in [0.06, 0.12, 0.239] {
                    let engine = match(distance: 55)
                    engine.player.stamina = 12
                    XCTAssertTrue(engine.weave(direction: direction))
                    advance(elapsed - 0.01, update: engine.update)
                    incoming(punch, to: engine)
                    engine.update(deltaTime: 0.01)
                    XCTAssertLessThan(engine.player.hp, 100)
                    XCTAssertEqual(engine.roundPlayerDodgeCount, 0)
                    XCTAssertEqual(engine.successfulDodgeCount, 0)
                    XCTAssertEqual(engine.player.x, 250); XCTAssertEqual(engine.player.y, 295)
                    XCTAssertEqual(engine.player.invulnerable, 0)
                    XCTAssertNil(engine.lastPlayerDodgeGrade)
                }
            }
        }
    }

    func testExhaustionCancelsActiveWeaveAndQueuedHookBeforeEitherFighterCanEvade() {
        MainActor.assumeIsolated {
            for defenderIsPlayer in [true, false] {
                for direction in [-1, 1] {
                    // Also cover a lock that expires this tick: cancellation must precede timer decay.
                    for exhausted in [0.001, 1.0] {
                        let engine = match(distance: 55)
                        engine.enemy.stagger = 0
                        engine.enemy.facingX = -1
                        let defender = defenderIsPlayer ? engine.player : engine.enemy
                        let attacker = defenderIsPlayer ? engine.enemy : engine.player
                        XCTAssertTrue(defender.beginWeave(direction: direction))
                        defender.weave.advance(0.12)
                        XCTAssertTrue(defender.queueWeaveHook(base: direction < 0 ? .jab : .cross))
                        defender.exhausted = exhausted
                        let punch: Punch = direction < 0 ? .cross : .jab
                        XCTAssertTrue(engine.startAttack(attacker, punch: punch))
                        attacker.actionTime = CombatData.attacks[punch]!.activeStart - 0.005
                        let x = defender.x, y = defender.y
                        engine.update(deltaTime: 0.01)
                        XCTAssertLessThan(defender.hp, 100)
                        XCTAssertEqual(defender.x, x); XCTAssertEqual(defender.y, y)
                        XCTAssertEqual(defender.invulnerable, 0)
                        XCTAssertFalse(defender.weave.isActive)
                        XCTAssertEqual(defender.weave.comboDirection, 0)
                        XCTAssertEqual(defender.attackSerial, 0)
                        XCTAssertEqual(engine.roundPlayerDodgeCount, 0)
                        XCTAssertEqual(engine.roundEnemyDodgeCount, 0)
                    }
                }
            }
            // With no hit to cancel anything, even a momentary exhaustion discards the hook for good.
            let engine = match()
            XCTAssertTrue(engine.weave(direction: 1))
            XCTAssertTrue(engine.requestWeaveHook(base: .cross))
            advance(0.1, update: engine.update)
            let x = engine.player.x, y = engine.player.y
            engine.player.exhausted = 0.001
            advance(0.6, update: engine.update)
            XCTAssertEqual(engine.player.x, x); XCTAssertEqual(engine.player.y, y)
            XCTAssertEqual(engine.player.weave.comboDirection, 0)
            XCTAssertEqual(engine.player.attackSerial, 0)
            XCTAssertNil(engine.player.attack)
            XCTAssertTrue(engine.roundPlayerPunchCounts.isEmpty)
        }
    }

    func testQueuedHooksPayOnlyInMatchOnExecutionAndHitOnceAtEveryFPS() {
        MainActor.assumeIsolated {
            for fps in [30.0, 60, 120] {
                for direction in [-1, 1] {
                    for style in FightStyle.allCases {
                        let base: Punch = direction < 0 ? .jab : .cross
                        let hook = WeaveState.hook(base: base, direction: direction)!
                        let engine = match(), practice = gym()
                        engine.player.style = style; practice.player.style = style
                        var impacts: [CombatImpact] = []
                        var bagHits: [(Punch, Int)] = []
                        engine.onCombatEvent = { if case .impact(let hit) = $0 { impacts.append(hit) } }
                        practice.onHit = { bagHits.append(($0, $1)) }
                        XCTAssertTrue(engine.weave(direction: direction)); XCTAssertTrue(practice.weave(direction: direction))
                        XCTAssertTrue(engine.requestWeaveHook(base: base)); XCTAssertTrue(practice.requestWeaveHook(base: base))
                        XCTAssertEqual(engine.player.stamina, 88); XCTAssertEqual(practice.player.stamina, 100)
                        XCTAssertNil(engine.player.attack); XCTAssertNil(practice.player.attack)
                        XCTAssertTrue(engine.roundPlayerPunchCounts.isEmpty)
                        while engine.player.weave.elapsed < 0.22 {
                            XCTAssertFalse(engine.requestWeaveHook(base: base))
                            XCTAssertFalse(practice.requestWeaveHook(base: base))
                            engine.update(deltaTime: 1 / fps); practice.update(deltaTime: 1 / fps)
                        }
                        XCTAssertEqual(engine.player.attack, hook); XCTAssertEqual(practice.player.attack, hook)
                        XCTAssertEqual(engine.player.actionTime, 0); XCTAssertEqual(practice.player.actionTime, 0)
                        let cost = CombatData.attacks[hook]!.staminaCost * style.punchStaminaMultiplier
                        XCTAssertEqual(engine.player.stamina, 88 - cost, accuracy: 1e-8)
                        XCTAssertEqual(practice.player.stamina, 100)
                        XCTAssertEqual(practice.player.exhausted, 0)
                        XCTAssertEqual(engine.roundPlayerPunchCounts[hook], 1)
                        XCTAssertEqual(engine.player.attackSerial, 1); XCTAssertEqual(practice.player.attackSerial, 1)
                        XCTAssertFalse(engine.requestWeaveHook(base: base)); XCTAssertFalse(practice.requestWeaveHook(base: base))
                        advance(1, fps: fps) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                        XCTAssertEqual(impacts.count, 1); XCTAssertEqual(bagHits.count, 1)
                        XCTAssertEqual(impacts.first?.punch, hook); XCTAssertEqual(bagHits.first?.0, hook)
                        XCTAssertEqual(impacts.first?.damage, bagHits.first?.1)
                        XCTAssertEqual(impacts.first?.counter, false)
                        XCTAssertEqual(impacts.first?.perfectCounter, false)
                        XCTAssertEqual(engine.player.attackSerial, 1); XCTAssertEqual(practice.player.attackSerial, 1)
                    }
                }
            }
        }
    }

    func testSharedGraceWindowButUnaffordableHookIsDroppedOnlyInMatch() {
        MainActor.assumeIsolated {
            for direction in [-1, 1] {
                let base: Punch = direction < 0 ? .jab : .cross
                for elapsed in [0.22, 0.36, 0.479, 0.48] {
                    let engine = match(), practice = gym()
                    XCTAssertTrue(engine.weave(direction: direction)); XCTAssertTrue(practice.weave(direction: direction))
                    advance(elapsed) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                    let staminaBeforeHook = engine.player.stamina
                    for wrong in Punch.allCases where wrong != base {
                        XCTAssertFalse(engine.requestWeaveHook(base: wrong))
                        XCTAssertFalse(practice.requestWeaveHook(base: wrong))
                    }
                    XCTAssertEqual(engine.requestWeaveHook(base: base), elapsed < 0.48)
                    XCTAssertEqual(practice.requestWeaveHook(base: base), elapsed < 0.48)
                    XCTAssertEqual(engine.player.attack, elapsed < 0.48 ? WeaveState.hook(base: base, direction: direction) : nil)
                    XCTAssertEqual(practice.player.attack, engine.player.attack)
                    let hook = WeaveState.hook(base: base, direction: direction)!
                    let cost = CombatData.attacks[hook]!.staminaCost * engine.player.style.punchStaminaMultiplier
                    XCTAssertEqual(engine.player.stamina, staminaBeforeHook - (elapsed < 0.48 ? cost : 0), accuracy: 1e-8)
                    XCTAssertEqual(practice.player.stamina, 100)
                    XCTAssertEqual(practice.player.exhausted, 0)
                }
                let engine = match(), practice = gym()
                engine.player.stamina = 13; practice.player.stamina = 13
                XCTAssertTrue(engine.weave(direction: direction)); XCTAssertTrue(practice.weave(direction: direction))
                XCTAssertTrue(engine.requestWeaveHook(base: base)); XCTAssertTrue(practice.requestWeaveHook(base: base))
                advance(0.22) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                XCTAssertEqual(engine.player.stamina, 1); XCTAssertEqual(practice.player.stamina, 100)
                XCTAssertNil(engine.player.attack)
                XCTAssertEqual(practice.player.attack, WeaveState.hook(base: base, direction: direction))
                XCTAssertEqual(practice.player.attackSerial, 1)
                XCTAssertEqual(practice.player.exhausted, 0)
                engine.player.stamina = 100
                advance(0.2) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                XCTAssertNil(engine.player.attack)
                XCTAssertEqual(practice.player.attackSerial, 1)
                XCTAssertEqual(practice.player.stamina, 100)
                XCTAssertFalse(engine.requestWeaveHook(base: base)); XCTAssertFalse(practice.requestWeaveHook(base: base))
                XCTAssertTrue(engine.roundPlayerPunchCounts.isEmpty)
            }
        }
    }

    func testExactRemainingHookCostExhaustsOnlyMatchAndCancelsItsWeave() {
        MainActor.assumeIsolated {
            for direction in [-1, 1] {
                let engine = match(), practice = gym()
                let base: Punch = direction < 0 ? .jab : .cross
                let hook = WeaveState.hook(base: base, direction: direction)!
                let cost = CombatData.attacks[hook]!.staminaCost * engine.player.style.punchStaminaMultiplier
                XCTAssertTrue(engine.weave(direction: direction)); XCTAssertTrue(practice.weave(direction: direction))
                XCTAssertTrue(engine.requestWeaveHook(base: base)); XCTAssertTrue(practice.requestWeaveHook(base: base))
                engine.player.stamina = cost; practice.player.stamina = cost
                advance(0.22) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                XCTAssertEqual(engine.player.attack, hook); XCTAssertEqual(practice.player.attack, hook)
                XCTAssertEqual(engine.player.stamina, 0); XCTAssertEqual(practice.player.stamina, 100)
                XCTAssertEqual(engine.player.exhausted, CombatData.exhaustionDuration)
                XCTAssertEqual(engine.exhaustionCount, 1)
                XCTAssertFalse(engine.player.weave.isActive)
                XCTAssertEqual(engine.player.weave.comboDirection, 0)
                XCTAssertEqual(engine.player.invulnerable, 0)
                XCTAssertEqual(practice.player.exhausted, 0)
                XCTAssertTrue(practice.player.weave.isActive)
                let x = engine.player.x, y = engine.player.y
                advance(0.4) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                XCTAssertEqual(engine.player.x, x); XCTAssertEqual(engine.player.y, y)
                XCTAssertEqual(engine.player.attackSerial, 1) // Already-started punch still resolves normally.
                XCTAssertLessThan(engine.enemy.hp, 100)
                XCTAssertEqual(practice.player.stamina, 100)
                XCTAssertEqual(practice.player.exhausted, 0)
            }
        }
    }

    func testGymAllActionsRemainFreeAndEverySimulationUpdateRestoresFullStamina() {
        MainActor.assumeIsolated {
            for style in FightStyle.allCases {
                for action in ["idle", "move", "guard", "duckLeft", "duckRight", "backstep", "weaveLeft", "weaveRight"] {
                    let practice = gym(radius: 55)
                    practice.setStyle(style)
                    practice.player.stamina = 0
                    switch action {
                    case "move": practice.setMove(x: 1, y: 1)
                    case "guard": practice.setGuarding(true)
                    case "duckLeft": practice.setDuck(-1, active: true)
                    case "duckRight": practice.setDuck(1, active: true)
                    case "backstep": XCTAssertTrue(practice.backstep())
                    case "weaveLeft": XCTAssertTrue(practice.weave(direction: -1))
                    case "weaveRight": XCTAssertTrue(practice.weave(direction: 1))
                    default: break
                    }
                    XCTAssertEqual(practice.player.stamina, 0, action)
                    XCTAssertEqual(practice.player.exhausted, 0, action)
                    practice.update(deltaTime: 0.01)
                    XCTAssertEqual(practice.player.stamina, 100, action)
                    XCTAssertEqual(practice.player.exhausted, 0, action)
                    XCTAssertFalse(practice.playerLocked, action)
                }
                for punch in Punch.allCases {
                    let practice = gym(radius: 55)
                    practice.setStyle(style)
                    practice.player.stamina = 0
                    var hits = 0
                    practice.onHit = { _, _ in hits += 1 }
                    XCTAssertTrue(practice.startAttack(punch))
                    XCTAssertEqual(practice.player.stamina, 0)
                    advance(CombatData.attacks[punch]!.duration + 0.01) { dt in
                        practice.player.stamina = 0 // Recovery is unconditional, not idle-only regen.
                        practice.update(deltaTime: dt)
                        XCTAssertEqual(practice.player.stamina, 100)
                        XCTAssertEqual(practice.player.exhausted, 0)
                    }
                    XCTAssertEqual(hits, 1)
                }
                for direction in [-1, 1] {
                    for elapsed in [0.22, 0.36, 0.479] {
                        let practice = gym()
                        practice.setStyle(style)
                        XCTAssertTrue(practice.weave(direction: direction))
                        advance(elapsed, update: practice.update)
                        practice.player.stamina = 0
                        let base: Punch = direction < 0 ? .jab : .cross
                        XCTAssertTrue(practice.requestWeaveHook(base: base)) // No paid recovery-grace path.
                        XCTAssertEqual(practice.player.attack, WeaveState.hook(base: base, direction: direction))
                        XCTAssertEqual(practice.player.stamina, 0)
                        XCTAssertEqual(practice.player.exhausted, 0)
                        practice.update(deltaTime: 0.01)
                        XCTAssertEqual(practice.player.stamina, 100)
                        XCTAssertEqual(practice.player.exhausted, 0)
                    }
                }
            }
        }
    }

    func testPauseCancelResetAndRoundEndLeaveNoBufferedMomentum() {
        MainActor.assumeIsolated {
            for phase in [0.1, 0.4] {
                let engine = match(), practice = gym()
                XCTAssertTrue(engine.weave(direction: 1)); XCTAssertTrue(practice.weave(direction: 1))
                advance(phase) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                if phase < 0.22 {
                    XCTAssertTrue(engine.requestWeaveHook(base: .cross)); XCTAssertTrue(practice.requestWeaveHook(base: .cross))
                }
                engine.setMove(x: 1, y: 1); practice.setMove(x: 1, y: 1)
                engine.togglePause(); practice.togglePause()
                let state = engine.player.weave
                let x = engine.player.x, y = engine.player.y
                let stamina = engine.player.stamina
                XCTAssertFalse(state.isActive); XCTAssertEqual(state.comboDirection, 0)
                advance(1) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                XCTAssertEqual(engine.lastSimulationDeltaTime, 0)
                XCTAssertEqual(engine.player.weave, state); XCTAssertEqual(practice.player.weave, state)
                XCTAssertEqual(engine.player.stamina, stamina); XCTAssertEqual(practice.player.stamina, 100)
                XCTAssertFalse(engine.weave(direction: 1)); XCTAssertFalse(practice.weave(direction: 1))
                XCTAssertFalse(engine.requestWeaveHook(base: .cross)); XCTAssertFalse(practice.requestWeaveHook(base: .cross))
                engine.togglePause(); practice.togglePause()
                advance(0.6) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
                XCTAssertEqual(engine.player.x, x); XCTAssertEqual(engine.player.y, y)
                XCTAssertEqual(practice.player.y, y)
                XCTAssertNil(engine.player.attack); XCTAssertNil(practice.player.attack)
            }
            let engine = match(), practice = gym()
            XCTAssertTrue(engine.weave(direction: -1)); XCTAssertTrue(practice.weave(direction: -1))
            XCTAssertTrue(engine.requestWeaveHook(base: .jab)); XCTAssertTrue(practice.requestWeaveHook(base: .jab))
            engine.cancelWeaveInput(); practice.cancelWeaveInput()
            XCTAssertFalse(engine.weave(direction: 1)); XCTAssertFalse(practice.weave(direction: 1))
            advance(0.5) { dt in engine.update(deltaTime: dt); practice.update(deltaTime: dt) }
            XCTAssertEqual(engine.player.y, 295); XCTAssertEqual(practice.player.y, 295)
            XCTAssertNil(engine.player.attack); XCTAssertNil(practice.player.attack)
            XCTAssertTrue(engine.weave(direction: 1))
            XCTAssertTrue(engine.requestWeaveHook(base: .cross))
            engine.enemy.stagger = 0
            XCTAssertTrue(engine.enemy.beginWeave(direction: -1))
            XCTAssertTrue(engine.enemy.queueWeaveHook(base: .jab))
            let x = engine.player.x, y = engine.player.y
            let enemyX = engine.enemy.x, enemyY = engine.enemy.y
            engine.finishRound(outcome: .draw, knockout: false)
            XCTAssertFalse(engine.player.weave.isActive)
            XCTAssertFalse(engine.enemy.weave.isActive)
            XCTAssertFalse(engine.weave(direction: 1))
            advance(0.6, update: engine.update)
            XCTAssertEqual(engine.player.weave.comboDirection, 0)
            XCTAssertEqual(engine.enemy.weave.comboDirection, 0)
            XCTAssertNil(engine.player.attack); XCTAssertNil(engine.enemy.attack)
            XCTAssertEqual(engine.player.attackSerial, 0); XCTAssertEqual(engine.enemy.attackSerial, 0)
            XCTAssertEqual(engine.player.x, x); XCTAssertEqual(engine.player.y, y)
            XCTAssertEqual(engine.enemy.x, enemyX); XCTAssertEqual(engine.enemy.y, enemyY)
            XCTAssertTrue(engine.roundPlayerPunchCounts.isEmpty)
            XCTAssertTrue(engine.roundEnemyPunchCounts.isEmpty)
            engine.startRound()
            XCTAssertEqual(engine.player.weave, WeaveState())
            XCTAssertEqual(engine.enemy.weave, WeaveState())
            practice.player.reset(x: 235, y: 295)
            XCTAssertEqual(practice.player.weave, WeaveState())
        }
    }

    func testHeadEvasionOnlyInDirectionalWindowAndBodyOrWrongSideInterrupts() {
        MainActor.assumeIsolated {
            for direction in [-1, 1] {
                for punch in Punch.allCases {
                    for elapsed in [0.05, 0.06, 0.12, 0.239, 0.24, 0.36] {
                        let engine = match(distance: 55)
                        var dodges: [CombatEvent] = []
                        var impacts: [CombatImpact] = []
                        engine.onCombatEvent = {
                            if case .dodge = $0 { dodges.append($0) }
                            if case .impact(let impact) = $0 { impacts.append(impact) }
                        }
                        XCTAssertTrue(engine.weave(direction: direction))
                        advance(elapsed - 0.01, update: engine.update)
                        incoming(punch, to: engine)
                        engine.update(deltaTime: 0.01)
                        let evades = elapsed >= 0.06 && elapsed < 0.24 && CombatData.requiredDuck[punch] == direction
                        XCTAssertEqual(engine.player.hp == 100, evades, "\(direction), \(punch), \(elapsed)")
                        XCTAssertEqual(dodges, evades ? [.dodge(fighter: .player, grade: .normal)] : [])
                        XCTAssertEqual(engine.roundPlayerDodgeCount, evades ? 1 : 0)
                        XCTAssertEqual(engine.successfulDodgeCount, evades ? 1 : 0)
                        XCTAssertEqual(impacts.count, evades ? 0 : 1)
                        XCTAssertEqual(engine.rivalMomentTime, 0)
                        XCTAssertNil(engine.rivalMomentGrade)
                        XCTAssertFalse(engine.player.pendingDodgeCounter)
                        if evades {
                            XCTAssertEqual(engine.message, LocalizationManager.shared.t(.weaveEvadeMessage))
                        } else {
                            XCTAssertFalse(engine.player.weave.isActive)
                            XCTAssertEqual(engine.player.weave.comboDirection, 0)
                        }
                    }
                }
            }
        }
    }

    func testBothFightersAdvanceBeforeHitChecksAndAttackDisablesWeaveEvasion() {
        MainActor.assumeIsolated {
            for defenderIsPlayer in [true, false] {
                let engine = match(distance: 55)
                let defender = defenderIsPlayer ? engine.player : engine.enemy
                let attacker = defenderIsPlayer ? engine.enemy : engine.player
                engine.enemy.stagger = 0
                engine.enemy.facingX = -1
                XCTAssertTrue(defender.beginWeave(direction: 1))
                // Place at .05. A .01 step reaches the inclusive .06 evade boundary for BOTH sides.
                defender.weave.advance(0.05)
                XCTAssertTrue(engine.startAttack(attacker, punch: .jab))
                attacker.actionTime = 0.075
                engine.update(deltaTime: 0.01)
                XCTAssertEqual(defender.hp, 100)
                XCTAssertEqual(engine.roundPlayerDodgeCount, defenderIsPlayer ? 1 : 0)
                XCTAssertEqual(engine.roundEnemyDodgeCount, defenderIsPlayer ? 0 : 1)
            }
            let engine = match(distance: 55)
            XCTAssertTrue(engine.weave(direction: 1))
            advance(0.22, update: engine.update)
            XCTAssertTrue(engine.requestWeaveHook(base: .cross))
            incoming(.jab, to: engine)
            engine.update(deltaTime: 0.01) // Still .23, but attacking heads cannot evade.
            XCTAssertLessThan(engine.player.hp, 100)
            XCTAssertNil(engine.player.attack)
            XCTAssertFalse(engine.player.weave.isActive)
        }
    }

    func testHitStaggerAndKOCancelBufferedHookBeforeItCanLaunch() {
        MainActor.assumeIsolated {
            for knockout in [false, true] {
                let engine = match(distance: 55)
                if knockout { engine.player.hp = 1 }
                XCTAssertTrue(engine.weave(direction: -1))
                XCTAssertTrue(engine.requestWeaveHook(base: .jab))
                advance(0.21, update: engine.update)
                incoming(.rightBody, to: engine)
                engine.update(deltaTime: 0.01) // Hit and hook-ready on the same tick: interruption wins.
                XCTAssertEqual(engine.player.attackSerial, 0)
                XCTAssertFalse(engine.player.weave.isActive)
                XCTAssertEqual(engine.player.weave.comboDirection, 0)
                XCTAssertEqual(engine.player.knockedOut, knockout)
                advance(0.5, update: engine.update)
                XCTAssertNil(engine.player.attack)
                XCTAssertTrue(engine.roundPlayerPunchCounts.isEmpty)
            }
            let practice = gym()
            XCTAssertTrue(practice.weave(direction: -1))
            XCTAssertTrue(practice.requestWeaveHook(base: .jab))
            practice.player.stagger = 0.1
            advance(0.4, update: practice.update)
            XCTAssertFalse(practice.player.weave.isActive)
            XCTAssertNil(practice.player.attack)
            XCTAssertEqual(practice.player.y, 295)
        }
    }

    func testExistingDuckCombosAndGradedCounterRemainUnchanged() {
        MainActor.assumeIsolated {
            XCTAssertEqual(CombatData.comboPunch(base: .cross, guarding: false, duckDirection: -1), .rightHook)
            XCTAssertEqual(CombatData.comboPunch(base: .jab, guarding: false, duckDirection: 1), .leftHook)
            XCTAssertEqual(CombatData.comboPunch(base: .jab, guarding: false, duckDirection: -1), .leftBody)
            XCTAssertEqual(CombatData.comboPunch(base: .cross, guarding: false, duckDirection: 1), .rightBody)
            let engine = match(distance: 55), practice = gym(radius: 55)
            engine.setDuck(1, active: true); practice.setDuck(1, active: true)
            incoming(.jab, to: engine)
            engine.update(deltaTime: 0.01)
            XCTAssertEqual(engine.player.hp, 100)
            XCTAssertEqual(engine.lastPlayerDodgeGrade, .perfect)
            XCTAssertGreaterThan(engine.rivalMomentTime, 0)
            let combo = CombatData.comboPunch(base: .jab, guarding: false, duckDirection: 1)
            XCTAssertTrue(engine.startAttack(engine.player, punch: combo))
            XCTAssertTrue(engine.player.pendingDodgeCounter)
            XCTAssertTrue(practice.startAttack(combo))
            XCTAssertEqual(practice.player.stamina, 100) // Existing gym combos are still free.
            XCTAssertEqual(engine.player.duckDirection, 1)
            XCTAssertEqual(practice.player.duckDirection, 1)
        }
    }

    func testStartingWeaveClearsPriorPerfectDuckCounterTokenBeforeItsHook() {
        MainActor.assumeIsolated {
            for direction in [-1, 1] {
                let engine = match(distance: 55)
                engine.setDuck(1, active: true)
                incoming(.jab, to: engine)
                engine.update(deltaTime: 0.01)
                XCTAssertEqual(engine.lastPlayerDodgeGrade, .perfect)
                XCTAssertGreaterThan(engine.rivalMomentTime, 0)
                // Isolate the prior duck token from ordinary exposure/whiff counter damage.
                engine.enemy.attack = nil
                engine.enemy.exposed = 0
                XCTAssertTrue(engine.weave(direction: direction))
                XCTAssertEqual(engine.player.duckDirection, 0)
                let base: Punch = direction < 0 ? .jab : .cross
                let hook = WeaveState.hook(base: base, direction: direction)!
                XCTAssertTrue(engine.requestWeaveHook(base: base))
                var realElapsed = 0.0
                for _ in 0..<120 {
                    if engine.player.attack != nil { break }
                    engine.update(deltaTime: 0.01)
                    realElapsed += 0.01
                }
                // Follow the real slowdown; the old token would still be live when the hook starts.
                XCTAssertLessThan(realElapsed, DodgeGrade.perfect.counterWindow)
                XCTAssertEqual(engine.player.attack, hook)
                XCTAssertEqual(engine.lastPlayerDodgeGrade, .perfect)
                XCTAssertFalse(engine.player.pendingDodgeCounter)
                var hits: [CombatImpact] = []
                engine.onCombatEvent = { if case .impact(let hit) = $0 { hits.append(hit) } }
                advance(0.25, update: engine.update)
                XCTAssertEqual(hits.count, 1)
                XCTAssertEqual(hits.first?.counter, false)
                XCTAssertEqual(hits.first?.perfectCounter, false)
                let damage = Int((Double(CombatData.attacks[hook]!.damage) * engine.player.style.damageMultiplier).rounded())
                XCTAssertEqual(hits.first?.damage, damage)
                XCTAssertEqual(engine.perfectCounterCount, 0)
            }
        }
    }

    func testWeaveUsesOnlyExistingExposureCounterWithoutSpecialDamage() {
        MainActor.assumeIsolated {
            let engine = match(distance: 55)
            XCTAssertTrue(engine.weave(direction: -1))
            advance(0.21, update: engine.update)
            incoming(.cross, to: engine)
            engine.update(deltaTime: 0.01)
            XCTAssertEqual(engine.lastPlayerDodgeGrade, .normal)
            XCTAssertTrue(engine.requestWeaveHook(base: .jab))
            XCTAssertFalse(engine.player.pendingDodgeCounter)
            var hits: [CombatImpact] = []
            engine.onCombatEvent = { if case .impact(let hit) = $0 { hits.append(hit) } }
            // Freeze the attacker's recovery to isolate the existing 0.18 exposure window.
            engine.enemy.attack = nil
            advance(0.17, update: engine.update)
            XCTAssertEqual(hits.count, 1)
            let base = CombatData.attacks[.leftHook]!.damage
            let exposed = Int((Double(base) * CombatData.exposedDamageMultiplier).rounded())
            let expected = Int((Double(exposed) * CombatData.bodyHookCounterMultiplier).rounded())
            XCTAssertEqual(hits.first?.damage, expected)
            XCTAssertEqual(hits.first?.counter, true)
            XCTAssertEqual(hits.first?.perfectCounter, false)
            XCTAssertEqual(engine.perfectCounterCount, 0)
        }
    }

}