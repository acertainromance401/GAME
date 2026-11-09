import StoreKitTest
import XCTest
import UIKit

final class RIVALUITests: XCTestCase {
    @MainActor
    func testCompactTopHUDKeepsNormalFightControlsAndStoryClock() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "fight"
        app.launch()
        defer { app.terminate() }
        let jab = app.buttons["JAB"]
        XCTAssertTrue(jab.waitForExistence(timeout: 8))
        let clock = app.descendants(matching: .any)["combatRoundClock"]
        let commentary = app.staticTexts["combatCommentary"]
        XCTAssertTrue(commentary.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(clock.frame.height, 45)
        XCTAssertEqual(clock.frame.width, 100, accuracy: 0.5)
        XCTAssertEqual(clock.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertEqual(commentary.frame.height, 18, accuracy: 0.5)
        XCTAssertLessThanOrEqual(commentary.frame.maxY, app.frame.minY + 80)
        XCTAssertGreaterThanOrEqual(commentary.frame.minY, clock.frame.maxY + 3)
        for identifier in ["combatPlayerMeter", "combatRivalMeter"] {
            let meter = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(meter.exists)
            XCTAssertLessThanOrEqual(meter.frame.height, 46)
            XCTAssertLessThanOrEqual(meter.frame.maxY, commentary.frame.minY - 4)
        }
        let compact = app.frame.height < 390 || app.frame.width < 700
        for identifier in ["WEAVE_LEFT", "WEAVE_RIGHT"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.isHittable)
            XCTAssertEqual(control.frame.width, compact ? 52 : 58, accuracy: 0.5)
            XCTAssertEqual(control.frame.height, compact ? 46 : 54, accuracy: 0.5)
        }
        let cross = app.buttons["CROSS"]
        let backstep = app.buttons["BACKSTEP"]
        XCTAssertTrue(jab.isHittable)
        XCTAssertTrue(cross.isHittable)
        XCTAssertEqual(jab.frame.width, compact ? 80 : 94, accuracy: 0.5)
        XCTAssertEqual(jab.frame.height, compact ? 66 : 76, accuracy: 0.5)
        XCTAssertEqual(cross.frame.minX - jab.frame.maxX, 7, accuracy: 0.5)
        XCTAssertEqual(jab.frame.minY - backstep.frame.maxY, 6, accuracy: 0.5)
        XCTAssertEqual(backstep.frame.midX, (jab.frame.midX + cross.frame.midX) / 2, accuracy: 0.5)
        let fightImage = try screenImage(XCUIScreen.main.screenshot(), size: app.frame.size)
        let fightShot = XCTAttachment(image: fightImage)
        fightShot.name = "compact-top-hud-fight"
        fightShot.lifetime = .keepAlways
        add(fightShot)
        app.terminate()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "story-corner"
        app.launch()
        let storyClock = app.descendants(matching: .any)["storyRoundClock"]
        XCTAssertTrue(storyClock.waitForExistence(timeout: 8))
        XCTAssertEqual(storyClock.frame.width, 126, accuracy: 0.5)
        XCTAssertLessThanOrEqual(storyClock.frame.height, 61)
        XCTAssertLessThanOrEqual(storyClock.frame.maxY, app.frame.minY + 72)
        let storyShot = XCTAttachment(image: try screenImage(XCUIScreen.main.screenshot(), size: app.frame.size))
        storyShot.name = "compact-top-hud-story"
        storyShot.lifetime = .keepAlways
        add(storyShot)
    }

    @MainActor
    func testEnlargedLockerKeepsNormalControlsAndEquipmentStates() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "0"
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["mainMenuWaitingRoom"].waitForExistence(timeout: 8))
        app.buttons["mainMenuWaitingRoom"].tap()
        XCTAssertTrue(app.buttons["lockerDone"].waitForExistence(timeout: 5))
        assertLockerControlsInsideViewport(app)
        let identifiers = ["waitingRoomClose", "lockerDone", "lockerStyleTab", "lockerOutfitTab",
                           "lockerStanceTab", "lockerStoryTab"]
        let frames = identifiers.map { ($0, app.buttons[$0].frame) }
        app.buttons["lockerStyle-in_fighting"].tap()
        XCTAssertTrue(app.buttons["lockerStyle-in_fighting"].isSelected)
        capture("locker-enlarged-styles")
        app.buttons["lockerOutfitTab"].tap()
        let blackout = app.buttons["lockerOutfit-blackout"]
        reveal(blackout, in: app.scrollViews["lockerOptions"])
        blackout.tap()
        XCTAssertTrue(blackout.isSelected)
        XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].label.contains("미리보기"))
        for (identifier, frame) in frames {
            XCTAssertEqual(app.buttons[identifier].frame, frame)
            XCTAssertTrue(app.buttons[identifier].isHittable)
        }
        let preview = app.otherElements["lockerBoxerPreview"].frame
        let metadata = try JSONSerialization.data(withJSONObject: [
            "preview": [Double(preview.minX), Double(preview.minY), Double(preview.width), Double(preview.height)],
            "controls": Dictionary(uniqueKeysWithValues: frames.map { identifier, frame in
                (identifier, [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)])
            })
        ])
        let attachment = XCTAttachment(data: metadata, uniformTypeIdentifier: "public.json")
        attachment.name = "locker-enlarged-geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        capture("locker-enlarged-outfit")
        app.buttons["lockerDone"].tap()
        XCTAssertTrue(app.buttons["mainMenuWaitingRoom"].waitForExistence(timeout: 5))
        app.buttons["mainMenuWaitingRoom"].tap()
        XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].label.contains("착용 중"))
        app.buttons["lockerStanceTab"].tap()
        let southpaw = app.buttons["lockerStance-southpaw"]
        reveal(southpaw, in: app.scrollViews["lockerOptions"])
        southpaw.tap()
        XCTAssertTrue(southpaw.isSelected)
        XCTAssertTrue(app.staticTexts["lockerStancePreviewStatus"].label.contains("미리보기"))
    }

    @MainActor
    func testPaperLockerKeepsStyleOutfitStanceAndStoryStatesAccurate() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        for language in ["ko", "en", "ja"] {
            let app = XCUIApplication()
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
            app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = language == "en" ? "1" : "0"
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launch()
            XCTAssertTrue(app.buttons["mainMenuWaitingRoom"].waitForExistence(timeout: 8))
            app.buttons["mainMenuWaitingRoom"].tap()
            XCTAssertTrue(app.buttons["lockerDone"].waitForExistence(timeout: 5))
            assertLockerControlsInsideViewport(app)
            XCTAssertGreaterThan(app.otherElements["lockerTabs"].frame.minX, app.frame.width * 0.35)
            capture("locker-native-\(language)-styles")
            for style in ["out_boxing", "in_fighting", "standard"] {
                let choice = app.buttons["lockerStyle-\(style)"]
                XCTAssertTrue(choice.isHittable)
                choice.tap()
                XCTAssertTrue(choice.isSelected)
                XCTAssertTrue(choice.label.contains(app.staticTexts["lockerSelectedStyle"].label))
                XCTAssertFalse(app.staticTexts["lockerSelectedStyleDetail"].label.isEmpty)
            }
            app.buttons["lockerOutfitTab"].tap()
            let options = app.scrollViews["lockerOptions"]
            let blackout = app.buttons["lockerOutfit-blackout"]
            reveal(blackout, in: options)
            XCTAssertTrue(blackout.isHittable)
            blackout.tap()
            XCTAssertTrue(blackout.isSelected)
            let previewWord = language == "ko" ? "미리보기" : language == "en" ? "Preview" : "プレビュー"
            XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].label.contains(previewWord))
            reveal(app.staticTexts["lockerSelectedOutfitRequirement"], in: options)
            XCTAssertFalse(app.staticTexts["lockerSelectedOutfitRequirement"].label.isEmpty)
            capture("locker-native-\(language)-outfit-preview")
            app.buttons["lockerDone"].tap()
            XCTAssertTrue(app.buttons["mainMenuWaitingRoom"].waitForExistence(timeout: 5))
            app.buttons["mainMenuWaitingRoom"].tap()
            XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].waitForExistence(timeout: 5))
            let equippedWord = language == "ko" ? "착용 중" : language == "en" ? "Equipped" : "着用中"
            XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].label.contains(equippedWord))
            app.buttons["lockerOutfitTab"].tap()
            let classic = app.buttons["lockerOutfit-classic"]
            reveal(classic, in: app.scrollViews["lockerOptions"])
            classic.tap()
            XCTAssertTrue(classic.isSelected)
            XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].label.contains(equippedWord))
            app.buttons["lockerStanceTab"].tap()
            let southpaw = app.buttons["lockerStance-southpaw"]
            reveal(southpaw, in: app.scrollViews["lockerOptions"])
            southpaw.tap()
            XCTAssertTrue(southpaw.isSelected)
            XCTAssertTrue(app.staticTexts["lockerStancePreviewStatus"].label.contains(previewWord))
            capture("locker-native-\(language)-stance-preview")
            app.buttons["lockerStoryTab"].tap()
            XCTAssertTrue(app.buttons["lockerOutfit-storyStarter"].exists)
            XCTAssertTrue(app.buttons["lockerOutfit-storyChampion"].exists)
            let purchase = app.buttons["lockerStoryPurchase"]
            if purchase.exists {
                reveal(purchase, in: app.scrollViews["lockerOptions"])
                purchase.tap()
                XCTAssertTrue(app.buttons["storyPurchaseClose"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["waitingRoomClose"].exists)
                XCTAssertFalse(app.buttons["lockerDone"].exists)
                app.buttons["storyPurchaseClose"].tap()
                XCTAssertTrue(app.buttons["lockerStoryTab"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["lockerStoryTab"].isSelected)
            }
            app.buttons["lockerDone"].tap()
            XCTAssertTrue(app.buttons["mainMenuWaitingRoom"].waitForExistence(timeout: 5))
            app.buttons["mainMenuWaitingRoom"].tap()
            XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].label.contains(equippedWord))
            XCTAssertTrue(app.staticTexts["lockerStancePreviewStatus"].label.contains(equippedWord))
            app.buttons["waitingRoomClose"].tap()
            app.terminate()
        }
    }

    @MainActor
    func testPaperLockerLargeTextKeepsAllChoicesAndExitReachable() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        for language in ["ko", "en", "ja"] {
            let app = XCUIApplication()
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
            app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "1"
            app.launchArguments = ["-pixelBoxingLanguage", language, "-UIPreferredContentSizeCategoryName",
                                   "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            XCTAssertTrue(app.buttons["mainMenuWaitingRoom"].waitForExistence(timeout: 8))
            reveal(app.buttons["mainMenuWaitingRoom"], in: app.scrollViews.firstMatch)
            app.buttons["mainMenuWaitingRoom"].tap()
            XCTAssertTrue(app.buttons["lockerDone"].waitForExistence(timeout: 5))
            assertLockerControlsInsideViewport(app)
            let options = app.scrollViews["lockerOptions"]
            let style = app.buttons["lockerStyle-out_boxing"]
            reveal(style, in: options)
            style.tap()
            capture("locker-native-\(language)-large-style")
            XCTAssertTrue(style.isSelected)
            app.buttons["lockerOutfitTab"].tap()
            let blackout = app.buttons["lockerOutfit-blackout"]
            reveal(blackout, in: app.scrollViews["lockerOptions"])
            XCTAssertTrue(blackout.isHittable)
            blackout.tap()
            XCTAssertTrue(blackout.isSelected)
            let requirement = app.staticTexts["lockerSelectedOutfitRequirement"]
            let outfitOptions = app.scrollViews["lockerOptions"]
            reveal(requirement, in: outfitOptions, fullyVisible: true)
            XCTAssertTrue(requirement.isHittable)
            XCTAssertGreaterThanOrEqual(requirement.frame.minY, outfitOptions.frame.minY)
            XCTAssertLessThanOrEqual(requirement.frame.maxY, outfitOptions.frame.maxY)
            let previewWord = language == "ko" ? "미리보기" : language == "en" ? "Preview" : "プレビュー"
            XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].label.contains(previewWord))
            capture("locker-native-\(language)-large-text")
            app.buttons["lockerStanceTab"].tap()
            let stance = app.buttons["lockerStance-orthodox"]
            reveal(stance, in: app.scrollViews["lockerOptions"])
            XCTAssertTrue(stance.isHittable)
            stance.tap()
            XCTAssertTrue(stance.isSelected)
            app.buttons["lockerStoryTab"].tap()
            let storyOptions = app.scrollViews["lockerOptions"]
            let starter = app.buttons["lockerOutfit-storyStarter"]
            reveal(starter, in: storyOptions)
            capture("locker-native-\(language)-large-story-choice")
            XCTAssertTrue(starter.isHittable, starter.debugDescription)
            starter.tap()
            XCTAssertTrue(starter.isSelected)
            let starterRequirement = app.staticTexts["lockerOutfitRequirement-storyStarter"]
            reveal(starterRequirement, in: storyOptions, fullyVisible: true)
            XCTAssertTrue(starterRequirement.isHittable)
            XCTAssertGreaterThanOrEqual(starterRequirement.frame.minY, storyOptions.frame.minY)
            XCTAssertLessThanOrEqual(starterRequirement.frame.maxY, storyOptions.frame.maxY)
            capture("locker-native-\(language)-large-story-requirement")
            let appearanceIdentifiers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lockerAppearance-"))
                .allElementsBoundByIndex.filter { $0.isEnabled }.map(\.identifier)
            XCTAssertFalse(appearanceIdentifiers.isEmpty)
            for identifier in appearanceIdentifiers {
                let appearance = app.buttons[identifier]
                reveal(appearance, in: storyOptions, fullyVisible: true)
                XCTAssertTrue(appearance.isHittable)
                appearance.tap()
                capture("locker-native-\(language)-large-\(identifier)")
                XCTAssertTrue(appearance.isSelected, appearance.debugDescription)
            }
            let champion = app.buttons["lockerOutfit-storyChampion"]
            reveal(champion, in: storyOptions)
            XCTAssertTrue(champion.isHittable)
            champion.tap()
            XCTAssertTrue(champion.isSelected)
            let southpaw = app.buttons["lockerStance-southpaw"]
            reveal(southpaw, in: storyOptions)
            XCTAssertTrue(southpaw.isHittable)
            southpaw.tap()
            XCTAssertTrue(southpaw.isSelected)
            assertLockerControlsInsideViewport(app)
            app.buttons["waitingRoomClose"].tap()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    private func assertLockerControlsInsideViewport(_ app: XCUIApplication) {
        for id in ["waitingRoomClose", "lockerDone", "lockerStyleTab", "lockerOutfitTab", "lockerStanceTab", "lockerStoryTab"] {
            let control = app.buttons[id]
            XCTAssertTrue(control.isHittable, id)
            let height = control.frame.height
            XCTAssertGreaterThanOrEqual(height + height.ulp * 8, id == "lockerDone" ? 48 : 44, id)
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX + 10, id)
            XCTAssertGreaterThanOrEqual(control.frame.minY, app.frame.minY + 10, id)
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX - 10, id)
            XCTAssertLessThanOrEqual(control.frame.maxY, app.frame.maxY - 10, id)
        }
    }

    @MainActor
    func testStoryRosterSitsBelowReplayControlsAndBesidePreparation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        for language in ["ko", "en", "ja"] {
            let app = XCUIApplication()
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "story-selection"
            app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "1"
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launch()
            let list = app.scrollViews["storyOpponentList"]
            XCTAssertTrue(list.waitForExistence(timeout: 10))
            let action = app.buttons["storyChallenge"]
            XCTAssertTrue(action.isHittable)
            XCTAssertLessThanOrEqual(list.frame.maxY, action.frame.minY)
            XCTAssertLessThanOrEqual(action.frame.minY - list.frame.maxY, 16)
            XCTAssertGreaterThan(list.frame.maxY, app.frame.height * 0.70)
            let back = app.buttons["storyBack"]
            XCTAssertTrue(back.isHittable)
            XCTAssertGreaterThanOrEqual(back.frame.minX, app.frame.minX + 10)
            XCTAssertLessThanOrEqual(back.frame.maxX, app.frame.maxX - 10)
            for id in ["storyReplayIntroduction", "storyReplayRivalScene"] {
                let replay = app.buttons[id]
                XCTAssertTrue(replay.isHittable)
                XCTAssertGreaterThanOrEqual(replay.frame.height, 44)
                XCTAssertGreaterThanOrEqual(replay.frame.width, 44)
                XCTAssertLessThanOrEqual(replay.frame.maxY, list.frame.minY)
                XCTAssertLessThanOrEqual(replay.frame.maxX, app.frame.maxX - 10)
            }
            capture("story-lower-roster-\(language)-lineup")
            app.buttons["storyOpponent_pressure"].tap()
            XCTAssertTrue(app.buttons["storyOpponent_pressure"].isSelected)
            capture("story-lower-roster-\(language)-selected")
            app.buttons["storyOpponent_basic"].tap()
            app.buttons["storyReplayIntroduction"].tap()
            XCTAssertTrue(app.buttons["storyIntroductionExit"].waitForExistence(timeout: 5))
            app.buttons["storyIntroductionExit"].tap()
            XCTAssertTrue(app.buttons["storyChallenge"].waitForExistence(timeout: 5))
            app.buttons["storyReplayRivalScene"].tap()
            XCTAssertTrue(app.buttons["storyRivalSceneSkip"].waitForExistence(timeout: 5))
            app.buttons["storyRivalSceneSkip"].tap()
            XCTAssertTrue(app.buttons["storyChallenge"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testApprovedFightCardAndVisibleRankingInEveryLanguage() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        for language in ["ko", "en", "ja"] {
            let app = XCUIApplication()
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
            app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "1"
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launch()
            let ranking = app.buttons["mainMenuLeaderboard"]
            XCTAssertTrue(ranking.waitForExistence(timeout: 10))
            XCTAssertTrue(ranking.isHittable)
            XCTAssertGreaterThanOrEqual(ranking.frame.height, 44)
            capture("native-approved-\(language)-main")
            ranking.tap()
            XCTAssertTrue(app.buttons["leaderboardClose"].waitForExistence(timeout: 5))
            app.buttons["leaderboardClose"].tap()
            app.buttons["mainMenuStory"].tap()
            XCTAssertTrue(app.buttons["storyShowLineup"].waitForExistence(timeout: 5))
            capture("native-approved-\(language)-story-lineup")
            let list = app.scrollViews["storyOpponentList"]
            for opponent in ["basic", "pressure", "outboxer", "counter", "southpaw", "slugger", "rival"] {
                let button = app.buttons["storyOpponent_\(opponent)"]
                for _ in 0..<7 {
                    if button.isHittable { break }
                    list.swipeLeft()
                }
                XCTAssertTrue(button.isHittable, "\(language): missing bout \(opponent)")
                button.tap()
                XCTAssertTrue(button.isSelected)
                XCTAssertTrue(button.label.contains(app.staticTexts["storySelectedOpponent"].label))
            }
            capture("native-approved-\(language)-story-selected")
            app.buttons["storyShowLineup"].tap()
            XCTAssertTrue(app.buttons["storyOpponent_rival"].isSelected)
            XCTAssertTrue(app.buttons["storyBack"].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons["storyChallenge"].frame.height, 48)
            app.buttons["storyBack"].tap()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testRivalCoreExperienceBrandingInEveryLanguage() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        for (language, rewards) in [("ko", "RIVAL 경기 보상"), ("en", "RIVAL BOUT REWARDS"), ("ja", "RIVAL対戦報酬")] {
            let app = XCUIApplication()
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launch()
            let rival = app.buttons["mainMenuContinue"]
            XCTAssertTrue(rival.waitForExistence(timeout: 10))
            XCTAssertTrue(rival.label.contains("RIVAL"))
            for forbidden in ["무료", "FREE", "無料"] {
                XCTAssertFalse(rival.label.localizedCaseInsensitiveContains(forbidden))
            }
            capture("rival-branding-\(language)-menu")
            app.buttons["mainMenuWaitingRoom"].tap()
            XCTAssertTrue(app.buttons["lockerOutfitTab"].waitForExistence(timeout: 5))
            app.buttons["lockerOutfitTab"].tap()
            XCTAssertTrue(app.staticTexts[rewards].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testMotionLabFrameControlsAndProductionPlayback() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-rival-motion-lab"]
        app.launch()
        XCTAssertTrue(app.buttons["motionLabContact"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["motionLabFrame"].label.contains("Frame 0 /"))
        app.buttons["motionLabForward"].tap()
        XCTAssertTrue(app.staticTexts["motionLabFrame"].label.contains("Frame 1 /"))
        app.buttons["motionLabBack"].tap()
        XCTAssertTrue(app.staticTexts["motionLabFrame"].label.contains("Frame 0 /"))
        app.buttons["motionLabContact"].tap()
        XCTAssertTrue(app.staticTexts["motionLabResult"].label.contains("HIT"))
        capture("motion-lab-jab-contact")
        app.segmentedControls["motionLabPunch"].buttons["CROSS"].tap()
        XCTAssertTrue(app.staticTexts["motionLabFrame"].label.contains("Frame 0 /"))
        app.buttons["motionLabContact"].tap()
        XCTAssertTrue(app.staticTexts["motionLabResult"].label.contains("HIT"))
        capture("motion-lab-cross-contact")
        app.buttons["motionLabReset"].tap()
        let initialFrame = app.staticTexts["motionLabFrame"].label
        app.buttons["motionLabPlay"].tap()
        XCTAssertEqual(app.buttons["motionLabPlay"].label, "Pause")
        let advancing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", initialFrame), object: app.staticTexts["motionLabFrame"])
        XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 3), .completed)
        app.buttons["motionLabPlay"].tap()
        XCTAssertEqual(app.buttons["motionLabPlay"].label, "Play")
        let pausedFrame = app.staticTexts["motionLabFrame"].label
        let unexpectedlyAdvancing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", pausedFrame), object: app.staticTexts["motionLabFrame"])
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedlyAdvancing], timeout: 0.5), .timedOut)
        app.terminate()
    }

    @MainActor
    func testCaptureReleaseReviewScreens() throws {
        try captureReleaseReviewScreens(language: "en")
    }

    @MainActor
    func testCaptureKoreanReleaseReviewScreens() throws {
        try captureReleaseReviewScreens(language: "ko")
    }

    @MainActor
    func testCaptureJapaneseReleaseReviewScreens() throws {
        try captureReleaseReviewScreens(language: "ja")
    }

    @MainActor
    private func captureReleaseReviewScreens(language: String) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let configuration = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "StoryReview", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let app = XCUIApplication()
        app.launchArguments = ["-pixelBoxingLanguage", language, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["mainMenuStory"].waitForExistence(timeout: 20))
        captureReleaseScreen("review-\(language)-01-main-menu", app: app)

        app.buttons["mainMenuStory"].tap()
        XCTAssertTrue(app.buttons["storyChallenge"].waitForExistence(timeout: 20))
        app.buttons["storyChallenge"].tap()
        let purchaseButton = app.buttons["storyPurchaseBuy"]
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 20))
        XCTAssertTrue(NSPredicate(format: "enabled == true").evaluate(with: purchaseButton)
            || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: purchaseButton)], timeout: 30) == .completed)
        XCTAssertTrue(purchaseButton.label.contains("2.99"))
        XCTAssertTrue(app.buttons["storyPurchaseRestore"].isHittable)
        captureReleaseScreen("review-\(language)-02-story-purchase", app: app)

        purchaseButton.tap()
        XCTAssertTrue(purchaseButton.waitForNonExistence(timeout: 30))
        XCTAssertTrue(app.buttons["storyChallenge"].waitForExistence(timeout: 15))
        if language == "en" {
            XCTAssertTrue(app.staticTexts["STORY ACCESS CONFIRMED"].waitForNonExistence(timeout: 8))
        }
        XCTAssertTrue(app.buttons["storyChallenge"].isEnabled)
        XCTAssertTrue(app.buttons["storyOpponent_basic"].isSelected)
        captureReleaseScreen("review-\(language)-03-story-progression", app: app)
        app.buttons["storyOpponent_southpaw"].tap()
        XCTAssertFalse(app.buttons["storyChallenge"].isEnabled)
        captureReleaseScreen("review-\(language)-06-story-southpaw", app: app)
        app.buttons["storyOpponent_outboxer"].tap()
        let lockedChallenge = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == false"), object: app.buttons["storyChallenge"])
        XCTAssertEqual(XCTWaiter.wait(for: [lockedChallenge], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["storyReplayIntroduction"].exists)
        XCTAssertFalse(app.buttons["storyReplayRivalScene"].exists)
        app.buttons["storyBack"].tap()

        app.buttons["mainMenuWaitingRoom"].tap()
        XCTAssertTrue(app.buttons["lockerDone"].waitForExistence(timeout: 10))
        app.buttons["lockerOutfitTab"].tap()
        captureReleaseScreen("review-\(language)-07-locker", app: app)
        app.buttons["lockerDone"].tap()

        app.buttons["mainMenuGym"].tap()
        XCTAssertTrue(app.buttons["gymExit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["JAB"].isHittable)
        captureReleaseScreen("review-\(language)-04-gym", app: app)
        app.buttons["gymExit"].tap()

        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 10))
        app.buttons["mainMenuContinue"].tap()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 15))
        captureReleaseScreen("review-\(language)-05-rival-fight", app: app)
        app.terminate()
    }

    @MainActor
    private func captureReleaseScreen(_ name: String, app: XCUIApplication) {
        // SceneKit's initial frame and route fades can lag behind accessibility.
        Thread.sleep(forTimeInterval: name.hasSuffix("01-main-menu") ? 2 : 0.8)
        for identifier in ["storyUnlockBanner", "outfitUnlockBanner"] {
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForNonExistence(timeout: 8))
        }
        capture(name)
    }

    @MainActor
    func testCaptureOpeningForVisualInspection() {
        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_OPENING_VISUAL_TEST"] = "1"
        app.launchEnvironment["RIVAL_OPENING_CAPTURE_BEAT"] = "1"
        app.launch()

        XCTAssertTrue(app.otherElements["appOpening"].waitForExistence(timeout: 8))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "RIVAL animated opening"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCaptureRedesignedMainMenuForVisualInspection() {
        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 8))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "RIVAL redesigned main menu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testStorySelectionKeepsSelectionAndActionsReachableInEveryLanguage() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        for language in ["ko", "en", "ja"] {
            let app = XCUIApplication()
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
            app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = language == "en" ? "1" : "0"
            app.launchArguments = ["-pixelBoxingLanguage", language]
            if language == "en" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            XCTAssertTrue(app.buttons["mainMenuStory"].waitForExistence(timeout: 8))
            reveal(app.buttons["mainMenuStory"], in: app.scrollViews.firstMatch)
            app.buttons["mainMenuStory"].tap()
            XCTAssertTrue(app.buttons["storyBack"].waitForExistence(timeout: 5))
            let list = app.scrollViews["storyOpponentList"]
            let pressure = app.buttons["storyOpponent_pressure"]
            XCTAssertTrue(pressure.waitForExistence(timeout: 5))
            reveal(pressure, in: list)
            XCTAssertTrue(pressure.isHittable)
            pressure.tap()
            XCTAssertTrue(pressure.isSelected)
            let selected = app.staticTexts["storySelectedOpponent"]
            XCTAssertTrue(selected.exists)
            XCTAssertTrue(pressure.label.contains(selected.label))
            let basic = app.buttons["storyOpponent_basic"]
            reveal(basic, in: list)
            basic.tap()
            XCTAssertTrue(basic.isSelected)
            reveal(pressure, in: list)
            pressure.tap()
            XCTAssertTrue(pressure.isSelected)
            XCTAssertFalse(basic.isSelected)
            XCTAssertTrue(pressure.label.contains(selected.label))
            let action = app.buttons["storyChallenge"]
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.height, 48)
            XCTAssertLessThanOrEqual(action.frame.maxY, app.frame.maxY)
            XCTAssertTrue(app.buttons["storyBack"].isHittable)
            capture("app-motion-story-selection-\(language)")
            let advice = app.staticTexts["storyOpponentAdvice"]
            reveal(advice, in: app.scrollViews["storyOpponentDetails"])
            XCTAssertTrue(advice.isHittable)
            XCTAssertFalse(advice.label.isEmpty)
            capture("app-motion-story-advice-\(language)")
            action.tap()
            let start = app.buttons["storyStartFresh"]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            XCTAssertTrue(start.isHittable)
            XCTAssertGreaterThanOrEqual(start.frame.height, 48)
            app.buttons["waitingRoomClose"].tap()
            XCTAssertTrue(pressure.waitForExistence(timeout: 5))
            XCTAssertTrue(pressure.isSelected)
            app.buttons["storyBack"].tap()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testInternalMenusMatchMainAndLockedOutfitStaysPreviewOnly() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launch()
        XCTAssertTrue(app.buttons["mainMenuWaitingRoom"].waitForExistence(timeout: 8))
        app.buttons["mainMenuWaitingRoom"].tap()
        XCTAssertTrue(app.buttons["lockerOutfitTab"].waitForExistence(timeout: 3))
        let tabHeight = app.buttons["lockerOutfitTab"].frame.height
        // Accessibility frame subtraction can lose a few floating-point ULPs.
        XCTAssertGreaterThanOrEqual(tabHeight + tabHeight.ulp * 8, 44)
        capture("RIVAL full-screen locker - styles")
        app.buttons["lockerOutfitTab"].tap()
        XCTAssertTrue(app.buttons["lockerOutfitTab"].isSelected)
        let lockedOutfit = app.buttons["lockerOutfit-blackout"]
        XCTAssertTrue(lockedOutfit.waitForExistence(timeout: 3))
        reveal(lockedOutfit, in: app.scrollViews["lockerOptions"])
        XCTAssertTrue(lockedOutfit.isHittable)
        lockedOutfit.tap()
        XCTAssertTrue(lockedOutfit.isSelected)
        XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].label.contains("미리보기"))
        capture("RIVAL full-screen locker - outfit preview")
        app.buttons["waitingRoomClose"].tap()
        app.buttons["mainMenuWaitingRoom"].tap()
        XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["lockerPreviewStatus"].label.contains("착용 중"))
        app.buttons["waitingRoomClose"].tap()

        app.buttons["mainMenuSettings"].tap()
        XCTAssertTrue(app.buttons["settingsClose"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settingsSound"].isHittable)
        XCTAssertTrue(app.buttons["settingsHaptics"].isHittable)
        capture("RIVAL compact settings panel")
        app.buttons["settingsClose"].tap()

        app.buttons["mainMenuLeaderboard"].tap()
        XCTAssertTrue(app.buttons["leaderboardClose"].waitForExistence(timeout: 3))
        capture("RIVAL full-screen leaderboard")
        app.buttons["leaderboardClose"].tap()

        app.buttons["mainMenuGym"].tap()
        XCTAssertTrue(app.buttons["gymExit"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["JAB"].isHittable)
        XCTAssertTrue(app.buttons["CROSS"].isHittable)
        capture("RIVAL gym shared controls")
        app.buttons["gymExit"].tap()
        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLargeTextInternalMenusKeepCloseAndSelectionReachable() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "1"
        app.launchArguments = ["-pixelBoxingLanguage", "en", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 8))
        reveal(app.buttons["mainMenuWaitingRoom"], in: app.scrollViews.firstMatch)
        app.buttons["mainMenuWaitingRoom"].tap()
        XCTAssertTrue(app.buttons["waitingRoomClose"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["waitingRoomClose"].isHittable)
        XCTAssertTrue(app.buttons["lockerOutfitTab"].isHittable)
        app.buttons["lockerOutfitTab"].tap()
        let outfit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lockerOutfit-")).firstMatch
        reveal(outfit, in: app.scrollViews.firstMatch)
        XCTAssertTrue(outfit.isHittable)
        capture("RIVAL large-text locker")
        app.buttons["waitingRoomClose"].tap()
        app.buttons["mainMenuSettings"].tap()
        XCTAssertTrue(app.buttons["settingsClose"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settingsClose"].isHittable)
        reveal(app.buttons["settingsSound"], in: app.scrollViews.firstMatch)
        XCTAssertTrue(app.buttons["settingsSound"].isHittable)
        capture("RIVAL large-text settings")
        app.buttons["settingsClose"].tap()
        reveal(app.buttons["mainMenuLeaderboard"], in: app.scrollViews.firstMatch)
        app.buttons["mainMenuLeaderboard"].tap()
        XCTAssertTrue(app.buttons["leaderboardClose"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["leaderboardClose"].isHittable)
        capture("RIVAL large-text leaderboard")
        app.buttons["leaderboardClose"].tap()
        app.buttons["mainMenuStoryNavigation"].tap()
        let pressure = app.buttons["storyOpponent_pressure"]
        XCTAssertTrue(pressure.waitForExistence(timeout: 5))
        reveal(pressure, in: app.scrollViews["storyOpponentList"])
        pressure.tap()
        XCTAssertTrue(pressure.isSelected)
        XCTAssertTrue(app.buttons["storyBack"].isHittable)
        XCTAssertTrue(app.buttons["storyChallenge"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["storyChallenge"].frame.height, 48)
        capture("native-approved-large-story")
        app.buttons["storyBack"].tap()
        app.terminate()
    }

    @MainActor
    func testNewGameConfirmationKeepsCancellationSafe() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launch()
        XCTAssertTrue(app.buttons["mainMenuNewGame"].waitForExistence(timeout: 8))
        let startLabel = app.buttons["mainMenuContinue"].label
        app.buttons["mainMenuNewGame"].tap()
        XCTAssertTrue(app.buttons["resetCancel"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["mainMenuContinue"].exists)
        XCTAssertTrue(app.buttons["resetConfirm"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["resetConfirm"].frame.height, 44)
        XCTAssertTrue(app.staticTexts["RIVAL이 기억한 플레이 습관과 이번 대전의 점수가 지워집니다. 라운드 1부터 다시 시작합니다."].exists)
        capture("RIVAL new game confirmation")
        app.buttons["resetCancel"].tap()
        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["mainMenuContinue"].label, startLabel)
        XCTAssertFalse(app.buttons["resetConfirm"].exists)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testPremiumMenuIsReadableInEveryLanguage() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        for (language, fightAction) in [("ko", "경기 시작"), ("en", "Start bout"), ("ja", "試合開始")] {
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launch()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.images["mainMenuWordmark"].exists)
            XCTAssertTrue(app.buttons["mainMenuContinue"].label.contains(fightAction))
            for id in ["mainMenuContinue", "mainMenuWaitingRoom", "mainMenuGym", "mainMenuLeaderboard", "mainMenuSettings", "mainMenuNewGame"] {
                let button = app.buttons[id]
                XCTAssertTrue(button.isHittable, "\(language): \(id) is not reachable")
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                XCTAssertGreaterThan(button.frame.minX, app.frame.minX + 10)
                XCTAssertLessThan(button.frame.maxX, app.frame.maxX - 10)
            }
            let wins = app.descendants(matching: .any).matching(identifier: "menuTotalWins").firstMatch
            XCTAssertEqual(wins.value as? String, "0", "Menu displays the real isolated record, not an invented level")
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "RIVAL premium main menu \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    @MainActor
    func testMenuOverlaysBlockUnderlyingFightAction() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launch()
        XCTAssertTrue(app.buttons["mainMenuSettings"].waitForExistence(timeout: 8))
        app.buttons["mainMenuSettings"].tap()
        XCTAssertTrue(app.buttons["settingsClose"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["mainMenuContinue"].exists)
        app.buttons["settingsClose"].tap()
        XCTAssertTrue(app.buttons["mainMenuWaitingRoom"].waitForExistence(timeout: 3))
        app.buttons["mainMenuWaitingRoom"].tap()
        XCTAssertTrue(app.buttons["waitingRoomClose"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["mainMenuContinue"].exists)
        app.buttons["waitingRoomClose"].tap()
        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 3))
        app.buttons["mainMenuContinue"].tap()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testMenuLargeTextAndReducedMotionKeepActionsReachable() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "1"
        app.launchArguments = ["-pixelBoxingLanguage", "en", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 8))
        let scroll = app.scrollViews.firstMatch
        for id in ["mainMenuContinue", "mainMenuWaitingRoom", "mainMenuGym", "mainMenuLeaderboard", "mainMenuNewGame"] {
            let button = app.buttons[id]
            reveal(button, in: scroll)
            XCTAssertTrue(button.isHittable, "Large text cannot hide \(id)")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        for id in ["menuTotalWins", "menuBestStreak"] {
            let record = app.descendants(matching: .any).matching(identifier: id).firstMatch
            reveal(record, in: scroll)
            XCTAssertTrue(record.isHittable, "Large-text records remain reachable")
        }
        XCTAssertTrue(app.buttons["mainMenuSettings"].isHittable)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "RIVAL menu accessibility text and reduced motion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, fullyVisible: Bool = false) {
        // A full-velocity swipe can fling past an entire large-text row. Use short drags and correct
        // direction from the actual element frame instead of blindly continuing toward the bottom.
        var dragFraction: CGFloat = 0.32
        var previousAboveViewport: Bool?
        for _ in 0..<18 {
            let exists = element.exists
            if exists && element.isHittable {
                if !fullyVisible { return }
                if element.frame.minY >= scroll.frame.minY && element.frame.maxY <= scroll.frame.maxY { return }
            }
            let aboveViewport = exists && (fullyVisible ? element.frame.minY < scroll.frame.minY : element.frame.midY < scroll.frame.minY)
            if fullyVisible, let previousAboveViewport, previousAboveViewport != aboveViewport {
                dragFraction *= 0.5
            }
            previousAboveViewport = aboveViewport
            let startY: CGFloat = aboveViewport ? 0.40 : 0.72
            let endY = startY + (aboveViewport ? dragFraction : -dragFraction)
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: startY))
                .press(forDuration: 0.05,
                       thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: endY)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    @MainActor
    func testLandscapeGameStartsWithComboControls() {
        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "fight"
        app.launch()

        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)

        let controlLabels = [
            "전진", "후퇴", "왼쪽 이동", "오른쪽 이동",
            "왼쪽 더킹", "가드", "오른쪽 더킹", "백스텝", "JAB", "CROSS",
        ]
        for label in controlLabels {
            let control = app.buttons[label]
            XCTAssertTrue(control.exists, "Missing control: \(label)")
            XCTAssertTrue(control.isHittable, "Control is outside the touchable landscape viewport: \(label)")
        }

        let forwardFrame = app.buttons["전진"].frame
        XCTAssertGreaterThan(forwardFrame.width, 48)
        XCTAssertGreaterThan(forwardFrame.height, 44)
        XCTAssertGreaterThan(app.buttons["왼쪽 이동"].frame.minX, 20)
        XCTAssertLessThan(app.buttons["CROSS"].frame.maxX, app.frame.maxX - 20)

        for removedAttack in ["L BODY", "R BODY", "L HOOK", "R HOOK", "L UPPER", "R UPPER"] {
            XCTAssertFalse(app.buttons[removedAttack].exists, "Legacy attack button remains visible: \(removedAttack)")
        }

        app.buttons["JAB"].tap()

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "RIVAL iPhone landscape fight"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["오른쪽 이동"].press(forDuration: 0.8)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        let strafeAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        strafeAttachment.name = "RIVAL stabilized strafe camera"
        strafeAttachment.lifetime = .keepAlways
        add(strafeAttachment)
    }

    @MainActor
    func testMainMenuEntersFightThroughSkippableIntro() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launch()
        let start = app.buttons["mainMenuContinue"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        let skip = app.buttons["skipFightIntro"]
        if skip.waitForExistence(timeout: 1) { skip.tap() }
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["CROSS"].isHittable)
    }

    @MainActor
    func testCombatHUDAndTouchTargetsInEveryLanguage() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        for (language, labels) in [
            ("ko", ["전진", "후퇴", "왼쪽 이동", "오른쪽 이동", "가드", "왼쪽 더킹", "오른쪽 더킹"]),
            ("en", ["Forward", "Back", "Move Left", "Move Right", "Guard", "Duck Left", "Duck Right"]),
            ("ja", ["前進", "後退", "左移動", "右移動", "ガード", "左ダッキング", "右ダッキング"])
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "fight"
            app.launch()
            XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
            for identifier in ["JAB", "CROSS", "BACKSTEP", "WEAVE_LEFT", "WEAVE_RIGHT"] {
                XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1)
                let control = app.buttons[identifier]
                XCTAssertTrue(control.isHittable, "\(language): \(identifier)")
                XCTAssertGreaterThanOrEqual(control.frame.width, 44)
                XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                XCTAssertGreaterThan(control.frame.minX, app.frame.minX + 20)
                XCTAssertLessThan(control.frame.maxX, app.frame.maxX - 20)
            }
            let grid = [
                [app.buttons["WEAVE_LEFT"], app.buttons[labels[0]], app.buttons["WEAVE_RIGHT"]],
                [app.buttons[labels[2]], app.buttons[labels[4]], app.buttons[labels[3]]],
                [app.buttons[labels[5]], app.buttons[labels[1]], app.buttons[labels[6]]]
            ]
            let frames = grid.map { row in row.map(\.frame) }
            for (rowIndex, row) in frames.enumerated() {
                for (columnIndex, frame) in row.enumerated() {
                    XCTAssertEqual(frame.width, 58, accuracy: 0.5)
                    XCTAssertEqual(frame.height, 54, accuracy: 0.5)
                    XCTAssertEqual(frame.midX, frames[0][columnIndex].midX, accuracy: 0.5)
                    XCTAssertEqual(frame.midY, row[0].midY, accuracy: 0.5)
                    if columnIndex > 0 {
                        XCTAssertEqual(frame.minX - row[columnIndex - 1].maxX, 5, accuracy: 0.5)
                    }
                    if rowIndex > 0 {
                        XCTAssertEqual(frame.minY - frames[rowIndex - 1][columnIndex].maxY, 5, accuracy: 0.5)
                    }
                }
            }
            let jab = app.buttons["JAB"].frame
            let cross = app.buttons["CROSS"].frame
            let backstep = app.buttons["BACKSTEP"].frame
            for attack in [jab, cross] {
                XCTAssertEqual(attack.width, 94, accuracy: 0.5)
                XCTAssertEqual(attack.height, 76, accuracy: 0.5)
                XCTAssertEqual(attack.minY - backstep.maxY, 6, accuracy: 0.5)
            }
            XCTAssertLessThan(jab.midX, cross.midX)
            XCTAssertEqual(cross.minX - jab.maxX, 7, accuracy: 0.5)
            XCTAssertEqual(backstep.width, 196, accuracy: 0.5)
            XCTAssertEqual(backstep.height, 44, accuracy: 0.5)
            XCTAssertEqual(backstep.midX, (jab.midX + cross.midX) / 2, accuracy: 0.5)
            XCTAssertLessThan(frames[0][2].maxX, backstep.minX)
            let clock = app.descendants(matching: .any)["combatRoundClock"]
            XCTAssertTrue(clock.exists)
            let commentary = app.staticTexts["combatCommentary"]
            XCTAssertTrue(commentary.waitForExistence(timeout: 3))
            XCTAssertFalse(commentary.label.isEmpty)
            XCTAssertLessThanOrEqual(commentary.frame.width, 500.5)
            XCTAssertLessThanOrEqual(commentary.frame.height, 20.5)
            XCTAssertLessThanOrEqual(commentary.frame.maxY, app.frame.minY + 100.5)
            XCTAssertEqual(commentary.frame.midX, app.frame.midX, accuracy: 2)
            XCTAssertEqual(clock.frame.midX, app.frame.midX, accuracy: 2)
            let playerMeter = app.descendants(matching: .any)["combatPlayerMeter"]
            let rivalMeter = app.descendants(matching: .any)["combatRivalMeter"]
            XCTAssertGreaterThan(playerMeter.frame.width, 210)
            XCTAssertGreaterThan(rivalMeter.frame.width, 210)
            XCTAssertLessThanOrEqual(rivalMeter.frame.maxX + 8, app.buttons["combatSettings"].frame.minX)
            let screenshot = XCUIScreen.main.screenshot()
            let image = try screenImage(screenshot, size: app.frame.size)
            let raster = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(raster.bitsPerPixel, 32)
            let data = try XCTUnwrap(raster.dataProvider?.data)
            let pixels = try XCTUnwrap(CFDataGetBytePtr(data))
            for frame in [frames[0][1], frames[1][0], frames[1][1], frames[1][2], frames[2][1]] {
                let x = Int(frame.midX - app.frame.minX) - 14
                let y = Int(frame.midY - app.frame.minY) - 14
                var visibleInk = 0
                for row in y..<(y + 28) {
                    for column in x..<(x + 28) {
                        let offset = row * raster.bytesPerRow + column * 4
                        if pixels[offset] > 200 && pixels[offset + 1] > 200 && pixels[offset + 2] > 200 {
                            visibleInk += 1
                        }
                    }
                }
                XCTAssertGreaterThan(visibleInk, 20, "\(language): direction and guard icons must render, not just expose a button.")
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "combat-ui-\(language)-fight"
            attachment.lifetime = .keepAlways
            add(attachment)
            let previousCall = commentary.label
            app.buttons["JAB"].tap()
            let updatedCall = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label != %@ AND label != ''", previousCall), object: commentary)
            XCTAssertEqual(XCTWaiter.wait(for: [updatedCall], timeout: 3), .completed)
            XCTAssertLessThanOrEqual(commentary.frame.maxY, app.frame.minY + 100.5)
            capture("restored-commentary-\(language)-jab")
            app.buttons["combatSettings"].tap()
            XCTAssertTrue(app.buttons["settingsClose"].waitForExistence(timeout: 3))
            XCTAssertFalse(commentary.exists, "Paused settings must not leave a live fight call on screen.")
            app.buttons["settingsClose"].tap()
            XCTAssertTrue(commentary.waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    @MainActor
    func testRingButtonsRemainReachableAfterOriginalMainMenuIntro() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launch()
        let start = app.buttons["mainMenuContinue"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["CROSS"].isHittable)
        XCTAssertTrue(app.buttons["BACKSTEP"].isHittable)
        app.terminate()
    }

    @MainActor
    func testRingButtonsKeepKnockoutAndNextRoundFlowAtNormalSettings() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "knockout"
        app.launch()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["combatCommentary"].exists)
        app.buttons["JAB"].press(forDuration: 0.8)
        let next = app.buttons["nextRound"]
        XCTAssertTrue(next.waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)["roundSummary"].exists)
        XCTAssertFalse(app.staticTexts["combatCommentary"].exists)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        capture("remaining-native-rival-round-result-ko")
        next.tap()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["CROSS"].isHittable)
        XCTAssertFalse(next.exists)
        XCTAssertTrue(app.staticTexts["combatCommentary"].waitForExistence(timeout: 3))
        app.buttons["가드"].press(forDuration: 0.4)
        app.buttons["BACKSTEP"].tap()
        XCTAssertTrue(app.buttons["JAB"].isHittable)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "ring-native-ko-next-round"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }

    @MainActor
    func testLocalizedResultsKeepTheActionVisibleWithLargeText() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        for (language, roundText, dodgeText) in [
            ("ko", "라운드", "회피 성공"),
            ("en", "Round", "Dodges"),
            ("ja", "ラウンド", "回避成功")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["-pixelBoxingLanguage", language]
            if language == "en" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
                app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "1"
            }
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "knockout"
            app.launch()
            XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
            app.buttons["JAB"].tap()
            let next = app.buttons["nextRound"]
            XCTAssertTrue(next.waitForExistence(timeout: 6))
            XCTAssertTrue(next.isHittable)
            XCTAssertGreaterThanOrEqual(next.frame.height, 48)
            XCTAssertLessThan(next.frame.maxY, app.frame.maxY)
            XCTAssertGreaterThan(next.frame.minX, app.frame.minX + 20)
            XCTAssertLessThan(next.frame.maxX, app.frame.maxX - 20)
            let summary = app.descendants(matching: .any)["roundSummary"]
            XCTAssertTrue(summary.label.contains(roundText))
            XCTAssertTrue(summary.label.contains(dodgeText))
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "combat-ui-\(language)-result\(language == "en" ? "-large-text" : "")"
            attachment.lifetime = .keepAlways
            add(attachment)
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            next.tap()
            XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 4))
            XCTAssertFalse(next.exists)
            app.terminate()
        }
    }

    @MainActor
    func testRemainingPaperMenusInEveryLanguageAtNormalSettings() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        for language in ["ko", "en", "ja"] {
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
            app.launch()
            XCTAssertTrue(app.buttons["mainMenuSettings"].waitForExistence(timeout: 8))
            let startLabel = app.buttons["mainMenuContinue"].label
            app.buttons["mainMenuSettings"].tap()
            XCTAssertTrue(app.buttons["settingsClose"].waitForExistence(timeout: 4))
            XCTAssertFalse(app.buttons["mainMenuContinue"].exists)
            for identifier in ["settingsSound", "settingsHaptics"] {
                let setting = app.buttons[identifier]
                XCTAssertTrue(setting.isHittable)
                if language == "ko" {
                    let originalValue = setting.isSelected
                    setting.tap()
                    let changedValue = setting.isSelected
                    setting.tap()
                    XCTAssertNotEqual(changedValue, originalValue)
                    XCTAssertEqual(setting.isSelected, originalValue)
                }
            }
            capture("remaining-native-settings-\(language)")
            app.buttons["settingsClose"].tap()

            app.buttons["mainMenuNewGame"].tap()
            XCTAssertTrue(app.buttons["resetCancel"].waitForExistence(timeout: 4))
            XCTAssertTrue(app.buttons["resetConfirm"].isHittable)
            capture("remaining-native-reset-\(language)")
            app.buttons["resetCancel"].tap()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 4))
            XCTAssertEqual(app.buttons["mainMenuContinue"].label, startLabel)

            app.buttons["mainMenuRivalAnalysis"].tap()
            XCTAssertTrue(app.buttons["rivalAnalysisClose"].waitForExistence(timeout: 4))
            capture("remaining-native-corner-notes-\(language)")
            app.buttons["rivalAnalysisClose"].tap()

            app.buttons["mainMenuLeaderboard"].tap()
            XCTAssertTrue(app.buttons["leaderboardClose"].waitForExistence(timeout: 4))
            capture("remaining-native-ranking-\(language)")
            app.buttons["leaderboardClose"].tap()

            app.buttons["mainMenuGym"].tap()
            XCTAssertTrue(app.buttons["gymExit"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["JAB"].isHittable)
            XCTAssertTrue(app.buttons["CROSS"].isHittable)
            capture("remaining-native-gym-\(language)")
            app.buttons["gymExit"].tap()

            app.buttons["mainMenuStoryNavigation"].tap()
            XCTAssertTrue(app.buttons["storyChallenge"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["storyBack"].waitForExistence(timeout: 4))
            app.buttons["storyBack"].tap()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 4))
            XCTAssertEqual(app.buttons["mainMenuContinue"].label, startLabel)
            app.terminate()
        }
    }

    @MainActor
    func testPaperStoryOfferClosesWithoutTransactionInEveryLanguage() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        for language in ["ko", "en", "ja"] {
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "story-offer"
            app.launch()
            XCTAssertTrue(app.buttons["storyPurchaseClose"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["storyPurchaseClose"].isHittable)
            XCTAssertTrue(app.buttons["storyPurchaseBuy"].exists)
            XCTAssertTrue(app.buttons["storyPurchaseRestore"].exists)
            XCTAssertTrue(app.buttons["storyPurchaseRestore"].isHittable)
            XCTAssertTrue(app.otherElements["storyOfferArtwork"].exists)
            XCTAssertFalse(app.buttons["mainMenuContinue"].exists)
            capture("remaining-native-story-offer-\(language)")
            app.buttons["storyPurchaseClose"].tap()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 4))
            app.terminate()
        }
    }

    @MainActor
    func testPaperStoryCornerAndResultKeepNormalBoutFlow() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "story-corner"
        app.launch()
        let next = app.buttons["storyNextRound"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["combatCommentary"].exists)
        XCTAssertTrue(next.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["roundRecordTable"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["roundRecordDodges"].isHittable)
        XCTAssertTrue(app.staticTexts["roundRecordTopAttack"].isHittable)
        XCTAssertEqual(app.staticTexts["roundRecordPlayerDodges"].label, "0")
        XCTAssertEqual(app.staticTexts["roundRecordEnemyDodges"].label, "0")
        capture("remaining-native-story-corner-ko")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 12), .completed)
        next.tap()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["CROSS"].isHittable)
        XCTAssertFalse(next.exists)
        XCTAssertTrue(app.staticTexts["combatCommentary"].waitForExistence(timeout: 3))
        app.terminate()

        for action in ["storyRetry", "storyResultExit"] {
            app.launchArguments = ["-pixelBoxingLanguage", "ja"]
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "story-result"
            app.launch()
            XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
            let commentary = app.staticTexts["combatCommentary"]
            XCTAssertTrue(commentary.waitForExistence(timeout: 3))
            XCTAssertLessThanOrEqual(commentary.frame.maxY, app.frame.minY + 110.5)
            capture("restored-commentary-story-ja-\(action)")
            app.buttons["JAB"].tap()
            XCTAssertTrue(app.otherElements["storyBoutResult"].waitForExistence(timeout: 8))
            XCTAssertFalse(commentary.exists)
            XCTAssertTrue(app.descendants(matching: .any)["roundRecordTable"].firstMatch.exists)
            XCTAssertTrue(app.staticTexts["roundRecordDodges"].isHittable)
            XCTAssertTrue(app.staticTexts["roundRecordTopAttack"].isHittable)
            XCTAssertTrue(app.buttons["storyRetry"].isHittable)
            XCTAssertTrue(app.buttons["storyResultExit"].isHittable)
            capture("remaining-native-story-result-ja-\(action)")
            app.buttons[action].tap()
            if action == "storyRetry" {
                XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 15))
                XCTAssertFalse(app.otherElements["storyBoutResult"].exists)
                let introSkip = app.buttons["storyIntroductionSkip"]
                XCTAssertTrue(introSkip.waitForExistence(timeout: 3))
                XCTAssertFalse(commentary.exists, "The retry introduction must not show live commentary.")
                XCTAssertTrue(introSkip.isHittable)
                introSkip.tap()
                XCTAssertTrue(commentary.waitForExistence(timeout: 3))
                XCTAssertTrue(app.buttons["JAB"].isHittable)
            } else {
                XCTAssertTrue(app.buttons["storyBack"].waitForExistence(timeout: 8))
                XCTAssertTrue(app.buttons["storyChallenge"].exists)
            }
            app.terminate()
        }
    }

    @MainActor
    func testStoryCornerKeepsContinueReachableWithLargeText() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-pixelBoxingLanguage", "en", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "story-corner"
        app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "1"
        app.launch()
        let next = app.buttons["storyNextRound"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThanOrEqual(next.frame.height, 48)
        XCTAssertLessThan(next.frame.maxY, app.frame.maxY)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "combat-ui-story-corner-large-text"
        attachment.lifetime = .keepAlways
        add(attachment)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 12), .completed)
        next.tap()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["CROSS"].isHittable)
        XCTAssertFalse(next.exists)
    }

    @MainActor
    func testStoryResultPreservesRetryAndNavigation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-pixelBoxingLanguage", "ja"]
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "story-result"
        app.launch()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["combatCommentary"].waitForExistence(timeout: 3))
        let fightAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fightAttachment.name = "combat-ui-story-fight-restored-narrator-ja"
        fightAttachment.lifetime = .keepAlways
        add(fightAttachment)
        app.buttons["JAB"].tap()
        XCTAssertTrue(app.otherElements["storyBoutResult"].waitForExistence(timeout: 8))
        let retry = app.buttons["storyRetry"]
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertLessThan(retry.frame.maxY, app.frame.maxY)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "combat-ui-story-result-ja"
        attachment.lifetime = .keepAlways
        add(attachment)
        retry.tap()
        let skip = app.buttons["storyIntroductionSkip"]
        if skip.waitForExistence(timeout: 1) { skip.tap() }
        XCTAssertFalse(app.otherElements["storyBoutResult"].exists)
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testModeNavigationRestoresMainControlsAtNormalSettings() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "0"
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 8))
        let identifiers = ["mainMenuContinue", "mainMenuStoryNavigation", "mainMenuWaitingRoom", "mainMenuGym"]
        let frames = identifiers.map { identifier in
            XCTAssertTrue(app.buttons[identifier].isHittable)
            return (identifier, app.buttons[identifier].frame)
        }
        capture("mode-native-main")
        for mode in [
            (entry: "mainMenuStoryNavigation", exit: "storyBack", image: "mode-native-story"),
            (entry: "mainMenuGym", exit: "gymExit", image: "mode-native-gym")
        ] {
            app.buttons[mode.entry].tap()
            XCTAssertTrue(app.buttons[mode.exit].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[mode.exit].isHittable)
            XCTAssertFalse(app.buttons["mainMenuContinue"].exists)
            capture(mode.image)
            app.buttons[mode.exit].tap()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 5))
            for (identifier, frame) in frames {
                XCTAssertTrue(app.buttons[identifier].isHittable)
                XCTAssertEqual(app.buttons[identifier].frame, frame)
            }
        }
    }

    @MainActor
    func testApprovedBrandingKeepsMainStoryAndGymFlowAtNormalSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        for language in ["ko", "en", "ja"] {
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
            app.launch()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.images["mainMenuWordmark"].exists)
            XCTAssertTrue(app.buttons["mainMenuLeaderboard"].isHittable)
            capture("brand-native-main-\(language)")

            app.buttons["mainMenuStoryNavigation"].tap()
            XCTAssertTrue(app.buttons["storyBack"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.images["storyWordmark"].exists)
            let roster = app.scrollViews["storyOpponentList"]
            let challenge = app.buttons["storyChallenge"]
            XCTAssertTrue(roster.exists)
            XCTAssertTrue(challenge.isHittable)
            XCTAssertLessThanOrEqual(roster.frame.maxY, challenge.frame.minY)
            capture("brand-native-story-lineup-\(language)")
            app.buttons["storyOpponent_pressure"].tap()
            XCTAssertTrue(app.buttons["storyOpponent_pressure"].isSelected)
            XCTAssertTrue(app.buttons["storyReplayIntroduction"].isHittable)
            XCTAssertLessThanOrEqual(app.buttons["storyReplayIntroduction"].frame.maxY, roster.frame.minY)
            capture("brand-native-story-selected-\(language)")
            app.buttons["storyBack"].tap()

            app.buttons["mainMenuGym"].tap()
            XCTAssertTrue(app.buttons["gymGuide"].waitForExistence(timeout: 5))
            let jabFrame = app.buttons["JAB"].frame
            let exitFrame = app.buttons["gymExit"].frame
            capture("brand-native-gym-\(language)")
            app.buttons["JAB"].tap()
            app.buttons["gymGuide"].tap()
            XCTAssertTrue(app.staticTexts["gymGuideTitle"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["gymGuideClose"].isHittable)
            for identifier in ["JAB", "gymExit"] {
                let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                    object: app.buttons[identifier])
                XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
            }
            try captureGymGuide("brand-native-gym-guide-\(language)", app: app)
            app.buttons["gymGuideClose"].tap()
            XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["JAB"].isHittable)
            XCTAssertEqual(app.buttons["JAB"].frame, jabFrame)
            XCTAssertEqual(app.buttons["gymExit"].frame, exitFrame)
            app.buttons["JAB"].tap()
            app.buttons["gymExit"].tap()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    private func screenImage(_ screenshot: XCUIScreenshot, size: CGSize) throws -> UIImage {
        let source = try XCTUnwrap(screenshot.image.cgImage)
        let oriented = UIImage(cgImage: source, scale: screenshot.image.scale,
                               orientation: source.width < source.height ? .left : .up)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    @MainActor
    private func captureGymGuide(_ name: String, app: XCUIApplication) throws {
        let heading = app.staticTexts["gymGuideTitle"]
        let close = app.buttons["gymGuideClose"]
        let height: CGFloat = 84 * 300 / 1064
        let mark = CGRect(x: heading.frame.minX - app.frame.minX,
                          y: close.frame.midY - app.frame.minY - height / 2,
                          width: 84, height: height).integral
        let deadline = Date().addingTimeInterval(2)
        var screenshot = XCUIScreen.main.screenshot()
        var visibleInk = 0
        var minimumInk = 0
        repeat {
            screenshot = XCUIScreen.main.screenshot()
            let image = try screenImage(screenshot, size: app.frame.size)
            let crop = try XCTUnwrap(image.cgImage?.cropping(to: mark))
            var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            try pixels.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress,
                    width: crop.width, height: crop.height, bitsPerComponent: 8,
                    bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            }
            visibleInk = stride(from: 0, to: pixels.count, by: 4).reduce(0) { count, offset in
                count + (pixels[offset] > 100 && pixels[offset + 1] < 100 && pixels[offset + 2] < 100 ? 1 : 0)
            }
            minimumInk = crop.width * crop.height / 5
            if visibleInk >= minimumInk { break }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThanOrEqual(visibleInk, minimumInk,
            "The guide must render the red wordmark, not just expose its title and close button.")
    }

    @MainActor
    func testGymSharesLocalizedControlsAndReturnsToMenu() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launch()
        XCTAssertTrue(app.buttons["mainMenuGym"].waitForExistence(timeout: 8))
        app.buttons["mainMenuGym"].tap()
        XCTAssertTrue(app.buttons["gymExit"].waitForExistence(timeout: 8))
        for identifier in ["JAB", "CROSS", "BACKSTEP", "WEAVE_LEFT", "WEAVE_RIGHT"] {
            XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1)
            XCTAssertTrue(app.buttons[identifier].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons[identifier].frame.height, 44)
        }
        app.buttons["가드"].press(forDuration: 0.3)
        XCTAssertEqual(app.buttons["가드"].value as? String, "해제됨")
        app.buttons["JAB"].tap()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "combat-ui-gym-ko"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["gymExit"].tap()
        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testKnockoutRevealsResultThenAllowsNextRound() {
        exerciseKnockout(reducedMotion: false)
    }

    @MainActor
    func testReducedMotionKnockoutKeepsResultAndControlsUsable() {
        exerciseKnockout(reducedMotion: true)
    }

    @MainActor
    private func exerciseKnockout(reducedMotion: Bool) {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "knockout"
        if reducedMotion { app.launchEnvironment["RIVAL_REDUCED_MOTION_TEST"] = "1" }
        app.launch()
        let jab = app.buttons["JAB"]
        XCTAssertTrue(jab.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["nextRound"].exists)
        jab.tap()

        let next = app.buttons["nextRound"]
        XCTAssertTrue(next.waitForExistence(timeout: 6))
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)
        XCTAssertLessThan(next.frame.maxY, app.frame.maxY)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = reducedMotion ? "RIVAL reduced-motion KO result" : "RIVAL KO result after fall"
        attachment.lifetime = .keepAlways
        add(attachment)

        let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: next)
        wait(for: [enabled], timeout: 5)
        next.tap()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["nextRound"].exists)
        XCTAssertTrue(app.buttons["CROSS"].isHittable)
    }
}
