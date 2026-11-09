import SceneKit
import SwiftUI
import XCTest
@testable import RIVAL

@MainActor
final class MainMenuPresentationTests: XCTestCase {
    #if !DEBUG
    func testReleaseExcludesDeveloperAccessAndUsesOrthodoxByDefault() {
        XCTAssertFalse(StoryProgress.temporarilyUnlockStory)
        XCTAssertFalse(StoryProgress.temporarilyUnlockCutscenes)
        XCTAssertFalse(StoryProgress.temporarilyUnlockEquipment)
        let store = StoryProgressStore(defaults: nil)
        XCTAssertEqual(store.progress.equippedStance, .orthodox)
        XCTAssertNil(store.progress.equippedAppearance)
        XCTAssertTrue(store.progress.isUnlocked(.basic))
        XCTAssertFalse(store.progress.isUnlocked(.southpaw))
        for opponent: StoryOpponent? in [nil, .basic] {
            let controller = GameController(persistsProgress: false, feedbackEnabled: false,
                storyOpponent: opponent, storyStore: store)
            controller.start(resumingStory: false, shortStoryIntroduction: true)
            controller.finishStoryIntroduction()
            XCTAssertEqual(controller.playerStance, .orthodox)
            XCTAssertEqual(controller.engine.player.stance, .orthodox)
        }
    }
    #endif

    #if DEBUG
    func testDeveloperPreviewPreservesSelectedStanceAndAppearanceAcrossNewMatches() throws {
        let suiteName = "rival.tests.developer-stance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for (stance, appearance): (BoxingStance, StoryOpponent?) in [(.orthodox, nil), (.southpaw, .pressure)] {
            let saved = StoryProgressStore(defaults: defaults)
            saved.equipStance(.southpaw)
            saved.equipAppearance(.southpaw)
            saved.equipStance(stance)
            saved.equipAppearance(appearance)
            let reopened = StoryProgressStore.developerPreview(defaults: defaults)
            XCTAssertEqual(reopened.progress.equippedStance, stance)
            XCTAssertEqual(reopened.progress.equippedAppearance, appearance)
            for opponent: StoryOpponent? in [nil, .basic] {
                let controller = GameController(persistsProgress: false, feedbackEnabled: false,
                    storyOpponent: opponent, storyStore: reopened)
                XCTAssertEqual(controller.playerStance, stance)
                XCTAssertEqual(controller.equippedAppearance, appearance)
                controller.start(resumingStory: false, shortStoryIntroduction: true)
                controller.finishStoryIntroduction()
                XCTAssertEqual(controller.engine.player.stance, stance)
                XCTAssertEqual(controller.playerStance, stance)
                XCTAssertEqual(StoryProgressStore.developerPreview(defaults: defaults).progress.equippedStance, stance)
            }
        }
    }

    func testStoryResumePreservesCheckpointStanceWithoutOverwritingFutureSelection() throws {
        let store = StoryProgressStore.developerPreview(defaults: nil)
        let engine = CombatEngine(persistHabits: false, storyOpponent: .basic)
        engine.player.stance = .southpaw
        engine.startSession()
        store.save(try XCTUnwrap(engine.storyCheckpoint()))
        store.equipStance(.orthodox)
        let controller = GameController(persistsProgress: false, feedbackEnabled: false,
            storyOpponent: .basic, storyStore: store)
        XCTAssertEqual(controller.playerStance, .orthodox)
        controller.start(resumingStory: true)
        XCTAssertEqual(controller.playerStance, .southpaw)
        XCTAssertEqual(controller.engine.player.stance, .southpaw)
        XCTAssertEqual(store.progress.equippedStance, .orthodox)
    }
    #endif

    func testBackgroundMusicIsLimitedToPreparationScreens() throws {
        let music = BackgroundMusicPlayer()
        let player = try XCTUnwrap(music.player)
        defer { music.update(isActive: false, isMuted: false) }
        for screen: AppScreen in [.loading, .mainMenu, .storySelection] {
            XCTAssertTrue(screen.allowsBackgroundMusic)
            music.update(isActive: screen.allowsBackgroundMusic, isMuted: false)
            XCTAssertTrue(player.isPlaying, music.errorMessage ?? "Menu music did not play.")
        }
        player.currentTime = 5
        for screen: AppScreen in [.vsSplash, .battle, .practice, .storyBattle, .storySceneReplay] {
            XCTAssertFalse(screen.allowsBackgroundMusic)
            music.update(isActive: screen.allowsBackgroundMusic, isMuted: false)
            XCTAssertFalse(player.isPlaying)
            XCTAssertTrue(music.player === player)
        }
        music.update(isActive: AppScreen.mainMenu.allowsBackgroundMusic, isMuted: false)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentTime, 5, accuracy: 0.2)
        music.update(isActive: true, isMuted: true)
        XCTAssertFalse(player.isPlaying)
    }

    func testCrowdCheerIsShortFadedAndReservedForHighlights() throws {
        let buffer = try XCTUnwrap(SoundManager.loadCrowdCheerBuffer(sampleRate: 44_100))
        XCTAssertEqual(buffer.format.sampleRate, 44_100)
        XCTAssertEqual(buffer.format.channelCount, 1)
        XCTAssertEqual(Double(buffer.frameLength) / buffer.format.sampleRate, 2, accuracy: 0.001)
        let channel = try XCTUnwrap(buffer.floatChannelData)[0]
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let peak = try XCTUnwrap(samples.map { abs($0) }.max())
        XCTAssertGreaterThan(peak, 0.01)
        XCTAssertLessThanOrEqual(peak, 0.251)
        XCTAssertLessThan(try XCTUnwrap(samples.prefix(10).map { abs($0) }.max()), 0.002)
        XCTAssertLessThan(try XCTUnwrap(samples.suffix(10).map { abs($0) }.max()), 0.0002)
        for attacker: Combatant in [.player, .rival] {
            for knockout in [false, true] {
                let impact = CombatImpact(attacker: attacker, punch: .leftHook, damage: 20,
                    guarded: false, guardBroken: true, counter: true, perfectCounter: true, knockout: knockout)
                if knockout {
                    XCTAssertEqual(SoundManager.crowdReactionVolume(for: .impact(impact)), 0.46)
                } else {
                    XCTAssertNil(SoundManager.crowdReactionVolume(for: .impact(impact)))
                }
            }
        }
        XCTAssertEqual(SoundManager.crowdReactionVolume(for: .roundEnded(outcome: .playerWin, knockout: false)), 0.34)
        for outcome: RoundOutcome in [.playerWin, .playerLoss, .draw] {
            XCTAssertNil(SoundManager.crowdReactionVolume(for: .roundEnded(outcome: outcome, knockout: true)))
        }
        XCTAssertNil(SoundManager.crowdReactionVolume(for: .roundEnded(outcome: .playerLoss, knockout: false)))
        XCTAssertNil(SoundManager.crowdReactionVolume(for: .roundEnded(outcome: .draw, knockout: false)))
        XCTAssertNil(SoundManager.crowdReactionVolume(for: .roundStarted))
        XCTAssertNil(SoundManager.crowdReactionVolume(for: .dodge(fighter: .player, grade: .perfect)))
    }

    func testBackgroundMusicLoopsAndRespectsMuteForegroundAndInterruptions() async throws {
        let music = BackgroundMusicPlayer()
        let player = try XCTUnwrap(music.player, music.errorMessage ?? "Music was not loaded.")
        XCTAssertEqual(player.numberOfLoops, -1)
        XCTAssertEqual(player.numberOfChannels, 2)
        XCTAssertEqual(player.duration, 21.36, accuracy: 0.15)
        XCTAssertEqual(player.volume, 0.16, accuracy: 0.001)
        music.update(isActive: true, isMuted: false)
        defer { music.update(isActive: false, isMuted: false) }
        XCTAssertTrue(player.isPlaying, music.errorMessage ?? "Playback did not start.")
        player.currentTime = 5
        music.update(isActive: true, isMuted: false)
        XCTAssertTrue(music.player === player)
        XCTAssertEqual(player.currentTime, 5, accuracy: 0.2)
        music.update(isActive: true, isMuted: true)
        XCTAssertFalse(player.isPlaying)
        music.update(isActive: false, isMuted: false)
        XCTAssertFalse(player.isPlaying)
        music.update(isActive: true, isMuted: false)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentTime, 5, accuracy: 0.2)
        music.interruptionBegan()
        XCTAssertFalse(player.isPlaying)
        music.update(isActive: false, isMuted: false)
        music.update(isActive: true, isMuted: false)
        XCTAssertFalse(player.isPlaying)
        music.interruptionEnded(shouldResume: false)
        XCTAssertFalse(player.isPlaying)
        music.update(isActive: true, isMuted: false)
        XCTAssertFalse(player.isPlaying)
        music.interruptionEnded(shouldResume: true)
        XCTAssertTrue(player.isPlaying)
        player.currentTime = player.duration - 0.05
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(player.isPlaying)
        XCTAssertLessThan(player.currentTime, 1, "The track did not repeat at its end.")
    }

    func testModeFadesUseTheSharedFastTimingWithoutAnimatingCombatOrCinematics() {
        let modes: [AppScreen] = [.mainMenu, .storySelection, .practice]
        let timedScreens: [AppScreen] = [.loading, .vsSplash, .battle, .storyBattle, .storySceneReplay]
        for source in modes {
            for destination in modes {
                let animation = source.modeTransitionAnimation(to: destination, reducedMotion: false)
                if source == destination {
                    XCTAssertNil(animation)
                } else {
                    XCTAssertEqual(animation, .easeOut(duration: 0.20))
                }
            }
            for destination in timedScreens {
                XCTAssertNil(source.modeTransitionAnimation(to: destination, reducedMotion: false))
                XCTAssertNil(destination.modeTransitionAnimation(to: source, reducedMotion: false))
            }
        }
        for source in timedScreens {
            for destination in timedScreens {
                XCTAssertNil(source.modeTransitionAnimation(to: destination, reducedMotion: false))
            }
        }
        XCTAssertLessThanOrEqual(UIStyleKit.fastDuration, 0.20)
    }

    func testApprovedBrandAssetsAndLaunchScreenUseTheSharedWordmark() throws {
        for name in ["RivalWordmark", "LaunchLogo", "ArenaVictory", "GymPosterArt", "StoryLineup", "StoryArena"] {
            XCTAssertNotNil(UIImage(named: name), "Missing approved brand asset: \(name)")
        }
        let mark = try XCTUnwrap(UIImage(named: "RivalWordmark"))
        XCTAssertEqual(mark.size.width / mark.size.height, 1064 / 300, accuracy: 0.01)
        let launchLogo = try XCTUnwrap(UIImage(named: "LaunchLogo"))
        XCTAssertEqual(launchLogo.size, CGSize(width: 148, height: 42))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UILaunchStoryboardName") as? String, "LaunchScreen")
        let launch = try XCTUnwrap(UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController())
        launch.view.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        launch.view.layoutIfNeeded()
        let image = try XCTUnwrap(launch.view.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(image.frame.width, 148, accuracy: 0.01)
        XCTAssertEqual(image.frame.height, 42, accuracy: 0.01)
        XCTAssertEqual(image.frame.minY, 32, accuracy: 0.01)
        XCTAssertEqual(image.frame.midX, launch.view.bounds.midX, accuracy: 0.01)
    }

    func testGymGuideCopyIsAvailableInEveryLanguage() {
        for language in AppLanguage.allCases {
            for key in [L.gymGuideTitle, .gymGuideIntroduction, .gymGuideDistance, .gymGuideDefense,
                        .gymGuideCombinations, .gymGuideResume] {
                XCTAssertFalse(key.text(for: language).isEmpty)
            }
        }
        XCTAssertEqual(L.gymGuideTitle.text(for: .korean), "연습 안내")
        XCTAssertEqual(L.gymGuideResume.text(for: .english), "Back to practice")
        XCTAssertEqual(L.gymGuideResume.text(for: .japanese), "練習に戻る")
    }

    func testLockerSamplesUseTheOriginalPreviewCameraAndEquipment() throws {
        let scene = StylePreviewScene()
        scene.configure()
        scene.setReducedMotion(true)
        scene.background.contents = UIColor.clear
        let label = try XCTUnwrap(scene.rootNode.childNode(withName: "playerIdentityLabel", recursively: true))
        label.isHidden = true
        let camera = scene.cameraNode.simdTransform
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.cameraNode

        for outfit in OutfitID.allCases {
            scene.setOutfit(outfit)
            scene.update(at: 0)
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 512, height: 512),
                                          antialiasingMode: .multisampling4X)
            let source = try XCTUnwrap(image.cgImage)
            let crop = try XCTUnwrap(source.cropping(to: CGRect(x: 172, y: 278, width: 160, height: 100)))
            let attachment = XCTAttachment(image: UIImage(cgImage: crop))
            attachment.name = "LockerOutfit-\(outfit.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(scene.cameraNode.simdTransform, camera)
        }
        scene.setOutfit(.classic)
        for style in FightStyle.allCases {
            scene.setStyle(style)
            scene.update(at: 0)
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 256, height: 256),
                                          antialiasingMode: .multisampling4X)
            let attachment = XCTAttachment(image: image)
            attachment.name = "LockerStyle-\(style.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(scene.cameraNode.simdTransform, camera)
        }
        XCTAssertEqual(scene.cameraNode.camera?.fieldOfView, 40)
    }

    func testEnlargedLockerPreviewKeepsAllModelsInsideTheFixedCamera() throws {
        let scene = StylePreviewScene()
        scene.configure()
        let originalCamera = scene.cameraNode.simdTransform
        scene.setEnlargedPreview(true)
        scene.setChampionBelt(true)
        let camera = scene.cameraNode.simdTransform
        let size = CGSize(width: 308.6666666666667, height: 224.6666666666667)
        let view = SCNView(frame: CGRect(origin: .zero, size: size))
        view.scene = scene
        view.pointOfView = scene.cameraNode
        var previews: [(FightStyle, StoryOpponent?)] = FightStyle.allCases.map { ($0, nil) }
        previews += StoryOpponent.allCases.map { (.standard, $0) }
        for (index, preview) in previews.enumerated() {
            scene.setAppearance(preview.1)
            scene.setStyle(preview.0)
            scene.setOutfit(.blackout)
            for frame in 0..<16 {
                scene.update(at: Double(index * 17 + frame))
                _ = view.snapshot()
                var minX = Float.greatestFiniteMagnitude
                var minY = Float.greatestFiniteMagnitude
                var maxX = -Float.greatestFiniteMagnitude
                var maxY = -Float.greatestFiniteMagnitude
                scene.rootNode.enumerateChildNodes { node, _ in
                    guard let geometry = node.geometry else { return }
                    var ancestor: SCNNode? = node
                    while let current = ancestor {
                        guard !current.isHidden, current.opacity > 0,
                              current.name != "playerIdentityLabel" else { return }
                        ancestor = current.parent
                    }
                    let box = geometry.boundingBox
                    for x in [box.min.x, box.max.x] {
                        for y in [box.min.y, box.max.y] {
                            for z in [box.min.z, box.max.z] {
                                let point = view.projectPoint(node.convertPosition(SCNVector3(x, y, z), to: nil))
                                XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                                minX = min(minX, point.x)
                                minY = min(minY, point.y)
                                maxX = max(maxX, point.x)
                                maxY = max(maxY, point.y)
                            }
                        }
                    }
                }
                let description = "\(preview), frame \(frame), bounds \(minX),\(minY),\(maxX),\(maxY)"
                XCTAssertGreaterThanOrEqual(minX, 3, description)
                XCTAssertGreaterThanOrEqual(minY, 3, description)
                XCTAssertLessThanOrEqual(maxX, Float(size.width) - 3, description)
                XCTAssertLessThanOrEqual(maxY, Float(size.height) - 3, description)
                XCTAssertEqual(scene.cameraNode.simdTransform, camera)
            }
        }
        XCTAssertEqual(scene.cameraNode.camera?.fieldOfView, 38)
        scene.setEnlargedPreview(false)
        XCTAssertEqual(scene.cameraNode.camera?.fieldOfView, 40)
        XCTAssertEqual(scene.cameraNode.simdTransform, originalCamera)
        for outfit in OutfitID.allCases {
            let sample = try XCTUnwrap(UIImage(named: outfit.lockerSampleAssetName))
            XCTAssertEqual(sample.size, CGSize(width: 160, height: 100))
        }
    }

    func testEveryLockerChoiceHasItsActualModelSampleAndLocalizedStateCopy() {
        let names = OutfitID.allCases.map(\.lockerSampleAssetName) + FightStyle.allCases.map(\.lockerSampleAssetName)
        XCTAssertEqual(Set(names).count, 15)
        for name in names {
            XCTAssertNotNil(UIImage(named: name), "Missing original-model locker sample: \(name)")
        }
        for language in AppLanguage.allCases {
            for key in [L.lockerPreparation, .lockerStylesTitle, .lockerOutfitsTitle, .lockerStancesTitle,
                        .lockerReady, .lockerSelectionHint, .outfitOwnedLabel] {
                XCTAssertFalse(key.text(for: language).isEmpty)
            }
        }
    }

    func testRivalPositioningIsNotAPriceTierAcrossLanguages() {
        for language in AppLanguage.allCases {
            let expectedBout: String
            let premiumWord: String
            switch language {
            case .korean:
                expectedBout = "RIVAL 대전"
                premiumWord = "프리미엄"
            case .english:
                expectedBout = "RIVAL BOUT"
                premiumWord = "PREMIUM"
            case .japanese:
                expectedBout = "RIVAL対戦"
                premiumWord = "プレミアム"
            }
            XCTAssertEqual(StoryPurchaseText.rivalBout.text(for: language), expectedBout)
            XCTAssertTrue(StoryPurchaseText.rivalRewards.text(for: language).contains("RIVAL"))
            XCTAssertTrue(StoryPurchaseText.offerTitle.text(for: language).contains(premiumWord))
            XCTAssertTrue(StoryPurchaseText.storyButtonSubtitle.text(for: language).contains(premiumWord))
            let copy = [StoryPurchaseText.rivalBout, .rivalRewards, .rivalRewardsDetail, .offerTitle, .storyButtonSubtitle]
                .map { $0.text(for: language) }.joined(separator: " ")
            for forbidden in ["무료", "FREE", "無料"] {
                XCTAssertFalse(copy.localizedCaseInsensitiveContains(forbidden))
            }
        }
    }

    func testSceneLedLayoutReservesTheCenterForTheOriginalPortrait() {
        for size in [CGSize(width: 568, height: 320), CGSize(width: 667, height: 375),
                     CGSize(width: 718, height: 354), CGSize(width: 830, height: 410)] {
            let layout = MainMenuLayout(size: size)
            XCTAssertGreaterThanOrEqual(layout.featureWidth, 168)
            XCTAssertGreaterThanOrEqual(layout.storyWidth, 158)
            XCTAssertGreaterThanOrEqual(layout.portraitClearWidth, 160)
            XCTAssertEqual(layout.featureWidth + layout.storyWidth + layout.portraitClearWidth + MainMenuLayout.gutter * 2,
                           size.width - MainMenuLayout.horizontalPadding * 2, accuracy: 0.001)
        }
    }

    func testEveryStoryEncounterHasItsApprovedPortraitAndRosterAsset() {
        for name in ["StoryLineup", "StoryArena"] +
            StoryOpponent.allCases.flatMap({ [$0.storyPortraitAssetName, $0.storyBustAssetName] }) {
            XCTAssertNotNil(UIImage(named: name), "Missing approved UI asset: \(name)")
        }
        XCTAssertEqual(StoryOpponent.allCases.count, 7)
        XCTAssertNotEqual(StoryOpponent.basic.storyPortraitAssetName, StoryOpponent.rival.storyPortraitAssetName)
    }

    func testBoxingCopyIsLocalizedWithoutClaimingAnObservedRead() {
        for language in AppLanguage.allCases {
            for key in [L.menuHeadline, .menuCornerLine, .menuFightAction] {
                XCTAssertFalse(key.text(for: language).isEmpty)
            }
            XCTAssertFalse(L.menuCornerLine.text(for: language).contains("%"))
            XCTAssertFalse(L.resetConfirmBody.text(for: language).isEmpty)
        }
        XCTAssertEqual(L.menuFightAction.text(for: .korean), "경기 시작")
        XCTAssertEqual(L.menuCornerLine.text(for: .english), "If he reads your jab, go to the body.")
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