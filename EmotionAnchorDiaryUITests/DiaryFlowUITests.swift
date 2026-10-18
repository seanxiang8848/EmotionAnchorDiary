import XCTest

final class DiaryFlowUITests: XCTestCase {
    func testDiaryScreenOpensSettingsAndShowsPrivacyActions() throws {
        let app = XCUIApplication()
        launchDiary(in: app)

        XCTAssertTrue(app.staticTexts["今天的心情在哪儿？"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["保存并生成共情"].exists)

        openSettings(in: app)

        XCTAssertTrue(app.switches["启动时使用 Face ID 或设备密码"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["导出日记"].exists)
        XCTAssertTrue(app.buttons["删除所有本地日记和目标…"].exists)
    }

    func testEmptyEntryShowsValidationMessage() throws {
        let app = XCUIApplication()
        launchDiary(in: app)

        app.buttons["保存并生成共情"].tap()

        XCTAssertTrue(app.staticTexts["请填写内容后再提交"].waitForExistence(timeout: 5))
    }

    func testHistoryScreenShowsEmptyState() throws {
        let app = XCUIApplication()
        launchDiary(in: app)

        app.buttons["查看历史条目"].tap()

        XCTAssertTrue(app.staticTexts["暂无记录"].waitForExistence(timeout: 10))
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.staticTexts["今天的心情在哪儿？"].exists)
    }

    func testDeleteAllDataRequiresConfirmation() throws {
        let app = XCUIApplication()
        launchDiary(in: app)
        openSettings(in: app)

        app.buttons["删除所有本地日记和目标…"].tap()

        let confirmation = app.buttons["删除全部数据"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["导出日记"].exists)
    }

    private func launchDiary(in app: XCUIApplication) {
        app.launchArguments += ["-allowCloudAnalysis", "NO"]
        app.launch()
    }

    private func openSettings(in app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
    }
}
