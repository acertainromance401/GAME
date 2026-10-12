import XCTest
import SceneKit
@testable import RIVAL

@MainActor
final class MotionPolishTests: XCTestCase {
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