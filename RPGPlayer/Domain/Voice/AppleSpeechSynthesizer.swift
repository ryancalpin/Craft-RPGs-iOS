@preconcurrency import AVFoundation
import Foundation

@MainActor
public protocol AppleSpeechSynthesizerDriver: AnyObject, Sendable {
    func speak(
        text: String,
        voiceIdentifier: String?,
        language: String?,
        settings: SpeechVoiceSettings,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    )

    func stop()
}

@MainActor
public final class AppleSpeechSynthesizer: SpeechSynthesizer {
    public nonisolated let providerID: VoiceProviderID = .appleSpeech

    private let driver: any AppleSpeechSynthesizerDriver

    public init() {
        driver = AVSpeechSynthesizerDriver()
    }

    public init(driver: any AppleSpeechSynthesizerDriver) {
        self.driver = driver
    }

    public func synthesize(
        _ request: SpeechSynthesisRequest
    ) async throws -> SpeechSynthesisResult {
        guard request.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw SpeechSynthesisError.blankText
        }

        let driver = self.driver
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    driver.speak(
                        text: request.text,
                        voiceIdentifier: request.voiceID,
                        language: request.language,
                        settings: request.settings
                    ) { result in
                        continuation.resume(with: result)
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    driver.stop()
                }
            }
        } catch let error as SpeechSynthesisError {
            throw error
        } catch is CancellationError {
            throw SpeechSynthesisError.cancelled
        } catch {
            throw SpeechSynthesisError.failed
        }

        return SpeechSynthesisResult(
            providerID: .appleSpeech,
            output: .platformPlayback
        )
    }
}

@MainActor
private final class AVSpeechSynthesizerDriver: NSObject,
    AppleSpeechSynthesizerDriver,
    @preconcurrency AVSpeechSynthesizerDelegate
{
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (@Sendable (Result<Void, Error>) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        text: String,
        voiceIdentifier: String?,
        language: String?,
        settings: SpeechVoiceSettings,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.completion = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceIdentifier.flatMap {
            AVSpeechSynthesisVoice(identifier: $0)
        } ?? language.flatMap {
            AVSpeechSynthesisVoice(language: $0)
        }
        utterance.rate = settings.rate
        utterance.pitchMultiplier = settings.pitchMultiplier
        utterance.volume = settings.volume
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else {
            finish(.failure(SpeechSynthesisError.cancelled))
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        finish(.failure(SpeechSynthesisError.cancelled))
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        finish(.success(()))
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        finish(.failure(SpeechSynthesisError.cancelled))
    }

    private func finish(_ result: Result<Void, Error>) {
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }
}
