import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func baselineSuppressesBehaviorPromptsUntilSevenCompleteDaysAndSurvivesRestart() throws {
    let fixture = try BaselineFixture()
    defer { fixture.remove() }
    for day in 1...6 {
        let status = try fixture.store.record(fixture.day(day, coverage: .complete, eligibleDrift: day.isMultiple(of: 2) ? 1 : 0))
        #expect(status.suppressesBehaviorPrompts)
        #expect(status.completeDayCount == day)
    }
    let complete = try fixture.store.record(fixture.day(7, coverage: .complete, eligibleDrift: 2))
    #expect(complete.isComplete)
    #expect(!complete.suppressesBehaviorPrompts)
    #expect(complete.observedEligibleDriftCount == 5)
    let frozen = try fixture.store.record(fixture.day(8, coverage: .complete, eligibleDrift: 9))
    #expect(frozen.completeDayCount == 7)
    #expect(frozen.days.contains(where: { $0.localDay == "2026-07-08" }) == false)

    let reopened = try BaselineObservationStore(databaseURL: fixture.databaseURL)
    let restored = try reopened.status()
    #expect(restored.isComplete)
    #expect(restored.completeDayCount == 7)
    #expect(restored.report.averageObservedWorkMinutes == 40)
}

@Test
func limitedAndMissingDaysStayVisibleWithoutAdvancingOrDowngradingTheGate() throws {
    let fixture = try BaselineFixture()
    defer { fixture.remove() }
    _ = try fixture.store.record(fixture.day(1, coverage: .limited))
    _ = try fixture.store.record(fixture.day(2, coverage: .missing))
    _ = try fixture.store.record(fixture.day(3, coverage: .complete))
    var status = try fixture.store.status()
    #expect(status.days.count == 3)
    #expect(status.completeDayCount == 1)
    #expect(status.remainingCompleteDays == 6)

    _ = try fixture.store.record(fixture.day(3, coverage: .limited))
    status = try fixture.store.status()
    #expect(status.completeDayCount == 1)
    #expect(status.days.first { $0.localDay == "2026-07-03" }?.coverage == .complete)
}

@Test
func reconciliationCountsOnlyFinishedCoveredDaysAndObservesDriftWithoutPromptRecords() throws {
    let fixture = try BaselineFixture()
    defer { fixture.remove() }
    for day in 1...7 {
        let localDay = String(format: "2026-07-%02d", day)
        let base = Int64(1_783_000_000 + day * 86_400)
        for minute in 0..<35 {
            let classification: BehaviorClassification = day == 4 && minute < 12 ? .gaming : .work
            try fixture.insertObservation(
                localDay: localDay,
                epoch: base + Int64(minute * 60),
                classification: classification
            )
        }
    }
    try fixture.insertObservation(
        localDay: "2026-07-08",
        epoch: 1_783_700_000,
        classification: .gaming
    )
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let today = try #require(ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z"))

    let status = try fixture.store.reconcileCompletedDays(before: today, calendar: calendar)

    #expect(status.completeDayCount == 7)
    #expect(status.isComplete)
    #expect(status.report.gamingDayCount == 1)
    #expect(status.report.totalGamingMinutes == 12)
    #expect(status.report.eligibleDriftCount == 1)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM prompt_episodes;") == 0)
    #expect(status.days.contains(where: { $0.localDay == "2026-07-08" }) == false)
}

@Test
func baselineAlertGuidanceRemainsConservativeForUnknownCoverageAndSparseDrift() {
    let uncertain = BaselineObservationReport(
        averageObservedWorkMinutes: 40,
        gamingDayCount: 1,
        totalGamingMinutes: 10,
        eligibleDriftCount: 4,
        unknownSharePercent: 35
    )
    #expect(uncertain.alertSensitivityGuidance.contains("too uncertain"))

    let quiet = BaselineObservationReport(
        averageObservedWorkMinutes: 50,
        gamingDayCount: 0,
        totalGamingMinutes: 0,
        eligibleDriftCount: 0,
        unknownSharePercent: 5
    )
    #expect(quiet.alertSensitivityGuidance.contains("gentle alerts"))
}

@Test
func baselineReportRespectsDailyReviewCorrectionsWithoutRewritingBehaviorEvidence() throws {
    let fixture = try BaselineFixture()
    defer { fixture.remove() }
    let base: Int64 = 1_783_000_000
    for minute in 0..<35 {
        try fixture.insertObservation(
            localDay: "2026-07-01",
            epoch: base + Int64(minute * 60),
            classification: minute < 12 ? .gaming : .work
        )
    }
    try fixture.insertCorrection(
        localDay: "2026-07-01",
        start: base,
        end: base + 12 * 60,
        classification: .work
    )
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let today = try #require(ISO8601DateFormatter().date(from: "2026-07-02T12:00:00Z"))

    let status = try fixture.store.reconcileCompletedDays(before: today, calendar: calendar)

    #expect(status.completeDayCount == 1)
    #expect(status.report.totalGamingMinutes == 0)
    #expect(status.report.eligibleDriftCount == 0)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM behavior_records WHERE classification = 'gaming';") == 12)
}

@Test
func migration37AddsNonDestructiveBaselineLedgerAfterCorrectionRules() throws {
    let fixture = try BaselineFixture()
    defer { fixture.remove() }
    #expect(try fixture.scalar("SELECT MAX(version) FROM schema_migrations;") == 37)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'baseline_observation_days';") == 1)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'app_classification_correction_rules';") == 1)
}

private final class BaselineFixture {
    let databaseURL: URL
    let store: BaselineObservationStore

    init() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-observation-\(UUID().uuidString).sqlite")
        store = try BaselineObservationStore(
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_783_800_000) }
        )
    }

    func day(
        _ day: Int,
        coverage: BaselineDayCoverage,
        eligibleDrift: Int = 0
    ) -> BaselineObservationDay {
        BaselineObservationDay(
            localDay: String(format: "2026-07-%02d", day),
            observedMinutes: coverage == .missing ? 0 : 60,
            workMinutes: coverage == .missing ? 0 : 40,
            gamingMinutes: coverage == .missing ? 0 : 10,
            distractingMinutes: coverage == .missing ? 0 : 5,
            unknownMinutes: coverage == .missing ? 0 : 5,
            eligibleDriftCount: eligibleDrift,
            coverage: coverage,
            recordedAt: Date(timeIntervalSince1970: 1_783_800_000 + Double(day))
        )
    }

    func insertObservation(
        localDay: String,
        epoch: Int64,
        classification: BehaviorClassification
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw BaselineObservationStoreError.openDatabase
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let sql = "INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES (?, ?, '12-00-00', 'Fixture', '', '', 0, NULL, '2026-07-08T12:00:00Z', ?, 0);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw BaselineObservationStoreError.openDatabase
        }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        sqlite3_bind_int64(statement, 2, epoch)
        bind(classification.rawValue, statement, 3)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw BaselineObservationStoreError.openDatabase
        }
    }

    func scalar(_ sql: String) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw BaselineObservationStoreError.openDatabase
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw BaselineObservationStoreError.openDatabase
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw BaselineObservationStoreError.openDatabase
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func insertCorrection(
        localDay: String,
        start: Int64,
        end: Int64,
        classification: BehaviorClassification
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw BaselineObservationStoreError.openDatabase
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let sql = "INSERT INTO daily_review_corrections(id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc) VALUES (?, ?, ?, ?, ?, NULL, '2026-07-08T12:00:00Z');"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw BaselineObservationStoreError.openDatabase
        }
        defer { sqlite3_finalize(statement) }
        bind(UUID().uuidString, statement, 1)
        bind(localDay, statement, 2)
        sqlite3_bind_int64(statement, 3, start)
        sqlite3_bind_int64(statement, 4, end)
        bind(classification.rawValue, statement, 5)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw BaselineObservationStoreError.openDatabase
        }
    }

    func remove() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
}
