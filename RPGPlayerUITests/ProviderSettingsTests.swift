import XCTest

@MainActor
final class ProviderSettingsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCredentialCanSaveRelaunchReplaceAndDeleteWithoutReadback() {
        let storeID = "provider-settings-\(UUID().uuidString)"
        let firstToken = "sk-ui-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let replacementToken =
            "AIzaUi\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let app = launch(storeID: storeID, resetStore: true)

        openProviderSettings(in: app)
        let field = app.secureTextFields["apiKeyField-openAI"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.buttons["clearAPIKey-openAI"].label,
            "Clear OpenAI API key"
        )
        XCTAssertEqual(
            app.buttons["validateProviderCredential-openAI"].label,
            "Validate and Save OpenAI API key"
        )
        XCTAssertEqual(
            app.buttons["deleteProviderCredential-openAI"].label,
            "Remove saved OpenAI API key"
        )
        field.tap()
        field.typeText(firstToken)
        app.buttons["validateProviderCredential-openAI"].tap()

        let status = app.staticTexts["providerCredentialStatus-openAI"]
        XCTAssertTrue(
            waitForLabel(
                "Saved on this device",
                in: status,
                timeout: 3
            )
        )
        XCTAssertEqual(
            app.buttons["validateProviderCredential-openAI"].label,
            "Validate and Replace OpenAI API key"
        )
        XCTAssertTrue(
            waitForLabel(
                "Validated and saved",
                in: app.staticTexts["providerValidationState-openAI"],
                timeout: 3
            )
        )
        XCTAssertFalse(visibleText(in: app, contains: firstToken))
        app.terminate()

        let relaunched = launch(storeID: storeID, resetStore: false)
        openProviderSettings(in: relaunched)
        let relaunchedStatus = relaunched.staticTexts[
            "providerCredentialStatus-openAI"
        ]
        XCTAssertTrue(
            waitForLabel(
                "Saved on this device",
                in: relaunchedStatus,
                timeout: 3
            )
        )
        XCTAssertFalse(visibleText(in: relaunched, contains: firstToken))

        let relaunchedField = relaunched.secureTextFields[
            "apiKeyField-openAI"
        ]
        relaunchedField.tap()
        relaunchedField.typeText(replacementToken)
        relaunched.buttons["clearAPIKey-openAI"].tap()
        XCTAssertEqual(relaunchedField.value as? String, "OpenAI API key")
        XCTAssertEqual(relaunchedStatus.label, "Saved on this device")

        relaunchedField.tap()
        relaunchedField.typeText(replacementToken)
        relaunched.buttons["validateProviderCredential-openAI"].tap()
        XCTAssertTrue(
            waitForLabel(
                "Validated and saved",
                in: relaunched.staticTexts[
                    "providerValidationState-openAI"
                ],
                timeout: 3
            )
        )
        XCTAssertFalse(
            visibleText(in: relaunched, contains: replacementToken)
        )

        relaunched.buttons["deleteProviderCredential-openAI"].tap()
        let confirmation = relaunched.alerts["Remove OpenAI API key?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["Remove API Key"].tap()
        XCTAssertTrue(
            waitForLabel("Not saved", in: relaunchedStatus, timeout: 3)
        )
        XCTAssertFalse(
            visibleText(in: relaunched, contains: replacementToken)
        )
    }

    func testProductionRouteKeepsValidationUnavailableWithoutFixture() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-start-at-library",
            "-persistence-test-store",
            "provider-prod-\(UUID().uuidString)",
            "-reset-persistence-test-store"
        ]
        app.launch()

        openProviderSettings(in: app)
        let validationText = app.staticTexts[
            "providerValidationState-openAI"
        ]
        XCTAssertTrue(
            waitForLabel(
                "Provider validation is not connected yet.",
                in: validationText,
                timeout: 3
            )
        )
        let field = app.secureTextFields["apiKeyField-openAI"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText(
            "unit-production-unavailable-\(UUID().uuidString)"
        )
        XCTAssertFalse(
            app.buttons["validateProviderCredential-openAI"].isEnabled
        )
    }

    private func launch(
        storeID: String,
        resetStore: Bool
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-start-at-library",
            "-persistence-test-store",
            storeID,
            "-provider-settings-fixture",
            "accepting"
        ]
        if resetStore {
            app.launchArguments.append("-reset-persistence-test-store")
        }
        app.launch()
        return app
    }

    private func openProviderSettings(in app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)["campaignLibraryView"]
                .waitForExistence(timeout: 3)
        )
        let settingsButton = app.buttons["providerSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["providerSettingsView"]
                .waitForExistence(timeout: 2)
        )
    }

    private func waitForLabel(
        _ label: String,
        in element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        return XCTWaiter.wait(
            for: [expectation],
            timeout: timeout
        ) == .completed
    }

    private func visibleText(
        in app: XCUIApplication,
        contains token: String
    ) -> Bool {
        app.descendants(matching: .any).allElementsBoundByIndex.contains {
            element in
            if element.label.contains(token) {
                return true
            }
            return (element.value as? String)?.contains(token) == true
        }
    }
}
