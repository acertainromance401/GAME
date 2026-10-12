import XCTest
@testable import RIVAL

/// Pure profile checks: no audio engine, haptic generator, device settings or saved progress.
@MainActor
final class ImpactFeedbackTests: XCTestCase {
    func testFamilyHapticsIncreaseInSmallStepsWithoutChangingAudio() {
        let cases: [(punch: Punch, texture: ImpactFeedback.Texture, haptic: ImpactFeedback.Haptic,
                     previous: Double, current: Double, volume: Float)] = [
            (.jab, .jab, .light, 0.32, 0.38, 0.62),
            (.cross, .cross, .heavy, 0.62, 0.69, 0.76),
            (.leftBody, .body, .medium, 0.52, 0.59, 0.72),
            (.rightBody, .body, .medium, 0.52, 0.59, 0.72),
            (.leftHook, .hook, .heavy, 0.68, 0.75, 0.80),
            (.rightHook, .hook, .heavy, 0.68, 0.75, 0.80),
            (.leftUppercut, .uppercut, .heavy, 0.76, 0.83, 0.84),
            (.rightUppercut, .uppercut, .heavy, 0.76, 0.83, 0.84),
        ]
        for item in cases {
            for attacker in [Combatant.player, .rival] {
                let impact = hit(item.punch, attacker: attacker)
                let feedback = ImpactFeedback.sample(impact)
                XCTAssertEqual(feedback.texture, item.texture)
                XCTAssertEqual(feedback.haptic, item.haptic)
                XCTAssertEqual(feedback.intensity, item.current, accuracy: 0.00001)
                XCTAssertGreaterThan(feedback.intensity, item.previous)
                XCTAssertLessThanOrEqual(feedback.intensity - item.previous, 0.070001)
                XCTAssertEqual(feedback.volume, item.volume, accuracy: 0.00001)
            }
        }
    }

    func testBlockGuardBreakAndKnockoutPreservePriorityAndHeadroom() {
        for punch in Punch.allCases {
            let block = ImpactFeedback.sample(hit(punch, guarded: true))
            let guardBreak = ImpactFeedback.sample(hit(punch, guarded: true, guardBroken: true))
            let knockout = ImpactFeedback.sample(hit(punch, guarded: true, guardBroken: true, knockout: true))
            XCTAssertEqual(block.texture, .blocked)
            XCTAssertEqual(block.haptic, .soft)
            XCTAssertEqual(block.intensity, 0.30)
            XCTAssertEqual(block.volume, 0.48)
            XCTAssertEqual(guardBreak.texture, .guardBreak)
            XCTAssertEqual(guardBreak.haptic, .rigid)
            XCTAssertEqual(guardBreak.intensity, 0.90)
            XCTAssertEqual(guardBreak.volume, 0.85)
            XCTAssertEqual(knockout.texture, .knockout)
            XCTAssertEqual(knockout.haptic, .heavy)
            XCTAssertEqual(knockout.intensity, 1)
            XCTAssertEqual(knockout.volume, 0.95)
            let ordinary = ImpactFeedback.sample(hit(punch))
            XCTAssertGreaterThan(ordinary.intensity, block.intensity)
            XCTAssertLessThan(ordinary.intensity, guardBreak.intensity)
        }
    }

    func testPreviouslyUnusedCounterGainIsNotAppliedOnTopOfLiveTuning() {
        for punch in Punch.allCases {
            for guarded in [false, true] {
                let original = hit(punch, guarded: guarded)
                let baseline = ImpactFeedback.sample(original)
                for perfect in [false, true] {
                    let counter = CombatImpact(attacker: original.attacker, punch: punch, damage: original.damage,
                                               guarded: guarded, guardBroken: false, counter: true,
                                               perfectCounter: perfect, knockout: false)
                    XCTAssertEqual(ImpactFeedback.sample(counter), baseline)
                }
            }
        }
    }

    private func hit(_ punch: Punch, attacker: Combatant = .player, guarded: Bool = false,
                     guardBroken: Bool = false, knockout: Bool = false) -> CombatImpact {
        CombatImpact(attacker: attacker, punch: punch, damage: CombatData.attacks[punch]?.damage ?? 0,
                     guarded: guarded, guardBroken: guardBroken, counter: false,
                     perfectCounter: false, knockout: knockout)
    }
}