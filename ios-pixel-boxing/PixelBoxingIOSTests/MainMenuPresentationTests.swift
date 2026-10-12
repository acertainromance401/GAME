import SceneKit
import XCTest
@testable import RIVAL

@MainActor
final class MainMenuPresentationTests: XCTestCase {
    func testLandscapeLayoutKeepsControlsAndPortraitSeparate() {
        // Safe-area viewports, not device claims; the physical UI run covers iPhone 12 mini.
        for size in [CGSize(width: 568, height: 320), CGSize(width: 667, height: 375),
                     CGSize(width: 718, height: 354), CGSize(width: 830, height: 410)] {
            let layout = MainMenuLayout(size: size)
            XCTAssertGreaterThanOrEqual(layout.menuWidth, 252)
            XCTAssertGreaterThan(layout.heroWidth, 230)
            XCTAssertEqual(layout.menuWidth + layout.gutter + layout.heroWidth,
                           size.width - MainMenuLayout.horizontalPadding * 2, accuracy: 0.001)
            XCTAssertEqual(layout.contentHeight, size.height - MainMenuLayout.verticalPadding * 2)
        }
    }

    func testIdleMotionIsBoundedAndNotOneSynchronizedSine() {
        for frame in 0..<600 {
            let motion = MenuIdleMotion.sample(at: Double(frame) / 30, reducedMotion: false)
            XCTAssertLessThanOrEqual(abs(motion.breath), 0.0181)
            XCTAssertLessThanOrEqual(abs(motion.weightShift), 0.0281)
            XCTAssertLessThanOrEqual(abs(motion.leftGuard), 0.0321)
            XCTAssertLessThanOrEqual(abs(motion.rightGuard), 0.0271)
            XCTAssertLessThanOrEqual(abs(motion.headSway), 0.0141)
        }
        let first = MenuIdleMotion.sample(at: 0, reducedMotion: false)
        let later = MenuIdleMotion.sample(at: 4.8, reducedMotion: false)
        XCTAssertEqual(first.breath, later.breath, accuracy: 0.00001)
        XCTAssertNotEqual(first.rightGuard, later.rightGuard)
        XCTAssertNotEqual(first.weightShift, later.weightShift)
    }

    func testMenuIdleKeepsFeetPlantedForEveryStyle() {
        for style in FightStyle.allCases {
            let neutral = FightPose.neutral(stride: 0, style: style)
            for sample in 0..<120 {
                var pose = neutral
                pose.applyMenuIdle(MenuIdleMotion.sample(at: Double(sample) / 10, reducedMotion: false))
                XCTAssertEqual(pose.leftFoot, neutral.leftFoot)
                XCTAssertEqual(pose.rightFoot, neutral.rightFoot)
                XCTAssertEqual(pose.rootY, neutral.rootY)
                XCTAssertLessThan(abs(pose.leftShoulder.y - neutral.leftShoulder.y), 0.015)
                XCTAssertLessThan(abs(pose.rightGlove.y - neutral.rightGlove.y), 0.03)
            }
        }
    }

    func testReducedMotionAndInvalidTimeProduceStaticIdle() {
        XCTAssertEqual(MenuIdleMotion.sample(at: 6.5, reducedMotion: true), MenuIdleMotion())
        XCTAssertEqual(MenuIdleMotion.sample(at: .infinity, reducedMotion: false), MenuIdleMotion())
        XCTAssertEqual(MenuIdleMotion.sample(at: .nan, reducedMotion: false), MenuIdleMotion())
    }

    func testMenuPortraitCannotAdvanceCombatOrOverwriteFighters() {
        let engine = CombatEngine(persistHabits: false)
        engine.startRound()
        engine.player.hp = 64
        engine.enemy.hp = 41
        engine.player.x = 215
        engine.enemy.x = 347
        XCTAssertTrue(engine.startAttack(engine.player, punch: .cross, recordsHabit: true))
        engine.player.actionTime = 0.12
        let before = engine.snapshot
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        let scene = Arena3DScene(engine: engine)
        scene.setCinematicMode(true, presentation: .menuPortrait)

        for frame in 0..<300 { scene.update(at: 1 + Double(frame) / 30) }
        XCTAssertEqual(engine.roundTime, before.time)
        XCTAssertEqual(engine.phase, .fight)
        XCTAssertEqual(engine.player.hp, 64)
        XCTAssertEqual(engine.enemy.hp, 41)
        XCTAssertEqual(engine.player.x, 215)
        XCTAssertEqual(engine.enemy.x, 347)
        XCTAssertEqual(engine.player.attack, .cross)
        XCTAssertEqual(engine.player.actionTime, 0.12)
        XCTAssertTrue(events.isEmpty)
        scene.setCinematicMode(false)
        XCTAssertEqual(engine.player.attack, .cross)
        XCTAssertEqual(engine.enemy.x, 347)
    }

    func testMenuPortraitUsesExistingBoxerAndRestoresLighting() throws {
        let scene = Arena3DScene(engine: CombatEngine(persistHabits: false))
        let intensities = scene.rootNode.childNodes.compactMap { $0.light?.intensity }
        let player = try XCTUnwrap(scene.rootNode.childNode(withName: "playerBoxer", recursively: true))
        let ring = try XCTUnwrap(scene.rootNode.childNode(withName: "ringCanvas", recursively: true))
        let initialRingTransform = ring.simdTransform
        let count = scene.rootNode.childNodes.count
        scene.setCinematicMode(true, presentation: .menuPortrait)
        scene.update(at: 1)
        XCTAssertTrue(player.isHidden)
        XCTAssertNotNil(scene.rootNode.childNode(withName: "rivalLeftGlove", recursively: true))
        XCTAssertEqual(scene.cameraNode.camera?.fieldOfView, 34)
        XCTAssertEqual(scene.cameraNode.camera?.bloomIntensity, 0)
        XCTAssertEqual(ring.simdTransform, initialRingTransform)
        for frame in 1..<240 { scene.update(at: 1 + Double(frame) / 30) }
        XCTAssertEqual(scene.rootNode.childNodes.count, count)
        scene.setCinematicMode(true, presentation: .matchIntro)
        scene.update(at: 9)
        XCTAssertFalse(player.isHidden)
        XCTAssertEqual(scene.rootNode.childNodes.compactMap { $0.light?.intensity }, intensities)
        XCTAssertEqual(scene.cameraNode.camera?.fieldOfView, 50)
    }

    func testReducedMotionPortraitHasNoCameraOrGloveDrift() throws {
        let scene = Arena3DScene(engine: CombatEngine(persistHabits: false))
        scene.setCinematicMode(true, presentation: .menuPortrait)
        scene.setReducedMotion(true)
        scene.update(at: 1)
        let camera = scene.cameraNode.simdTransform
        let glove = try XCTUnwrap(scene.rootNode.childNode(withName: "rivalLeftGlove", recursively: true))
        let hand = glove.simdTransform
        for frame in 1..<150 { scene.update(at: 1 + Double(frame) / 30) }
        XCTAssertEqual(scene.cameraNode.simdTransform, camera)
        XCTAssertEqual(glove.simdTransform, hand)
    }

    func testMenuCopyIsLocalizedAndDoesNotInventRivalMetrics() {
        let keys: [L] = [.menuFightAction, .menuRedCorner, .menuRecordTitle, .menuTotalWins, .menuBestStreak]
        for language in AppLanguage.allCases {
            for key in keys { XCTAssertFalse(key.text(for: language).isEmpty) }
        }
        XCTAssertNotEqual(L.menuTotalWins.text(for: .korean), L.menuTotalWins.text(for: .japanese))
        XCTAssertEqual(L.menuTotalWins.text(for: .english), "TOTAL WINS")
    }
}