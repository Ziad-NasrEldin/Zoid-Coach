import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func modelRunLedgerCachesValidatedStructuredOutputAndEnforcesDailyBudget() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-model-runs-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ModelRunStore(databaseURL: databaseURL)
    let now = Date(timeIntervalSince1970: 1_752_153_600)
    let run = ModelRun(
        id: "run-1",
        provider: "ollama",
        model: "qwen",
        schemaVersion: 2,
        promptVersion: 3,
        normalizedInputHash: "hash-1",
        validationState: .validated,
        startedAtUTC: now,
        finishedAtUTC: now.addingTimeInterval(0.25),
        durationMilliseconds: 250
    )

    try store.record(run)

    #expect(try store.cachedValidatedRun(provider: "ollama", model: "qwen", schemaVersion: 2, normalizedInputHash: "hash-1") == run)
    #expect(try store.requestCount(provider: "ollama", since: now.addingTimeInterval(-1)) == 1)
    #expect(try store.canStartRequest(provider: "ollama", dailyBudget: 1, now: now) == false)
    #expect(try store.canStartRequest(provider: "codex", dailyBudget: 1, now: now) == false)
}

@Test
func modelRunReservationAtomicallySharesBudgetAcrossProviders() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-model-global-budget-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ModelRunStore(databaseURL: databaseURL)
    let now = Date(timeIntervalSince1970: 1_752_153_600)
    let first = ModelRun(
        id: "reservation-1",
        provider: "ollama",
        model: "local",
        schemaVersion: 1,
        promptVersion: 1,
        normalizedInputHash: "first",
        validationState: .pending,
        startedAtUTC: now
    )
    let second = ModelRun(
        id: "reservation-2",
        provider: "codex-cli",
        model: "remote",
        schemaVersion: 1,
        promptVersion: 1,
        normalizedInputHash: "second",
        validationState: .pending,
        startedAtUTC: now
    )

    #expect(try store.reserveRequest(first, dailyBudget: 1, monthlyBudget: 10, now: now))
    #expect(try store.reserveRequest(second, dailyBudget: 1, monthlyBudget: 10, now: now) == false)
    #expect(try store.requestCount(since: now.addingTimeInterval(-1)) == 1)
}

@Test
func modelRunLedgerEnforcesMonthlyBudgetAcrossDailyBoundary() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-model-monthly-budget-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ModelRunStore(databaseURL: databaseURL)
    let calendar = Calendar(identifier: .gregorian)
    let previousDay = Date(timeIntervalSince1970: 1_752_153_600)
    let laterSameMonth = previousDay.addingTimeInterval(3 * 86_400)
    let nextMonth = previousDay.addingTimeInterval(32 * 86_400)
    try store.record(ModelRun(
        id: "monthly-1",
        provider: "codex-cli",
        model: "gpt",
        schemaVersion: 1,
        promptVersion: 1,
        normalizedInputHash: "monthly-hash",
        validationState: .validated,
        startedAtUTC: previousDay
    ))

    #expect(try store.canStartRequest(
        provider: "codex-cli",
        dailyBudget: 10,
        monthlyBudget: 1,
        now: laterSameMonth,
        calendar: calendar
    ) == false)
    #expect(try store.canStartRequest(
        provider: "codex-cli",
        dailyBudget: 10,
        monthlyBudget: 1,
        now: nextMonth,
        calendar: calendar
    ))
}

@Test
func invalidModelRunsAreAuditedButNeverUsedAsCacheHits() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-invalid-model-runs-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ModelRunStore(databaseURL: databaseURL)
    let run = ModelRun(
        id: "run-invalid",
        provider: "ollama",
        model: "qwen",
        schemaVersion: 2,
        promptVersion: 3,
        normalizedInputHash: "bad-hash",
        validationState: .rejected,
        redactedDiagnostic: "schema mismatch",
        startedAtUTC: Date(timeIntervalSince1970: 1_752_153_600)
    )

    try store.record(run)

    #expect(try store.cachedValidatedRun(provider: "ollama", model: "qwen", schemaVersion: 2, normalizedInputHash: "bad-hash") == nil)
}
