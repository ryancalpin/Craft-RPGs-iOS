import XCTest
@testable import RPGPlayer

final class PlayerFixtureTests: XCTestCase {
    func testFixtureSupportsBothPresentations() {
        let fixture = PlayerSessionState.fixture
        XCTAssertFalse(fixture.latestMessage.prose.isEmpty)
        XCTAssertGreaterThanOrEqual(fixture.latestMessage.beats.count, 3)
        XCTAssertFalse(fixture.choices.isEmpty)
    }

    func testEveryFixtureIdentifierIsUnique() {
        let fixture = PlayerSessionState.fixture
        let ids = fixture.latestMessage.beats.map(\.id) + fixture.choices.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
