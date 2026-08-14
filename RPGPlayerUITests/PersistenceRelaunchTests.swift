import XCTest

@MainActor
final class PersistenceRelaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testImportedCampaignAppearsInLibraryAndCanBeReopenedAfterExit() {
        let app = launch(
            storeID: "task9-library-flow",
            resetStore: true,
            fixture: "success"
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["campaignLibraryView"]
                .waitForExistence(timeout: 3)
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

        app.buttons["projectDrawerButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["projectDrawer"]
                .waitForExistence(timeout: 2)
        )
        app.buttons["closeProjectDrawer"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["campaignLibraryView"]
                .waitForExistence(timeout: 3)
        )
        let campaign = app.buttons["Greyhaven Ready"]
        XCTAssertTrue(campaign.waitForExistence(timeout: 2))
        campaign.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["sceneCanvas"]
                .waitForExistence(timeout: 3)
        )
    }

    func testImportedCampaignRestoresExactBeatAfterRelaunch() {
        let storeID = "task9-relaunch-flow"
        let app = launch(
            storeID: storeID,
            resetStore: true,
            fixture: "success"
        )
        importSuccessfulCampaign(in: app)

        let title = app.staticTexts["campaignTitle"]
        let beatPosition = app.staticTexts["visualNovelBeatPosition"]
        let secondBeat = app.staticTexts[
            "The Fogbound Harbor\n\nA harbor mystery prepared as project-world content."
        ]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Greyhaven Ready")
        XCTAssertTrue(beatPosition.waitForExistence(timeout: 2))
        XCTAssertEqual(beatPosition.value as? String, "1 of 2")

        app.buttons["nextBeat"].tap()

        XCTAssertTrue(secondBeat.waitForExistence(timeout: 2))
        XCTAssertEqual(beatPosition.value as? String, "2 of 2")
        let titleFrame = title.frame
        let sceneFrame = app.otherElements["sceneCanvas"].frame
        let cardFrame = app.otherElements["visualNovelCard"].frame
        app.terminate()

        let relaunched = launch(
            storeID: storeID,
            resetStore: false,
            startsAtLibrary: false
        )
        let relaunchedTitle = relaunched.staticTexts["campaignTitle"]
        let relaunchedPosition = relaunched.staticTexts[
            "visualNovelBeatPosition"
        ]
        let relaunchedSecondBeat = relaunched.staticTexts[
            "The Fogbound Harbor\n\nA harbor mystery prepared as project-world content."
        ]

        XCTAssertTrue(
            relaunched.otherElements["sceneCanvas"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(relaunchedTitle.waitForExistence(timeout: 2))
        XCTAssertEqual(relaunchedTitle.label, "Greyhaven Ready")
        XCTAssertTrue(relaunchedSecondBeat.waitForExistence(timeout: 2))
        XCTAssertEqual(relaunchedPosition.value as? String, "2 of 2")
        assertEqualFrame(relaunchedTitle.frame, titleFrame)
        assertEqualFrame(
            relaunched.otherElements["sceneCanvas"].frame,
            sceneFrame
        )
        assertEqualFrame(
            relaunched.otherElements["visualNovelCard"].frame,
            cardFrame
        )
    }

    func testNativeCampaignPersistsAndReopensAfterRelaunch() {
        let storeID = "task9-native-library-flow"
        let app = launch(
            storeID: storeID,
            resetStore: true,
            startsAtLibrary: true
        )

        XCTAssertTrue(
            app.buttons["newCampaignButton"].waitForExistence(timeout: 3)
        )
        app.buttons["newCampaignButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["newCampaignView"]
                .waitForExistence(timeout: 2)
        )

        let titleField = app.textFields["newCampaignTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("The Quiet Meridian")
        app.buttons["createCampaignButton"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["sceneCanvas"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            app.staticTexts["campaignTitle"].label,
            "The Quiet Meridian"
        )

        app.terminate()

        let relaunched = launch(
            storeID: storeID,
            resetStore: false,
            startsAtLibrary: false
        )
        XCTAssertTrue(
            relaunched.descendants(matching: .any)["sceneCanvas"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            relaunched.staticTexts["campaignTitle"].label,
            "The Quiet Meridian"
        )
    }

    private func launch(
        storeID: String,
        resetStore: Bool,
        fixture: String? = nil,
        startsAtLibrary: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-persistence-test-store",
            storeID
        ]
        if startsAtLibrary {
            app.launchArguments.append("-start-at-library")
        }
        if resetStore {
            app.launchArguments.append("-reset-persistence-test-store")
        }
        if let fixture {
            app.launchArguments += ["-import-flow-fixture", fixture]
        }
        app.launch()
        return app
    }

    private func importSuccessfulCampaign(in app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)["campaignLibraryView"]
                .waitForExistence(timeout: 3)
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
    }

    private func assertEqualFrame(
        _ actual: CGRect,
        _ expected: CGRect,
        accuracy: CGFloat = 1
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy)
    }
}
