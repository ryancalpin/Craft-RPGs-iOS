import XCTest
@testable import RPGPlayer

final class AppMetadataTests: XCTestCase {
    func testDisplayNameUsesWorkingProductName() {
        XCTAssertEqual(AppMetadata.displayName, "RPGPlayer")
    }

    func testIPadDeclaresEverySupportedInterfaceOrientation() throws {
        let infoURL = Bundle.main.bundleURL.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoURL)
        let info = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any]
        )
        let orientations = try XCTUnwrap(
            info["UISupportedInterfaceOrientations~ipad"] as? [String]
        )

        XCTAssertEqual(
            Set(orientations),
            Set([
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight"
            ])
        )
    }
}
