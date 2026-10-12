import StoreKitTest
import XCTest

final class RIVALUITests: XCTestCase {
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
        capture("review-\(language)-01-main-menu")

        app.buttons["mainMenuStory"].tap()
        let purchaseButton = app.buttons["storyPurchaseBuy"]
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 20))
        XCTAssertTrue(NSPredicate(format: "enabled == true").evaluate(with: purchaseButton)
            || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: purchaseButton)], timeout: 30) == .completed)
        XCTAssertTrue(purchaseButton.label.contains("2.99"))
        XCTAssertTrue(app.buttons["storyPurchaseRestore"].isHittable)
        capture("review-\(language)-02-story-purchase")

        purchaseButton.tap()
        XCTAssertTrue(app.buttons["storyChallenge"].waitForExistence(timeout: 15))
        if language == "en" {
            XCTAssertTrue(app.staticTexts["STORY ACCESS CONFIRMED"].waitForNonExistence(timeout: 8))
        }
        XCTAssertTrue(app.buttons["storyChallenge"].isEnabled)
        capture("review-\(language)-03-story-progression")
        app.buttons["storyOpponent_outboxer"].tap()
        let lockedChallenge = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == false"), object: app.buttons["storyChallenge"])
        XCTAssertEqual(XCTWaiter.wait(for: [lockedChallenge], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["storyReplayIntroduction"].exists)
        XCTAssertFalse(app.buttons["storyReplayRivalScene"].exists)
        app.buttons["storyBack"].tap()

        app.buttons["mainMenuGym"].tap()
        XCTAssertTrue(app.buttons["gymExit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["JAB"].isHittable)
        capture("review-\(language)-04-gym")
        app.buttons["gymExit"].tap()

        XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 10))
        app.buttons["mainMenuContinue"].tap()
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 15))
        capture("review-\(language)-05-rival-fight")
        app.terminate()
    }

    @MainActor
    func testCaptureOpeningForVisualInspection() {
        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_OPENING_VISUAL_TEST"] = "1"
        app.launchEnvironment["RIVAL_OPENING_CAPTURE_BEAT"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["RIVAL"].waitForExistence(timeout: 8))

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
    func testInternalMenusMatchMainAndLockedOutfitStaysPreviewOnly() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
        app.launchArguments = ["-pixelBoxingLanguage", "ko"]
        app.launch()
        XCTAssertTrue(app.buttons["mainMenuWaitingRoom"].waitForExistence(timeout: 8))
        app.buttons["mainMenuWaitingRoom"].tap()
        XCTAssertTrue(app.buttons["lockerOutfitTab"].waitForExistence(timeout: 3))
        capture("RIVAL full-screen locker - styles")
        app.buttons["lockerOutfitTab"].tap()
        let lockedOutfit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lockerOutfit-")).element(boundBy: 1)
        XCTAssertTrue(lockedOutfit.waitForExistence(timeout: 3))
        lockedOutfit.tap()
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
        XCTAssertTrue(app.staticTexts["학습 메모리와 현재 점수가 삭제되고 ROUND 1부터 다시 시작됩니다."].exists)
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
        for language in ["ko", "en", "ja"] {
            app.launchEnvironment["RIVAL_PRESENTATION_TEST"] = "menu"
            app.launchArguments = ["-pixelBoxingLanguage", language]
            app.launch()
            XCTAssertTrue(app.buttons["mainMenuContinue"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["mainMenuWordmark"].exists)
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
        let skip = app.buttons["skipFightIntro"]
        if skip.waitForExistence(timeout: 1) { skip.tap() }
        XCTAssertTrue(app.buttons["JAB"].waitForExistence(timeout: 4))
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
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement) {
        // A full-velocity swipe can fling past an entire large-text row. Use short drags and correct
        // direction from the actual element frame instead of blindly continuing toward the bottom.
        for _ in 0..<18 {
            if element.isHittable { return }
            let aboveViewport = element.frame.midY < scroll.frame.minY
            let startY = aboveViewport ? 0.40 : 0.72
            let endY = aboveViewport ? 0.72 : 0.40
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
