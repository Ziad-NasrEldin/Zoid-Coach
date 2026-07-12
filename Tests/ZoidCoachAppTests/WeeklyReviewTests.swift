import Foundation
import SQLite3
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func weeklyReviewWithTwoCoveredDaysShowsDataQualityInsteadOfConclusions() throws {
    let databaseURL = weeklyTemporaryDatabaseURL("limited")
    defer { weeklyRemoveDatabaseFiles(at: databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    try insertCoveredDay(databaseURL, day: "2026-06-30", epoch: 1_751_328_000)
    try insertCoveredDay(databaseURL, day: "2026-07-01", epoch: 1_751_414_400)

    let store = try WeeklyReviewStore(
        databaseURL: databaseURL,
        calendar: weeklyCalendar,
        now: { weeklyReferenceDate }
    )
    let snapshot = try store.load()

    #expect(snapshot.dateRange == WeeklyReviewDateRange(startDay: "2026-06-29", endDay: "2026-07-05"))
    #expect(snapshot.coveredDays == 2)
    #expect(snapshot.quality == .limited)
    #expect(snapshot.patterns.isEmpty)
    #expect(snapshot.experiment == nil)
    #expect(snapshot.qualityExplanation.contains("1 more day"))
}

@Test
func weeklyReviewAggregatesOutcomesPatternsAndOnlyOneExperiment() throws {
    let databaseURL = weeklyTemporaryDatabaseURL("sufficient")
    defer { weeklyRemoveDatabaseFiles(at: databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    for (offset, day) in ["2026-06-30", "2026-07-01", "2026-07-02"].enumerated() {
        try insertCoveredDay(databaseURL, day: day, epoch: 1_751_328_000 + Int64(offset * 86_400))
    }
    try weeklyExecute(databaseURL, """
    INSERT INTO daily_plans(id, local_day, timezone_identifier, state, capacity_minutes, usable_capacity_minutes, policy_version, generated_at_utc, delayed_after_wake)
    VALUES ('plan-1', '2026-07-01', 'Africa/Cairo', 'accepted', 300, 240, 1, '2026-07-01T05:00:00Z', 0);
    INSERT INTO daily_plan_items(id, plan_id, source_task_id, rank, estimate_minutes, estimate_confidence, reason, evidence_ids_json, is_main_objective, state)
    VALUES ('item-1', 'plan-1', 'task-1', 1, 45, 'high', 'Due today', '[]', 1, 'completed'),
           ('item-2', 'plan-1', 'task-2', 2, 30, 'medium', 'Available', '[]', 0, 'pending');
    INSERT INTO task_history(task_id, state, occurred_at)
    VALUES ('task-blocked', 'blocked', '2026-07-01T08:00:00Z'),
           ('task-blocked', 'blocked', '2026-07-02T08:00:00Z');
    INSERT INTO prompt_episodes(id, decision_key, prompt_type, state, title, summary, action_token, payload_json, created_at_utc)
    VALUES ('prompt-1', 'weekly-prompt-1', 'RECOVERY', 'responded', 'Return gently', 'Choose one next step', 'prompt-token-1', '{}', '2026-07-02T09:00:00Z');
    INSERT INTO prompt_responses(id, prompt_id, action_token, response, surface, responded_at_utc)
    VALUES ('response-1', 'prompt-1', 'response-token-1', 'smaller_step', 'today', '2026-07-02T09:05:00Z');
    INSERT INTO prompt_response_effects(response_id, prompt_id, effect_type, state, created_at_utc, updated_at_utc)
    VALUES ('response-1', 'prompt-1', 'smaller_step', 'applied', '2026-07-02T09:05:00Z', '2026-07-02T09:06:00Z');
    INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, ingested_at, classification)
    VALUES ('2026-07-02', CAST(strftime('%s', '2026-07-02T09:10:00Z') AS INTEGER), '12:10', 'Code', '', '', 0, '2026-07-02T09:10:00Z', 'work');
    """)
    try recordWeeklyLearningEvidence(databaseURL, dayOffset: 0)

    let store = try WeeklyReviewStore(
        databaseURL: databaseURL,
        calendar: weeklyCalendar,
        now: { weeklyReferenceDate }
    )
    let first = try store.load()
    let second = try store.load()

    #expect(first.quality == .sufficient)
    #expect(first.coveredDays == 3)
    #expect(first.outcomes.plannedTasks == 2)
    #expect(first.outcomes.completedTasks == 1)
    #expect(first.outcomes.completedPercent == 50)
    #expect(first.patterns.contains(where: { $0.kind == .estimateAccuracy }))
    #expect(first.patterns.contains(where: { $0.kind == .bestWorkWindow }))
    #expect(first.patterns.contains(where: { $0.kind == .driftTrigger }))
    #expect(first.patterns.contains(where: { $0.kind == .gamingBudget }))
    #expect(first.patterns.contains(where: { $0.kind == .promptUsefulness }))
    #expect(first.patterns.contains(where: { $0.kind == .promptRecovery }))
    #expect(first.patterns.contains(where: { $0.kind == .blockedTasks }))
    #expect(first.patterns.first(where: { $0.kind == .gamingBudget })?.examples.first?.contains("first observed") == true)
    #expect(first.patterns.first(where: { $0.kind == .promptRecovery })?.conclusion.contains("1 of 1") == true)
    #expect(first.patterns.first(where: { $0.kind == .promptRecovery })?.examples.first?.contains("within 30 minutes") == true)
    #expect(first.patterns.allSatisfy { !$0.alternativeExplanation.isEmpty && $0.sampleCount > 0 })
    #expect(first.experiment?.state == .proposed)
    #expect(second.experiment?.id == first.experiment?.id)
    #expect(try weeklyScalarInt(databaseURL, "SELECT COUNT(*) FROM weekly_review_experiments;") == 1)
}

@Test
func weeklyReviewDoesNotUseLearningEvidenceOutsideThePriorWeek() throws {
    let databaseURL = weeklyTemporaryDatabaseURL("stable-window")
    defer { weeklyRemoveDatabaseFiles(at: databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    for (offset, day) in ["2026-06-30", "2026-07-01", "2026-07-02"].enumerated() {
        try insertCoveredDay(databaseURL, day: day, epoch: 1_751_328_000 + Int64(offset * 86_400))
    }
    try recordWeeklyLearningEvidence(databaseURL, dayOffset: -14)
    try recordWeeklyLearningEvidence(databaseURL, dayOffset: 8)

    let snapshot = try WeeklyReviewStore(
        databaseURL: databaseURL,
        calendar: weeklyCalendar,
        now: { weeklyReferenceDate }
    ).load()

    #expect(!snapshot.patterns.contains(where: { $0.kind == .estimateAccuracy }))
    #expect(!snapshot.patterns.contains(where: { $0.kind == .bestWorkWindow }))
}

@Test
func weeklyDriftPatternUsesCorrectedSessionsInsteadOfRawClassifications() throws {
    let databaseURL = weeklyTemporaryDatabaseURL("corrections")
    defer { weeklyRemoveDatabaseFiles(at: databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    for (offset, day) in ["2026-06-30", "2026-07-01", "2026-07-02"].enumerated() {
        let epoch = 1_751_328_000 + Int64(offset * 86_400)
        try insertCoveredDay(databaseURL, day: day, epoch: epoch)
        try weeklyExecute(databaseURL, """
        INSERT INTO daily_review_corrections(id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc)
        VALUES ('correction-\(offset)', '\(day)', \(epoch + 1800), \(epoch + 3600), 'work', NULL, '\(day)T19:00:00Z');
        """)
    }
    try weeklyExecute(databaseURL, """
    INSERT INTO learning_aggregates(aggregate_type, aggregate_key, sample_count, median_value, confidence, policy_version, updated_at_utc)
    VALUES ('estimate', 'coding|medium', 4, 1.05, 0.72, 1, '2026-07-05T18:00:00Z');
    """)

    let snapshot = try WeeklyReviewStore(
        databaseURL: databaseURL,
        calendar: weeklyCalendar,
        now: { weeklyReferenceDate }
    ).load()
    let drift = try #require(snapshot.patterns.first(where: { $0.kind == .driftTrigger }))

    #expect(drift.examples.contains(where: { $0.contains("Messages") }))
    #expect(!drift.examples.contains(where: { $0.contains("Game") }))
}

@Test
func weeklyExperimentEditAcceptRejectAndTrackingSurviveStoreRestart() throws {
    let databaseURL = weeklyTemporaryDatabaseURL("experiment")
    defer { weeklyRemoveDatabaseFiles(at: databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    for (offset, day) in ["2026-06-30", "2026-07-01", "2026-07-02"].enumerated() {
        try insertCoveredDay(databaseURL, day: day, epoch: 1_751_328_000 + Int64(offset * 86_400))
    }
    try weeklyExecute(databaseURL, """
    INSERT INTO learning_aggregates(aggregate_type, aggregate_key, sample_count, median_value, confidence, policy_version, updated_at_utc)
    VALUES ('estimate', 'writing|medium', 6, 1.20, 0.88, 1, '2026-07-05T18:00:00Z');
    """)
    let store = try WeeklyReviewStore(databaseURL: databaseURL, calendar: weeklyCalendar, now: { weeklyReferenceDate })
    let id = try #require(store.load().experiment?.id)

    let edited = try store.editExperiment(
        id: id,
        title: "Protect the first task",
        instruction: "Start the first task before opening messages.",
        measurement: "Count covered days with a focused first interval."
    )
    #expect(edited.title == "Protect the first task")
    #expect(edited.state == .proposed)

    let accepted = try store.acceptExperiment(id: id)
    #expect(accepted.state == .accepted)
    #expect(accepted.trackingWeekStart == "2026-07-06")

    let restarted = try WeeklyReviewStore(databaseURL: databaseURL, calendar: weeklyCalendar, now: { weeklyReferenceDate })
    let tracked = try #require(restarted.load().experiment)
    #expect(tracked.state == .accepted)
    #expect(tracked.title == "Protect the first task")
    #expect(tracked.trackingDaysCompleted == 3)

    let rejected = try restarted.rejectExperiment(id: id)
    #expect(rejected.state == .rejected)
    #expect(rejected.trackingWeekStart == nil)
    #expect(try WeeklyReviewStore(databaseURL: databaseURL, calendar: weeklyCalendar, now: { weeklyReferenceDate }).load().experiment?.state == .rejected)
}

@Test
func weeklyExperimentRejectsBlankOrUnboundedEditsWithoutChangingStoredProposal() throws {
    let databaseURL = weeklyTemporaryDatabaseURL("validation")
    defer { weeklyRemoveDatabaseFiles(at: databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    for (offset, day) in ["2026-06-30", "2026-07-01", "2026-07-02"].enumerated() {
        try insertCoveredDay(databaseURL, day: day, epoch: 1_751_328_000 + Int64(offset * 86_400))
    }
    try weeklyExecute(databaseURL, """
    INSERT INTO learning_aggregates(aggregate_type, aggregate_key, sample_count, median_value, confidence, policy_version, updated_at_utc)
    VALUES ('estimate', 'planning|medium', 4, 1.10, 0.75, 1, '2026-07-05T18:00:00Z');
    """)
    let store = try WeeklyReviewStore(databaseURL: databaseURL, calendar: weeklyCalendar, now: { weeklyReferenceDate })
    let original = try #require(store.load().experiment)

    #expect(throws: WeeklyReviewStoreError.self) {
        try store.editExperiment(id: original.id, title: " ", instruction: "Do one thing", measurement: "Count it")
    }
    #expect(throws: WeeklyReviewStoreError.self) {
        try store.editExperiment(id: original.id, title: String(repeating: "x", count: 121), instruction: "Do one thing", measurement: "Count it")
    }
    #expect(try store.load().experiment?.title == original.title)
}

private let weeklyReferenceDate = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!

private var weeklyCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: "Africa/Cairo")!
    calendar.firstWeekday = 2
    return calendar
}

private func insertCoveredDay(_ databaseURL: URL, day: String, epoch: Int64) throws {
    try weeklyExecute(databaseURL, """
    INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc)
    VALUES ('\(day)', 'accepted', '\(day)T18:00:00Z', '\(day)T18:00:00Z');
    INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, ingested_at, classification)
    VALUES ('\(day)', \(epoch), '09:00', 'Code', '', '', 0, '\(day)T09:00:00Z', 'work'),
           ('\(day)', \(epoch + 1800), '09:30', 'Game', '', '', 0, '\(day)T09:30:00Z', 'gaming'),
           ('\(day)', \(epoch + 3600), '10:00', 'Messages', '', '', 0, '\(day)T10:00:00Z', 'distracting');
    """)
}

private func recordWeeklyLearningEvidence(_ databaseURL: URL, dayOffset: Int) throws {
    let store = try LearningAggregateStore(databaseURL: databaseURL)
    let context = EstimateLearningContext(taskType: "coding", project: "Zoid 666")
    let base = try #require(weeklyCalendar.date(byAdding: .day, value: dayOffset, to: ISO8601DateFormatter().date(from: "2026-06-30T08:00:00Z")!))
    for index in 0..<5 {
        let startedAt = try #require(weeklyCalendar.date(byAdding: .day, value: index % 3, to: base))
        let completedAt = startedAt.addingTimeInterval(45 * 60)
        _ = try store.recordEstimateSample(EstimateLearningSample(
            id: "estimate-\(dayOffset)-\(index)",
            context: context,
            estimatedMinutes: 30,
            actualAlignedMinutes: 45,
            trackingCoverage: 0.9,
            completedAt: completedAt
        ))
        _ = try store.recordWorkWindowSample(WorkWindowLearningSample(
            id: "window-\(dayOffset)-\(index)",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(90 * 60),
            trackingCoverage: 0.9
        ), timeZoneIdentifier: "Africa/Cairo")
    }
}

private func weeklyTemporaryDatabaseURL(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-weekly-\(label)-\(UUID().uuidString).sqlite")
}

private func weeklyRemoveDatabaseFiles(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}

private func weeklyExecute(_ url: URL, _ sql: String) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw WeeklyTestDatabaseError.open }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw WeeklyTestDatabaseError.sql(String(cString: sqlite3_errmsg(database)))
    }
}

private func weeklyScalarInt(_ url: URL, _ sql: String) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw WeeklyTestDatabaseError.open }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw WeeklyTestDatabaseError.sql("prepare") }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw WeeklyTestDatabaseError.sql("row") }
    return Int(sqlite3_column_int(statement, 0))
}

private enum WeeklyTestDatabaseError: Error {
    case open
    case sql(String)
}
