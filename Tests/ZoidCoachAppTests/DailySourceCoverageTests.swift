import Foundation
import SQLite3
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func coverageSeparatesActiveObservedAlignedUnknownAndMissingTime() throws {
    let fixture = try CoverageFixture()
    defer { fixture.remove() }
    try fixture.insertTaskInterval(startMinute: 0, endMinute: 60)
    for minute in 0..<50 { try fixture.insertObservation(minute: minute, classification: .work) }
    for minute in 50..<60 { try fixture.insertObservation(minute: minute, classification: .unknown) }
    try fixture.insertSource(state: "healthy", detail: "Current local records", checkedMinute: 61)

    let coverage = try fixture.load()

    #expect(coverage.activeTaskMinutes == 60)
    #expect(coverage.observedTaskMinutes == 60)
    #expect(coverage.alignedTaskMinutes == 50)
    #expect(coverage.missingTaskMinutes == 0)
    #expect(coverage.workMinutes == 50)
    #expect(coverage.unknownMinutes == 10)
    #expect(coverage.distractingMinutes == 0)
    #expect(coverage.unknownSharePercent == 17)
    #expect(coverage.precision == .approximate)
}

@Test
func incompleteCoverageRoundsTotalsAndNeverClassifiesMissingTime() throws {
    let fixture = try CoverageFixture()
    defer { fixture.remove() }
    try fixture.insertTaskInterval(startMinute: 0, endMinute: 60)
    for minute in 0..<20 { try fixture.insertObservation(minute: minute, classification: .work) }
    try fixture.insertSource(state: "stale", detail: "No new records", checkedMinute: 61)

    let coverage = try fixture.load()

    #expect(coverage.coveragePercent == 33)
    #expect(coverage.missingTaskMinutes == 40)
    #expect(coverage.workMinutes == 20)
    #expect(coverage.gamingMinutes == 0)
    #expect(coverage.distractingMinutes == 0)
    #expect(coverage.isLowCoverage)
    #expect(coverage.displayMinutes(coverage.workMinutes) == "about 20 min observed")
    #expect(coverage.missingExplanation.contains("not counted as work, gaming, or distraction"))
}

@Test
func coverageWithoutAnActiveTaskRefusesToInventWholeDayMissingMinutes() throws {
    let fixture = try CoverageFixture()
    defer { fixture.remove() }
    for minute in 0..<15 { try fixture.insertObservation(minute: minute, classification: .distracting) }

    let coverage = try fixture.load()

    #expect(coverage.activeTaskMinutes == 0)
    #expect(coverage.coveragePercent == nil)
    #expect(coverage.missingTaskMinutes == 0)
    #expect(coverage.missingExplanation.contains("cannot estimate whole-day missing time"))
}

@Test
func idleIsReliableOnlyWithHealthyAdequateCoverage() throws {
    let healthy = try CoverageFixture()
    defer { healthy.remove() }
    try healthy.insertTaskInterval(startMinute: 0, endMinute: 60)
    for minute in 0..<55 { try healthy.insertObservation(minute: minute, classification: .work) }
    for minute in 55..<60 { try healthy.insertObservation(minute: minute, classification: .idle) }
    try healthy.insertSource(state: "healthy", detail: "Current", checkedMinute: 61)
    #expect(try healthy.load().idleIsReliable)

    let stale = try CoverageFixture()
    defer { stale.remove() }
    try stale.insertTaskInterval(startMinute: 0, endMinute: 60)
    for minute in 0..<55 { try stale.insertObservation(minute: minute, classification: .work) }
    for minute in 55..<60 { try stale.insertObservation(minute: minute, classification: .idle) }
    try stale.insertSource(state: "stale", detail: "Stopped", checkedMinute: 61)
    #expect(try stale.load().idleIsReliable == false)
}

@Test
func missingSourceCheckpointKeepsOtherwiseCompleteCoverageApproximate() throws {
    let fixture = try CoverageFixture()
    defer { fixture.remove() }
    try fixture.insertTaskInterval(startMinute: 0, endMinute: 60)
    for minute in 0..<55 { try fixture.insertObservation(minute: minute, classification: .work) }
    for minute in 55..<60 { try fixture.insertObservation(minute: minute, classification: .idle) }

    let coverage = try fixture.load()

    #expect(coverage.coveragePercent == 100)
    #expect(coverage.precision == .approximate)
    #expect(coverage.isLowCoverage)
    #expect(coverage.idleIsReliable == false)
}

@Test
func reviewCorrectionsChangeCoverageCategoriesWithoutRewritingSourceEvidence() throws {
    let fixture = try CoverageFixture()
    defer { fixture.remove() }
    try fixture.insertTaskInterval(startMinute: 0, endMinute: 30)
    for minute in 0..<30 { try fixture.insertObservation(minute: minute, classification: .gaming) }
    try fixture.insertCorrection(startMinute: 0, endMinute: 30, classification: .work)
    try fixture.insertSource(state: "healthy", detail: "Current", checkedMinute: 31)

    let coverage = try fixture.load()

    #expect(coverage.workMinutes == 30)
    #expect(coverage.gamingMinutes == 0)
    #expect(coverage.alignedTaskMinutes == 30)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM behavior_records WHERE classification = 'gaming';") == 30)
}

@Test
func newestScreenwatchCheckpointExplainsTheCoverageProblemAfterRestart() throws {
    let fixture = try CoverageFixture()
    defer { fixture.remove() }
    try fixture.insertSource(state: "healthy", detail: "Was current", checkedMinute: 10)
    try fixture.insertSource(state: "stale", detail: "No record for 20 minutes", checkedMinute: 30)

    var coverage = try fixture.load()
    #expect(coverage.source?.state == "stale")
    #expect(coverage.source?.detail == "No record for 20 minutes")

    let reopened = try DailySourceCoverageStore(databaseURL: fixture.databaseURL, now: { fixture.dayEnd })
    coverage = try reopened.load(day: fixture.day, calendar: fixture.calendar)
    #expect(coverage.source?.state == "stale")
    #expect(coverage.source?.detail == "No record for 20 minutes")
}

@Test
func historicalCoverageNeverUsesASourceCheckpointFromALaterDay() throws {
    let fixture = try CoverageFixture()
    defer { fixture.remove() }
    try fixture.insertSource(state: "healthy", detail: "Historical day was current", checkedMinute: 10)
    try fixture.insertSource(state: "stale", detail: "A later day became stale", checkedMinute: 24 * 60 + 10)

    let coverage = try fixture.load()

    #expect(coverage.source?.state == "healthy")
    #expect(coverage.source?.detail == "Historical day was current")
}

@MainActor
@Test
func selectedDayGenerationPreventsAnOlderLoadFromReplacingTheNewDay() async throws {
    let firstDay = Date(timeIntervalSince1970: 1_780_000_000)
    let secondDay = firstDay.addingTimeInterval(86_400)
    let firstStarted = DispatchSemaphore(value: 0)
    let releaseFirst = DispatchSemaphore(value: 0)
    let controller = DailySourceCoverageController(loader: { day, _ in
        if day == firstDay {
            firstStarted.signal()
            releaseFirst.wait()
            return coverageResult(day: "first")
        }
        return coverageResult(day: "second")
    })

    let firstLoad = try #require(controller.load(day: firstDay))
    await Task.detached { firstStarted.wait() }.value
    let secondLoad = try #require(controller.load(day: secondDay))
    await secondLoad.value
    releaseFirst.signal()
    await firstLoad.value

    #expect(controller.coverage?.localDay == "second")
    #expect(controller.errorMessage == nil)
    #expect(controller.isLoading == false)
}

@MainActor
@Test
func retryReplacesCoverageErrorWithFreshSelectedDayEvidence() async throws {
    let attempts = LockedAttemptCounter()
    let controller = DailySourceCoverageController(loader: { _, _ in
        if attempts.next() == 1 { throw DailySourceCoverageStoreError.openDatabase }
        return coverageResult(day: "recovered")
    })
    let day = Date(timeIntervalSince1970: 1_780_000_000)

    let failedLoad = try #require(controller.load(day: day))
    await failedLoad.value
    #expect(controller.errorMessage != nil)
    #expect(controller.coverage == nil)

    let retryLoad = try #require(controller.load(day: day))
    await retryLoad.value
    #expect(controller.coverage?.localDay == "recovered")
    #expect(controller.errorMessage == nil)
}

private final class LockedAttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private func coverageResult(day: String) -> DailySourceCoverage {
    DailySourceCoverage(
        localDay: day,
        activeTaskMinutes: 0,
        observedTaskMinutes: 0,
        alignedTaskMinutes: 0,
        missingTaskMinutes: 0,
        workMinutes: 0,
        gamingMinutes: 0,
        distractingMinutes: 0,
        idleMinutes: 0,
        unknownMinutes: 0,
        source: nil
    )
}

private final class CoverageFixture: @unchecked Sendable {
    let databaseURL: URL
    let day: Date
    let dayEnd: Date
    var calendar: Calendar
    private let formatter = ISO8601DateFormatter()
    private let dayKey = "2026-07-10"

    init() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-source-coverage-\(UUID().uuidString).sqlite")
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        day = try #require(formatter.date(from: "2026-07-10T00:00:00Z"))
        dayEnd = try #require(formatter.date(from: "2026-07-11T00:00:00Z"))
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    }

    func load() throws -> DailySourceCoverage {
        let store = try DailySourceCoverageStore(databaseURL: databaseURL, now: { self.dayEnd })
        return try store.load(day: day, calendar: calendar)
    }

    func insertObservation(minute: Int, classification: BehaviorClassification) throws {
        try execute(
            "INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES (?, ?, '00-00-00', 'Fixture', '', '', 0, NULL, '2026-07-10T00:00:00Z', ?, 0);",
            textBindings: [1: dayKey, 3: classification.rawValue],
            intBindings: [2: Int64(day.timeIntervalSince1970) + Int64(minute * 60)]
        )
    }

    func insertTaskInterval(startMinute: Int, endMinute: Int) throws {
        try execute(
            "INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES ('task', ?, ?);",
            textBindings: [
                1: formatter.string(from: day.addingTimeInterval(TimeInterval(startMinute * 60))),
                2: formatter.string(from: day.addingTimeInterval(TimeInterval(endMinute * 60)))
            ]
        )
    }

    func insertCorrection(startMinute: Int, endMinute: Int, classification: BehaviorClassification) throws {
        try execute(
            "INSERT INTO daily_review_corrections(id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc) VALUES (?, ?, ?, ?, ?, NULL, '2026-07-11T00:00:00Z');",
            textBindings: [1: UUID().uuidString, 2: dayKey, 5: classification.rawValue],
            intBindings: [
                3: Int64(day.timeIntervalSince1970) + Int64(startMinute * 60),
                4: Int64(day.timeIntervalSince1970) + Int64(endMinute * 60)
            ]
        )
    }

    func insertSource(state: String, detail: String, checkedMinute: Int) throws {
        try execute(
            "INSERT INTO source_checkpoints(source_id, state, detail, evidence, checked_at) VALUES ('screenwatch-canonical-source', ?, ?, 'Local fixture source', ?);",
            textBindings: [
                1: state,
                2: detail,
                3: formatter.string(from: day.addingTimeInterval(TimeInterval(checkedMinute * 60)))
            ]
        )
    }

    func scalar(_ sql: String) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw DailySourceCoverageStoreError.openDatabase
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DailySourceCoverageStoreError.openDatabase
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DailySourceCoverageStoreError.openDatabase }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func remove() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }

    private func execute(
        _ sql: String,
        textBindings: [Int32: String] = [:],
        intBindings: [Int32: Int64] = [:]
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw DailySourceCoverageStoreError.openDatabase
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DailySourceCoverageStoreError.openDatabase
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in textBindings {
            _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        }
        for (index, value) in intBindings { sqlite3_bind_int64(statement, index, value) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DailySourceCoverageStoreError.openDatabase }
    }
}
