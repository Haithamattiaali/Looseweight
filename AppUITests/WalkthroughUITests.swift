import XCTest

/// Walks every screen in the simulator and saves a screenshot of each — the visual proof that the app works.
final class WalkthroughUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTest"] + arguments
        if let photo = ProcessInfo.processInfo.environment["LW_DEMO_PHOTO"] {
            app.launchEnvironment["LW_DEMO_PHOTO"] = photo
        }
        app.launch()
        return app
    }

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"], !directory.isEmpty {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }

    private func tapTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        if tab.waitForExistence(timeout: 5) {
            tab.tap()
        } else {
            app.buttons[title].firstMatch.tap()
        }
    }

    func testOnboardingBuildsAPlan() {
        let app = launch(["-resetState"])
        let next = app.buttons["onboardingContinue"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        snap("01-welcome")
        next.tap()
        sleep(1)
        snap("02-about-you")
        next.tap()
        sleep(1)
        snap("03-goal")
        next.tap()
        XCTAssertTrue(app.staticTexts["planTarget"].waitForExistence(timeout: 10))
        snap("04-plan")
        next.tap()
        XCTAssertTrue(app.buttons["scanFirstMeal"].waitForExistence(timeout: 15))
        snap("05-today-empty")
    }

    func testScanAnalyseReviewAndSave() {
        let app = launch(["-seedDemoData"])
        let scan = app.buttons["scanAccessory"]
        XCTAssertTrue(scan.waitForExistence(timeout: 25))
        sleep(1)
        snap("06-today")

        scan.tap()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15))
        sleep(1)
        snap("07-camera")

        shutter.tap()
        _ = app.staticTexts["Identifying each food"].waitForExistence(timeout: 5)
        snap("08-analysing")

        let save = app.buttons["saveMeal"]
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        sleep(1)
        snap("09-review")

        let firstItem = app.staticTexts["Grilled chicken breast"]
        if firstItem.waitForExistence(timeout: 5) {
            firstItem.tap()
            sleep(1)
            snap("10-review-adjust")
        }

        save.tap()
        XCTAssertTrue(app.buttons["scanAccessory"].waitForExistence(timeout: 15))
        sleep(1)
        snap("11-today-after-save")

        tapTab("Progress", in: app)
        XCTAssertTrue(app.buttons["logWeight"].waitForExistence(timeout: 10))
        sleep(1)
        snap("12-progress")

        tapTab("Settings", in: app)
        sleep(2)
        snap("13-settings")
    }
}
