import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test("AI budget status counts every provider and model in one non-bypassable budget")
func aiBudgetStatusCountsEveryProviderAndModel() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-ai-budget-status-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ModelRunStore(databaseURL: databaseURL)
    let now = Date(timeIntervalSince1970: 1_752_499_200)
    var draft = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "UTC"))
    draft.aiDailyRequestBudget = 3
    draft.aiMonthlyRequestBudget = 10
    _ = try PolicyStore(databaseURL: databaseURL).saveSystemMaintenancePolicy(
        draft.policy(preserving: .defaults(timeZoneIdentifier: "UTC"))
    )

    try store.record(testRun(id: "ollama", provider: "ollama", model: "llama3", at: now.addingTimeInterval(-60)))
    try store.record(testRun(id: "codex-a", provider: "codex", model: "gpt-5", at: now.addingTimeInterval(-120)))
    try store.record(testRun(id: "codex-b", provider: "codex", model: "gpt-5.6", at: now.addingTimeInterval(-180)))

    let status = try AIBudgetStatusService(databaseURL: databaseURL).load(now: now)

    #expect(status.dailyUsed == 3)
    #expect(status.monthlyUsed == 3)
    #expect(status.isExhausted)
    #expect(status.scopeMessage.contains("all providers and models"))
    #expect(status.fallbackMessage.contains("local"))
    #expect(status.fallbackMessage.contains("no paid request"))
}

@Test("AI budget status distinguishes disabled budgets and calculates UTC resets")
func aiBudgetStatusReportsDisabledAndResetBoundaries() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-ai-budget-disabled-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    _ = try ModelRunStore(databaseURL: databaseURL)
    var draft = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "UTC"))
    draft.aiDailyRequestBudget = 0
    draft.aiMonthlyRequestBudget = 0
    _ = try PolicyStore(databaseURL: databaseURL).saveSystemMaintenancePolicy(
        draft.policy(preserving: .defaults(timeZoneIdentifier: "UTC"))
    )
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-14T12:00:00Z"))

    let status = try AIBudgetStatusService(databaseURL: databaseURL).load(now: now)

    #expect(status.isDisabled)
    #expect(status.nextDailyReset == ISO8601DateFormatter().date(from: "2026-07-15T00:00:00Z"))
    #expect(status.nextMonthlyReset == ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z"))
    #expect(status.fallbackMessage.contains("no paid request"))
}

private func testRun(id: String, provider: String, model: String, at date: Date) -> ModelRun {
    ModelRun(
        id: id,
        provider: provider,
        model: model,
        schemaVersion: 1,
        promptVersion: 1,
        normalizedInputHash: id,
        validationState: .validated,
        redactedDiagnostic: nil,
        startedAtUTC: date,
        finishedAtUTC: date,
        durationMilliseconds: 1
    )
}
