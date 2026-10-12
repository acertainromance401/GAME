import SceneKit
import XCTest
@testable import RIVAL

@MainActor
final class CombatPresentationTests: XCTestCase {
    func testLegacyStatsKeepWinsWhenNewRewardKeysAreMissing() throws {
        let data = Data(#"{"winsByStyle":{"standard":72,"out_boxing":28}}"#.utf8)
        let stats = try JSONDecoder().decode(PlayerStats.self, from: data)

        XCTAssertEqual(stats.totalWins, 100)
        XCTAssertEqual(stats.gymSeconds, 0)
        XCTAssertEqual(stats.perfectRoundWins, 0)
        XCTAssertEqual(stats.currentWinStreak, 0)
        XCTAssertEqual(stats.bestWinStreak, 0)
        XCTAssertTrue(OutfitID.blackout.isUnlocked(
            highestRound: 1, totalWins: stats.totalWins, gymSeconds: stats.gymSeconds,
            perfectRoundWins: stats.perfectRoundWins, bestWinStreak: stats.bestWinStreak,
            winsByStyle: stats.winsByStyle
        ))
    }

    func testCurrentStatsRoundTripPreservesAllRewards() throws {
        let stats = PlayerStats(
            winsByStyle: [FightStyle.infighting.rawValue: 55], gymSeconds: 86400,
            perfectRoundWins: 12, currentWinStreak: 4, bestWinStreak: 20
        )
        let data = try JSONEncoder().encode(stats)
        XCTAssertEqual(try JSONDecoder().decode(PlayerStats.self, from: data), stats)
    }

    func testOlderStreakWithoutBestKeepsItsUnlockProgress() throws {
        let data = Data(#"{"winsByStyle":{},"currentWinStreak":23}"#.utf8)
        let stats = try JSONDecoder().decode(PlayerStats.self, from: data)
        XCTAssertEqual(stats.bestWinStreak, 23)
    }

    func testStatsDecodeIgnoresUnknownFutureKeys() throws {
        let data = Data(#"{"gymSeconds":7200,"bestWinStreak":11,"futureField":999,"flags":{"x":1}}"#.utf8)
        let stats = try JSONDecoder().decode(PlayerStats.self, from: data)

        XCTAssertEqual(stats.totalWins, 0)
        XCTAssertEqual(stats.gymSeconds, 7200, accuracy: 0.001)
        XCTAssertEqual(stats.currentWinStreak, 0)
        XCTAssertEqual(stats.bestWinStreak, 11)
    }

    func testPreferredStyleFallsBackToKnownStyleWhenUnknownKeyHasHigherWins() throws {
        let data = Data(#"{"winsByStyle":{"future_style":40,"standard":3,"in_fighting":2}}"#.utf8)
        let stats = try JSONDecoder().decode(PlayerStats.self, from: data)

        XCTAssertEqual(stats.totalWins, 45)
        XCTAssertEqual(stats.preferredStyle, .standard)
    }

    func testHitEventIsEmittedOnceAtActiveFrame() {
        let engine = closeRangeEngine()
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        engine.update(deltaTime: 0.05)
        XCTAssertTrue(impacts(in: events).isEmpty)
        engine.update(deltaTime: 0.05)

        let hits = impacts(in: events)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.attacker, .player)
        XCTAssertEqual(hits.first?.punch, .jab)
        XCTAssertEqual(hits.first?.damage, 6)
        XCTAssertEqual(hits.first?.level, .light)
        advance(engine, until: { engine.player.attack == nil })
        XCTAssertEqual(impacts(in: events).count, 1)
    }

    func testDodgeAndCounterAreNotLostBetweenHUDPublications() {
        let controller = isolatedController()
        let engine = controller.engine
        performPerfectDodge(engine)
        XCTAssertEqual(controller.snapshot.successfulDodgeCount, 0, "No HUD publication since start")
        XCTAssertEqual(controller.presentation.signature, .counterWindow)

        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        XCTAssertNil(controller.presentation.signature, "The counter opportunity was accepted")
        advance(engine, until: { engine.perfectCounterCount == 1 })
        XCTAssertEqual(controller.presentation.signature, .perfectCounter)
        XCTAssertEqual(controller.presentation.impactLevel, .perfectCounter)
        XCTAssertEqual(controller.snapshot.enemyHP, 100, "Feedback is independent of HUD polling")
    }

    func testGuardBreakHasOneImpactAndNoRedundantExhaustionCue() {
        let engine = closeRangeEngine()
        engine.player.stamina = 5
        engine.setGuarding(true)
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertTrue(engine.startAttack(engine.enemy, punch: .jab))
        engine.update(deltaTime: 0.05)
        engine.update(deltaTime: 0.05)

        let hits = impacts(in: events)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.guarded, true)
        XCTAssertEqual(hits.first?.guardBroken, true)
        XCTAssertEqual(hits.first?.level, .guardBreak)
        XCTAssertEqual(engine.exhaustionCount, 1, "Gameplay still records exhaustion")
        XCTAssertFalse(events.contains { if case .exhausted = $0 { return true }; return false })
    }

    func testMissDoesNotProduceImpactFeedback() {
        let engine = CombatEngine(persistHabits: false)
        engine.startRound()
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        advance(engine, until: { engine.player.attack == nil })
        XCTAssertTrue(impacts(in: events).isEmpty)
        XCTAssertTrue(events.contains(.whiff(fighter: .player)))
    }

    func testRejectedAttackDoesNotProducePresentationEvent() {
        let engine = closeRangeEngine()
        engine.player.stamina = 0
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertFalse(engine.startAttack(engine.player, punch: .cross))
        XCTAssertTrue(events.isEmpty)
    }

    func testOrdinaryAndBlockedHitsDoNotShakeCamera() {
        let presentation = CombatPresentation()
        presentation.receive(.impact(impact(damage: 6)))
        XCTAssertEqual(presentation.cameraImpulse, 0)
        presentation.receive(.roundStarted)
        presentation.receive(.impact(impact(damage: 4, guarded: true)))
        XCTAssertEqual(presentation.cameraImpulse, 0)
        presentation.receive(.impact(impact(damage: 14)))
        XCTAssertGreaterThan(presentation.cameraImpulse, 0)
        XCTAssertLessThan(presentation.cameraImpulse, 0.5)
    }

    func testKnockoutPreemptsCounterAndNormalFeedback() {
        let presentation = CombatPresentation()
        presentation.receive(.dodge(fighter: .player, grade: .perfect))
        presentation.receive(.impact(impact(perfectCounter: true)))
        presentation.receive(.impact(impact(knockout: true)))
        presentation.receive(.impact(impact(damage: 6)))
        presentation.receive(.dodge(fighter: .player, grade: .perfect))

        XCTAssertEqual(presentation.signature, .knockout)
        XCTAssertEqual(presentation.impactLevel, .knockout)
        XCTAssertEqual(presentation.cameraImpulse, ImpactLevel.knockout.cameraStrength, accuracy: 0.0001)
        presentation.advance(deltaTime: ImpactLevel.knockout.duration / 2)
        XCTAssertEqual(presentation.cameraImpulse, ImpactLevel.knockout.cameraStrength / 4, accuracy: 0.0001)
    }

    func testKnockoutClockWaitsThenAppearsAndFinishesOnRealTime() {
        let presentation = CombatPresentation()
        presentation.receive(.impact(impact(knockout: true)))
        XCTAssertEqual(presentation.signature, .knockout, "Priority is immediate, not the large banner")
        XCTAssertEqual(presentation.knockoutClockPhase, .waiting)
        presentation.advance(deltaTime: 0.19)
        XCTAssertEqual(presentation.knockoutClockPhase, .waiting)
        presentation.advance(deltaTime: 0.011)
        XCTAssertEqual(presentation.knockoutClockPhase, .visible)
        presentation.advance(deltaTime: 0.58)
        XCTAssertEqual(presentation.knockoutClockPhase, .visible)
        presentation.advance(deltaTime: 0.02)
        XCTAssertEqual(presentation.knockoutClockPhase, .finished)
        XCTAssertNil(presentation.signature)
        presentation.receive(.roundStarted)
        XCTAssertEqual(presentation.knockoutClockPhase, .inactive)
    }

    func testKnockoutClockResetCancelsPendingDisplayAndPauseDoesNotAdvanceIt() {
        let presentation = CombatPresentation()
        for beforeReset in [0.10, 0.25, 1.0] {
            presentation.receive(.impact(impact(knockout: true)))
            presentation.advance(deltaTime: beforeReset)
            let phase = presentation.knockoutClockPhase
            for invalidTime in [0.0, -1, Double.nan, Double.infinity] {
                presentation.advance(deltaTime: invalidTime)
                XCTAssertEqual(presentation.knockoutClockPhase, phase)
            }
            presentation.receive(.roundStarted)
            presentation.advance(deltaTime: 1)
            XCTAssertEqual(presentation.knockoutClockPhase, .inactive)
            XCTAssertNil(presentation.signature)
        }
        presentation.receive(.impact(impact(perfectCounter: true)))
        XCTAssertEqual(presentation.signature, .perfectCounter)
        XCTAssertEqual(presentation.knockoutClockPhase, .inactive)
        XCTAssertEqual(CombatPresentationTiming.knockoutResultReveal, 0.95)
        XCTAssertEqual(CombatPresentationTiming.decisionResultReveal, 0.35)
    }

    func testPresentationExpiresAndRoundResetClearsAllEffects() {
        let presentation = CombatPresentation()
        presentation.receive(.impact(impact(perfectCounter: true)))
        for _ in 0..<60 { presentation.advance(deltaTime: 1.0 / 60) }
        XCTAssertNil(presentation.signature)
        XCTAssertNil(presentation.impactLevel)
        XCTAssertEqual(presentation.cameraImpulse, 0)
        presentation.receive(.impact(impact(knockout: true)))
        presentation.receive(.roundStarted)
        XCTAssertNil(presentation.signature)
        XCTAssertEqual(presentation.impactTime, 0)
    }

    func testCameraFocusUsesFastEntryHoldAndReturn() {
        let duration = DodgeGrade.perfect.focusDuration
        XCTAssertEqual(CombatCameraFocus.envelope(remaining: duration, duration: duration), 0)
        XCTAssertGreaterThan(CombatCameraFocus.envelope(remaining: duration - 0.03, duration: duration), 0.8)
        XCTAssertEqual(CombatCameraFocus.envelope(remaining: 0.30, duration: duration), 1)
        XCTAssertLessThan(CombatCameraFocus.envelope(remaining: 0.03, duration: duration), 0.1)
        XCTAssertEqual(CombatCameraFocus.envelope(remaining: 0, duration: duration), 0)
    }

    func testKnockoutCameraOwnsFocusEvenDuringItsEntry() {
        let remaining = CombatData.koMomentDuration - 0.01
        let focus = CombatCameraFocus.sample(dodgeGrade: .perfect, dodgeTime: 0.3, knockoutTime: remaining, reducedMotion: false)
        let expected = CombatData.koMomentCameraZoom * CombatCameraFocus.envelope(remaining: remaining, duration: CombatData.koMomentDuration)
        XCTAssertEqual(focus.push, expected, accuracy: 0.0001)
        XCTAssertLessThan(focus.push, DodgeGrade.perfect.cameraZoom, "Must choose KO, not max of two unrelated envelopes")
    }

    func testReducedMotionRemovesCameraEffectsButKeepsCounterCue() {
        let focus = CombatCameraFocus.sample(dodgeGrade: .perfect, dodgeTime: 0.3, knockoutTime: 0.3, reducedMotion: true)
        XCTAssertEqual(focus.push, 0)
        XCTAssertEqual(focus.fieldOfView, 50)
        let controller = isolatedController()
        controller.scene3D.setReducedMotion(true)
        performPerfectDodge(controller.engine)
        XCTAssertEqual(controller.presentation.signature, .counterWindow)
        controller.engine.update(deltaTime: 0.05)
        XCTAssertEqual(controller.engine.lastSimulationDeltaTime, 0.05 * DodgeGrade.perfect.timeScale, accuracy: 0.0001)
        controller.scene3D.update(at: 1)
        XCTAssertEqual(controller.scene3D.cameraNode.camera?.fieldOfView, 50)
    }

    func testFinalDodgeFocusFrameStillUsesItsOriginalScale() {
        let engine = closeRangeEngine()
        performPerfectDodge(engine)
        while engine.rivalMomentTime > 0.05 { engine.update(deltaTime: 0.025) }
        let remaining = engine.rivalMomentTime
        XCTAssertGreaterThan(remaining, 0)
        let roundTime = engine.roundTime
        engine.update(deltaTime: remaining)
        XCTAssertEqual(engine.lastSimulationDeltaTime, remaining * DodgeGrade.perfect.timeScale, accuracy: 0.000001)
        XCTAssertEqual(roundTime - engine.roundTime, remaining * DodgeGrade.perfect.timeScale, accuracy: 0.000001)
        XCTAssertNil(engine.rivalMomentGrade)
    }

    func testKnockoutFallPrecedesResultAndWinnerFinishesPunch() {
        let engine = closeRangeEngine()
        engine.enemy.hp = 5
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        advance(engine, until: { engine.phase == .roundBreak })
        XCTAssertFalse(engine.snapshot.showsRoundResult)
        XCTAssertNotNil(engine.player.attack)
        for _ in 0..<13 { engine.update(deltaTime: 0.05) }
        XCTAssertFalse(engine.snapshot.showsRoundResult, "The slowed fall must not be hidden by the result card")
        advance(engine, until: { engine.snapshot.showsRoundResult })
        XCTAssertEqual(engine.enemy.knockdown, 1)
        XCTAssertNil(engine.player.attack, "The finishing hand returns instead of freezing in extension")
        XCTAssertEqual(impacts(in: events).count, 1, "Post-round animation never resolves more hits")
        XCTAssertEqual(engine.playerScore, 1)
        XCTAssertFalse(engine.snapshot.canAdvanceRound)
        engine.requestNextRound()
        XCTAssertEqual(engine.phase, .roundBreak)
        advance(engine, until: { engine.snapshot.canAdvanceRound })
        engine.requestNextRound()
        XCTAssertEqual(engine.phase, .fight)
        XCTAssertFalse(engine.snapshot.showsRoundResult)
        XCTAssertEqual(engine.koMomentTime, 0)
    }

    func testDecisionBreakHasNoKnockoutEffect() {
        let engine = closeRangeEngine()
        engine.finishRound(outcome: .draw, knockout: false)
        XCTAssertFalse(engine.snapshot.showsRoundResult)
        advance(engine, until: { engine.snapshot.showsRoundResult })
        XCTAssertEqual(engine.koMomentTime, 0)
        XCTAssertFalse(engine.lastRoundWasKnockout)
        XCTAssertFalse(engine.snapshot.canAdvanceRound)
    }

    func testRivalCannotMakeNewDecisionsAfterRoundEnds() {
        let engine = closeRangeEngine()
        engine.finishRound(outcome: .playerLoss, knockout: true)
        let position = engine.enemy.x
        let stamina = engine.enemy.stamina
        for decision in ["circle_left", "dodge_left", "dodge_back", Punch.jab.rawValue] {
            XCTAssertFalse(engine.performEnemyDecision(decision))
        }
        XCTAssertEqual(engine.enemy.x, position)
        XCTAssertEqual(engine.enemy.stamina, stamina)
    }

    func testRoundRecordUpdatesOnceWithoutWaitingForHUD() {
        let controller = isolatedController()
        controller.engine.finishRound(outcome: .playerWin, knockout: false)
        XCTAssertEqual(controller.playerStats.totalWins, 1)
        XCTAssertEqual(controller.playerStats.perfectRoundWins, 1)
        controller.publishSnapshot()
        controller.publishSnapshot()
        controller.engine.finishRound(outcome: .playerWin, knockout: false)
        XCTAssertEqual(controller.playerStats.totalWins, 1)
    }

    func testInactivityClearsHeldInputAndPausesPresentationClock() {
        let controller = isolatedController()
        controller.move(x: 1, y: 0, active: true)
        controller.guardButton(active: true)
        controller.duckButton(direction: 1, active: true)
        controller.presentation.receive(.impact(impact(perfectCounter: true)))
        controller.suspendForInactivity()
        XCTAssertEqual(controller.engine.phase, .paused)
        XCTAssertEqual(controller.engine.moveX, 0)
        XCTAssertFalse(controller.engine.player.guarding)
        XCTAssertEqual(controller.engine.player.duckDirection, 0)
        controller.scene3D.update(at: 1)
        controller.scene3D.update(at: 1.05)
        XCTAssertEqual(controller.presentation.impactTime, ImpactLevel.perfectCounter.duration)
        XCTAssertEqual(controller.engine.lastSimulationDeltaTime, 0)
        controller.pause()
        controller.synchronizeHeldControls()
        XCTAssertFalse(controller.engine.player.guarding)
        XCTAssertEqual(controller.engine.moveX, 0)
    }

    func testOpeningCinematicDoesNotAdvanceGameplayOrEmitHits() {
        let engine = closeRangeEngine()
        let scene = Arena3DScene(engine: engine)
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        let initialTime = engine.roundTime
        let initialPosition = engine.player.x
        scene.setCinematicMode(true, presentation: .appOpening)
        for frame in 0..<100 { scene.update(at: 1 + Double(frame) / 60) }
        scene.setCinematicMode(false)
        XCTAssertEqual(engine.roundTime, initialTime)
        XCTAssertEqual(engine.player.hp, 100)
        XCTAssertEqual(engine.enemy.hp, 100)
        XCTAssertEqual(engine.player.x, initialPosition)
        XCTAssertTrue(events.isEmpty)
    }

    func testPunchTrailIsShortAndDisabledForReducedMotion() throws {
        let controller = isolatedController()
        let scene = controller.scene3D
        controller.engine.enemy.stagger = 1000
        XCTAssertTrue(controller.engine.startAttack(controller.engine.player, punch: .cross))
        let trail = try XCTUnwrap(scene.rootNode.childNode(withName: "playerRightPunchTrail", recursively: true))
        var visibleSamples = 0
        for frame in 0..<15 {
            scene.update(at: 1 + Double(frame) / 60)
            if !trail.isHidden {
                visibleSamples += 1
                let capsule = try XCTUnwrap(trail.geometry as? SCNCapsule)
                XCTAssertLessThanOrEqual(capsule.height, 0.321)
                XCTAssertEqual(capsule.firstMaterial?.blendMode, .alpha)
            }
        }
        XCTAssertGreaterThan(visibleSamples, 0)
        scene.setReducedMotion(true)
        scene.update(at: 1.25)
        XCTAssertTrue(trail.isHidden)
    }

    private func impact(
        damage: Int = 12, guarded: Bool = false, perfectCounter: Bool = false, knockout: Bool = false
    ) -> CombatImpact {
        CombatImpact(attacker: .player, punch: .cross, damage: damage, guarded: guarded,
                     guardBroken: false, counter: perfectCounter, perfectCounter: perfectCounter, knockout: knockout)
    }

    private func impacts(in events: [CombatEvent]) -> [CombatImpact] {
        events.compactMap { if case let .impact(hit) = $0 { return hit }; return nil }
    }

    private func isolatedController() -> GameController {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.engine.player.x = 280
        controller.engine.enemy.x = 330
        return controller
    }

    private func closeRangeEngine() -> CombatEngine {
        let engine = CombatEngine(persistHabits: false)
        engine.startRound()
        engine.player.x = 280
        engine.enemy.x = 330
        return engine
    }

    private func performPerfectDodge(_ engine: CombatEngine) {
        XCTAssertTrue(engine.startAttack(engine.enemy, punch: .cross))
        engine.update(deltaTime: 0.05)
        engine.setDuck(-1, active: true)
        engine.update(deltaTime: 0.05)
        engine.update(deltaTime: 0.05)
        XCTAssertEqual(engine.lastPlayerDodgeGrade, .perfect)
    }

    private func advance(
        _ engine: CombatEngine, until condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<240 {
            if condition() { return }
            engine.update(deltaTime: 0.01)
        }
        XCTAssertTrue(condition(), "Combat event did not resolve within the bounded time", file: file, line: line)
    }
}