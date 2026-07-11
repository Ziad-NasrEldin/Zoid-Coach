import Foundation
import SQLite3

private let trustGateSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct PlannerTrustGateStatus: Equatable, Sendable {
    public let observedCycleCount: Int
    public let requiredCycleCount: Int
    public let requiredWakeCycleCount: Int

    public var allowsAutomaticWrites: Bool { observedCycleCount >= requiredCycleCount }
    public var allowsWakeWrites: Bool { observedCycleCount >= requiredWakeCycleCount }
}

public final class PlannerTrustGateStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let requiredCycles: Int
    private let requiredWakeCycles: Int
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL, requiredCycles: Int = 7, requiredWakeCycles: Int = 14) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else { throw PlannerTrustGateStoreError.openDatabase }
        database = handle
        self.requiredCycles = max(1, requiredCycles)
        self.requiredWakeCycles = max(max(1, requiredCycles), requiredWakeCycles)
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    @discardableResult
    public func recordShadowCycle(
        localDay: String,
        planVersion: Int,
        itemCount: Int,
        stayedWithinCapacity: Bool,
        observedAt: Date = Date()
    ) throws -> PlannerTrustGateStatus {
        let sql = "INSERT OR IGNORE INTO planner_trust_cycles (local_day, plan_version, item_count, stayed_within_capacity, external_writes_suppressed, observed_at_utc) VALUES (?, ?, ?, ?, 1, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PlannerTrustGateStoreError.write
        }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        sqlite3_bind_int(statement, 2, Int32(planVersion))
        sqlite3_bind_int(statement, 3, Int32(itemCount))
        sqlite3_bind_int(statement, 4, stayedWithinCapacity ? 1 : 0)
        bind(formatter.string(from: observedAt), statement, 5)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PlannerTrustGateStoreError.write }
        return try status()
    }

    public func status() throws -> PlannerTrustGateStatus {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM planner_trust_cycles WHERE item_count > 0 AND stayed_within_capacity = 1 AND external_writes_suppressed = 1;", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw PlannerTrustGateStoreError.read }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw PlannerTrustGateStoreError.read }
        return PlannerTrustGateStatus(
            observedCycleCount: Int(sqlite3_column_int(statement, 0)),
            requiredCycleCount: requiredCycles,
            requiredWakeCycleCount: requiredWakeCycles
        )
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, trustGateSQLiteTransient) }
    }
}

public enum PlannerTrustGateStoreError: Error {
    case openDatabase
    case write
    case read
}
