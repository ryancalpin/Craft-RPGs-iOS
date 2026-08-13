import Foundation

public protocol AIProvider: Sendable {
    var id: ProviderID { get }

    func models() async throws -> [ProviderModel]

    func streamTurn(
        _ request: TurnRequest
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error>

    func cancel(requestID: UUID) async
}

public struct PlayerAction: Codable, Equatable, Sendable {
    public let text: String
    public let additionalContext: String?

    public init(text: String, additionalContext: String? = nil) {
        self.text = text
        self.additionalContext = additionalContext
    }
}

public struct TurnRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let campaignID: UUID
    public let expectedSequence: Int64
    public let action: PlayerAction
    public let context: TurnContext
    /// The assembly inputs used to produce `context.contextHash`.
    ///
    /// Older callers may omit this for requests that do not cross a native
    /// tool boundary. A continuation must retain it so its hash covers the
    /// same canonical budget and metadata contract as the initial context.
    public let contextAssembly: TurnContextAssembly?

    public init(
        requestID: UUID,
        campaignID: UUID,
        expectedSequence: Int64,
        action: PlayerAction,
        context: TurnContext,
        contextAssembly: TurnContextAssembly? = nil
    ) {
        self.requestID = requestID
        self.campaignID = campaignID
        self.expectedSequence = expectedSequence
        self.action = action
        self.context = context
        self.contextAssembly = contextAssembly
    }

    public init(
        requestID: UUID,
        campaignID: UUID,
        expectedSequence: Int64,
        action: PlayerAction,
        assembly: TurnContextAssembly
    ) {
        self.init(
            requestID: requestID,
            campaignID: campaignID,
            expectedSequence: expectedSequence,
            action: action,
            context: assembly.context,
            contextAssembly: assembly
        )
    }
}
