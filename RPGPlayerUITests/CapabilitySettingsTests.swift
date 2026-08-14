import XCTest

@MainActor
final class CapabilitySettingsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSettingsExposeModelImageAndVoiceRouting() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-start-at-library",
            "-persistence-test-store",
            "capability-settings-\(UUID().uuidString)",
            "-reset-persistence-test-store",
            "-provider-settings-fixture",
            "accepting"
        ]
        app.launch()

        let library = app.descendants(matching: .any)["campaignLibraryView"]
        XCTAssertTrue(library.waitForExistence(timeout: 3))
        app.buttons["providerSettingsButton"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["providerSettingsView"]
                .waitForExistence(timeout: 2)
        )

        XCTAssertTrue(app.buttons["aiModelsSettingsLink"].exists)
        XCTAssertTrue(app.buttons["imageSettingsLink"].exists)
        XCTAssertTrue(app.buttons["voiceSettingsLink"].exists)

        app.buttons["aiModelsSettingsLink"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["aiModelSettingsView"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["primaryTextModelPicker"].exists)
        XCTAssertTrue(app.buttons["fallbackTextModelPicker"].exists)
        XCTAssertTrue(app.switches["automaticTextFallbackToggle"].exists)
        app.buttons["Settings"].tap()

        app.buttons["imageSettingsLink"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["imageGenerationSettingsView"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["primaryImageModelPicker"].exists)
        XCTAssertTrue(app.buttons["fallbackImageModelPicker"].exists)
        XCTAssertTrue(app.switches["automaticImageFallbackToggle"].exists)
        app.buttons["Settings"].tap()

        app.buttons["voiceSettingsLink"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["voiceSettingsView"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["voiceProviderPicker"].exists)
        XCTAssertTrue(app.secureTextFields["voiceAPIKeyField-elevenLabs"].exists)
    }
}
