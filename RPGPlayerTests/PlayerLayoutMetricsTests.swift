import XCTest
import UIKit
@testable import RPGPlayer

final class PlayerLayoutMetricsTests: XCTestCase {
    func testReferencePhoneUsesRecordedDrawerProportions() {
        XCTAssertEqual(PlayerLayoutMetrics.projectDrawerWidth(for: 440), 316.8, accuracy: 0.001)
        XCTAssertEqual(PlayerLayoutMetrics.overviewDrawerWidth(for: 440), 396, accuracy: 0.001)
    }

    func testRegularWidthCapsDrawersToPreserveContentDensity() {
        XCTAssertEqual(PlayerLayoutMetrics.projectDrawerWidth(for: 1024), 420, accuracy: 0.001)
        XCTAssertEqual(PlayerLayoutMetrics.overviewDrawerWidth(for: 1024), 620, accuracy: 0.001)
    }

    func testTransientInvalidGeometryNeverProducesAnInvalidFrameWidth() {
        for availableWidth in [CGFloat(-1), .nan, -.infinity] {
            let projectWidth = PlayerLayoutMetrics.projectDrawerWidth(for: availableWidth)
            let overviewWidth = PlayerLayoutMetrics.overviewDrawerWidth(for: availableWidth)

            XCTAssertTrue(projectWidth.isFinite)
            XCTAssertGreaterThanOrEqual(projectWidth, 0)
            XCTAssertTrue(overviewWidth.isFinite)
            XCTAssertGreaterThanOrEqual(overviewWidth, 0)
        }
    }

    func testTransientInvalidSafeAreaInsetsClampToZero() {
        for inset in [CGFloat(-1), .nan, -.infinity] {
            XCTAssertEqual(PlayerLayoutMetrics.safeAreaInset(inset), 0)
        }
        XCTAssertEqual(PlayerLayoutMetrics.safeAreaInset(34), 34)
    }

    @MainActor
    func testSearchKeyboardAccessoryUsesOneContinuousChromeAndNativeTargets() {
        for width in [CGFloat(440), 1_032] {
            let accessory = SearchKeyboardAccessoryView(
                frame: CGRect(x: 0, y: 0, width: width, height: 48)
            )

            accessory.layoutIfNeeded()
            accessory.chromeView.layoutIfNeeded()
            accessory.chromeView.contentView.layoutIfNeeded()

            XCTAssertEqual(accessory.bounds.height, 48, accuracy: 0.5)
            XCTAssertEqual(accessory.chromeView.frame.minX, 20, accuracy: 0.5)
            XCTAssertEqual(accessory.chromeView.frame.minY, 0, accuracy: 0.5)
            XCTAssertEqual(
                accessory.chromeView.frame.width,
                width - 40,
                accuracy: 0.5
            )
            XCTAssertEqual(accessory.chromeView.frame.height, 48, accuracy: 0.5)
            XCTAssertEqual(
                accessory.chromeView.layer.cornerRadius,
                24,
                accuracy: 0.5
            )

            for button in [
                accessory.previousButton,
                accessory.nextButton,
                accessory.dismissButton
            ] {
                XCTAssertTrue(
                    button.isDescendant(of: accessory.chromeView.contentView)
                )
                XCTAssertEqual(button.frame.width, 44, accuracy: 0.5)
                XCTAssertEqual(button.frame.height, 44, accuracy: 0.5)
            }

            XCTAssertFalse(accessory.previousButton.isEnabled)
            XCTAssertFalse(accessory.nextButton.isEnabled)
            XCTAssertEqual(
                accessory.dismissButton.accessibilityIdentifier,
                "dismissSearchKeyboard"
            )
        }
    }
}
