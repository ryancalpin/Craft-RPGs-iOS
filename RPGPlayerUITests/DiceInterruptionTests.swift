import XCTest

@MainActor
final class DiceInterruptionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPendingRollLivesInStoryFlowAndResolvesOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "dice-interruption"]
        app.launch()

        let card = app.descendants(matching: .any)[
            "diceRollCard-00000000-0000-4000-8000-000000000901"
        ]
        XCTAssertTrue(card.waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.buttons["diceRollButton-00000000-0000-4000-8000-000000000901"]
                .isHittable
        )
        XCTAssertFalse(app.descendants(matching: .any)["diceToolbar"].exists)

        app.buttons[
            "diceRollButton-00000000-0000-4000-8000-000000000901"
        ].tap()
        let sheet = app.descendants(matching: .any)["diceRollSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["confirmDiceRoll"].isHittable)

        app.buttons["confirmDiceRoll"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["diceRollTotal"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.buttons["confirmDiceRoll"].exists)
        XCTAssertTrue(app.buttons["doneDiceRoll"].isHittable)

        app.buttons["doneDiceRoll"].tap()
        XCTAssertFalse(sheet.waitForExistence(timeout: 1))
        XCTAssertFalse(card.exists)
        XCTAssertTrue(app.staticTexts["latestGMQuestion"].exists)
    }
}
