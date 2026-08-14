import XCTest

@MainActor
final class CampaignVoiceAssignmentsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLiveCampaignExposesPersistentVoiceAssignments() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-start-at-library",
            "-persistence-test-store",
            "campaign-voice-\(UUID().uuidString)",
            "-reset-persistence-test-store",
            "-import-flow-fixture",
            "cancel"
        ]
        app.launch()

        app.buttons["newCampaignButton"].tap()
        let titleField = app.textFields["newCampaignTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Voice Harbor")
        app.buttons["createCampaignButton"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["sceneCanvas"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["overviewDrawerButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["overviewDrawer"]
                .waitForExistence(timeout: 2)
        )
        app.buttons["overviewDrawerSettings"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["campaignDataView"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["campaignVoiceAssignmentsLink"].exists)
        app.buttons["campaignVoiceAssignmentsLink"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["campaignVoiceAssignmentsView"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["voiceAssignmentTarget-narrator"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["voiceAssignmentTarget-gm"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["voiceAssignmentTarget-player"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["refreshCampaignVoicesButton"].exists)
    }
}
