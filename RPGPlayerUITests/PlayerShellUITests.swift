import XCTest

@MainActor
final class PlayerShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDrawersOpenAsOverlaysAndRemainExclusive() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "player-shell"]
        app.launch()

        let scene = app.otherElements["sceneCanvas"]
        XCTAssertTrue(scene.waitForExistence(timeout: 2))
        let sceneFrame = scene.frame
        XCTAssertEqual(sceneFrame, app.frame)

        app.buttons["projectDrawerButton"].tap()
        let projectDrawer = app.descendants(matching: .any)["projectDrawer"]
        XCTAssertTrue(projectDrawer.waitForExistence(timeout: 2))
        waitForDrawerPresentation(app, identifier: "projectDrawer")
        XCTAssertEqual(
            projectDrawer.frame.width,
            min(app.frame.width * 0.72, 420),
            accuracy: 2
        )
        XCTAssertEqual(scene.frame, sceneFrame)

        let closeProjectDrawer = app.buttons["closeProjectDrawer"]
        XCTAssertTrue(closeProjectDrawer.isHittable)
        closeProjectDrawer.tap()
        app.buttons["overviewDrawerButton"].tap()
        let overviewDrawer = app.descendants(matching: .any)["overviewDrawer"]
        XCTAssertTrue(overviewDrawer.waitForExistence(timeout: 2))
        waitForDrawerPresentation(app, identifier: "overviewDrawer")
        XCTAssertEqual(
            overviewDrawer.frame.width,
            min(app.frame.width * 0.90, 620),
            accuracy: 2
        )
        XCTAssertTrue(app.buttons["overviewDrawerSettings"].isHittable)
        XCTAssertTrue(app.buttons["closeOverviewDrawer"].isHittable)
        XCTAssertFalse(projectDrawer.exists)
        XCTAssertEqual(scene.frame, sceneFrame)
    }

    func testProjectDrawerIncludesRecordingTabAndActionHierarchy() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "player-shell"]
        app.launch()

        app.buttons["projectDrawerButton"].tap()
        let projectDrawer = app.descendants(matching: .any)["projectDrawer"]
        XCTAssertTrue(projectDrawer.waitForExistence(timeout: 2))
        waitForDrawerPresentation(app, identifier: "projectDrawer")
        XCTAssertFalse(app.buttons["overviewDrawerButton"].isHittable)
        XCTAssertTrue(app.buttons["projectFilesTab"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["projectSearchTab"].exists)
        XCTAssertTrue(app.buttons["projectPackagesTab"].exists)
        if app.frame.width >= 430 {
            XCTAssertLessThanOrEqual(
                app.buttons["projectFilesTab"].frame.minX - projectDrawer.frame.minX,
                8
            )
        }
        XCTAssertTrue(app.descendants(matching: .any)["projectActionRow"].exists)
        let actionIdentifiers = app.frame.width < 430
            ? [
                "projectNewFile",
                "projectNewFolder",
                "projectActionOverflow",
                "projectFolderView",
                "projectFileView"
            ]
            : [
                "projectNewFile",
                "projectNewFolder",
                "projectImportFiles",
                "projectRefreshFiles",
                "projectFolderView",
                "projectFileView"
            ]
        for identifier in actionIdentifiers {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.minX, projectDrawer.frame.minX)
            XCTAssertLessThanOrEqual(control.frame.maxX, projectDrawer.frame.maxX)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        XCTAssertTrue(app.scrollViews["projectFileTree"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["projectProfileCard"].exists)
        XCTAssertEqual(app.buttons["closeProjectDrawer"].label, "Exit Game")

        app.buttons["projectSearchTab"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["projectActionRow"].exists)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.exists)
        let settingsFrame = settings.frame

        let searchField = app.textFields["projectSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 1))
        XCTAssertGreaterThanOrEqual(searchField.frame.height, 44)
        let emptyState = app.staticTexts["projectSearchEmptyState"]
        XCTAssertTrue(emptyState.exists)
        XCTAssertLessThanOrEqual(emptyState.frame.minY - searchField.frame.maxY, 60)
        searchField.tap()
        let dismissKeyboard = app.buttons["dismissSearchKeyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 1))
        XCTAssertTrue(dismissKeyboard.isHittable)
        XCTAssertGreaterThanOrEqual(dismissKeyboard.frame.width, 44)
        XCTAssertGreaterThanOrEqual(dismissKeyboard.frame.height, 44)
        let previousSearchField = app.buttons["Previous search field"]
        let nextSearchField = app.buttons["Next search field"]
        XCTAssertFalse(previousSearchField.isEnabled)
        XCTAssertFalse(nextSearchField.isEnabled)
        XCTAssertEqual(previousSearchField.frame.height, 44, accuracy: 1)
        XCTAssertEqual(nextSearchField.frame.height, 44, accuracy: 1)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        XCTAssertLessThanOrEqual(
            previousSearchField.frame.minX - keyboard.frame.minX,
            24
        )
        XCTAssertLessThanOrEqual(
            keyboard.frame.maxX - dismissKeyboard.frame.maxX,
            24
        )
        XCTAssertEqual(
            previousSearchField.frame.midY,
            dismissKeyboard.frame.midY,
            accuracy: 1
        )
        XCTAssertLessThanOrEqual(
            abs(dismissKeyboard.frame.maxY - keyboard.frame.minY),
            24
        )
        XCTAssertEqual(settings.frame.minY, settingsFrame.minY, accuracy: 1)
        XCTAssertGreaterThan(settings.frame.maxY, keyboard.frame.minY)

        let searchKeyboardCapture = XCTAttachment(screenshot: app.screenshot())
        searchKeyboardCapture.name = "project-search-keyboard"
        searchKeyboardCapture.lifetime = .keepAlways
        add(searchKeyboardCapture)

        searchField.typeText("road")
        dismissKeyboard.tap()
        XCTAssertFalse(keyboard.waitForExistence(timeout: 1))
        app.buttons["closeProjectDrawer"].tap()
        app.buttons["projectDrawerButton"].tap()
        waitForDrawerPresentation(app, identifier: "projectDrawer")
        app.buttons["projectSearchTab"].tap()
        XCTAssertEqual(app.textFields["projectSearchField"].value as? String, "road")
    }

    func testPackagesTabClosesDrawerAndPresentsBottomSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "player-shell"]
        app.launch()

        app.buttons["projectDrawerButton"].tap()
        let projectDrawer = app.descendants(matching: .any)["projectDrawer"]
        XCTAssertTrue(projectDrawer.waitForExistence(timeout: 2))
        waitForDrawerPresentation(app, identifier: "projectDrawer")
        app.buttons["projectPackagesTab"].tap()

        let packageSheet = app.descendants(matching: .any)["packageSheet"]
        XCTAssertTrue(packageSheet.waitForExistence(timeout: 2))
        XCTAssertFalse(projectDrawer.exists)
        if app.frame.width < 700 {
            XCTAssertGreaterThanOrEqual(
                packageSheet.frame.height / app.frame.height,
                0.74
            )
        } else {
            XCTAssertEqual(
                packageSheet.frame.midX,
                app.frame.midX,
                accuracy: 2
            )
            XCTAssertGreaterThanOrEqual(packageSheet.frame.width, 500)
            XCTAssertLessThanOrEqual(packageSheet.frame.width, 700)
            XCTAssertGreaterThanOrEqual(packageSheet.frame.height, 500)
            XCTAssertLessThanOrEqual(
                packageSheet.frame.height / app.frame.height,
                0.55
            )
        }
        XCTAssertTrue(app.buttons["closePackageSheet"].isHittable)
        XCTAssertTrue(app.buttons["packageProjectTab"].exists)
        XCTAssertTrue(app.buttons["packageCommunityTab"].exists)
        XCTAssertTrue(app.buttons["packageSort"].exists)
        XCTAssertTrue(app.buttons["packageInstall"].exists)

        let packageCard = app.descendants(matching: .any)["packageFixtureCard"]
        XCTAssertTrue(packageCard.exists)
        XCTAssertGreaterThanOrEqual(packageCard.frame.height, 320)

        let featuredInstall = app.buttons["packageInstall"]
        XCTAssertEqual(featuredInstall.label, "Install")
        featuredInstall.tap()
        XCTAssertEqual(featuredInstall.label, "Installed")

        app.buttons["packageProjectTab"].tap()
        XCTAssertTrue(app.staticTexts["Roadside Encounters"].waitForExistence(timeout: 1))
        XCTAssertEqual(app.buttons["packageInstall"].label, "Install")

        app.buttons["packageCommunityTab"].tap()
        XCTAssertTrue(app.staticTexts["Lantern Road Compendium"].waitForExistence(timeout: 1))
        XCTAssertEqual(app.buttons["packageInstall"].label, "Installed")
    }

    func testOverviewUsesRecordingModuleDensity() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "player-shell"]
        app.launch()

        app.buttons["overviewDrawerButton"].tap()
        waitForDrawerPresentation(app, identifier: "overviewDrawer")

        let mapArtwork = app.descendants(matching: .any)["overviewMapArtwork"]
        XCTAssertTrue(mapArtwork.exists)
        XCTAssertEqual(
            mapArtwork.frame.width / mapArtwork.frame.height,
            16.0 / 9.0,
            accuracy: 0.08
        )
        XCTAssertTrue(app.buttons["overviewMusicPlay"].exists)
        XCTAssertTrue(app.buttons["overviewMapExpand"].exists)
        XCTAssertTrue(app.buttons["overviewMapZoomIn"].exists)
        XCTAssertTrue(app.buttons["overviewMapZoomOut"].exists)

        let pinnedFile = app.descendants(matching: .any)["overviewPinnedFilePreview"]
        XCTAssertTrue(pinnedFile.exists)
        XCTAssertGreaterThanOrEqual(pinnedFile.frame.height, mapArtwork.frame.height * 1.45)

        let musicModule = app.buttons["Music Player"]
        musicModule.tap()
        XCTAssertEqual(musicModule.value as? String, "Collapsed")
        app.buttons["closeOverviewDrawer"].tap()
        app.buttons["overviewDrawerButton"].tap()
        waitForDrawerPresentation(app, identifier: "overviewDrawer")
        XCTAssertEqual(app.buttons["Music Player"].value as? String, "Collapsed")
    }

    func testAssistantTabPreservesDraftAndAppendsFixtureMessage() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "player-shell"]
        app.launch()

        app.buttons["overviewDrawerButton"].tap()
        waitForDrawerPresentation(app, identifier: "overviewDrawer")
        app.buttons["assistantTab"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["assistantContextBar"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["assistantToolResult"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["assistantTokenBar"].exists)
        XCTAssertTrue(app.buttons["assistantRecordsUtility"].exists)
        XCTAssertTrue(app.buttons["assistantHistoryUtility"].exists)
        XCTAssertTrue(app.buttons["assistantLatestUtility"].exists)

        let composer = app.textFields["assistantComposer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["sendAssistantMessage"].isEnabled)
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        composer.typeText("Summarize the road")

        app.buttons["overviewTab"].tap()
        app.buttons["assistantTab"].tap()
        XCTAssertEqual(composer.value as? String, "Summarize the road")

        app.buttons["closeOverviewDrawer"].tap()
        app.buttons["overviewDrawerButton"].tap()
        waitForDrawerPresentation(app, identifier: "overviewDrawer")
        XCTAssertTrue(composer.waitForExistence(timeout: 1))
        XCTAssertEqual(composer.value as? String, "Summarize the road")

        app.buttons["sendAssistantMessage"].tap()
        let sentMessage = app.staticTexts["Summarize the road"]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 1))
        XCTAssertTrue(sentMessage.isHittable)
        XCTAssertTrue(app.buttons["assistantActionsDisclosure"].exists)

        app.buttons["closeOverviewDrawer"].tap()
        app.buttons["overviewDrawerButton"].tap()
        waitForDrawerPresentation(app, identifier: "overviewDrawer")
        XCTAssertTrue(app.staticTexts["Summarize the road"].exists)
    }

    func testVisualNovelAdvancesAndClosesIntoTranscript() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "visual-novel"]
        app.launch()

        let titleCard = app.otherElements["visualNovelCard"]
        XCTAssertTrue(titleCard.exists)
        XCTAssertTrue(app.staticTexts["THE ASCENDANT ROAD"].exists)
        XCTAssertTrue(app.staticTexts["A light where no traveler should be"].exists)
        XCTAssertFalse(app.buttons["previousBeat"].exists)
        XCTAssertGreaterThan(titleCard.frame.minY, app.frame.height * 0.58)
        XCTAssertGreaterThan(titleCard.frame.maxY, app.frame.height * 0.84)

        let narration = app.buttons["narrationControl"]
        let close = app.buttons["closeVisualNovel"]
        let next = app.buttons["nextBeat"]
        for control in [narration, close, next] {
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }

        let titleCapture = XCTAttachment(screenshot: app.screenshot())
        titleCapture.name = "visual-novel-title"
        titleCapture.lifetime = .keepAlways
        add(titleCapture)

        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 1))

        let dialogueCard = app.otherElements["visualNovelCard"]
        XCTAssertTrue(app.buttons["previousBeat"].isHittable)
        XCTAssertTrue(app.staticTexts["Neutral"].exists)
        XCTAssertEqual(dialogueCard.frame.maxY, titleCard.frame.maxY, accuracy: 2)
        XCTAssertLessThanOrEqual(dialogueCard.frame.minY, titleCard.frame.minY)
        XCTAssertLessThan(dialogueCard.frame.minY, app.frame.height * 0.65)

        let dialogueCapture = XCTAttachment(screenshot: app.screenshot())
        dialogueCapture.name = "visual-novel-dialogue"
        dialogueCapture.lifetime = .keepAlways
        add(dialogueCapture)

        close.tap()
        XCTAssertTrue(
            app.otherElements["transcriptSurface"].waitForExistence(timeout: 1)
        )
    }

    func testLastVisualNovelBeatEndsSceneIntoPlayerTurn() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "visual-novel"]
        app.launch()

        let next = app.buttons["nextBeat"]
        XCTAssertTrue(next.waitForExistence(timeout: 2))
        next.tap()
        next.tap()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 1))
        XCTAssertTrue(next.label.contains("End of scene — your move"))

        next.tap()
        XCTAssertTrue(
            app.otherElements["transcriptSurface"].waitForExistence(timeout: 1)
        )
        XCTAssertFalse(app.otherElements["visualNovelCard"].exists)
    }

    private func waitForDrawerPresentation(
        _ app: XCUIApplication,
        identifier: String
    ) {
        let drawer = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(drawer.waitForExistence(timeout: 2))
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Settled"),
            object: drawer
        )
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 2), .completed)
    }
}
