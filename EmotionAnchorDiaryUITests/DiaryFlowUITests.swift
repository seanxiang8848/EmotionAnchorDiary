import XCTest

final class DiaryFlowUITests: XCTestCase {
    func testDiaryScreenOpensSettingsAndShowsPrivacyActions() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-allowCloudAnalysis", "NO"]
        app.launch()

        XCTAssertTrue(app.staticTexts["今天的心情在哪儿？"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["保存并生成共情"].exists)

        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.exists)
        settingsButton.tap()

        XCTAssertTrue(app.switches["启动时使用 Face ID 或设备密码"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["导出日记"].exists)
        XCTAssertTrue(app.buttons["删除所有本地日记和目标…"].exists)
    }
}
