import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func remoteStructuredProviderRequiresExplicitAuthorizationWhileLoopbackDoesNot() throws {
    #expect(throws: StructuredGenerationError.remoteProcessingNotAuthorized) {
        _ = try HTTPStructuredGenerationProvider(
            providerID: "remote", modelID: "model",
            endpoint: URL(string: "https://models.example.test/generate")!,
            allowsRemoteProcessing: false
        )
    }
    _ = try HTTPStructuredGenerationProvider(
        providerID: "ollama", modelID: "local",
        endpoint: URL(string: "http://127.0.0.1:11434/generate")!,
        allowsRemoteProcessing: false
    )
}

@Test
func auditedStructuredProviderRecordsValidationAndEnforcesDailyBudget() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("structured-audit-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ModelRunStore(databaseURL: databaseURL)
    let now = Date(timeIntervalSince1970: 1_752_153_600)
    let provider = AuditedStructuredGenerationProvider(
        provider: DeterministicStructuredGenerationProvider(output: Data(#"{"value":1}"#.utf8)),
        store: store,
        dailyRequestBudget: 1,
        now: { now }
    )
    let request = StructuredGenerationRequest(
        schemaName: "test", schemaVersion: 1, promptVersion: 1, prompt: "Return value",
        inputJSON: Data(#"{"input":1}"#.utf8), outputSchemaJSON: Data(#"{"type":"object"}"#.utf8)
    )

    #expect(try await provider.generate(request).json == Data(#"{"value":1}"#.utf8))
    await #expect(throws: StructuredGenerationError.requestBudgetExceeded) { try await provider.generate(request) }
    #expect(try store.requestCount(provider: "rules", since: now.addingTimeInterval(-1)) == 1)
}

@Test
func auditedStructuredProviderRejectsRequestAtMonthlyBudget() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("structured-monthly-budget-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ModelRunStore(databaseURL: databaseURL)
    let previousDay = Date(timeIntervalSince1970: 1_752_153_600)
    let now = previousDay.addingTimeInterval(3 * 86_400)
    try store.record(ModelRun(
        id: "prior-request",
        provider: "rules",
        model: "deterministic",
        schemaVersion: 1,
        promptVersion: 1,
        normalizedInputHash: "prior",
        validationState: .validated,
        startedAtUTC: previousDay
    ))
    let provider = AuditedStructuredGenerationProvider(
        provider: DeterministicStructuredGenerationProvider(output: Data(#"{"value":1}"#.utf8)),
        store: store,
        dailyRequestBudget: 10,
        monthlyRequestBudget: 1,
        now: { now }
    )
    let request = StructuredGenerationRequest(
        schemaName: "test",
        schemaVersion: 1,
        promptVersion: 1,
        prompt: "Return value",
        inputJSON: Data(#"{"input":1}"#.utf8),
        outputSchemaJSON: Data(#"{"type":"object"}"#.utf8)
    )

    await #expect(throws: StructuredGenerationError.requestBudgetExceeded) {
        try await provider.generate(request)
    }
}

@Test
func auditedPlanningAdvisorReservesBudgetBeforeUsingAdvice() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("planning-advisor-budget-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ModelRunStore(databaseURL: databaseURL)
    let now = Date(timeIntervalSince1970: 1_752_153_600)
    let advisor = AuditedPlanningAdvisor(
        advisor: FixedPlanningAdvisor(),
        providerID: "codex-cli",
        modelID: "test-model",
        store: store,
        gate: StructuredGenerationConcurrencyGate(),
        dailyRequestBudget: 1,
        monthlyRequestBudget: 10,
        now: { now }
    )
    let input = PlanningAdviceInput(
        id: "task",
        title: "Prepare proposal",
        dueDate: nil,
        reminderPriority: 5,
        carryoverDays: 0,
        deferralCount: 0,
        recentAlignedMinutes: 0
    )

    #expect(try await advisor.advise(on: [input], recentBehavior: []).count == 1)
    await #expect(throws: StructuredGenerationError.requestBudgetExceeded) {
        try await advisor.advise(on: [input], recentBehavior: [])
    }
    #expect(try store.requestCount(since: now.addingTimeInterval(-1)) == 1)
}

private struct FixedPlanningAdvisor: PlanningAdvising {
    func advise(
        on tasks: [PlanningAdviceInput],
        recentBehavior: [PlanningBehaviorEvidence]
    ) async throws -> [PlanningAdvice] {
        tasks.map { PlanningAdvice(id: $0.id, adjustment: 10, reason: "Test advice") }
    }
}
