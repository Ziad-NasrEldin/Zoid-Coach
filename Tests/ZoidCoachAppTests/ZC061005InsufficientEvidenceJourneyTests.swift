import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func zc061005UncertainOverlapWithdrawsStrongDriftAndQueuesOneSafeConfirmation() throws {
    let fixture = try ZC061005JourneyFixture()
    defer { fixture.remove() }
    try fixture.startTechnicalTask()
    try fixture.insertUnknownSafari(minutes: 10)
    let strong = try fixture.seedStrongGamingDrift()

    #expect(try fixture.gamingService.produce(
        policy: fixture.policy,
        gamingStatus: fixture.gamingStatus,
        baselineStatus: fixture.baseline
    ) == .suppressed(.limitedCoverage))

    let withdrawn = try #require(fixture.promptStore.episode(promptID: strong.id))
    #expect(withdrawn.state == .dismissed)
    #expect(withdrawn.resolutionOrigin == .system)
    #expect(withdrawn.resolutionReason == .screenwatchEvidenceInvalid)
    #expect(try fixture.promptStore.unresolved().allSatisfy { $0.type != "GAMING_DRIFT" })

    guard case let .queued(confirmation, wasInserted) = try fixture.ambiguityService.produce() else {
        Issue.record("Expected one ambiguity confirmation")
        return
    }
    #expect(wasInserted)
    #expect(confirmation.type == "AMBIGUOUS_ACTIVITY")
    #expect(confirmation.title == "Did this support QA ZC-061-005 technical task?")
    #expect(confirmation.summary.contains("about 10 minutes in Safari"))
    #expect(confirmation.summary.contains("cannot show your intent"))
    #expect(!confirmation.summary.contains(fixture.privateTitle))
    #expect(!confirmation.summary.contains(fixture.privateURL))
    #expect(!confirmation.payload.values.contains(fixture.privateTitle))
    #expect(!confirmation.payload.values.contains(fixture.privateURL))
    #expect(!confirmation.title.localizedCaseInsensitiveContains("research"))
    #expect(!confirmation.summary.localizedCaseInsensitiveContains("research"))

    #expect(try fixture.ambiguityService.produce() == .suppressed(.alreadyHandled))
    #expect(try fixture.promptStore.unresolved().filter { $0.type == "AMBIGUOUS_ACTIVITY" }.count == 1)
}

@Test(arguments: [
    ZC061005Boundary.belowThreshold,
    .stale,
    .noActiveTask,
])
func zc061005IneligibleEvidenceNeverQueuesAnyPrompt(boundary: ZC061005Boundary) throws {
    let fixture = try ZC061005JourneyFixture()
    defer { fixture.remove() }
    if boundary != .noActiveTask {
        try fixture.startTechnicalTask()
    }
    switch boundary {
    case .belowThreshold:
        try fixture.insertUnknownSafari(minutes: 9)
    case .stale:
        try fixture.insertUnknownSafari(minutes: 10, endingAt: fixture.now.addingTimeInterval(-4 * 60))
    case .noActiveTask:
        try fixture.insertUnknownSafari(minutes: 10)
    }

    let result = try fixture.ambiguityService.produce()
    switch boundary {
    case .belowThreshold: #expect(result == .suppressed(.belowMaterialThreshold))
    case .stale: #expect(result == .suppressed(.staleEvidence))
    case .noActiveTask: #expect(result == .suppressed(.noActiveTask))
    }
    #expect(try fixture.promptStore.unresolved().isEmpty)
}

@Test
func zc061005SQLFailureFailsClosedInsteadOfProducingAPrompt() throws {
    let fixture = try ZC061005JourneyFixture()
    defer { fixture.remove() }
    try fixture.startTechnicalTask()
    try fixture.insertUnknownSafari(minutes: 10)
    try fixture.replaceBehaviorTableWithInvalidSchema()

    #expect(throws: AmbiguousActivityPromptServiceError.self) {
        _ = try fixture.ambiguityService.produce()
    }
    #expect(throws: GamingDriftPromptServiceError.self) {
        _ = try fixture.gamingService.produce(
            policy: fixture.policy,
            gamingStatus: fixture.gamingStatus,
            baselineStatus: fixture.baseline
        )
    }
    #expect(try fixture.promptStore.unresolved().isEmpty)
}

private enum ZC061005Boundary: CaseIterable, Sendable {
    case belowThreshold
    case stale
    case noActiveTask
}

private final class ZC061005JourneyFixture: @unchecked Sendable {
    let root: URL
    let databaseURL: URL
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let sourceDay = "2026-07-13"
    let taskID = "qa-zc061005-technical-task"
    let privateTitle = "qa-zc061005-private-tutorial-secret"
    let privateURL = "https://qa-zc061005.private.invalid/token"
    let promptStore: PromptInboxStore
    let ambiguityService: AmbiguousActivityPromptService
    let gamingService: GamingDriftPromptService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zc061005-journey-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("zoid.sqlite")
        let fixedNow = now
        promptStore = try PromptInboxStore(
            databaseURL: databaseURL,
            now: { fixedNow },
            makeID: { UUID().uuidString }
        )
        ambiguityService = try AmbiguousActivityPromptService(
            databaseURL: databaseURL,
            promptStore: promptStore,
            now: { fixedNow }
        )
        gamingService = try GamingDriftPromptService(
            databaseURL: databaseURL,
            promptStore: promptStore,
            now: { fixedNow }
        )
        try execute("""
        INSERT INTO source_tasks(
            source_id, title, priority, is_completed, updated_at, source_kind, declared_context
        ) VALUES (
            '\(taskID)', 'QA ZC-061-005 technical task', 9, 0,
            '2026-07-13T09:00:00Z', 'local', 'technical'
        );
        """)
    }

    var gamingStatus: GamingStatus {
        GamingStatus(
            budgetMinutes: 0,
            usedMinutes: 10,
            unlockedRemainingMinutes: 0,
            nextUnlockReason: "Finish priority work",
            confidenceIsLimited: false
        )
    }

    var baseline: BaselineObservationStatus {
        BaselineObservationStatus(
            days: (1...7).map { day in
                BaselineObservationDay(
                    localDay: String(format: "2026-07-%02d", day),
                    observedMinutes: 60,
                    workMinutes: 45,
                    gamingMinutes: 0,
                    distractingMinutes: 0,
                    unknownMinutes: 15,
                    eligibleDriftCount: 0,
                    coverage: .complete,
                    recordedAt: now
                )
            },
            report: BaselineObservationReport(
                averageObservedWorkMinutes: 45,
                gamingDayCount: 0,
                totalGamingMinutes: 0,
                eligibleDriftCount: 0,
                unknownSharePercent: 25
            )
        )
    }

    var policy: UserPolicy {
        let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
        return UserPolicy(
            operatingMode: .suggest,
            automationPause: .running,
            schedule: SchedulePolicy(
                timeZoneIdentifier: "UTC",
                workWindows: [WeeklyWorkWindow(
                    weekdays: Weekday.allCases,
                    start: LocalTime(hour: 8, minute: 0),
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
                coachingLevel: .accountability,
                dailyPromptCap: 3,
                promptCooldownMinutes: 5,
                taskStartGraceMinutes: 0,
                returnFromIdleGraceMinutes: 0,
                budgetEnabled: true
            ),
            reminderLists: defaults.reminderLists
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func startTechnicalTask() throws {
        try TaskExecutionStore(databaseURL: databaseURL).apply(
            .start,
            taskID: taskID,
            at: now.addingTimeInterval(-11 * 60)
        )
    }

    func insertUnknownSafari(minutes: Int, endingAt: Date? = nil) throws {
        let latest = Int64((endingAt ?? now.addingTimeInterval(-30)).timeIntervalSince1970)
        let first = latest - Int64(max(0, minutes - 1) * 60)
        for offset in 0..<minutes {
            try execute("""
            INSERT INTO behavior_records(
                source_day, epoch, time_label, app_name, window_title, url,
                has_screenshot, screenshot_path, ingested_at, classification,
                classification_policy_version
            ) VALUES (
                '\(sourceDay)', \(first + Int64(offset * 60)), 'qa-zc061005-\(offset)',
                'Safari', '\(privateTitle)', '\(privateURL)', 0, NULL,
                '2026-07-13T10:00:00Z', 'unknown', 1
            );
            """)
        }
    }

    func seedStrongGamingDrift() throws -> PromptEpisode {
        try promptStore.enqueue(PromptDraft(
            decisionKey: "gaming-drift:\(sourceDay):seed",
            type: "GAMING_DRIFT",
            title: "Is this gaming intentional?",
            summary: "Strong coaching must be withdrawn when the evidence becomes uncertain.",
            actions: [PromptAction(kind: .returnToActiveTask, title: "Return to task")],
            payload: ["allowsDismissal": "false"]
        )).episode
    }

    func replaceBehaviorTableWithInvalidSchema() throws {
        try execute("DROP TABLE behavior_records; CREATE TABLE behavior_records(source_day TEXT);")
    }

    private func execute(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else { throw ZC061005JourneyFixtureError.database }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw ZC061005JourneyFixtureError.database
        }
    }
}

private enum ZC061005JourneyFixtureError: Error {
    case database
}
