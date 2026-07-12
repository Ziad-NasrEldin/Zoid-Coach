import Foundation
import SQLite3
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func dailyReviewGroupsCoveredActivityWithoutExposingPrivateFields() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)
    try fixture.insert(epoch: 1_783_663_260, app: "Cursor", classification: .work)
    try fixture.insert(epoch: 1_783_663_900, app: "Steam", classification: .gaming)

    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.sessions.count == 2)
    #expect(snapshot.sessions[0].application == "Cursor")
    #expect(snapshot.sessions[0].observationCount == 2)
    #expect(snapshot.sessions[1].classification == .gaming)
    #expect(snapshot.totals.first { $0.classification == .work }?.minutes == 2)
    #expect(snapshot.totals.first { $0.classification == .gaming }?.minutes == 1)
}

@Test
func dailyReviewKeepsCompletedTasksVisibleAfterTheyLeaveTheActiveList() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    let formatter = DateFormatter()
    formatter.calendar = .current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    let completedAt = formatter.date(from: fixture.sourceDay)!.addingTimeInterval(12 * 3_600)
    let history = try TaskHistoryStore(databaseURL: fixture.databaseURL)
    try history.record(
        taskID: "reminder:launch",
        state: .completed,
        title: "Ship the launch brief",
        sourceKind: .reminders,
        at: completedAt
    )

    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.completedTasks.count == 1)
    #expect(snapshot.completedTasks[0].title == "Ship the launch brief")
    #expect(snapshot.completedTasks[0].sourceKind == .reminders)
    #expect(snapshot.sessions.isEmpty)
}

@Test
func correctionAndTaskAttachmentPersistAndRecalculateTotalsAfterRestart() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "YouTube", classification: .distracting)
    try fixture.insert(epoch: 1_783_663_260, app: "YouTube", classification: .distracting)
    let original = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]

    try fixture.store.correct(original, to: .work, taskID: "Write proposal", from: nil)
    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    let corrected = try reopened.load(sourceDay: fixture.sourceDay)

    #expect(corrected.sessions.count == 1)
    #expect(corrected.sessions[0].classification == .work)
    #expect(corrected.sessions[0].taskID == "Write proposal")
    #expect(corrected.totals == [DailyReviewTotal(classification: .work, minutes: 2)])
}

@Test
func futureClassificationRulePersistsCanBeReplacedAndRemovedWithoutRewritingCorrection() throws {
    let fixedNow = Date(timeIntervalSince1970: 1_783_700_000)
    let fixture = try DailyReviewFixture(now: { fixedNow })
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "YouTube", classification: .distracting)
    let original = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]

    try fixture.store.correct(
        original,
        to: .work,
        taskID: "Research",
        applyToFuture: true
    )
    _ = try fixture.store.upsertClassificationRule(for: original, classification: .gaming)

    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    var rules = try reopened.classificationRules()
    let historical = try reopened.load(sourceDay: fixture.sourceDay)
    #expect(rules.count == 1)
    #expect(rules[0].application == "YouTube")
    #expect(rules[0].normalizedApplication == "youtube")
    #expect(rules[0].classification == .gaming)
    #expect(historical.sessions[0].classification == .work)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM app_classification_correction_rules;") == 2)

    try reopened.removeClassificationRule(normalizedApplication: "  YOUTUBE  ")
    rules = try reopened.classificationRules()
    #expect(rules.isEmpty)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM app_classification_correction_rules;") == 3)
    #expect(try reopened.load(sourceDay: fixture.sourceDay).sessions[0].classification == .work)
}

@Test
func futureClassificationRuleRejectsIdleAndUnknownAsUnsafeAppDefaults() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Safari", classification: .unknown)
    let session = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]

    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.upsertClassificationRule(for: session, classification: .unknown)
    }
    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.upsertClassificationRule(for: session, classification: .idle)
    }
    #expect(throws: DailyReviewStoreError.self) {
        try fixture.store.correct(session, to: .unknown, applyToFuture: true)
    }
    #expect(try fixture.store.classificationRules().isEmpty)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM daily_review_corrections;") == 0)
}

@Test
func splitCorrectionChangesOnlyTheSecondHalfOfASession() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    for offset in [0, 60, 120, 180] {
        try fixture.insert(
            epoch: 1_783_663_200 + Int64(offset),
            app: "Safari",
            classification: .unknown
        )
    }
    let original = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]
    let midpoint = original.start.addingTimeInterval(original.end.timeIntervalSince(original.start) / 2)

    try fixture.store.correct(original, to: .work, taskID: "Research", from: midpoint)
    let corrected = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(corrected.sessions.count == 2)
    #expect(corrected.sessions.map(\.classification) == [.unknown, .work])
    #expect(corrected.sessions[0].taskID == nil)
    #expect(corrected.sessions[1].taskID == "Research")
}

@Test
func hypothesisDecisionAndConfirmationAreDurableAndCorrectionReopensReview() throws {
    let confirmationDate = Date(timeIntervalSince1970: 1_783_700_000)
    let fixture = try DailyReviewFixture(now: { confirmationDate })
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Steam", classification: .gaming)
    let session = try fixture.store.load(sourceDay: fixture.sourceDay).sessions[0]

    try fixture.store.setHypothesisState(.rejected, sourceDay: fixture.sourceDay)
    try fixture.store.confirm(sourceDay: fixture.sourceDay)
    var snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)
    #expect(snapshot.hypothesisState == .rejected)
    #expect(snapshot.confirmedAt == confirmationDate)

    try fixture.store.correct(session, to: .work, taskID: nil, from: nil)
    snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)
    #expect(snapshot.hypothesisState == .pending)
    #expect(snapshot.confirmedAt == nil)
}

@Test
func offlineWorkPersistsAcrossRestartAndRemainsSeparateFromObservedCoverage() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)
    let startedAt = Date(timeIntervalSince1970: 1_783_666_800)

    let id = try fixture.store.saveOfflineWork(
        sourceDay: fixture.sourceDay,
        taskID: "Draft contract",
        startedAt: startedAt,
        durationMinutes: 45,
        note: "Client workshop"
    )
    let reopened = try DailyReviewStore(databaseURL: fixture.databaseURL)
    let snapshot = try reopened.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.offlineWork.count == 1)
    #expect(snapshot.offlineWork[0].id == id)
    #expect(snapshot.offlineWork[0].taskID == "Draft contract")
    #expect(snapshot.offlineWork[0].note == "Client workshop")
    #expect(snapshot.observedMinutes == 1)
    #expect(snapshot.offlineMinutes == 45)
    #expect(snapshot.actualMinutes == 46)
}

@Test
func offlineWorkCanBeCorrectedIdempotentlyAndReopensAConfirmedReview() throws {
    let confirmationDate = Date(timeIntervalSince1970: 1_783_700_000)
    let fixture = try DailyReviewFixture(now: { confirmationDate })
    defer { fixture.remove() }
    let startedAt = Date(timeIntervalSince1970: 1_783_666_800)
    let id = try fixture.store.saveOfflineWork(
        id: "offline-1",
        sourceDay: fixture.sourceDay,
        taskID: nil,
        startedAt: startedAt,
        durationMinutes: 20,
        note: "Unassigned work"
    )
    try fixture.store.confirm(sourceDay: fixture.sourceDay)

    _ = try fixture.store.saveOfflineWork(
        id: id,
        sourceDay: fixture.sourceDay,
        taskID: "Research",
        startedAt: startedAt,
        durationMinutes: 35,
        note: "Corrected after review"
    )
    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.offlineWork.count == 1)
    #expect(snapshot.offlineWork[0].durationMinutes == 35)
    #expect(snapshot.offlineWork[0].taskID == "Research")
    #expect(snapshot.confirmedAt == nil)
}

@Test
func offlineWorkValidatesDurationAndCanBeDeletedWithoutTouchingObservations() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)
    let startedAt = Date(timeIntervalSince1970: 1_783_666_800)

    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.saveOfflineWork(
            sourceDay: fixture.sourceDay,
            taskID: nil,
            startedAt: startedAt,
            durationMinutes: 0,
            note: nil
        )
    }
    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.saveOfflineWork(
            sourceDay: fixture.sourceDay,
            taskID: "   ",
            startedAt: startedAt,
            durationMinutes: 15,
            note: "\n"
        )
    }
    #expect(throws: DailyReviewStoreError.self) {
        _ = try fixture.store.saveOfflineWork(
            sourceDay: fixture.sourceDay,
            taskID: String(repeating: "x", count: 201),
            startedAt: startedAt,
            durationMinutes: 15,
            note: nil
        )
    }
    let id = try fixture.store.saveOfflineWork(
        sourceDay: fixture.sourceDay,
        taskID: "Research",
        startedAt: startedAt,
        durationMinutes: 15,
        note: nil
    )
    try fixture.store.deleteOfflineWork(id: id, sourceDay: fixture.sourceDay)
    let snapshot = try fixture.store.load(sourceDay: fixture.sourceDay)

    #expect(snapshot.offlineWork.isEmpty)
    #expect(snapshot.observedMinutes == 1)
}

@Test
func migrationCreatesReviewTablesWithoutChangingBehaviorEvidence() throws {
    let fixture = try DailyReviewFixture()
    defer { fixture.remove() }
    try fixture.insert(epoch: 1_783_663_200, app: "Cursor", classification: .work)

    let result = try AutonomousDatabaseMigrator(databaseURL: fixture.databaseURL).migrate()

    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM behavior_records;") == 1)
    #expect(try fixture.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('daily_reviews', 'daily_review_corrections', 'offline_work_entries');") == 3)
}

private final class DailyReviewFixture {
    let databaseURL: URL
    let sourceDay = "2026-07-10"
    let store: DailyReviewStore

    init(now: @escaping @Sendable () -> Date = Date.init) throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoid-daily-review-\(UUID().uuidString).sqlite")
        store = try DailyReviewStore(databaseURL: databaseURL, now: now)
    }

    func insert(epoch: Int64, app: String, classification: BehaviorClassification) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else { throw DailyReviewTestError.database }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let sql = "INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES (?, ?, '09:00', ?, 'private title', 'https://private.example', 0, NULL, '2026-07-10T09:00:00Z', ?, 1);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DailyReviewTestError.database }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sourceDay, -1, SQLITE_TRANSIENT_REVIEW)
        sqlite3_bind_int64(statement, 2, epoch)
        sqlite3_bind_text(statement, 3, app, -1, SQLITE_TRANSIENT_REVIEW)
        sqlite3_bind_text(statement, 4, classification.rawValue, -1, SQLITE_TRANSIENT_REVIEW)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DailyReviewTestError.database }
    }

    func scalar(_ sql: String) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { throw DailyReviewTestError.database }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DailyReviewTestError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DailyReviewTestError.database }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func remove() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
}

private enum DailyReviewTestError: Error { case database }

private let SQLITE_TRANSIENT_REVIEW = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
