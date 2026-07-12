import Foundation
import SQLite3
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

private let diagnosticsSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@Test
func localDiagnosticsExposeDatabaseAndRulesOnlyAIState() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-local-diagnostics-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("zoid.sqlite3")
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let policyStore = try PolicyStore(databaseURL: databaseURL)
    _ = try policyStore.saveSystemMaintenancePolicy(policy(aiProvider: .disabled))

    let snapshot = LocalSystemDiagnosticsService(databaseURL: databaseURL).inspect()

    #expect(snapshot.database.state == .healthy)
    #expect(snapshot.database.sizeBytes > 0)
    #expect(snapshot.database.schemaVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(snapshot.database.lastMigrationAt != nil)
    #expect(snapshot.database.fileName == "zoid.sqlite3")
    #expect(snapshot.ai.provider == .disabled)
    #expect(snapshot.ai.modeLabel == "Rules only")
    #expect(snapshot.ai.recentFailures.isEmpty)
}

@Test
func localDiagnosticsListOnlyRecentProviderFailuresWithoutPrivateContent() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-local-diagnostics-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("zoid.sqlite3")
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let policyStore = try PolicyStore(databaseURL: databaseURL)
    _ = try policyStore.saveSystemMaintenancePolicy(policy(aiProvider: .localOllama))
    try insertModelRun(
        databaseURL: databaseURL,
        id: "failure-new",
        provider: "ollama",
        state: "providerFailure",
        diagnostic: "timeout\n  without request content",
        startedAt: "2026-07-12T09:00:00Z"
    )
    try insertModelRun(
        databaseURL: databaseURL,
        id: "validated",
        provider: "ollama",
        state: "validated",
        diagnostic: nil,
        startedAt: "2026-07-12T08:00:00Z"
    )

    let snapshot = LocalSystemDiagnosticsService(databaseURL: databaseURL).inspect()

    #expect(snapshot.ai.provider == .localOllama)
    #expect(snapshot.ai.modeLabel == "Local Ollama")
    #expect(snapshot.ai.recentFailures.count == 1)
    #expect(snapshot.ai.recentFailures[0].provider == "ollama")
    #expect(snapshot.ai.recentFailures[0].state == "Provider failure")
    #expect(snapshot.ai.recentFailures[0].diagnostic == "timeout without request content")
    #expect(!snapshot.ai.recentFailures[0].diagnostic.contains("failure-new"))
}

@Test
func localDiagnosticsFailClosedForMissingOrCorruptDatabase() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-local-diagnostics-\(UUID().uuidString)", isDirectory: true)
    let missingURL = root.appendingPathComponent("missing.sqlite3")
    let corruptURL = root.appendingPathComponent("corrupt.sqlite3")
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let missing = LocalSystemDiagnosticsService(databaseURL: missingURL).inspect()
    #expect(missing.database.state == .unavailable)
    #expect(missing.database.detail == "The local database has not been created yet.")
    #expect(!FileManager.default.fileExists(atPath: missingURL.path))

    try Data("not a database".utf8).write(to: corruptURL)
    let corrupt = LocalSystemDiagnosticsService(databaseURL: corruptURL).inspect()
    #expect(corrupt.database.state == .attention)
    #expect(corrupt.database.detail.contains("could not be verified"))
    #expect(corrupt.ai.modeLabel == "Unavailable")
}

private func insertModelRun(
    databaseURL: URL,
    id: String,
    provider: String,
    state: String,
    diagnostic: String?,
    startedAt: String
) throws {
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
        throw DiagnosticsTestError.open
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    let sql = """
    INSERT INTO model_runs
    (id, provider, model, schema_version, prompt_version, normalized_input_hash,
     validation_state, redacted_diagnostic, started_at_utc)
    VALUES (?, ?, 'test-model', 1, 1, ?, ?, ?, ?);
    """
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw DiagnosticsTestError.prepare
    }
    defer { sqlite3_finalize(statement) }
    bind(id, statement, 1)
    bind(provider, statement, 2)
    bind(UUID().uuidString, statement, 3)
    bind(state, statement, 4)
    if let diagnostic {
        bind(diagnostic, statement, 5)
    } else {
        sqlite3_bind_null(statement, 5)
    }
    bind(startedAt, statement, 6)
    guard sqlite3_step(statement) == SQLITE_DONE else { throw DiagnosticsTestError.insert }
}

private func policy(aiProvider: AIProviderSelection) -> UserPolicy {
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    var draft = SettingsPolicyDraft(policy: original)
    draft.selectAIProvider(aiProvider)
    return draft.policy(preserving: original)
}

private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
    sqlite3_bind_text(statement, index, value, -1, diagnosticsSQLiteTransient)
}

private enum DiagnosticsTestError: Error {
    case open
    case prepare
    case insert
}
