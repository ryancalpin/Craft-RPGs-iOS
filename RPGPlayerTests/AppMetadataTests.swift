import XCTest
@testable import RPGPlayer

final class AppMetadataTests: XCTestCase {
    func testDisplayNameUsesWorkingProductName() {
        XCTAssertEqual(AppMetadata.displayName, "RPGPlayer")
    }
}
