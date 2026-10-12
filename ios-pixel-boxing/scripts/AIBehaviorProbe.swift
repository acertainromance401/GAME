// Compile with the real CombatCore, CombatPresentation, CombatText, Localization, RivalAI,
// CombatInput and DefensiveMotion sources. See README for the checked-in runner.
// No UIKit, simulator, renderer, persistence, network, sound or haptic generators are involved.
import Foundation
import simd

@main
struct AIBehaviorProbe {
    @MainActor
    static func main() {
        let early = RivalDifficulty(round: 1)
        let late = RivalDifficulty(round: 200)
        precondition(early.decisionInterval > late.decisionInterval)
        precondition(late.movementEffort < 1 && late.reactionChance < 1 && late.reactionDelay > 0.05)
        for round in [1, 5, 20, 50, 100, 200, 1_000] {
            let skill = RivalDifficulty(round: round)
            print("round=\(round) interval=\(rounded(skill.decisionInterval)) move=\(rounded(CombatData.movementSpeed * skill.movementEffort)) readWeight=\(rounded(skill.learningWeight))")
        }

        var observedPressure: [Double] = []
        for offset in [(100.0, 0.0), (-100.0, 0.0), (0.0, 100.0), (0.0, -100.0)] {
            let engine = CombatEngine(persistHabits: false, randomSeed: 1)
            engine.resumeSession()
            engine.player.x = 295; engine.player.y = 295
            engine.enemy.x = 295 + offset.0; engine.enemy.y = 295 + offset.1
            engine.enemy.stagger = 100
            engine.setMove(x: 1, y: 0)
            for _ in 0..<5 { engine.update(deltaTime: 0.05) }
            engine.finishRound(outcome: .draw, knockout: false)
            observedPressure.append(engine.habits.snapshot.pressureRatio)
        }
        precondition(observedPressure.allSatisfy { abs($0 - 1) < 0.00001 }, "Forward intent must be rotation invariant")

        let engine = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 42)
        engine.resumeSession()
        engine.enemy.stamina = 0
        let masked = engine.enemyActionWeights(distance: 50)
        precondition(Punch.allCases.allSatisfy { masked[$0.rawValue, default: 0] == 0 })
        engine.enemy.stamina = 100
        let distant = engine.enemyActionWeights(distance: 110)
        precondition(Punch.allCases.allSatisfy { distant[$0.rawValue, default: 0] == 0 })
        engine.player.x = 250; engine.enemy.x = 350
        let before = engine.enemy.x
        engine.update(deltaTime: 0.05)
        precondition(engine.enemy.x < before, "Rival must close the old 95–112 range dead zone")
        precondition(engine.player.hp == 100 && engine.enemy.hp == 100)

        let replayA = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 99)
        let replayB = CombatEngine(persistHabits: false, initialRound: 200, randomSeed: 99)
        replayA.resumeSession(); replayB.resumeSession()
        for _ in 0..<600 {
            replayA.update(deltaTime: 1.0 / 60); replayB.update(deltaTime: 1.0 / 60)
            precondition(replayA.enemy.x == replayB.enemy.x && replayA.enemy.y == replayB.enemy.y)
            precondition(replayA.enemy.attack == replayB.enemy.attack && replayA.player.hp == replayB.player.hp)
        }
        var modifiers = CombatModifiers()
        for direction in [-1, 1] {
            modifiers.reset()
            modifiers.setDuck(direction, active: true)
            for base in [Punch.jab, .cross] {
                precondition(modifiers.punch(base: base) == CombatData.comboPunch(base: base, guarding: false, duckDirection: direction))
            }
        }
        modifiers.setDuck(-1, active: true)
        modifiers.setDuck(1, active: false)
        precondition(modifiers.duckDirection == -1)
        modifiers.guarding = true
        precondition(modifiers.punch(base: .jab) == .leftUppercut && modifiers.punch(base: .cross) == .rightUppercut)
        modifiers.reset()
        precondition(modifiers == CombatModifiers())
        let stepStart = BackstepMotion.sample(elapsed: 0.03)
        let stepEnd = BackstepMotion.sample(elapsed: 0.15)
        precondition(stepStart.rearLift > 0 && stepStart.frontLift == 0)
        precondition(stepEnd.rearLift == 0 && stepEnd.frontLift > 0)
        precondition(BackstepMotion.sample(elapsed: BackstepMotion.duration) == BackstepMotion())
        let foot = SIMD3<Float>(0.31, 0.14, 0.29)
        let offset = SIMD3<Float>(-0.26, 0.035, -0.2)
        let rotation = simd_quatf(angle: 0.18, axis: SIMD3<Float>(0, 0, 1))
        let local = DefensiveMotion.plantedFoot(foot, posePosition: offset, poseRotation: rotation)
        precondition(simd_distance(rotation.act(local) + offset, foot) < 0.00001)
        precondition(DefensiveMotion.guardBlend(current: 0.25, raised: true, deltaTime: 0, reducedMotion: false) == 0.25)
        print("INPUT AND DEFENSIVE MOTION MATH CHECKS PASSED")
        print("AI REGRESSION CHECKS PASSED")
        for pattern in Pattern.allCases {
            var earlyWins = 0
            var earlyMovement = 0.0
            for round in [1, 200] {
                var wins = 0
                var damageTaken = 0
                var rivalMovement = 0.0
                for seed in 1...12 {
                    let result = bout(round: round, pattern: pattern, seed: UInt64(seed))
                    wins += result.rivalWon ? 1 : 0
                    damageTaken += result.damageToPlayer
                    rivalMovement += result.distanceMoved
                }
                print("\(pattern.rawValue) round=\(round) rivalWins=\(wins)/12 playerDamage=\(rounded(Double(damageTaken) / 12)) rivalTravel=\(rounded(rivalMovement / 12))")
                if round == 1 {
                    earlyWins = wins
                    earlyMovement = rivalMovement
                } else {
                    precondition(rivalMovement > earlyMovement, "Late rivals must use more footwork in these fixed fixtures")
                    if pattern != .duckBody {
                        precondition(earlyWins <= 3 && wins >= earlyWins + 3, "Beginner/expert distinction regressed")
                    }
                }
            }
        }
    }

    enum Pattern: String, CaseIterable { case jab, duckBody, mixed }

    @MainActor
    static func bout(round: Int, pattern: Pattern, seed: UInt64) -> (rivalWon: Bool, damageToPlayer: Int, distanceMoved: Double) {
        let engine = CombatEngine(persistHabits: false, initialRound: round, randomSeed: seed)
        engine.resumeSession()
        var strikes = 0
        var movement = 0.0
        for _ in 0..<6_000 {
            guard engine.phase == .fight else { break }
            let distance = hypot(engine.enemy.x - engine.player.x, engine.enemy.y - engine.player.y)
            engine.setMove(x: distance > (pattern == .jab ? 85 : 58) ? 1 : 0, y: 0)
            engine.setDuck(pattern == .duckBody ? -1 : 0, active: pattern == .duckBody)
            if engine.player.attack == nil, engine.player.stamina > 22 {
                let sequence: [Punch] = [.jab, .cross, .leftBody, .rightHook, .rightBody, .leftUppercut]
                let punch: Punch = pattern == .jab ? .jab : (pattern == .duckBody ? .leftBody : sequence[strikes % sequence.count])
                                if let spec = CombatData.attacks[punch], distance <= spec.range * engine.player.style.reachMultiplier + 17,
                                     engine.startAttack(engine.player, punch: punch, recordsHabit: true) { strikes += 1 }
            }
            let oldX = engine.enemy.x
            let oldY = engine.enemy.y
            engine.update(deltaTime: 1.0 / 60)
            for fighter in [engine.player, engine.enemy] {
                precondition((0...100).contains(fighter.hp) && (0...100).contains(fighter.stamina))
                precondition(fighter.x.isFinite && fighter.y.isFinite)
                precondition((CombatData.ringMinimum...CombatData.ringMaximum).contains(fighter.x))
                precondition((CombatData.ringMinimum...CombatData.ringMaximum).contains(fighter.y))
            }
            movement += hypot(engine.enemy.x - oldX, engine.enemy.y - oldY)
        }
        return (engine.lastRoundOutcome == .playerLoss, 100 - engine.player.hp, movement)
    }

    static func rounded(_ value: Double) -> String { String(format: "%.3f", value) }
}