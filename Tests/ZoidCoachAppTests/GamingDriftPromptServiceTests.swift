import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func gamingDriftStaysQuietUntilBaselineCompletesThenQueuesEvidenceFirstPrompt() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)

    #expect(try fixture.service.produce(
        policy: fixture.policy(),
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline(completeDays: 6)
    ) == .suppressed(.observingBaseline))
    #expect(try fixture.promptStore.unresolved().isEmpty)

    let result = try fixture.service.produce(
        policy: fixture.policy(),
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline(completeDays: 7)
    )
    guard case let .queued(episode, wasInserted) = result else {
        Issue.record("Expected a queued coaching prompt")
        return
    }
    #expect(wasInserted)
    #expect(episode.type == "GAMING_DRIFT")
    #expect(episode.summary.contains("10 minutes in Steam"))
    #expect(episode.summary.contains("Ship client proposal remains unfinished"))
    #expect(episode.actions.first?.kind == .returnToActiveTask)
    #expect(episode.actions.first?.role == .primary)
    #expect(episode.payload["coachingLevel"] == CoachingLevel.gentle.rawValue)
    #expect(try fixture.promptStore.unresolved().count == 1)

    let reopened = try PromptInboxStore(databaseURL: fixture.databaseURL, now: { fixture.clock.now })
    #expect(try reopened.unresolved().first?.id == episode.id)
}

@Test
func gamingDriftRequiresTenFreshCertainMinutesAndAnExhaustedAllowance() throws {
    let short = try GamingPromptFixture()
    defer { short.remove() }
    try short.insertPriorityTask()
    try short.insertGaming(minutes: 9)
    #expect(try short.service.produce(
        policy: short.policy(), gamingStatus: short.gamingStatus, baselineStatus: short.baseline()
    ) == .suppressed(.belowThreshold))

    let uncertain = try GamingPromptFixture()
    defer { uncertain.remove() }
    try uncertain.insertPriorityTask()
    try uncertain.insertGaming(minutes: 10)
    #expect(try uncertain.service.produce(
        policy: uncertain.policy(),
        gamingStatus: GamingStatus(
            budgetMinutes: 0,
            usedMinutes: 10,
            unlockedRemainingMinutes: 0,
            nextUnlockReason: "",
            confidenceIsLimited: true
        ),
        baselineStatus: uncertain.baseline()
    ) == .suppressed(.limitedCoverage))

    let unlocked = try GamingPromptFixture()
    defer { unlocked.remove() }
    try unlocked.insertPriorityTask()
    try unlocked.insertGaming(minutes: 10)
    #expect(try unlocked.service.produce(
        policy: unlocked.policy(),
        gamingStatus: GamingStatus(
            budgetMinutes: 60,
            usedMinutes: 10,
            unlockedRemainingMinutes: 50,
            nextUnlockReason: "",
            confidenceIsLimited: false
        ),
        baselineStatus: unlocked.baseline()
    ) == .suppressed(.gamingIsUnlocked))
}

@Test
func gamingDriftHonorsPauseWorkWindowBreakEndDayAndIncompleteWorkGates() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)

    #expect(try fixture.service.produce(
        policy: fixture.policy(paused: true), gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.automationPaused))
    #expect(try fixture.service.produce(
        policy: fixture.policy(workStart: LocalTime(hour: 12, minute: 0)),
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.outsideWorkWindow))

    try fixture.insertOpenPause(.break)
    #expect(try fixture.service.produce(
        policy: fixture.policy(), gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.acceptedBreak))
    try fixture.closePauses()
    try fixture.insertOpenPause(.endingWorkday)
    #expect(try fixture.service.produce(
        policy: fixture.policy(), gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.workdayClosed))

    let noPlan = try GamingPromptFixture()
    defer { noPlan.remove() }
    try noPlan.insertGaming(minutes: 10)
    #expect(try noPlan.service.produce(
        policy: noPlan.policy(), gamingStatus: noPlan.gamingStatus, baselineStatus: noPlan.baseline()
    ) == .suppressed(.noIncompletePriorityWork))
}

@Test
func gamingDriftUsesCorrectionsAndDoesNotRepeatTheSameSession() throws {
    let corrected = try GamingPromptFixture()
    defer { corrected.remove() }
    try corrected.insertPriorityTask()
    try corrected.insertGaming(minutes: 10)
    try corrected.correctCurrentSession(to: .work)
    #expect(try corrected.service.produce(
        policy: corrected.policy(), gamingStatus: corrected.gamingStatus, baselineStatus: corrected.baseline()
    ) == .suppressed(.noGamingSession))

    let deduped = try GamingPromptFixture()
    defer { deduped.remove() }
    try deduped.insertPriorityTask()
    try deduped.insertGaming(minutes: 10)
    guard case .queued = try deduped.service.produce(
        policy: deduped.policy(), gamingStatus: deduped.gamingStatus, baselineStatus: deduped.baseline()
    ) else {
        Issue.record("Expected first prompt")
        return
    }
    #expect(try deduped.service.produce(
        policy: deduped.policy(), gamingStatus: deduped.gamingStatus, baselineStatus: deduped.baseline()
    ) == .suppressed(.intentionalOverrideActive))
    #expect(try deduped.promptStore.unresolved().count == 1)
}

@Test
func intentionalGamingOverrideEndsOnWorkAndExpiresAcrossRestart() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .accountability)
    guard case let .queued(episode, _) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the initial accountability prompt")
        return
    }

    _ = try fixture.promptStore.respond(
        promptID: episode.id,
        action: .continueIntentionally,
        actionToken: PromptResponseToken.make(
            promptID: episode.id,
            action: .continueIntentionally
        ),
        surface: .dashboard
    )
    #expect(try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.intentionalOverrideActive))

    fixture.advance(minutes: 5)
    try fixture.insertWork(minutes: 1)
    #expect(try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.noGamingSession))

    fixture.advance(minutes: 56)
    try fixture.insertGaming(minutes: 10)
    let reopenedStore = try PromptInboxStore(
        databaseURL: fixture.databaseURL,
        now: { [clock = fixture.clock] in clock.now }
    )
    let restartedService = try GamingDriftPromptService(
        databaseURL: fixture.databaseURL,
        promptStore: reopenedStore,
        now: { [clock = fixture.clock] in clock.now }
    )
    guard case let .queued(reprompt, wasInserted) = try restartedService.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected normal coaching after the override window")
        return
    }
    #expect(wasInserted)
    #expect(reprompt.id != episode.id)
    #expect(reprompt.actions.contains { $0.kind == .continueIntentionally })
}

@Test
func resolvedGamingPromptStillDeduplicatesAndEnforcesCooldownAfterRestart() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .accountability)
    guard case let .queued(episode, _) = try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected the first accountability prompt")
        return
    }

    _ = try fixture.promptStore.respond(
        promptID: episode.id,
        action: .continueIntentionally,
        actionToken: PromptResponseToken.make(
            promptID: episode.id,
            action: .continueIntentionally
        ),
        surface: .dashboard
    )
    #expect(try fixture.service.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.sessionAlreadyHandled))

    fixture.advance(minutes: 30)
    try fixture.insertGaming(minutes: 10)
    let reopenedStore = try PromptInboxStore(
        databaseURL: fixture.databaseURL,
        now: { [clock = fixture.clock] in clock.now }
    )
    let restartedService = try GamingDriftPromptService(
        databaseURL: fixture.databaseURL,
        promptStore: reopenedStore,
        now: { [clock = fixture.clock] in clock.now }
    )
    #expect(try restartedService.produce(
        policy: policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline()
    ) == .suppressed(.cooldownActive))
}

@Test
func coachingLevelEnforcesCooldownAndDailyPromptLimitAcrossSeparateSessions() throws {
    let fixture = try GamingPromptFixture()
    defer { fixture.remove() }
    try fixture.insertPriorityTask()
    try fixture.insertGaming(minutes: 10)
    let policy = fixture.policy(level: .accountability)
    guard case .queued = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected first accountability prompt")
        return
    }

    fixture.advance(minutes: 30)
    try fixture.insertGaming(minutes: 10)
    #expect(try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) == .suppressed(.cooldownActive))

    fixture.advance(minutes: 31)
    try fixture.insertGaming(minutes: 10)
    guard case .queued = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected second accountability prompt after cooldown")
        return
    }
    fixture.advance(minutes: 61)
    try fixture.insertGaming(minutes: 10)
    guard case .queued = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    ) else {
        Issue.record("Expected third accountability prompt")
        return
    }
    fixture.advance(minutes: 61)
    try fixture.insertGaming(minutes: 10)
    let fourth = try fixture.service.produce(
        policy: policy, gamingStatus: fixture.gamingStatus, baselineStatus: fixture.baseline()
    )
    #expect(fourth == .suppressed(.dailyLimitReached), "Unexpected fourth result: \(fourth)")
    #expect(try fixture.promptStore.unresolved().isEmpty)
}

@Test
func legacyGamingPolicyDefaultsToGentleCoaching() throws {
    let data = Data(#"{"version":1,"dailyBudgetMinutes":60,"priorityTaskRewardMinutes":15}"#.utf8)
    let decoded = try JSONDecoder().decode(GamingPolicy.self, from: data)
    #expect(decoded.coachingLevel == .gentle)
}

private final class GamingPromptFixture: @unchecked Sendable {
    final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    let databaseURL: URL
    let clock: Clock
    let promptStore: PromptInboxStore
    let service: GamingDriftPromptService
    let gamingStatus = GamingStatus(
        budgetMinutes: 0,
        usedMinutes: 10,
        unlockedRemainingMinutes: 0,
        nextUnlockReason: "Finish priority work",
        confidenceIsLimited: false
    )

    init() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gaming-prompt-\(UUID().uuidString).sqlite")
        clock = Clock(try #require(ISO8601DateFormatter().date(from: "2026-07-13T10:00:00Z")))
        promptStore = try PromptInboxStore(databaseURL: databaseURL, now: { [clock] in clock.now })
        service = try GamingDriftPromptService(
            databaseURL: databaseURL,
            promptStore: promptStore,
            now: { [clock] in clock.now }
        )
    }

    func remove() { try? FileManager.default.removeItem(at: databaseURL) }

    func advance(minutes: Int) {
        clock.now = clock.now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    func baseline(completeDays: Int = 7) -> BaselineObservationStatus {
        BaselineObservationStatus(
            days: (0..<completeDays).map { offset in
                BaselineObservationDay(
                    localDay: String(format: "2026-07-%02d", offset + 1),
                    observedMinutes: 60,
                    workMinutes: 45,
                    gamingMinutes: 10,
                    distractingMinutes: 0,
                    unknownMinutes: 5,
                    eligibleDriftCount: 0,
                    coverage: .complete,
                    recordedAt: clock.now
                )
            },
            report: BaselineObservationReport(
                averageObservedWorkMinutes: 45,
                gamingDayCount: completeDays,
                totalGamingMinutes: completeDays * 10,
                eligibleDriftCount: 0,
                unknownSharePercent: 8
            )
        )
    }

    func policy(
        paused: Bool = false,
        workStart: LocalTime = LocalTime(hour: 8, minute: 0),
        level: CoachingLevel = .gentle
    ) -> UserPolicy {
        let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
        return UserPolicy(
            operatingMode: .suggest,
            automationPause: paused ? .pausedIndefinitely : .running,
            schedule: SchedulePolicy(
                timeZoneIdentifier: "UTC",
                workWindows: [WeeklyWorkWindow(
                    weekdays: Weekday.allCases,
                    start: workStart,
                    end: LocalTime(hour: 18, minute: 0)
                )],
                quietHours: defaults.schedule.quietHours,
                nightlyPlanningTime: defaults.schedule.nightlyPlanningTime,
                morningConfirmationTime: defaults.schedule.morningConfirmationTime,
                planningCapacityPercent: defaults.schedule.planningCapacityPercent
            ),
            calendar: defaults.calendar,
            privacy: defaults.privacy,
            wake: defaults.wake,
            behavior: defaults.behavior,
            capture: defaults.capture,
            gaming: GamingPolicy(
                dailyBudgetMinutes: 0,
                priorityTaskRewardMinutes: 0,
                coachingLevel: level
            ),
            reminderLists: defaults.reminderLists
        )
    }

    func insertPriorityTask() throws {
        try execute("INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind) VALUES ('priority-1', 'Ship client proposal', 9, 0, '2026-07-13T09:00:00Z', 'local');")
        try execute("INSERT INTO daily_plan_entries(day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at, selection_reason, selection_score, is_optional) VALUES ('2026-07-13', 'priority-1', 1, 1, 60, '2026-07-13T09:00:00Z', 'main objective', 100, 0);")
    }

    func insertGaming(minutes: Int) throws {
        let end = Int64(clock.now.timeIntervalSince1970) - 60
        for offset in 0..<minutes {
            let epoch = end - Int64((minutes - 1 - offset) * 60)
            try execute("INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('2026-07-13', \(epoch), '09-00-00', 'Steam', '', '', 0, NULL, '2026-07-13T10:00:00Z', 'gaming', 1);")
        }
    }

    func insertWork(minutes: Int) throws {
        let end = Int64(clock.now.timeIntervalSince1970) - 60
        for offset in 0..<minutes {
            let epoch = end - Int64((minutes - 1 - offset) * 60)
            try execute("INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('2026-07-13', \(epoch), '09-00-00', 'Xcode', '', '', 0, NULL, '2026-07-13T10:00:00Z', 'work', 1);")
        }
    }

    func correctCurrentSession(to classification: BehaviorClassification) throws {
        let end = Int64(clock.now.timeIntervalSince1970)
        let start = end - 10 * 60
        try execute("INSERT INTO daily_review_corrections(source_day, start_epoch, end_epoch, classification, created_at_utc) VALUES ('2026-07-13', \(start), \(end), '\(classification.rawValue)', '2026-07-13T10:00:00Z');")
    }

    func insertOpenPause(_ reason: TaskPauseReason) throws {
        try execute("INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at) VALUES ('priority-1', '\(reason.rawValue)', '2026-07-13T09:55:00Z', NULL);")
    }

    func closePauses() throws {
        try execute("UPDATE task_pause_events SET resumed_at = '2026-07-13T09:56:00Z' WHERE resumed_at IS NULL;")
    }

    private func execute(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw GamingDriftPromptServiceError.openDatabase
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw GamingDriftPromptServiceError.database(String(cString: sqlite3_errmsg(database)))
        }
    }
}
