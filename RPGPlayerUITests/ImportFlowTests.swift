import XCTest

@MainActor
final class ImportFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCancelReturnsToCampaignLibraryWithoutLaunchingPlayer() {
        let app = launch(fixture: "cancel")

        app.buttons["importCampaignButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["importReviewView"]
                .waitForExistence(timeout: 3)
        )

        app.buttons["cancelImportButton"].tap()

        XCTAssertTrue(
            app.buttons["importCampaignButton"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.descendants(matching: .any)["sceneCanvas"].exists)
    }

    func testWarningReviewExplainsMissingReferenceAndAllowsCommit() {
        let app = launch(fixture: "warning")

        app.buttons["importCampaignButton"].tap()

        let review = app.descendants(matching: .any)["importReviewView"]
        XCTAssertTrue(review.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["What I understood"].exists)
        XCTAssertTrue(app.staticTexts["Greyhaven Warning"].exists)
        XCTAssertTrue(app.staticTexts["Missing references"].exists)
        XCTAssertTrue(app.staticTexts["project.currentSceneRecordID"].exists)
        XCTAssertTrue(app.buttons["confirmImportButton"].isEnabled)
    }

    func testFatalReviewShowsSafeDiagnosticsAndDisablesCommit() {
        let app = launch(fixture: "fatal")

        app.buttons["importCampaignButton"].tap()

        let review = app.descendants(matching: .any)["importReviewView"]
        XCTAssertTrue(review.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["invalid_metadata"].exists)
        XCTAssertTrue(app.staticTexts["project.json"].exists)
        XCTAssertTrue(app.staticTexts["The project metadata could not be read."].exists)
        XCTAssertFalse(app.staticTexts["PRIVATE SOURCE CONTENT"].exists)
        XCTAssertFalse(app.buttons["confirmImportButton"].isEnabled)
    }

    func testSuccessfulImportLaunchesTheUnchangedPlayerShell() {
        let app = launch(fixture: "success")

        app.buttons["importCampaignButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["importReviewView"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["confirmImportButton"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["sceneCanvas"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["projectDrawerButton"].exists)
        XCTAssertTrue(app.buttons["overviewDrawerButton"].exists)
        XCTAssertFalse(app.buttons["importCampaignButton"].exists)
    }

    private func launch(fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-start-at-library",
            "-persistence-test-store",
            "task7-import-\(fixture)",
            "-reset-persistence-test-store",
            "-import-flow-fixture",
            fixture
        ]
        app.launch()
        XCTAssertTrue(
            app.buttons["importCampaignButton"].waitForExistence(timeout: 3)
        )
        return app
    }
}
