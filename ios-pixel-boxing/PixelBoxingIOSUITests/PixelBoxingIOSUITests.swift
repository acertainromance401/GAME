import XCTest

final class RIVALUITests: XCTestCase {
    @MainActor
    func testLandscapeGameStartsWithComboControls() {
        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launch()

        let fightButton = app.buttons["경기 시작"]
        XCTAssertTrue(fightButton.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertTrue(app.staticTexts["MOVE & DEFENSE"].exists)
        XCTAssertTrue(app.staticTexts["JAB / CROSS 조합"].exists)
        XCTAssertTrue(app.staticTexts["L DUCK: 좌 바디 / 우 훅"].exists)
        XCTAssertTrue(app.staticTexts["R DUCK: 좌 훅 / 우 바디"].exists)
        XCTAssertLessThan(app.staticTexts["R DUCK: 좌 훅 / 우 바디"].frame.maxY, app.frame.maxY)

        fightButton.tap()
        XCTAssertFalse(fightButton.exists)

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
        XCTAssertTrue(app.buttons["일시정지"].exists)

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

        app.buttons["라이벌 학습 초기화"].tap()
        XCTAssertTrue(app.staticTexts["라이벌 학습을 초기화할까요?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["학습 메모리와 현재 점수가 삭제되고 ROUND 1부터 다시 시작됩니다."].exists)
        let resetButton = app.buttons["학습 초기화 후 라운드 1 재시작"]
        XCTAssertTrue(resetButton.isHittable)
        resetButton.tap()
        XCTAssertTrue(app.staticTexts["ROUND 1"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["라이벌 학습을 초기화할까요?"].exists)
        XCTAssertTrue(app.buttons["JAB"].isHittable)
    }
}
