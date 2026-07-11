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
    #expect(try store.canStartRequest(provider: "codex", dailyBudget: 1, now: now) == true)
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
