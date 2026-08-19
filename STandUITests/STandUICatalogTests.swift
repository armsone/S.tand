import XCTest

final class STandUICatalogTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testCaptureUICatalog() throws {
        launch(arguments: ["--ui-catalog-permissions"])
        XCTAssertTrue(app.buttons["권한 확인하고 시작"].waitForExistence(timeout: 5))
        capture("first_launch_permissions")

        launch()
        XCTAssertTrue(app.buttons["설정"].waitForExistence(timeout: 8))
        capture("home_portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["설정"].waitForExistence(timeout: 5))
        capture("home_landscape")

        XCUIDevice.shared.orientation = .portrait
        launch(arguments: ["--ui-catalog-editor"])
        XCTAssertTrue(app.buttons["저장"].waitForExistence(timeout: 5))
        capture("home_editor")

        launch()
        XCTAssertTrue(app.buttons["설정"].waitForExistence(timeout: 8))

        button(prefix: "잠소리").tap()
        XCTAssertTrue(app.navigationBars["잠소리"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["수면 리포트"].waitForExistence(timeout: 5))
        capture("recordings_report")
        app.buttons["잠소리 관리"].tap()
        let storageSummary = app.staticTexts["보관 현황"]
        let emptyRecordings = app.staticTexts["저장된 잠소리가 없습니다"]
        XCTAssertTrue(
            storageSummary.waitForExistence(timeout: 2)
                || emptyRecordings.waitForExistence(timeout: 2)
        )
        capture(storageSummary.exists ? "recordings_management" : "recordings_management_empty")
        dismissPresentedScreen()

        button(prefix: "보이소").tap()
        XCTAssertTrue(app.navigationBars["보이소"].waitForExistence(timeout: 5))
        capture("boyiso_setup")

        launch()
        XCTAssertTrue(app.buttons["설정"].waitForExistence(timeout: 8))
        app.buttons["설정"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        capture("settings_top")

        app.buttons["미드나이트 테마"].tap()
        capture("settings_midnight_theme")

        button(prefix: "시계 글꼴").tap()
        XCTAssertTrue(app.navigationBars["시계 글꼴"].waitForExistence(timeout: 5))
        capture("clock_font_options")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let radioShortcut = app.buttons["internet-radio-settings-shortcut"]
        XCTAssertTrue(radioShortcut.waitForExistence(timeout: 5))
        radioShortcut.tap()

        let firstChannelEditor = app.buttons["편안한 재즈 수정"]
        XCTAssertTrue(firstChannelEditor.waitForExistence(timeout: 5))
        XCTAssertTrue(firstChannelEditor.isHittable)
        capture("settings_lower_sections")

        firstChannelEditor.tap()
        capture("radio_channel_editor")

        let deleteChannel = app.buttons["편안한 재즈 삭제"]
        scrollTo(element: deleteChannel, description: "편안한 재즈 삭제")
        deleteChannel.tap()
        XCTAssertTrue(app.buttons["채널 삭제"].waitForExistence(timeout: 5))
        capture("radio_delete_confirmation")

        launch()
        XCTAssertTrue(app.buttons["설정"].waitForExistence(timeout: 8))
        app.buttons["설정"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        scrollTo(text: "추천 설정 복원")
        app.buttons["추천 설정 복원"].tap()
        XCTAssertTrue(app.buttons["추천 설정 복원"].waitForExistence(timeout: 5))
        capture("restore_confirmation")

        launch()
        XCTAssertTrue(app.buttons["설정"].waitForExistence(timeout: 8))
        app.buttons["설정"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        scrollTo(text: "내장 폰트 저작권")
        button(prefix: "내장 폰트 저작권").tap()
        XCTAssertTrue(app.navigationBars["폰트 저작권"].waitForExistence(timeout: 5))
        capture("font_licenses")
    }

    func testInternetRadioShortcutReachesInlineEditor() throws {
        launch()
        XCTAssertTrue(app.buttons["설정"].waitForExistence(timeout: 8))
        app.buttons["설정"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))

        let shortcut = app.buttons["internet-radio-settings-shortcut"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
        shortcut.tap()

        let editorButton = app.buttons["편안한 재즈 수정"]
        XCTAssertTrue(editorButton.waitForExistence(timeout: 5))
        XCTAssertTrue(editorButton.isHittable)
        editorButton.tap()

        XCTAssertTrue(app.staticTexts["인터넷 라디오 수정"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["이름 (선택)"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["internet-radio-address-field"].exists
        )
    }

    private func launch(arguments: [String] = []) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--ui-catalog"] + arguments
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["TZ"] = "Asia/Seoul"
        app.launchArguments += ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(prefix: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", prefix)
        ).firstMatch
    }

    private func dismissPresentedScreen() {
        let doneButton = app.buttons["완료"]
        if doneButton.exists && doneButton.isHittable {
            doneButton.tap()
        } else {
            app.swipeDown()
        }
        XCTAssertTrue(app.buttons["설정"].waitForExistence(timeout: 5))
    }

    private func scrollTo(text: String) {
        scrollTo(element: app.staticTexts[text], description: text)
    }

    private func scrollTo(element: XCUIElement, description: String) {
        for _ in 0..<8 where !element.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, "\(description) 항목을 화면 안에서 찾지 못했습니다.")
    }
}
