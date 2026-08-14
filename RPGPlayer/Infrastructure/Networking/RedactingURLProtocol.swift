#if DEBUG
import Foundation
import Synchronization

final class RedactingURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case http(
            statusCode: Int,
            headers: [String: String] = [:]
        )
        case nonHTTP
    }

    enum Step: Sendable {
        case chunk(Data)
        case failure(URLError.Code)
        case holdOpen
        case wait(ScriptGate)
    }

    actor ScriptGate {
        private var isResumed = false
        private var waiter: CheckedContinuation<Void, Never>?

        func wait() async {
            guard isResumed == false else { return }
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if isResumed {
                        continuation.resume()
                    } else {
                        waiter = continuation
                    }
                }
            } onCancel: {
                Task { await self.resume() }
            }
        }

        func resume() {
            guard isResumed == false else { return }
            isResumed = true
            waiter?.resume()
            waiter = nil
        }
    }

    struct Scenario: Sendable {
        let response: Response
        let steps: [Step]

        init(response: Response, steps: [Step]) {
            self.response = response
            self.steps = steps
        }
    }

    struct DiagnosticSnapshot: Equatable, Sendable {
        let method: String?
        let scheme: String?
        let host: String?
        let path: String
        let queryItemNames: [String]
        let bodyByteCount: Int?
        let bodyData: Data?
        let headers: [String: String]
    }

    struct Registration: Sendable {
        let request: URLRequest
        fileprivate let tag: UUID

        func waitUntilStarted() async {
            await RedactingURLProtocol.registry.waitUntilStarted(tag: tag)
        }

        func waitUntilHeldOpen() async {
            await RedactingURLProtocol.registry.waitUntilHeldOpen(tag: tag)
        }

        func waitUntilStopped() async {
            await RedactingURLProtocol.registry.waitUntilStopped(tag: tag)
        }

        func stopCount() async -> Int {
            await RedactingURLProtocol.registry.stopCount(tag: tag)
        }

        func diagnosticSnapshot() async -> DiagnosticSnapshot? {
            await RedactingURLProtocol.registry.diagnosticSnapshot(tag: tag)
        }
    }

    private struct LoadState {
        var worker: Task<Void, Never>?
        var heldContinuation: CheckedContinuation<Void, Never>?
        var isStopped = false
        var isCompleted = false
        var didReportStop = false
    }

    private final class LoadStateStorage: @unchecked Sendable {
        struct StopAction: Sendable {
            let worker: Task<Void, Never>?
            let held: CheckedContinuation<Void, Never>?
            let shouldReport: Bool
        }

        private let state = Mutex(LoadState())

        func install(worker: Task<Void, Never>) -> Bool {
            state.withLock { state in
                guard state.isStopped == false else { return true }
                state.worker = worker
                return false
            }
        }

        func stop() -> StopAction {
            state.withLock { state in
                guard state.isStopped == false else {
                    return StopAction(
                        worker: nil,
                        held: nil,
                        shouldReport: false
                    )
                }
                state.isStopped = true
                let action = StopAction(
                    worker: state.worker,
                    held: state.heldContinuation,
                    shouldReport: state.isCompleted == false
                        && state.didReportStop == false
                )
                state.worker = nil
                state.heldContinuation = nil
                state.didReportStop = true
                return action
            }
        }

        func isActive() -> Bool {
            state.withLock { state in
                state.isStopped == false && state.isCompleted == false
            }
        }

        func markCompletedIfActive() -> Bool {
            state.withLock { state in
                guard state.isStopped == false,
                      state.isCompleted == false else { return false }
                state.isCompleted = true
                return true
            }
        }

        func registerHeld(
            _ continuation: CheckedContinuation<Void, Never>,
            taskWasCancelled: Bool
        ) -> Bool {
            state.withLock { state in
                guard state.isStopped == false,
                      taskWasCancelled == false else { return true }
                state.heldContinuation = continuation
                return false
            }
        }

        func takeHeldContinuation() -> CheckedContinuation<Void, Never>? {
            state.withLock { state in
                let continuation = state.heldContinuation
                state.heldContinuation = nil
                return continuation
            }
        }
    }

    private final class WeakProtocolReference: @unchecked Sendable {
        weak var value: RedactingURLProtocol?

        init(_ value: RedactingURLProtocol) {
            self.value = value
        }
    }

    private static let requestTagKey =
        "com.calpinlabs.rpgplayer.redacting-url-protocol-tag"
    private static let registry = RedactingURLProtocolRegistry()

    private let loadState = LoadStateStorage()

    static func register(
        scenario: Scenario,
        for request: URLRequest
    ) async -> Registration {
        let tag = UUID()
        await registry.register(
            scenario: scenario,
            diagnosticSnapshot: diagnosticSnapshot(for: request),
            tag: tag
        )

        guard let mutableRequest = (request as NSURLRequest).mutableCopy()
            as? NSMutableURLRequest else {
            preconditionFailure("URLRequest must bridge to NSMutableURLRequest")
        }
        URLProtocol.setProperty(
            tag.uuidString,
            forKey: requestTagKey,
            in: mutableRequest
        )
        return Registration(
            request: mutableRequest as URLRequest,
            tag: tag
        )
    }

    override class func canInit(with request: URLRequest) -> Bool {
        requestTag(from: request) != nil
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let reference = WeakProtocolReference(self)
        let worker = Task {
            guard let protocolInstance = reference.value else { return }
            await protocolInstance.runScenario()
        }
        let cancelImmediately = loadState.install(worker: worker)
        if cancelImmediately {
            worker.cancel()
        }
    }

    override func stopLoading() {
        let tag = Self.requestTag(from: request)
        let stopped = loadState.stop()

        stopped.worker?.cancel()
        stopped.held?.resume()
        guard stopped.shouldReport, let tag else { return }
        let registry = Self.registry
        Task { @Sendable in
            await registry.recordStopped(tag: tag)
        }
    }

    private func runScenario() async {
        guard let tag = Self.requestTag(from: request),
              let scenario = await Self.registry.scenario(tag: tag) else {
            sendFailure(.resourceUnavailable)
            return
        }

        await Self.registry.recordStarted(tag: tag)
        await Self.registry.recordDiagnosticSnapshot(
            tag: tag,
            snapshot: Self.diagnosticSnapshot(for: request)
        )
        guard Task.isCancelled == false,
              isActive else { return }
        guard let response = Self.response(
            for: scenario.response,
            request: request
        ) else {
            sendFailure(.badServerResponse)
            return
        }
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )

        for step in scenario.steps {
            guard Task.isCancelled == false, isActive else { return }
            switch step {
            case .chunk(let data):
                await Task.yield()
                guard Task.isCancelled == false, isActive else { return }
                client?.urlProtocol(self, didLoad: data)
            case .failure(let code):
                sendFailure(code)
                return
            case .holdOpen:
                await Self.registry.recordHeldOpen(tag: tag)
                await waitWhileHeldOpen()
                return
            case .wait(let gate):
                await gate.wait()
            }
        }

        guard markCompletedIfActive() else { return }
        client?.urlProtocolDidFinishLoading(self)
    }

    private var isActive: Bool {
        loadState.isActive()
    }

    private func markCompletedIfActive() -> Bool {
        loadState.markCompletedIfActive()
    }

    private func sendFailure(_ code: URLError.Code) {
        guard markCompletedIfActive() else { return }
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }

    private func waitWhileHeldOpen() async {
        let loadState = loadState
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeImmediately = loadState.registerHeld(
                    continuation,
                    taskWasCancelled: Task.isCancelled
                )
                if resumeImmediately {
                    continuation.resume()
                }
            }
        } onCancel: {
            let continuation = loadState.takeHeldContinuation()
            continuation?.resume()
        }
    }

    private static func requestTag(from request: URLRequest) -> UUID? {
        guard let rawTag = URLProtocol.property(
            forKey: requestTagKey,
            in: request
        ) as? String else {
            return nil
        }
        return UUID(uuidString: rawTag)
    }

    private static func response(
        for response: Response,
        request: URLRequest
    ) -> URLResponse? {
        guard let url = request.url else { return nil }
        switch response {
        case .http(let statusCode, let headers):
            return HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        case .nonHTTP:
            return URLResponse(
                url: url,
                mimeType: nil,
                expectedContentLength: -1,
                textEncodingName: nil
            )
        }
    }

    private static func diagnosticSnapshot(
        for request: URLRequest
    ) -> DiagnosticSnapshot {
        let components = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        return DiagnosticSnapshot(
            method: request.httpMethod,
            scheme: components?.scheme,
            host: components?.host,
            path: components?.path ?? "",
            queryItemNames: components?.queryItems?
                .map(\.name)
                .sorted() ?? [],
            bodyByteCount: requestBodyData(for: request)?.count,
            bodyData: requestBodyData(for: request),
            headers: NetworkDiagnosticRedactor().redactedHeaders(
                request.allHTTPHeaderFields ?? [:]
            )
        )
    }

    private static func requestBodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }
}

private actor RedactingURLProtocolRegistry {
    private struct Entry {
        let scenario: RedactingURLProtocol.Scenario
        var diagnosticSnapshot: RedactingURLProtocol.DiagnosticSnapshot?
        var didStart = false
        var isHeldOpen = false
        var stopCount = 0
        var startedWaiters: [CheckedContinuation<Void, Never>] = []
        var heldWaiters: [CheckedContinuation<Void, Never>] = []
        var stoppedWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private var entries: [UUID: Entry] = [:]

    func register(
        scenario: RedactingURLProtocol.Scenario,
        diagnosticSnapshot: RedactingURLProtocol.DiagnosticSnapshot,
        tag: UUID
    ) {
        entries[tag] = Entry(
            scenario: scenario,
            diagnosticSnapshot: diagnosticSnapshot
        )
    }

    func scenario(tag: UUID) -> RedactingURLProtocol.Scenario? {
        entries[tag]?.scenario
    }

    func recordStarted(tag: UUID) {
        guard var entry = entries[tag] else { return }
        entry.didStart = true
        let waiters = entry.startedWaiters
        entry.startedWaiters.removeAll()
        entries[tag] = entry
        for waiter in waiters {
            waiter.resume()
        }
    }

    func recordDiagnosticSnapshot(
        tag: UUID,
        snapshot: RedactingURLProtocol.DiagnosticSnapshot
    ) {
        guard var entry = entries[tag] else { return }
        if let existing = entry.diagnosticSnapshot,
           snapshot.bodyData == nil,
           existing.bodyData != nil {
            entry.diagnosticSnapshot = RedactingURLProtocol.DiagnosticSnapshot(
                method: snapshot.method,
                scheme: snapshot.scheme,
                host: snapshot.host,
                path: snapshot.path,
                queryItemNames: snapshot.queryItemNames,
                bodyByteCount: existing.bodyByteCount,
                bodyData: existing.bodyData,
                headers: snapshot.headers
            )
        } else {
            entry.diagnosticSnapshot = snapshot
        }
        entries[tag] = entry
    }

    func recordHeldOpen(tag: UUID) {
        guard var entry = entries[tag] else { return }
        entry.isHeldOpen = true
        let waiters = entry.heldWaiters
        entry.heldWaiters.removeAll()
        entries[tag] = entry
        for waiter in waiters {
            waiter.resume()
        }
    }

    func recordStopped(tag: UUID) {
        guard var entry = entries[tag] else { return }
        entry.stopCount += 1
        let waiters = entry.stoppedWaiters
        entry.stoppedWaiters.removeAll()
        entries[tag] = entry
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted(tag: UUID) async {
        guard entries[tag]?.didStart == false else { return }
        await withCheckedContinuation { continuation in
            entries[tag]?.startedWaiters.append(continuation)
        }
    }

    func waitUntilHeldOpen(tag: UUID) async {
        guard entries[tag]?.isHeldOpen == false else { return }
        await withCheckedContinuation { continuation in
            entries[tag]?.heldWaiters.append(continuation)
        }
    }

    func waitUntilStopped(tag: UUID) async {
        guard entries[tag]?.stopCount == 0 else { return }
        await withCheckedContinuation { continuation in
            entries[tag]?.stoppedWaiters.append(continuation)
        }
    }

    func stopCount(tag: UUID) -> Int {
        entries[tag]?.stopCount ?? 0
    }

    func diagnosticSnapshot(
        tag: UUID
    ) -> RedactingURLProtocol.DiagnosticSnapshot? {
        entries[tag]?.diagnosticSnapshot
    }
}
#endif
