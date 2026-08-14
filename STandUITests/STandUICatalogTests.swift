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
        capture("01_first_launch_permissions")

        launch()
        XCTAssertTrue(app.buttons["설정 열기"].waitForExistence(timeout: 8))
        capture("02_home_portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["설정 열기"].waitForExistence(timeout: 5))
        capture("03_home_landscape")

        XCUIDevice.shared.orientation = .portrait
        launch(arguments: ["--ui-catalog-editor"])
        XCTAssertTrue(app.buttons["저장"].waitForExistence(timeout: 5))
        capture("04_home_editor")

        launch()
        XCTAssertTrue(app.buttons["설정 열기"].waitForExistence(timeout: 8))

        button(prefix: "잠소리 확인").tap()
        XCTAssertTrue(app.navigationBars["잠소리"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["수면 리포트"].waitForExistence(timeout: 5))
        capture("05_recordings")
        app.buttons["잠소리 관리"].tap()
        XCTAssertTrue(app.staticTexts["보관 현황"].waitForExistence(timeout: 5))
        capture("05b_sound_list")
        dismissPresentedScreen()

        button(prefix: "보이소").tap()
        XCTAssertTrue(app.navigationBars["보이소"].waitForExistence(timeout: 5))
        capture("06_boyiso_setup")

        launch()
        XCTAssertTrue(app.buttons["설정 열기"].waitForExistence(timeout: 8))
        app.buttons["설정 열기"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        capture("07_settings_top")

        app.buttons["미드나이트 테마"].tap()
        capture("08_settings_midnight_theme")

        button(prefix: "시계 글꼴").tap()
        XCTAssertTrue(app.navigationBars["시계 글꼴"].waitForExistence(timeout: 5))
        capture("09_clock_font_options")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        scrollTo(text: "인터넷 라디오")
        capture("10_settings_lower_sections")

        let firstChannelEditor = app.buttons["편안한 재즈 수정"]
        scrollTo(element: firstChannelEditor, description: "편안한 재즈 수정")
        firstChannelEditor.tap()
        capture("11_radio_channel_editor")

        let deleteChannel = app.buttons["편안한 재즈 삭제"]
        scrollTo(element: deleteChannel, description: "편안한 재즈 삭제")
        deleteChannel.tap()
        XCTAssertTrue(app.buttons["채널 삭제"].waitForExistence(timeout: 5))
        capture("12_radio_delete_confirmation")

        launch()
        XCTAssertTrue(app.buttons["설정 열기"].waitForExistence(timeout: 8))
        app.buttons["설정 열기"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        scrollTo(text: "추천 설정 복원")
        app.buttons["추천 설정 복원"].tap()
        XCTAssertTrue(app.buttons["추천 설정 복원"].waitForExistence(timeout: 5))
        capture("13_restore_confirmation")

        launch()
        XCTAssertTrue(app.buttons["설정 열기"].waitForExistence(timeout: 8))
        app.buttons["설정 열기"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        scrollTo(text: "내장 폰트 저작권")
        button(prefix: "내장 폰트 저작권").tap()
        XCTAssertTrue(app.navigationBars["폰트 저작권"].waitForExistence(timeout: 5))
        capture("14_font_licenses")
    }

    private func launch(arguments: [String] = []) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--ui-catalog"] + arguments
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()
    }

    private func capture(_ name: String) {
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
        let closeButton = app.buttons["닫기"]
        if closeButton.exists && closeButton.isHittable {
            closeButton.tap()
        } else {
            app.swipeDown()
        }
        XCTAssertTrue(app.buttons["설정 열기"].waitForExistence(timeout: 5))
    }

    private func scrollTo(text: String) {
        scrollTo(element: app.staticTexts[text], description: text)
    }

    private func scrollTo(element: XCUIElement, description: String) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(description) 항목을 화면 안에서 찾지 못했습니다.")
    }
}
