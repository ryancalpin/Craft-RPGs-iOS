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
        let moveSheet = app.descendants(matching: .any)["yourMoveSheet"]
        XCTAssertTrue(moveSheet.waitForExistence(timeout: 2))
        XCTAssertFalse(app.otherElements["visualNovelCard"].exists)
        XCTAssertFalse(app.buttons["confirmMove"].isEnabled)

        app.buttons["closeYourMoveSheet"].tap()
        XCTAssertTrue(
            app.otherElements["transcriptSurface"].waitForExistence(timeout: 1)
        )
        app.buttons["yourMoveDock"].tap()
        XCTAssertTrue(moveSheet.waitForExistence(timeout: 1))
    }

    func testYourMoveSheetRequiresAnAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-fixture",
            "player-shell",
            "-turn-sheet-geometry-test"
        ]
        app.launch()

        let transcript = app.descendants(matching: .any)["transcriptSurface"]
        let dock = app.buttons["yourMoveDock"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["transcriptActionsDisclosure"].exists)
        XCTAssertTrue(app.staticTexts["latestGMQuestion"].exists)
        XCTAssertTrue(dock.exists)
        XCTAssertTrue(
            (dock.value as? String)?.contains("The GM is waiting") == true
        )
        XCTAssertGreaterThan(dock.frame.minY, app.frame.height * 0.84)
        XCTAssertGreaterThan(transcript.frame.minX, app.frame.width * 0.10)
        XCTAssertLessThan(transcript.frame.maxY, dock.frame.minY)

        let collapsedCapture = XCTAttachment(screenshot: app.screenshot())
        collapsedCapture.name = "transcript-collapsed-move"
        collapsedCapture.lifetime = .keepAlways
        add(collapsedCapture)

        dock.tap()
        let moveSheet = app.descendants(matching: .any)["yourMoveSheet"]
        XCTAssertTrue(moveSheet.waitForExistence(timeout: 2))
        let sheetSurface = app.descendants(matching: .any)["yourMoveSurface"]
        XCTAssertTrue(sheetSurface.waitForExistence(timeout: 1))
        let transcriptViewport = app.scrollViews["transcriptScrollViewport"]
        XCTAssertTrue(transcriptViewport.exists)
        XCTAssertGreaterThanOrEqual(
            transcriptViewport.frame.minY,
            app.buttons["projectDrawerButton"].frame.maxY
        )
        XCTAssertEqual(
            sheetSurface.frame.minY,
            app.frame.minY + app.frame.height * (1_588.0 / 2_868.0),
            accuracy: 6
        )
        XCTAssertEqual(
            sheetSurface.frame.height,
            app.frame.height * (1_242.0 / 2_868.0),
            accuracy: 8
        )
        XCTAssertEqual(sheetSurface.frame.minX - app.frame.minX, 12, accuracy: 2)
        XCTAssertEqual(
            app.frame.maxX - sheetSurface.frame.maxX,
            12,
            accuracy: 2
        )
        XCTAssertEqual(
            app.frame.maxY - sheetSurface.frame.maxY,
            13,
            accuracy: 3
        )

        let expandedActions = app.buttons["transcriptActionsDisclosure"]
        let expandedQuestion = app.staticTexts["latestGMQuestion"]
        XCTAssertTrue(expandedActions.exists)
        XCTAssertTrue(expandedQuestion.exists)
        let geometryCapture = XCTAttachment(screenshot: app.screenshot())
        geometryCapture.name = "your-move-geometry"
        geometryCapture.lifetime = .keepAlways
        add(geometryCapture)
        XCTAssertFalse(
            expandedActions.frame.intersects(sheetSurface.frame),
            "Actions \(expandedActions.frame), sheet \(sheetSurface.frame)"
        )
        XCTAssertFalse(
            expandedQuestion.frame.intersects(sheetSurface.frame),
            "Question \(expandedQuestion.frame), sheet \(sheetSurface.frame)"
        )
        XCTAssertGreaterThanOrEqual(
            expandedQuestion.frame.minY - expandedActions.frame.maxY,
            0
        )
        XCTAssertLessThanOrEqual(
            expandedQuestion.frame.minY - expandedActions.frame.maxY,
            4
        )
        let questionToSheetGap =
            sheetSurface.frame.minY - expandedQuestion.frame.maxY
        XCTAssertGreaterThanOrEqual(questionToSheetGap, 0)
        if abs(app.frame.width - 440) <= 1 {
            XCTAssertGreaterThanOrEqual(questionToSheetGap, 55)
            XCTAssertLessThanOrEqual(questionToSheetGap, 90)
        }
        XCTAssertFalse(app.buttons["confirmMove"].isEnabled)

        let rows = [
            app.buttons["Stay in the shadow"],
            app.buttons["Call out to the rider"],
            app.buttons["Take the ridge path"]
        ]
        for row in rows {
            XCTAssertEqual(row.frame.minX - sheetSurface.frame.minX, 12, accuracy: 3)
            XCTAssertEqual(sheetSurface.frame.maxX - row.frame.maxX, 12, accuracy: 3)
            XCTAssertGreaterThanOrEqual(row.frame.height, 72)
            if abs(app.frame.width - 440) <= 1 {
                XCTAssertEqual(row.frame.height, 72, accuracy: 2)
            }
        }
        for pair in zip(rows, rows.dropFirst()) {
            XCTAssertEqual(pair.1.frame.minY - pair.0.frame.maxY, 8, accuracy: 3)
        }

        let confirm = app.buttons["confirmMove"]
        XCTAssertLessThanOrEqual(rows[2].frame.maxY, confirm.frame.minY)
        let customChoice = app.buttons["customMoveChoice"]
        XCTAssertGreaterThanOrEqual(customChoice.frame.minY, rows[2].frame.maxY)
        if abs(app.frame.width - 440) <= 1 {
            XCTAssertLessThan(customChoice.frame.minY, confirm.frame.minY)
        }
        XCTAssertEqual(confirm.frame.width, 94, accuracy: 2)
        XCTAssertEqual(
            sheetSurface.frame.maxY - confirm.frame.maxY,
            7,
            accuracy: 2
        )
        XCTAssertEqual(confirm.frame.height, 44, accuracy: 2)

        let expandedCapture = XCTAttachment(screenshot: app.screenshot())
        expandedCapture.name = "your-move-expanded"
        expandedCapture.lifetime = .keepAlways
        add(expandedCapture)

        let firstChoice = app.buttons["Stay in the shadow"]
        XCTAssertEqual(
            firstChoice.value as? String,
            "Watch the lantern road and learn who is following you. Not selected"
        )
        firstChoice.tap()
        XCTAssertEqual(
            firstChoice.value as? String,
            "Watch the lantern road and learn who is following you. Selected"
        )
        XCTAssertTrue(app.buttons["confirmMove"].isEnabled)
    }

    func testCustomMoveSeparatesContextAndKeepsConfirmAboveKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "player-shell"]
        app.launch()

        app.buttons["yourMoveDock"].tap()
        let moveSheet = app.descendants(matching: .any)["yourMoveSheet"]
        XCTAssertTrue(moveSheet.waitForExistence(timeout: 2))

        let firstChoice = app.buttons["Stay in the shadow"]
        let secondChoice = app.buttons["Call out to the rider"]
        firstChoice.tap()
        XCTAssertEqual(
            firstChoice.value as? String,
            "Watch the lantern road and learn who is following you. Selected"
        )
        secondChoice.tap()
        XCTAssertEqual(
            firstChoice.value as? String,
            "Watch the lantern road and learn who is following you. Not selected"
        )
        XCTAssertEqual(
            secondChoice.value as? String,
            "Risk being seen in exchange for a direct answer. Selected"
        )

        moveSheet.swipeUp()
        let customChoice = app.buttons["customMoveChoice"]
        XCTAssertTrue(customChoice.waitForExistence(timeout: 1))
        if !customChoice.isHittable {
            moveSheet.swipeUp()
        }
        customChoice.tap()

        let additionalContext = app.textViews["additionalContextEditor"]
        for _ in 0..<3 where !additionalContext.exists {
            moveSheet.swipeUp()
        }
        XCTAssertTrue(additionalContext.waitForExistence(timeout: 1))
        if !additionalContext.isHittable {
            moveSheet.swipeUp()
        }
        additionalContext.tap()
        additionalContext.typeText("Keep the approach quiet")
        let confirm = app.buttons["confirmMove"]
        XCTAssertFalse(confirm.isEnabled)

        let customAction = app.textViews["customActionEditor"]
        for _ in 0..<3 where !customAction.exists {
            moveSheet.swipeDown()
        }
        XCTAssertTrue(customAction.waitForExistence(timeout: 1))
        if !customAction.isHittable {
            moveSheet.swipeDown()
        }
        customAction.tap()
        customAction.typeText("Hold position and watch the road")
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(confirm.isHittable)

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, keyboard.frame.minY + 2)

        let keyboardCapture = XCTAttachment(screenshot: app.screenshot())
        keyboardCapture.name = "your-move-keyboard"
        keyboardCapture.lifetime = .keepAlways
        add(keyboardCapture)

        confirm.tap()
        XCTAssertFalse(moveSheet.waitForExistence(timeout: 1))
        XCTAssertTrue(
            app.descendants(matching: .any)["generationView"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.buttons["yourMoveDock"].exists)
    }

    func testSuggestedMoveStartsGenerationAndStopIsUserInitiated() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "player-shell"]
        app.launch()

        app.buttons["yourMoveDock"].tap()
        let moveSheet = app.descendants(matching: .any)["yourMoveSheet"]
        XCTAssertTrue(moveSheet.waitForExistence(timeout: 2))

        app.buttons["Stay in the shadow"].tap()
        let confirm = app.buttons["confirmMove"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        let generation = app.descendants(matching: .any)["generationView"]
        XCTAssertTrue(generation.waitForExistence(timeout: 2))
        XCTAssertFalse(moveSheet.exists)
        XCTAssertFalse(app.buttons["yourMoveDock"].exists)
        let disclosure = app.buttons["generationStepsDisclosure"]
        XCTAssertTrue(disclosure.exists)

        let card = app.descendants(matching: .any)["generationCard"]
        XCTAssertTrue(card.exists)
        let collapsedFrame = card.frame
        XCTAssertEqual(collapsedFrame.minX, 16, accuracy: 2)
        XCTAssertEqual(collapsedFrame.minY, 820, accuracy: 2)
        XCTAssertEqual(collapsedFrame.width, 408, accuracy: 2)
        XCTAssertEqual(collapsedFrame.height, 104, accuracy: 2)

        let statusBeforeStop = app.staticTexts["generationStatus"]
        XCTAssertTrue(statusBeforeStop.exists)
        let firstPhaseStarted = expectation(
            for: NSPredicate(format: "label != %@", "Getting ready…"),
            evaluatedWith: statusBeforeStop
        )
        wait(for: [firstPhaseStarted], timeout: 1.2)
        XCTAssertLessThanOrEqual(statusBeforeStop.frame.height, 24)

        let collapsedCapture = XCTAttachment(screenshot: app.screenshot())
        collapsedCapture.name = "generation-collapsed"
        collapsedCapture.lifetime = .keepAlways
        add(collapsedCapture)

        let stop = app.buttons["stopGeneration"]
        XCTAssertTrue(stop.isHittable)
        XCTAssertGreaterThanOrEqual(stop.frame.width, 44)
        XCTAssertGreaterThanOrEqual(stop.frame.height, 44)
        stop.tap()

        let status = app.staticTexts["generationStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 1))
        XCTAssertEqual(status.label, "Needs attention")
        XCTAssertFalse(app.descendants(matching: .any)["visualNovelCard"].exists)

        disclosure.tap()
        let firstStep = app.staticTexts["generationStep-0"]
        XCTAssertTrue(firstStep.waitForExistence(timeout: 1))
        let expandedFrame = card.frame
        XCTAssertEqual(expandedFrame.minX, collapsedFrame.minX, accuracy: 1)
        XCTAssertEqual(expandedFrame.width, collapsedFrame.width, accuracy: 1)
        XCTAssertEqual(expandedFrame.maxY, collapsedFrame.maxY, accuracy: 1)
        XCTAssertLessThan(expandedFrame.minY, collapsedFrame.minY)

        let expandedCapture = XCTAttachment(screenshot: app.screenshot())
        expandedCapture.name = "generation-expanded"
        expandedCapture.lifetime = .keepAlways
        add(expandedCapture)

        disclosure.tap()
        XCTAssertFalse(firstStep.waitForExistence(timeout: 1))
        XCTAssertEqual(card.frame.minY, collapsedFrame.minY, accuracy: 1)
        XCTAssertEqual(card.frame.height, collapsedFrame.height, accuracy: 1)
    }

    func testTurnSheetBlocksDrawerEdgeGestures() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "player-shell"]
        app.launch()

        app.buttons["yourMoveDock"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["yourMoveSheet"]
                .waitForExistence(timeout: 2)
        )

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.35))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.45, dy: 0.35)
                )
            )

        XCTAssertFalse(
            app.descendants(matching: .any)["projectDrawer"]
                .waitForExistence(timeout: 1)
        )
    }

    func testAccessibilityTextKeepsQuestionAboveMeasuredMoveDock() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-fixture",
            "player-shell",
            "-dynamic-type-accessibility-test"
        ]
        app.launch()

        let transcript = app.descendants(matching: .any)["transcriptSurface"]
        let dock = app.buttons["yourMoveDock"]
        let question = app.staticTexts["latestGMQuestion"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 2))
        XCTAssertTrue(dock.exists)
        XCTAssertGreaterThanOrEqual(dock.frame.height, 72)
        XCTAssertLessThanOrEqual(dock.frame.height, 160)

        for _ in 0..<12 {
            if question.exists,
               question.frame.maxY <= dock.frame.minY {
                break
            }
            transcript.swipeUp()
        }

        let accessibilityCapture = XCTAttachment(screenshot: app.screenshot())
        accessibilityCapture.name = "transcript-accessibility-xxxl"
        accessibilityCapture.lifetime = .keepAlways
        add(accessibilityCapture)

        XCTAssertTrue(question.isHittable)
        XCTAssertLessThanOrEqual(question.frame.maxY, dock.frame.minY)
        XCTAssertTrue(
            (dock.value as? String)?.contains("The GM is waiting") == true
        )
    }

    func testAccessibilityTurnSheetLetsConfirmGrowAboveKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-fixture",
            "player-shell",
            "-dynamic-type-accessibility-test"
        ]
        app.launch()

        let dock = app.buttons["yourMoveDock"]
        XCTAssertGreaterThan(dock.frame.height, 72)
        dock.tap()
        let moveSheet = app.descendants(matching: .any)["yourMoveSheet"]
        XCTAssertTrue(moveSheet.waitForExistence(timeout: 2))

        let confirm = app.buttons["confirmMove"]
        XCTAssertTrue(confirm.label.contains("Confirm"))
        XCTAssertGreaterThan(confirm.frame.width, 94)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)

        let customChoice = app.buttons["customMoveChoice"]
        for _ in 0..<12 where !customChoice.exists {
            moveSheet.swipeUp()
        }
        XCTAssertTrue(customChoice.exists)
        customChoice.tap()

        let customAction = app.textViews["customActionEditor"]
        XCTAssertTrue(customAction.waitForExistence(timeout: 1))
        customAction.typeText("Wait and watch")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(confirm.isHittable)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, keyboard.frame.minY + 2)
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
