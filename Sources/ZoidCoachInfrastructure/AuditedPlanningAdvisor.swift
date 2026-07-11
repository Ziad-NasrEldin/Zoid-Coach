import CryptoKit
import Foundation
import ZoidCoachCore

public struct AuditedPlanningAdvisor: PlanningAdvising, Sendable {
    private let advisor: any PlanningAdvising
    private let providerID: String
    private let modelID: String
    private let store: ModelRunStore
    private let gate: StructuredGenerationConcurrencyGate
    private let dailyRequestBudget: Int
    private let now: @Sendable () -> Date

    public init(
        advisor: any PlanningAdvising,
        providerID: String,
        modelID: String,
        store: ModelRunStore,
        gate: StructuredGenerationConcurrencyGate,
        dailyRequestBudget: Int = 100,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.advisor = advisor
        self.providerID = providerID
        self.modelID = modelID
        self.store = store
        self.gate = gate
        self.dailyRequestBudget = max(0, dailyRequestBudget)
        self.now = now
    }

    public func advise(on tasks: [PlanningAdviceInput], recentBehavior: [PlanningBehaviorEvidence]) async throws -> [PlanningAdvice] {
        let started = now()
        guard try store.canStartRequest(provider: providerID, dailyBudget: dailyRequestBudget, now: started) else {
            throw StructuredGenerationError.requestBudgetExceeded
        }
        try await gate.acquire()
        let inputHash = try normalizedHash(tasks: tasks, behavior: recentBehavior)
        do {
            let advice = try await advisor.advise(on: tasks, recentBehavior: recentBehavior)
            try store.record(run(inputHash: inputHash, state: .validated, started: started, finished: now(), diagnostic: nil))
            await gate.release()
            return advice
        } catch {
            try? store.record(run(inputHash: inputHash, state: .providerFailure, started: started, finished: now(), diagnostic: String(describing: type(of: error))))
            await gate.release()
            throw error
        }
    }

    private func normalizedHash(tasks: [PlanningAdviceInput], behavior: [PlanningBehaviorEvidence]) throws -> String {
        struct Input: Encodable { let tasks: [PlanningAdviceInput]; let behavior: [PlanningBehaviorEvidence] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Input(tasks: tasks, behavior: behavior))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func run(inputHash: String, state: ModelRunValidationState, started: Date, finished: Date, diagnostic: String?) -> ModelRun {
        ModelRun(
            id: UUID().uuidString, provider: providerID, model: modelID,
            schemaVersion: 1, promptVersion: 1, normalizedInputHash: inputHash,
            validationState: state, redactedDiagnostic: diagnostic,
            startedAtUTC: started, finishedAtUTC: finished,
            durationMilliseconds: max(0, Int(finished.timeIntervalSince(started) * 1_000))
        )
    }
}
