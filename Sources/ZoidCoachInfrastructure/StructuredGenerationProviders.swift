import Foundation
import CryptoKit
import ZoidCoachCore

public struct DeterministicStructuredGenerationProvider: StructuredGenerationProviding, Sendable {
    public let providerID = "rules"
    public let modelID = "deterministic-v1"
    private let output: Data

    public init(output: Data) { self.output = output }

    public func generate(_ request: StructuredGenerationRequest) async throws -> StructuredGenerationOutput {
        guard (try? JSONSerialization.jsonObject(with: output)) != nil else {
            throw StructuredGenerationError.invalidStructuredOutput
        }
        return StructuredGenerationOutput(provider: providerID, model: modelID, json: output)
    }
}

public struct HTTPStructuredGenerationProvider: StructuredGenerationProviding, Sendable {
    public let providerID: String
    public let modelID: String
    private let endpoint: URL
    private let allowsRemoteProcessing: Bool
    private let session: URLSession

    public init(providerID: String, modelID: String, endpoint: URL, allowsRemoteProcessing: Bool, session: URLSession = .shared) throws {
        let isLoopback = endpoint.host == "127.0.0.1" || endpoint.host == "localhost" || endpoint.host == "::1"
        guard endpoint.scheme == "http" || endpoint.scheme == "https", isLoopback || endpoint.scheme == "https" else {
            throw StructuredGenerationError.invalidEndpoint
        }
        guard isLoopback || allowsRemoteProcessing else {
            throw StructuredGenerationError.remoteProcessingNotAuthorized
        }
        self.providerID = providerID
        self.modelID = modelID
        self.endpoint = endpoint
        self.allowsRemoteProcessing = allowsRemoteProcessing
        self.session = session
    }

    public func generate(_ request: StructuredGenerationRequest) async throws -> StructuredGenerationOutput {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 90
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "schemaName": request.schemaName,
            "schemaVersion": request.schemaVersion,
            "promptVersion": request.promptVersion,
            "prompt": request.prompt,
            "input": try JSONSerialization.jsonObject(with: request.inputJSON),
            "outputSchema": try JSONSerialization.jsonObject(with: request.outputSchemaJSON)
        ])
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw StructuredGenerationError.unavailable
        }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw StructuredGenerationError.invalidStructuredOutput
        }
        return StructuredGenerationOutput(provider: providerID, model: modelID, json: data)
    }
}

public actor StructuredGenerationConcurrencyGate {
    private let maximumConcurrentRequests: Int
    private var activeRequests = 0

    public init(maximumConcurrentRequests: Int = 1) {
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
    }

    public func acquire() throws {
        guard activeRequests < maximumConcurrentRequests else { throw StructuredGenerationError.concurrencyLimitReached }
        activeRequests += 1
    }

    public func release() { activeRequests = max(0, activeRequests - 1) }
}

public struct AuditedStructuredGenerationProvider: StructuredGenerationProviding, Sendable {
    public var providerID: String { provider.providerID }
    public var modelID: String { provider.modelID }
    private let provider: any StructuredGenerationProviding
    private let store: ModelRunStore
    private let gate: StructuredGenerationConcurrencyGate
    private let dailyRequestBudget: Int
    private let now: @Sendable () -> Date

    public init(
        provider: any StructuredGenerationProviding,
        store: ModelRunStore,
        gate: StructuredGenerationConcurrencyGate = StructuredGenerationConcurrencyGate(),
        dailyRequestBudget: Int = 100,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.store = store
        self.gate = gate
        self.dailyRequestBudget = max(0, dailyRequestBudget)
        self.now = now
    }

    public func generate(_ request: StructuredGenerationRequest) async throws -> StructuredGenerationOutput {
        let started = now()
        guard try store.canStartRequest(provider: providerID, dailyBudget: dailyRequestBudget, now: started) else {
            throw StructuredGenerationError.requestBudgetExceeded
        }
        try await gate.acquire()
        do {
            let output = try await provider.generate(request)
            guard (try? JSONSerialization.jsonObject(with: output.json)) != nil else {
                throw StructuredGenerationError.invalidStructuredOutput
            }
            try store.record(modelRun(request: request, state: .validated, started: started, finished: now(), diagnostic: nil))
            await gate.release()
            return output
        } catch {
            await gate.release()
            try? store.record(modelRun(request: request, state: .rejected, started: started, finished: now(), diagnostic: String(describing: type(of: error))))
            throw error
        }
    }

    private func modelRun(request: StructuredGenerationRequest, state: ModelRunValidationState, started: Date, finished: Date, diagnostic: String?) -> ModelRun {
        let inputHash = SHA256.hash(data: request.inputJSON).map { String(format: "%02x", $0) }.joined()
        return ModelRun(
            id: UUID().uuidString,
            provider: providerID,
            model: modelID,
            schemaVersion: request.schemaVersion,
            promptVersion: request.promptVersion,
            normalizedInputHash: inputHash,
            validationState: state,
            redactedDiagnostic: diagnostic,
            startedAtUTC: started,
            finishedAtUTC: finished,
            durationMilliseconds: max(0, Int(finished.timeIntervalSince(started) * 1_000))
        )
    }
}
