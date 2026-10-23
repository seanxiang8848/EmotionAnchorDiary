import XCTest

final class DiaryFlowUITests: XCTestCase {
    /// P2-12：首次启动显示引导页，点“开始写日记”后进入主界面；再次启动不再显示。
    func testOnboardingShowsOnceAndCanBeDismissed() throws {
        let app = XCUIApplication()
        launchDiary(in: app, extraArguments: ["-ui-testing-show-onboarding"])

        XCTAssertTrue(app.staticTexts["欢迎使用情绪锚点日记"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["日记只保存在这台设备上，正文加密存储"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingContinueButton"].exists)

        app.buttons["onboardingContinueButton"].tap()

        XCTAssertTrue(app.staticTexts["今天的心情在哪儿？"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["欢迎使用情绪锚点日记"].exists)

        // 再次启动（不带强制参数时，已完成标记生效）不应再显示引导
        app.terminate()
        let relaunchedApp = XCUIApplication()
        launchDiary(in: relaunchedApp, extraArguments: ["-ui-testing-show-onboarding"])
        XCTAssertTrue(relaunchedApp.staticTexts["今天的心情在哪儿？"].waitForExistence(timeout: 10))
        XCTAssertFalse(relaunchedApp.staticTexts["欢迎使用情绪锚点日记"].exists)
    }

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

    func testCloudAnalysisDisabledUsesLocalEmpathy() throws {
        let app = XCUIApplication()
        launchDiary(in: app, extraArguments: ["-ui-testing-ai-success"])

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("I felt overwhelmed today!")
        app.buttons["完成"].tap()
        app.buttons["保存并生成共情"].tap()

        XCTAssertTrue(app.staticTexts["已保存并使用本地安慰文案"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["谢谢你写下这些感受。"].exists)
    }

    func testCloudAnalysisEnabledShowsAIResponse() throws {
        let app = XCUIApplication()
        launchDiary(in: app, cloudAnalysisAllowed: true, extraArguments: ["-ui-testing-ai-success"])

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("I felt overwhelmed today! I talked with a friend. I feel calmer now?")
        app.buttons["完成"].tap()
        app.buttons["保存并生成共情"].tap()

        XCTAssertTrue(app.staticTexts["谢谢你写下这些感受。"].waitForExistence(timeout: 10))
        let suggestion = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "做三次深呼吸")
        ).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
    }

    func testCloudAnalysisWithoutAPIKeyUsesLocalEmpathyAndPreservesDiary() throws {
        let app = XCUIApplication()
        launchDiary(in: app, cloudAnalysisAllowed: true, extraArguments: ["-ui-testing-ai-missing-key"])

        let note = "AI analysis must stay local when no API key is configured."
        let editor = app.textViews["diary-entry-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(note)
        app.buttons["完成"].tap()
        app.buttons["保存并生成共情"].tap()

        XCTAssertTrue(app.staticTexts["已保存并使用本地安慰文案"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["谢谢你写下这些感受。"].exists)
        app.buttons["查看历史条目"].tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 10))
    }

    func testCloudAnalysisFailureFallsBackAndPreservesDiary() throws {
        let app = XCUIApplication()
        launchDiary(in: app, cloudAnalysisAllowed: true, extraArguments: ["-ui-testing-ai-failure"])

        let note = "Cloud AI failure still saves this diary."
        let editor = app.textViews["diary-entry-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(note)
        app.buttons["完成"].tap()
        app.buttons["保存并生成共情"].tap()

        XCTAssertTrue(app.staticTexts["已保存并使用本地安慰文案"].waitForExistence(timeout: 10))
        app.buttons["查看历史条目"].tap()
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

    func testConfirmingDeleteAllRemovesDiaryFromHistory() throws {
        let app = XCUIApplication()
        launchDiary(in: app)

        let note = "This diary should be removed after confirmation."
        let editor = app.textViews["diary-entry-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(note)
        app.buttons["完成"].tap()
        app.buttons["保存并生成共情"].tap()
        XCTAssertTrue(app.staticTexts["已保存并使用本地安慰文案"].waitForExistence(timeout: 10))

        openSettings(in: app)
        app.buttons["删除所有本地日记和目标…"].tap()
        let deleteButton = app.buttons["删除全部数据"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        let deletionNotice = app.alerts["本机日记、目标和 AI 密钥已删除。"]
        XCTAssertTrue(deletionNotice.waitForExistence(timeout: 5))
        deletionNotice.buttons["好"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["查看历史条目"].tap()
        XCTAssertTrue(app.staticTexts["暂无记录"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[note].exists)
    }

    func testExportSavedDiaryPresentsSystemSavePicker() throws {
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

        // The simulator may not have an "On My iPhone" Files provider. Open
        // the browser, then cancel without claiming that a file was written
        // to a destination unavailable in CI.
        let browseButton = app.buttons["Browse"]
        XCTAssertTrue(browseButton.waitForExistence(timeout: 10))
        browseButton.tap()

        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10))
        cancelButton.tap()
        XCTAssertFalse(app.alerts["日记已导出。"].exists)
    }

    func testExportWithoutEntriesShowsHelpfulMessage() throws {
        let app = XCUIApplication()
        launchDiary(in: app)
        openSettings(in: app)

        app.buttons["导出日记"].tap()

        let emptyExportAlert = app.alerts["暂无日记可导出。"]
        XCTAssertTrue(emptyExportAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyExportAlert.buttons["好"].exists)
    }

    func testVoiceRecordingPermissionDenialShowsErrorWithoutRecording() throws {
        let app = XCUIApplication()
        launchDiary(in: app, extraArguments: ["-ui-testing-speech-denied"])

        app.buttons["语音记录"].tap()

        XCTAssertTrue(app.staticTexts["语音未获授权，请允许麦克风和语音识别后重试"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["语音记录"].exists)
        XCTAssertFalse(app.buttons["停止录音"].exists)
    }

    func testVoiceTranscriptCanBeSavedAndReadBackFromHistory() throws {
        let app = XCUIApplication()
        launchDiary(in: app, extraArguments: ["-ui-testing-speech-success"])

        app.buttons["语音记录"].tap()

        let editor = app.textViews["diary-entry-editor"]
        let transcript = "今天我感到有些紧张，但说出来后轻松了些。"
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains(transcript) == true)
        app.buttons["停止录音"].tap()
        app.buttons["保存并生成共情"].tap()

        XCTAssertTrue(app.staticTexts["已保存并使用本地安慰文案"].waitForExistence(timeout: 10))
        app.buttons["查看历史条目"].tap()
        XCTAssertTrue(app.staticTexts[transcript].waitForExistence(timeout: 10))
    }

    func testAppLockPreferenceControlsBackgroundLocking() throws {
        let app = XCUIApplication()
        launchDiary(in: app, extraArguments: ["-ui-testing-app-lock", "-ui-testing-reset-app-lock"])

        let lockTitle = app.staticTexts["情绪锚点日记已锁定"]
        let unlockButton = app.buttons["使用 Face ID 或设备密码解锁"]
        XCTAssertTrue(app.staticTexts["今天的心情在哪儿？"].waitForExistence(timeout: 10))

        openSettings(in: app)
        let appLockSwitch = app.switches["app-lock-toggle"]
        XCTAssertTrue(appLockSwitch.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSwitch(appLockSwitch, value: "0"))
        tapAppLockSwitch(appLockSwitch)
        XCTAssertTrue(waitForSwitch(appLockSwitch, value: "1"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["保存并生成共情"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(lockTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(unlockButton.exists)
        XCTAssertFalse(app.buttons["保存并生成共情"].exists)
        XCTAssertFalse(app.textViews.firstMatch.exists)

        unlockButton.tap()
        XCTAssertTrue(app.buttons["保存并生成共情"].waitForExistence(timeout: 5))

        openSettings(in: app)
        XCTAssertTrue(waitForSwitch(appLockSwitch, value: "1"))
        tapAppLockSwitch(appLockSwitch)
        XCTAssertTrue(waitForSwitch(appLockSwitch, value: "0"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["今天的心情在哪儿？"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["今天的心情在哪儿？"].waitForExistence(timeout: 5))
        XCTAssertFalse(lockTitle.exists)
    }

    func testFailedAppLockAuthenticationKeepsDiaryLocked() throws {
        let app = XCUIApplication()
        launchDiary(in: app, extraArguments: [
            "-ui-testing-app-lock",
            "-ui-testing-app-lock-failure",
            "-ui-testing-enable-app-lock"
        ])

        let unlockButton = app.buttons["使用 Face ID 或设备密码解锁"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 10))
        unlockButton.tap()

        XCTAssertTrue(app.staticTexts["验证未完成，请重试。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["保存并生成共情"].exists)
        XCTAssertFalse(app.textViews["diary-entry-editor"].exists)
    }

    private func launchDiary(
        in app: XCUIApplication,
        cloudAnalysisAllowed: Bool = false,
        extraArguments: [String] = []
    ) {
        app.launchArguments += ["-ui-testing", "-allowCloudAnalysis", cloudAnalysisAllowed ? "YES" : "NO"]
        app.launchArguments += extraArguments
        app.launch()
    }

    private func openSettings(in app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
    }

    private func waitForSwitch(_ element: XCUIElement, value: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func tapAppLockSwitch(_ element: XCUIElement) {
        XCTAssertTrue(element.isHittable)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }
}
