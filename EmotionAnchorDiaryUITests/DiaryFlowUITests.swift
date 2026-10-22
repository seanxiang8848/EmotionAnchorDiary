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

    func testDiaryEntryCanBeSavedAndReadBackFromHistory() throws {
        let app = XCUIApplication()
        launchDiary(in: app)

        let note = "A private note saved by the UI test."
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(note)
        app.buttons["完成"].tap()
        app.buttons["保存并生成共情"].tap()

        let historyButton = app.buttons["查看历史条目"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 10))
        historyButton.tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 10))
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

    func testExportSavedDiaryPresentsFilePicker() throws {
        let app = XCUIApplication()
        launchDiary(in: app)

        let note = "Export flow note from UI test."
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(note)
        app.buttons["完成"].tap()
        app.buttons["保存并生成共情"].tap()

        openSettings(in: app)
        app.buttons["导出日记"].tap()

        // The system document picker is presented only after the app fetches and
        // decrypts the saved entry and builds the export document.
        let cancelButton = app.buttons["取消"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10))
        cancelButton.tap()
        XCTAssertTrue(app.buttons["导出日记"].waitForExistence(timeout: 5))
    }

    private func launchDiary(in app: XCUIApplication) {
        app.launchArguments += ["-ui-testing", "-allowCloudAnalysis", "NO"]
        app.launch()
    }

    private func openSettings(in app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
    }
}
