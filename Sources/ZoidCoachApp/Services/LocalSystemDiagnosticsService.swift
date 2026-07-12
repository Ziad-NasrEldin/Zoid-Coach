import Foundation
import SQLite3
import ZoidCoachCore
import ZoidCoachInfrastructure

enum LocalDatabaseDiagnosticState: Equatable, Sendable {
    case healthy
    case attention
    case unavailable
}

struct LocalDatabaseDiagnostic: Equatable, Sendable {
    let state: LocalDatabaseDiagnosticState
    let detail: String
    let fileName: String
    let sizeBytes: Int64
    let schemaVersion: Int?
    let expectedSchemaVersion: Int
    let lastMigrationAt: Date?
}

struct LocalAIProviderFailure: Equatable, Identifiable, Sendable {
    let provider: String
    let state: String
    let diagnostic: String
    let occurredAt: Date

    var id: String { "\(provider)|\(occurredAt.timeIntervalSince1970)|\(state)" }
}

struct LocalAIDiagnostic: Equatable, Sendable {
    let provider: AIProviderSelection?
    let modeLabel: String
    let processingLabel: String
    let recentFailures: [LocalAIProviderFailure]
}

struct LocalSystemDiagnosticsSnapshot: Equatable, Sendable {
    let database: LocalDatabaseDiagnostic
    let ai: LocalAIDiagnostic
    let inspectedAt: Date
}

struct LocalSystemDiagnosticsService: Sendable {
    let databaseURL: URL
    var now: @Sendable () -> Date = Date.init

    init(
        databaseURL: URL = RuntimeEnvironment.current().databaseURL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.databaseURL = databaseURL
        self.now = now
    }

    func inspect() -> LocalSystemDiagnosticsSnapshot {
        let inspectedAt = now()
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return LocalSystemDiagnosticsSnapshot(
                database: LocalDatabaseDiagnostic(
                    state: .unavailable,
                    detail: "The local database has not been created yet.",
                    fileName: databaseURL.lastPathComponent,
                    sizeBytes: 0,
                    schemaVersion: nil,
                    expectedSchemaVersion: AutonomousDatabaseMigrator.currentVersion,
                    lastMigrationAt: nil
                ),
                ai: unavailableAI,
                inspectedAt: inspectedAt
            )
        }

        do {
            let database = try ReadOnlyDiagnosticsDatabase(url: databaseURL)
            let quickCheck = try database.scalarText("PRAGMA quick_check(1);")
            guard quickCheck == "ok" else {
                throw LocalSystemDiagnosticsError.integrityCheck(quickCheck ?? "no result")
            }
            let schemaVersion = try database.scalarInt(
                "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;"
            )
            let lastMigrationAt = try database.scalarText(
                "SELECT applied_at FROM schema_migrations ORDER BY version DESC LIMIT 1;"
            ).flatMap(Self.parseDatabaseDate)
            let sizeBytes = Self.localStoreSize(at: databaseURL)
            let state: LocalDatabaseDiagnosticState = schemaVersion == AutonomousDatabaseMigrator.currentVersion
                ? .healthy
                : .attention
            let detail = state == .healthy
                ? "Integrity check passed on the current schema."
                : "The database is readable but its schema is not current. Restart Zoid 666 to retry migration."
            let databaseDiagnostic = LocalDatabaseDiagnostic(
                state: state,
                detail: detail,
                fileName: databaseURL.lastPathComponent,
                sizeBytes: sizeBytes,
                schemaVersion: schemaVersion,
                expectedSchemaVersion: AutonomousDatabaseMigrator.currentVersion,
                lastMigrationAt: lastMigrationAt
            )
            return LocalSystemDiagnosticsSnapshot(
                database: databaseDiagnostic,
                ai: inspectAI(database: database),
                inspectedAt: inspectedAt
            )
        } catch {
            return LocalSystemDiagnosticsSnapshot(
                database: LocalDatabaseDiagnostic(
                    state: .attention,
                    detail: "The local database could not be verified. Zoid 666 left it unchanged.",
                    fileName: databaseURL.lastPathComponent,
                    sizeBytes: Self.localStoreSize(at: databaseURL),
                    schemaVersion: nil,
                    expectedSchemaVersion: AutonomousDatabaseMigrator.currentVersion,
                    lastMigrationAt: nil
                ),
                ai: unavailableAI,
                inspectedAt: inspectedAt
            )
        }
    }

    private func inspectAI(database: ReadOnlyDiagnosticsDatabase) -> LocalAIDiagnostic {
        let provider: AIProviderSelection?
        do {
            provider = try PolicyStore(databaseURL: databaseURL, readOnly: true)
                .current()?.policy.privacy.aiProvider ?? .disabled
        } catch {
            provider = nil
        }
        let failures = (try? database.providerFailures(limit: 5)) ?? []
        return LocalAIDiagnostic(
            provider: provider,
            modeLabel: provider.map(Self.aiModeLabel) ?? "Unavailable",
            processingLabel: provider.map(Self.processingLabel) ?? "Policy could not be read",
            recentFailures: failures
        )
    }

    private var unavailableAI: LocalAIDiagnostic {
        LocalAIDiagnostic(
            provider: nil,
            modeLabel: "Unavailable",
            processingLabel: "AI policy is unavailable until local storage is ready",
            recentFailures: []
        )
    }

    private static func aiModeLabel(_ provider: AIProviderSelection) -> String {
        switch provider {
        case .disabled: "Rules only"
        case .localOllama: "Local Ollama"
        case .codexCLI: "Codex CLI"
        case .appleOnDevice: "Apple on-device"
        case .remoteOpenAI: "Remote OpenAI"
        }
    }

    private static func processingLabel(_ provider: AIProviderSelection) -> String {
        switch provider {
        case .disabled: "Deterministic local rules remain active"
        case .localOllama, .appleOnDevice: "Processing stays on this Mac"
        case .codexCLI: "Requests use the configured local Codex CLI"
        case .remoteOpenAI: "Remote processing follows the configured evidence policy"
        }
    }

    private static func localStoreSize(at url: URL) -> Int64 {
        [url.path, url.path + "-wal", url.path + "-shm"].reduce(into: 0) { total, path in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            total += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
    }

    fileprivate static func parseDatabaseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }
}

private final class ReadOnlyDiagnosticsDatabase: @unchecked Sendable {
    private let database: OpaquePointer

    init(url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw LocalSystemDiagnosticsError.open
        }
        database = handle
        sqlite3_busy_timeout(database, 2_000)
    }

    deinit { sqlite3_close(database) }

    func scalarText(_ sql: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LocalSystemDiagnosticsError.query
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalSystemDiagnosticsError.query
        }
        guard let bytes = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: bytes)
    }

    func scalarInt(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LocalSystemDiagnosticsError.query
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalSystemDiagnosticsError.query
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    func providerFailures(limit: Int) throws -> [LocalAIProviderFailure] {
        var statement: OpaquePointer?
        let sql = """
        SELECT provider, validation_state, COALESCE(redacted_diagnostic, ''), started_at_utc
        FROM model_runs
        WHERE validation_state IN ('providerFailure', 'rejected')
        ORDER BY started_at_utc DESC
        LIMIT ?;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LocalSystemDiagnosticsError.query
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(0, limit)))
        var failures: [LocalAIProviderFailure] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let provider = text(statement, 0),
                  let state = text(statement, 1),
                  let occurredAtRaw = text(statement, 3),
                  let occurredAt = LocalSystemDiagnosticsService.parseDatabaseDate(occurredAtRaw) else {
                continue
            }
            let diagnostic = Self.safeDiagnostic(text(statement, 2))
            failures.append(LocalAIProviderFailure(
                provider: provider,
                state: state == "providerFailure" ? "Provider failure" : "Rejected output",
                diagnostic: diagnostic ?? "No redacted diagnostic was recorded",
                occurredAt: occurredAt
            ))
        }
        return failures
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }

    private static func safeDiagnostic(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(240))
    }
}

private enum LocalSystemDiagnosticsError: Error {
    case open
    case query
    case integrityCheck(String)
}
