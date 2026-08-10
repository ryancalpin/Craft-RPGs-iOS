import Foundation
import XCTest
@testable import RPGPlayer

final class TurnActivityAttributesTests: XCTestCase {
    func testContentStateRoundTripsWithinActivityPayloadLimit() throws {
        let expected = TurnActivityAttributes.ContentState(
            phase: .writingScene,
            status: "Weaving the story…",
            startedAt: Date(timeIntervalSince1970: 1_786_326_400),
            canCancel: true
        )

        let data = try JSONEncoder().encode(expected)
        let decoded = try JSONDecoder().decode(
            TurnActivityAttributes.ContentState.self,
            from: data
        )

        XCTAssertEqual(decoded, expected)
        XCTAssertLessThan(data.count, 4_096)
    }

    func testDeepLinkEscapesTurnIDAsOnePathSegment() throws {
        let attributes = TurnActivityAttributes(
            campaignID: try XCTUnwrap(
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
            ),
            campaignTitle: "Secrets must not enter the route",
            turnID: "turn /?# value"
        )

        let deepLink = try XCTUnwrap(attributes.deepLinkURL)
        XCTAssertEqual(
            deepLink.absoluteString,
            "rpgplayer://campaign/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/turn/turn%20%2F%3F%23%20value"
        )
        XCTAssertFalse(deepLink.absoluteString.contains("Secrets"))
    }
}
