import Foundation
import SQLite3
import ZoidCoachCore

public final class ScreenContextSelector: @unchecked Sendable {
    private let database: OpaquePointer
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            throw ScreenContextSelectorError.openDatabase
        }
        self.database = database
        self.fileManager = fileManager
        self.now = now
        self.makeID = makeID
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func select(
        reason: String,
        limit: Int,
        mayTransmitPrivateContent: Bool,
        excludingContentHashes: Set<String> = []
    ) throws -> ScreenContextSelection {
        guard mayTransmitPrivateContent else { throw ScreenContextSelectorError.privateContentNotAllowed }
        let maximum = min(max(limit, 1), 4)
        let sql = """
        SELECT id, path, content_hash, perceptual_fingerprint
        FROM screenshot_artifacts
        WHERE retention_until_utc > ?
        ORDER BY behavior_epoch DESC, id DESC
        LIMIT 80;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenContextSelectorError.prepare
        }
        defer { sqlite3_finalize(statement) }
        bind(ISO8601DateFormatter().string(from: now()), statement, 1)
        var identifiers: [String] = []
        var paths: [String] = []
        var hashes: [String] = []
        var fingerprints = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW, identifiers.count < maximum {
            let identifier = string(statement, 0)
            let path = string(statement, 1)
            let hash = string(statement, 2)
            let fingerprint = string(statement, 3)
            guard !excludingContentHashes.contains(hash),
                  fingerprints.insert(fingerprint).inserted,
                  fileManager.fileExists(atPath: path) else { continue }
            identifiers.append(identifier)
            paths.append(path)
            hashes.append(hash)
        }
        return ScreenContextSelection(
            id: makeID(),
            artifactIDs: identifiers,
            paths: paths,
            contentHashes: hashes,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedAt: now(),
            mayTransmitPrivateContent: true
        )
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }
}

public enum ScreenContextSelectorError: LocalizedError {
    case openDatabase
    case prepare
    case privateContentNotAllowed

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open Screenwatch context storage."
        case .prepare: "Could not select Screenwatch context."
        case .privateContentNotAllowed: "Selected screenshots require explicit private-content permission."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
