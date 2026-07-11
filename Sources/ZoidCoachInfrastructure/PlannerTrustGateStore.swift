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

public enum HistoricalShadowEvidenceCoverage: String, Equatable, Sendable {
    case complete
    case insufficientForReplay
}

public enum HistoricalShadowMissingEvidence: String, Equatable, Sendable {
    case historicalTaskSnapshot
    case historicalCalendarSnapshot
    case observedOutcome
    case validPlanShape
}

public struct HistoricalShadowEvaluationReport: Equatable, Sendable {
    public let localDay: String
    public let storedItemCount: Int
    public let evidenceCoverage: HistoricalShadowEvidenceCoverage
    public let missingEvidence: [HistoricalShadowMissingEvidence]
}

public struct RetrospectiveShadowEvaluation: Equatable, Sendable {
    public let localDay: String
    public let planVersion: Int
    public let itemCount: Int
    public let stayedWithinCapacity: Bool
    public let externalWritesSuppressed: Bool
    public let comparedWithObservedOutcome: Bool
    public let evidenceCoverage: HistoricalShadowEvidenceCoverage

    public init(localDay: String, planVersion: Int, itemCount: Int, stayedWithinCapacity: Bool, externalWritesSuppressed: Bool, comparedWithObservedOutcome: Bool, evidenceCoverage: HistoricalShadowEvidenceCoverage) {
        self.localDay = localDay
        self.planVersion = planVersion
        self.itemCount = itemCount
        self.stayedWithinCapacity = stayedWithinCapacity
        self.externalWritesSuppressed = externalWritesSuppressed
        self.comparedWithObservedOutcome = comparedWithObservedOutcome
        self.evidenceCoverage = evidenceCoverage
    }
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

    /// Inventories stored days that could be considered for a retrospective planner replay.
    ///
    /// The current schema has latest-state Reminder rows and Calendar identifiers, not immutable
    /// per-day source snapshots. Those omissions are deliberately reported instead of treating a
    /// historical manual plan as if it were an observed shadow run.
    public func historicalShadowEvaluationReport() throws -> [HistoricalShadowEvaluationReport] {
        let sql = """
        SELECT day_key, COUNT(*),
               SUM(CASE WHEN is_main_objective = 1 THEN 1 ELSE 0 END),
               SUM(CASE WHEN estimate_minutes IS NULL OR estimate_minutes <= 0 OR selection_reason IS NULL OR TRIM(selection_reason) = '' THEN 1 ELSE 0 END)
        FROM daily_plan_entries
        GROUP BY day_key
        ORDER BY day_key;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PlannerTrustGateStoreError.read
        }
        defer { sqlite3_finalize(statement) }
        var reports: [HistoricalShadowEvaluationReport] = []
        while sqlite3_step(statement) == SQLITE_ROW, let dayText = sqlite3_column_text(statement, 0) {
            let itemCount = Int(sqlite3_column_int(statement, 1))
            let mainCount = Int(sqlite3_column_int(statement, 2))
            let malformedCount = Int(sqlite3_column_int(statement, 3))
            var missing: [HistoricalShadowMissingEvidence] = [
                .historicalTaskSnapshot,
                .historicalCalendarSnapshot,
                .observedOutcome
            ]
            if !(1...5).contains(itemCount) || mainCount != 1 || malformedCount > 0 {
                missing.append(.validPlanShape)
            }
            reports.append(HistoricalShadowEvaluationReport(
                localDay: String(cString: dayText),
                storedItemCount: itemCount,
                evidenceCoverage: .insufficientForReplay,
                missingEvidence: missing
            ))
        }
        return reports
    }

    /// Records a retrospective replay only after its caller has assembled complete historical
    /// inputs, suppressed external writes, checked capacity, and compared the proposal to outcome.
    @discardableResult
    public func recordRetrospectiveEvaluation(_ evaluation: RetrospectiveShadowEvaluation, observedAt: Date = Date()) throws -> Bool {
        guard evaluation.evidenceCoverage == .complete,
              evaluation.comparedWithObservedOutcome,
              evaluation.externalWritesSuppressed,
              evaluation.stayedWithinCapacity,
              evaluation.itemCount > 0
        else { return false }
        _ = try recordShadowCycle(
            localDay: evaluation.localDay,
            planVersion: evaluation.planVersion,
            itemCount: evaluation.itemCount,
            stayedWithinCapacity: true,
            observedAt: observedAt
        )
        return true
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
