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
    private let monthlyRequestBudget: Int
    private let now: @Sendable () -> Date

    public init(
        advisor: any PlanningAdvising,
        providerID: String,
        modelID: String,
        store: ModelRunStore,
        gate: StructuredGenerationConcurrencyGate,
        dailyRequestBudget: Int = 100,
        monthlyRequestBudget: Int = 3_000,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.advisor = advisor
        self.providerID = providerID
        self.modelID = modelID
        self.store = store
        self.gate = gate
        self.dailyRequestBudget = max(0, dailyRequestBudget)
        self.monthlyRequestBudget = max(0, monthlyRequestBudget)
        self.now = now
    }

    public func advise(on tasks: [PlanningAdviceInput], recentBehavior: [PlanningBehaviorEvidence]) async throws -> [PlanningAdvice] {
        let inputHash = try normalizedHash(tasks: tasks, behavior: recentBehavior)
        let reservationID = UUID().uuidString
        try await gate.acquire()
        let started = now()
        let reserved: Bool
        do {
            reserved = try store.reserveRequest(
                run(id: reservationID, inputHash: inputHash, state: .pending, started: started, finished: started, diagnostic: nil),
                dailyBudget: dailyRequestBudget,
                monthlyBudget: monthlyRequestBudget,
                now: started
            )
        } catch {
            await gate.release()
            throw error
        }
        guard reserved else {
            await gate.release()
            throw StructuredGenerationError.requestBudgetExceeded
        }
        do {
            let advice = try await advisor.advise(on: tasks, recentBehavior: recentBehavior)
            try store.record(run(id: reservationID, inputHash: inputHash, state: .validated, started: started, finished: now(), diagnostic: nil))
            await gate.release()
            return advice
        } catch {
            try? store.record(run(id: reservationID, inputHash: inputHash, state: .providerFailure, started: started, finished: now(), diagnostic: String(describing: type(of: error))))
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

    private func run(id: String, inputHash: String, state: ModelRunValidationState, started: Date, finished: Date, diagnostic: String?) -> ModelRun {
        ModelRun(
            id: id, provider: providerID, model: modelID,
            schemaVersion: 1, promptVersion: 1, normalizedInputHash: inputHash,
            validationState: state, redactedDiagnostic: diagnostic,
            startedAtUTC: started, finishedAtUTC: finished,
            durationMilliseconds: max(0, Int(finished.timeIntervalSince(started) * 1_000))
        )
    }
}
