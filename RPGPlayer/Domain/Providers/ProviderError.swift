import Foundation

public enum ProviderError: Error, Equatable, Sendable {
    case invalidCredential
    case quotaExceeded
    case rateLimited(retryAfter: Date?)
    case contextExceeded
    case safetyRefusal
    case malformedResponse
    case connectivity
    case cancelled
    case serviceFailure(statusCode: Int?)

    public var isRetryableWithoutUserCorrection: Bool {
        switch self {
        case .rateLimited, .connectivity, .serviceFailure:
            true
        case .invalidCredential,
             .quotaExceeded,
             .contextExceeded,
             .safetyRefusal,
             .malformedResponse,
             .cancelled:
            false
        }
    }

    /// A second configured provider can sometimes recover from a quota error,
    /// even though retrying the same provider cannot.
    public var isFallbackEligible: Bool {
        isRetryableWithoutUserCorrection || self == .quotaExceeded
    }
}

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCredential:
            "The provider credential is invalid."
        case .quotaExceeded:
            "The provider account has no available quota."
        case .rateLimited:
            "The provider is temporarily rate limiting requests."
        case .contextExceeded:
            "The turn context exceeds the selected model's limit."
        case .safetyRefusal:
            "The provider declined to complete this turn."
        case .malformedResponse:
            "The provider returned an incomplete or malformed response."
        case .connectivity:
            "The provider could not be reached."
        case .cancelled:
            "The provider request was cancelled."
        case .serviceFailure:
            "The provider service could not complete the request."
        }
    }
}
