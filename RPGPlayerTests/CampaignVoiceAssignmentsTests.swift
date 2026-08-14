import Foundation
import Testing
@testable import RPGPlayer

struct CampaignVoiceAssignmentsTests {
    @Test
    func manualAssignmentEventUsesStableTargetKey() throws {
        let campaignID = try XCTUUID("10000000-0000-4000-8000-000000000001")
        let requestID = try XCTUUID("20000000-0000-4000-8000-000000000001")
        let event = VoiceAssignmentEventFactory.manualEvent(
            campaignID: campaignID,
            target: .character("guide"),
            voiceID: "voice-warm-01",
            requestID: requestID,
            timestamp: Date(timeIntervalSince1970: 42)
        )

        #expect(event.campaignID == campaignID)
        #expect(event.requestID == requestID)
        #expect(event.sequence == 0)
        guard case .voiceAssignmentChanged(let payload) = event.payload else {
            Issue.record("Expected a voice assignment event")
            return
        }
        #expect(payload.characterID == "guide")
        #expect(payload.voiceID == "voice-warm-01")
        #expect(payload.source == .manual)
    }
}

private func XCTUUID(_ value: String) throws -> UUID {
    guard let uuid = UUID(uuidString: value) else {
        throw VoiceAssignmentTestError.invalidUUID
    }
    return uuid
}

private enum VoiceAssignmentTestError: Error {
    case invalidUUID
}
