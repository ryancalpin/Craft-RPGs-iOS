import XCTest

@MainActor
final class CampaignDeletionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeletingImportedCampaignRequiresConfirmationAndReturnsToHost() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-start-at-library",
            "-persistence-test-store",
            "task8-campaign-deletion",
            "-reset-persistence-test-store",
            "-import-flow-fixture",
            "success"
        ]
        app.launch()

        XCTAssertTrue(
            app.buttons["importCampaignButton"].waitForExistence(timeout: 3)
        )
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
        app.buttons["overviewDrawerButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["overviewDrawer"]
                .waitForExistence(timeout: 2)
        )
        app.buttons["overviewDrawerSettings"].tap()

        let campaignDataView = app.descendants(matching: .any)[
            "campaignDataView"
        ]
        XCTAssertTrue(campaignDataView.waitForExistence(timeout: 2))

        let campaignDataCapture = XCTAttachment(screenshot: app.screenshot())
        campaignDataCapture.name = "campaign-data-view"
        campaignDataCapture.lifetime = .keepAlways
        add(campaignDataCapture)

        let deleteButton = app.buttons["deleteCampaignButton"]
        XCTAssertTrue(deleteButton.exists)
        deleteButton.tap()

        let confirmation = app.alerts["Delete “Greyhaven Ready”?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(
            confirmation.staticTexts[
                "This permanently deletes its events, imported assets, cached narration, and campaign key references."
            ].exists
        )
        confirmation.buttons["Cancel"].tap()

        XCTAssertTrue(campaignDataView.exists)
        XCTAssertTrue(deleteButton.exists)

        deleteButton.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["Delete Campaign"].tap()

        XCTAssertTrue(
            app.buttons["importCampaignButton"].waitForExistence(timeout: 4)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["sceneCanvas"].exists
        )
    }
}
