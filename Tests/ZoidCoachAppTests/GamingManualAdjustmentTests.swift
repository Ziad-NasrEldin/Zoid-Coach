import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func manualGamingAllowanceAdjustmentPersistsAndReplaysExactlyOnce() throws {
    let databaseURL = temporaryGamingAdjustmentDatabaseURL()
    defer { removeGamingAdjustmentDatabase(at: databaseURL) }
    let day = Date()
    let request = GamingManualAdjustmentRequest(
        requestID: "gaming-adjustment-v1:test-grant",
        day: day,
        minutes: 25,
        note: "Long commute"
    )

    let store = try GamingManualAdjustmentStore(databaseURL: databaseURL)
    let first = try store.record(request)
    let replay = try store.record(request)

    #expect(!first.replayed)
    #expect(replay.replayed)
    #expect(first.adjustment == replay.adjustment)
    #expect(try store.netMinutes(for: day) == 25)
    #expect(try store.adjustments(for: day).count == 1)

    let reopened = try GamingManualAdjustmentStore(databaseURL: databaseURL)
    #expect(try reopened.netMinutes(for: day) == 25)
    #expect(try reopened.adjustments(for: day).map(\.note) == ["Long commute"])
}

@Test
func manualGamingAllowanceRemovalCannotExceedPriorManualGrants() throws {
    let databaseURL = temporaryGamingAdjustmentDatabaseURL()
    defer { removeGamingAdjustmentDatabase(at: databaseURL) }
    let day = Date(timeIntervalSince1970: 1_752_489_600)
    let store = try GamingManualAdjustmentStore(databaseURL: databaseURL)
    _ = try store.record(.init(
        requestID: "gaming-adjustment-v1:test-add",
        day: day,
        minutes: 20,
        note: nil
    ))

    #expect(throws: GamingManualAdjustmentStoreError.removalExceedsManualGrant) {
        _ = try store.record(.init(
            requestID: "gaming-adjustment-v1:test-remove-too-much",
            day: day,
            minutes: -25,
            note: nil
        ))
    }
    #expect(try store.netMinutes(for: day) == 20)

    _ = try store.record(.init(
        requestID: "gaming-adjustment-v1:test-remove",
        day: day,
        minutes: -20,
        note: "Plans changed"
    ))
    #expect(try store.netMinutes(for: day) == 0)
    #expect(try store.adjustments(for: day).map(\.minutes) == [20, -20])
}

@Test
func manualGamingAllowanceRejectsUnsafeIntegerBoundariesWithoutMutation() throws {
    let databaseURL = temporaryGamingAdjustmentDatabaseURL()
    defer { removeGamingAdjustmentDatabase(at: databaseURL) }
    let day = Date(timeIntervalSince1970: 1_752_489_600)
    let store = try GamingManualAdjustmentStore(databaseURL: databaseURL)

    for (index, minutes) in [Int.min, -241, 0, 241, Int.max].enumerated() {
        #expect(throws: GamingManualAdjustmentStoreError.invalidRequest) {
            _ = try store.record(.init(
                requestID: "gaming-adjustment-v1:unsafe-\(index)",
                day: day,
                timeZoneIdentifier: "UTC",
                minutes: minutes,
                note: nil
            ))
        }
    }
    #expect(try store.netMinutes(for: day, timeZoneIdentifier: "UTC") == 0)
    #expect(try store.adjustments(for: day, timeZoneIdentifier: "UTC").isEmpty)
}

@Test
func manualGamingAllowanceRejectsIdempotencyConflictsAndPreservesOriginalEntry() throws {
    let databaseURL = temporaryGamingAdjustmentDatabaseURL()
    defer { removeGamingAdjustmentDatabase(at: databaseURL) }
    let day = Date(timeIntervalSince1970: 1_752_489_600)
    let store = try GamingManualAdjustmentStore(databaseURL: databaseURL)
    let requestID = "gaming-adjustment-v1:conflict"
    _ = try store.record(.init(
        requestID: requestID,
        day: day,
        timeZoneIdentifier: "UTC",
        minutes: 20,
        note: "Original"
    ))

    #expect(throws: GamingManualAdjustmentStoreError.idempotencyConflict) {
        _ = try store.record(.init(
            requestID: requestID,
            day: day,
            timeZoneIdentifier: "UTC",
            minutes: 25,
            note: "Different"
        ))
    }
    #expect(try store.netMinutes(for: day, timeZoneIdentifier: "UTC") == 20)
    #expect(try store.adjustments(for: day, timeZoneIdentifier: "UTC").map(\.note) == ["Original"])
}

@Test
func manualGamingAllowanceEnforcesDailyCapAndRollsBackRejectedWrite() throws {
    let databaseURL = temporaryGamingAdjustmentDatabaseURL()
    defer { removeGamingAdjustmentDatabase(at: databaseURL) }
    let day = Date(timeIntervalSince1970: 1_752_489_600)
    let store = try GamingManualAdjustmentStore(databaseURL: databaseURL)
    for index in 0..<6 {
        _ = try store.record(.init(
            requestID: "gaming-adjustment-v1:cap-\(index)",
            day: day,
            timeZoneIdentifier: "UTC",
            minutes: 240,
            note: nil
        ))
    }

    #expect(throws: GamingManualAdjustmentStoreError.dailyLimitExceeded) {
        _ = try store.record(.init(
            requestID: "gaming-adjustment-v1:cap-overflow",
            day: day,
            timeZoneIdentifier: "UTC",
            minutes: 5,
            note: nil
        ))
    }
    #expect(try store.netMinutes(for: day, timeZoneIdentifier: "UTC") == 1_440)
    #expect(try store.adjustments(for: day, timeZoneIdentifier: "UTC").count == 6)
}

@Test
func concurrentManualGamingAllowanceWritesSerializeWithoutLoss() async throws {
    let databaseURL = temporaryGamingAdjustmentDatabaseURL()
    defer { removeGamingAdjustmentDatabase(at: databaseURL) }
    let day = Date(timeIntervalSince1970: 1_752_489_600)
    let store = try GamingManualAdjustmentStore(databaseURL: databaseURL)

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<12 {
            group.addTask {
                _ = try store.record(.init(
                    requestID: "gaming-adjustment-v1:concurrent-\(index)",
                    day: day,
                    timeZoneIdentifier: "UTC",
                    minutes: 5,
                    note: "Entry \(index)"
                ))
            }
        }
        try await group.waitForAll()
    }

    #expect(try store.netMinutes(for: day, timeZoneIdentifier: "UTC") == 60)
    #expect(try store.adjustments(for: day, timeZoneIdentifier: "UTC").count == 12)
}

@Test
func manualGamingAdjustmentAuditTrailSurvivesReopenAndPrivacyRangeDeletion() throws {
    let databaseURL = temporaryGamingAdjustmentDatabaseURL()
    defer { removeGamingAdjustmentDatabase(at: databaseURL) }
    let timeZoneIdentifier = TimeZone.current.identifier
    let day = Date()
    let store = try GamingManualAdjustmentStore(databaseURL: databaseURL)
    _ = try store.record(.init(
        requestID: "gaming-adjustment-v1:audit-add",
        day: day,
        timeZoneIdentifier: timeZoneIdentifier,
        minutes: 30,
        note: "Friends online"
    ))
    _ = try store.record(.init(
        requestID: "gaming-adjustment-v1:audit-remove",
        day: day,
        timeZoneIdentifier: timeZoneIdentifier,
        minutes: -10,
        note: "Plans changed"
    ))

    let reopened = try GamingManualAdjustmentStore(databaseURL: databaseURL)
    let audit = try reopened.adjustments(for: day, timeZoneIdentifier: timeZoneIdentifier)
    #expect(audit.map(\.minutes) == [30, -10])
    #expect(audit.map(\.note) == ["Friends online", "Plans changed"])
    #expect(try reopened.netMinutes(for: day, timeZoneIdentifier: timeZoneIdentifier) == 20)

    let privacy = try PrivacyDataService(databaseURL: databaseURL)
    let plans = try privacy.storedDataInventory().dataClasses.first { $0.id == "plans" }
    #expect((plans?.recordCount ?? 0) >= 2)
    let start = Calendar.current.startOfDay(for: day)
    let end = try #require(Calendar.current.date(byAdding: .day, value: 1, to: start))
    #expect(try privacy.deleteDateRange(start: start, end: end) >= 2)
    #expect(try reopened.adjustments(for: day, timeZoneIdentifier: timeZoneIdentifier).isEmpty)
}

@Test
func manualGamingAllowanceChangesRemainingTimeWithoutChangingObservedUseOrAutomaticReward() {
    let status = GamingStatus(
        budgetMinutes: 60,
        earnedMinutes: 15,
        usedMinutes: 70,
        unlockedRemainingMinutes: 5,
        nextUnlockReason: "Priority-task reward already applied today.",
        confidenceIsLimited: false
    )

    let adjusted = status.applyingManualAdjustment(25)

    #expect(adjusted.manualAdjustmentMinutes == 25)
    #expect(adjusted.earnedMinutes == 15)
    #expect(adjusted.usedMinutes == 70)
    #expect(adjusted.unlockedRemainingMinutes == 30)
    #expect(adjusted.overageMinutes == 0)
    #expect(adjusted.allowanceBreakdown.contains("Manual +25m"))
}

@Test
func manualGamingAdjustmentFormExplainsInvalidRemovalBeforeSubmission() {
    var form = GamingManualAdjustmentForm(
        direction: .remove,
        minutes: 15,
        note: "",
        currentManualMinutes: 10
    )

    #expect(!form.canSubmit)
    #expect(form.validationMessage == "You can remove up to 10 manually granted minutes today.")

    form.minutes = 10
    #expect(form.canSubmit)
    #expect(form.signedMinutes == -10)
}

@Test
func manualGamingAdjustmentFormNeverNegatesUnsafeIntegerInput() {
    let form = GamingManualAdjustmentForm(
        direction: .remove,
        minutes: Int.min,
        note: "",
        currentManualMinutes: 10
    )

    #expect(form.signedMinutes == nil)
    #expect(!form.canSubmit)
}

@Test
func manualGamingAdjustmentFormExplainsDailyCapBeforeSubmission() {
    var form = GamingManualAdjustmentForm(
        direction: .add,
        minutes: 10,
        note: "",
        currentManualMinutes: 1_435
    )

    #expect(!form.canSubmit)
    #expect(form.validationMessage == "You can add up to 5 more manual minutes today.")
    form.minutes = 5
    #expect(form.canSubmit)

    let capped = GamingManualAdjustmentForm(
        direction: .add,
        minutes: 5,
        note: "",
        currentManualMinutes: 1_440
    )
    #expect(!capped.canSubmit)
    #expect(capped.validationMessage == "Today's manual allowance is already at the 1,440-minute maximum.")
}

@Test
func manualGamingAdjustmentRoundTripsThroughAgentMutationBoundary() async throws {
    let databaseURL = temporaryGamingAdjustmentDatabaseURL()
    defer { removeGamingAdjustmentDatabase(at: databaseURL) }
    let adjustments = try GamingManualAdjustmentStore(databaseURL: databaseURL)
    let router = try makeGamingAdjustmentRouter(
        databaseURL: databaseURL,
        adjustments: adjustments
    )
    let request = GamingManualAdjustmentRequest(
        requestID: "gaming-adjustment-v1:router",
        day: Date(timeIntervalSince1970: 1_752_489_600),
        minutes: 30,
        note: "Manual grant"
    )
    let command = AgentMutationCommand.recordGamingManualAdjustment(request)

    #expect(try JSONDecoder().decode(AgentMutationCommand.self, from: JSONEncoder().encode(command)) == command)
    let first = try await router.apply(command)
    let replay = try await router.apply(command)

    #expect(first.accepted)
    #expect(first.message == "Added 30 minutes to today's gaming allowance.")
    #expect(replay.accepted)
    #expect(replay.message == "This gaming-time adjustment was already saved.")
    #expect(try adjustments.netMinutes(for: request.day) == 30)
}

@MainActor
@Test
func todayAdjustmentActionSavesThroughAgentBoundaryAndRefreshesVisibleAllowance() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-gaming-adjustment-app-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let runtime = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    let day = Date()
    let rawSnapshot = gamingAdjustmentTodaySnapshot(day: day)
    try TodaySnapshotStore(databaseURL: runtime.databaseURL).save(rawSnapshot, for: day)
    let adjustments = try GamingManualAdjustmentStore(databaseURL: runtime.databaseURL)
    let model = AppModel(
        runtimeEnvironment: runtime,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: runtime,
            service: GamingAdjustmentNoopAgentRegistration()
        ),
        saveGamingManualAdjustment: { request in
            let result = try adjustments.record(request)
            let message: String
            if result.replayed {
                message = "This gaming-time adjustment was already saved."
            } else if result.adjustment.minutes > 0 {
                message = "Added \(result.adjustment.minutes) minutes to today's gaming allowance."
            } else {
                message = "Removed \(result.adjustment.minutes.magnitude) manually granted minutes from today's gaming allowance."
            }
            return AgentMutationReceipt(
                accepted: true,
                message: message
            )
        },
        loadGamingManualAdjustments: { adjustmentDay, timeZoneIdentifier in
            try adjustments.adjustments(
                for: adjustmentDay,
                timeZoneIdentifier: timeZoneIdentifier
            )
        },
        fetchAuthoritativeGamingSnapshot: { rawSnapshot },
        now: { day }
    )
    await model.refreshTodaySnapshot()
    #expect(model.todaySnapshot?.gaming.manualAdjustmentMinutes == 0)

    model.recordGamingManualAdjustment(minutes: 20, note: "Weekend exception")
    while model.isSavingGamingManualAdjustment {
        await Task.yield()
    }

    #expect(model.todaySnapshot?.gaming.manualAdjustmentMinutes == 20)
    #expect(model.todaySnapshot?.gaming.unlockedRemainingMinutes == 30)
    #expect(model.todaySnapshot?.gaming.usedMinutes == 50)
    #expect(model.gamingManualAdjustments.map(\.minutes) == [20])
    #expect(model.gamingManualAdjustmentLedgerError == nil)
    #expect(model.gamingManualAdjustmentMessage == "Added 20 minutes to today's gaming allowance.")
    #expect(model.gamingManualAdjustmentError == nil)
    #expect(try adjustments.adjustments(for: day, timeZoneIdentifier: "UTC").map(\.note) == ["Weekend exception"])

    model.recordGamingManualAdjustment(minutes: -5, note: "Leaving early")
    while model.isSavingGamingManualAdjustment {
        await Task.yield()
    }
    #expect(model.todaySnapshot?.gaming.manualAdjustmentMinutes == 15)
    #expect(model.todaySnapshot?.gaming.unlockedRemainingMinutes == 25)
    #expect(model.gamingManualAdjustments.map(\.minutes) == [20, -5])
    #expect(model.gamingManualAdjustments.map(\.note) == ["Weekend exception", "Leaving early"])

    let relaunched = AppModel(
        runtimeEnvironment: runtime,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: runtime,
            service: GamingAdjustmentNoopAgentRegistration()
        ),
        loadGamingManualAdjustments: { adjustmentDay, timeZoneIdentifier in
            try adjustments.adjustments(
                for: adjustmentDay,
                timeZoneIdentifier: timeZoneIdentifier
            )
        },
        fetchAuthoritativeGamingSnapshot: { rawSnapshot },
        now: { day }
    )
    await relaunched.refreshTodaySnapshot()
    #expect(relaunched.todaySnapshot?.gaming.manualAdjustmentMinutes == 15)
    #expect(relaunched.todaySnapshot?.gaming.unlockedRemainingMinutes == 25)
    #expect(relaunched.gamingManualAdjustments.map(\.minutes) == [20, -5])
    #expect(relaunched.gamingManualAdjustments.map(\.note) == ["Weekend exception", "Leaving early"])
}

@MainActor
@Test
func todayAdjustmentDisablesMutationWhenAuthoritativeLedgerCannotBeRead() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-gaming-adjustment-unavailable-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let runtime = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    let day = Date()
    let snapshot = gamingAdjustmentTodaySnapshot(day: day)
    try TodaySnapshotStore(databaseURL: runtime.databaseURL).save(snapshot, for: day)
    let model = AppModel(
        runtimeEnvironment: runtime,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: runtime,
            service: GamingAdjustmentNoopAgentRegistration()
        ),
        saveGamingManualAdjustment: { _ in
            Issue.record("A ledger-unavailable Today surface must not send a mutation")
            return AgentMutationReceipt(accepted: true, message: "Unexpected")
        },
        loadGamingManualAdjustments: { _, _ in
            throw GamingAdjustmentTestError.unavailable
        },
        fetchAuthoritativeGamingSnapshot: { snapshot },
        now: { day }
    )

    await model.refreshTodaySnapshot()
    #expect(model.gamingManualAdjustments.isEmpty)
    #expect(model.gamingManualAdjustmentLedgerError == "Manual allowance history is unavailable. Refresh Today after checking Agent source health.")
    model.recordGamingManualAdjustment(minutes: 15, note: nil)
    #expect(!model.isSavingGamingManualAdjustment)
    #expect(model.gamingManualAdjustmentMessage == nil)
}

@MainActor
@Test
func todayAdjustmentRejectsStaleDayAndTimeZoneBeforeAgentMutation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-gaming-adjustment-stale-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let runtime = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    let presentedDay = Date()
    let authoritativeDay = presentedDay.addingTimeInterval(24 * 60 * 60)
    let presented = gamingAdjustmentTodaySnapshot(day: presentedDay)
    let authoritative = gamingAdjustmentTodaySnapshot(day: authoritativeDay)
    try TodaySnapshotStore(databaseURL: runtime.databaseURL).save(presented, for: presentedDay)
    let model = AppModel(
        runtimeEnvironment: runtime,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: runtime,
            service: GamingAdjustmentNoopAgentRegistration()
        ),
        saveGamingManualAdjustment: { _ in
            Issue.record("A stale Today surface must not send a mutation")
            return AgentMutationReceipt(accepted: true, message: "Unexpected")
        },
        loadGamingManualAdjustments: { _, _ in [] },
        fetchAuthoritativeGamingSnapshot: { authoritative },
        now: { authoritativeDay }
    )

    await model.refreshTodaySnapshot()
    let loadedPresentedDay = try #require(model.todaySnapshot?.localDate)
    #expect(abs(loadedPresentedDay.timeIntervalSince(presentedDay)) < 1)
    model.recordGamingManualAdjustment(minutes: 15, note: nil)
    while model.isSavingGamingManualAdjustment {
        await Task.yield()
    }

    #expect(model.todaySnapshot?.localDate == authoritativeDay)
    #expect(model.gamingManualAdjustmentError == "Today or its time zone changed. Review the refreshed allowance before saving this adjustment.")
    #expect(model.gamingManualAdjustments.isEmpty)
}

@MainActor
@Test
func todayAdjustmentRejectsChangedTimeZoneEvenWhenLocalDayLabelMatches() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-gaming-adjustment-zone-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let runtime = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
    let day = Date()
    let presented = gamingAdjustmentTodaySnapshot(day: day, timeZoneIdentifier: "UTC")
    let authoritative = gamingAdjustmentTodaySnapshot(
        day: day,
        timeZoneIdentifier: "Africa/Cairo"
    )
    try TodaySnapshotStore(databaseURL: runtime.databaseURL).save(presented, for: day)
    let model = AppModel(
        runtimeEnvironment: runtime,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: runtime,
            service: GamingAdjustmentNoopAgentRegistration()
        ),
        saveGamingManualAdjustment: { _ in
            Issue.record("A changed time zone must not reuse the stale adjustment form")
            return AgentMutationReceipt(accepted: true, message: "Unexpected")
        },
        loadGamingManualAdjustments: { _, _ in [] },
        fetchAuthoritativeGamingSnapshot: { authoritative },
        now: { day }
    )

    await model.refreshTodaySnapshot()
    #expect(model.todaySnapshot?.timeZoneIdentifier == "UTC")
    model.recordGamingManualAdjustment(minutes: 15, note: nil)
    while model.isSavingGamingManualAdjustment {
        await Task.yield()
    }

    #expect(model.todaySnapshot?.timeZoneIdentifier == "Africa/Cairo")
    #expect(model.gamingManualAdjustmentError == "Today or its time zone changed. Review the refreshed allowance before saving this adjustment.")
}

private struct EmptyGamingAdjustmentCalendar: CalendarAvailabilitySource {
    func commitments(
        from start: Date,
        through end: Date,
        calendarIdentifiers: [String]
    ) async throws -> [ZoidCoachCore.CalendarCommitment] {
        []
    }
}

@MainActor
private final class GamingAdjustmentNoopAgentRegistration: AgentServiceRegistration {
    var status: AgentRegistrationStatus = .notRegistered

    func register() {
        status = .enabled
    }

    func unregister() {
        status = .notRegistered
    }
}

private func gamingAdjustmentTodaySnapshot(
    day: Date,
    timeZoneIdentifier: String = "UTC"
) -> TodaySnapshot {
    TodaySnapshot(
        localDate: day,
        timeZoneIdentifier: timeZoneIdentifier,
        mainObjective: nil,
        taskRows: [],
        activeTask: nil,
        recommendation: NextTaskRecommendation(
            taskID: nil,
            sentence: "No ready planned task remains.",
            reasons: []
        ),
        behavior: BehaviorSummary(gamingMinutes: 50),
        coverage: TelemetryCoverage(
            isLimited: false,
            explanation: "Observed activity is current.",
            lastObservationAt: day
        ),
        gaming: GamingStatus(
            budgetMinutes: 60,
            usedMinutes: 50,
            unlockedRemainingMinutes: 10,
            nextUnlockReason: "This policy uses a fixed daily gaming budget.",
            confidenceIsLimited: false
        ),
        sourceFreshnessExplanation: "Sources are current."
    )
}

private func makeGamingAdjustmentRouter(
    databaseURL: URL,
    adjustments: GamingManualAdjustmentStore
) throws -> AgentMutationRouter {
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    return AgentMutationRouter(
        outbox: outbox,
        stateStore: try AgentOwnedStateStore(databaseURL: databaseURL),
        taskHistory: try TaskHistoryStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        planScheduler: AgentPlanScheduler(
            plans: try AutonomousPlanStore(databaseURL: databaseURL),
            reminders: reminders,
            outbox: outbox,
            calendar: EmptyGamingAdjustmentCalendar()
        ),
        policyStore: try PolicyStore(databaseURL: databaseURL),
        reminderSnapshots: reminders,
        privacyData: try PrivacyDataService(databaseURL: databaseURL),
        gamingManualAdjustments: adjustments
    )
}

private func temporaryGamingAdjustmentDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-gaming-adjustment-\(UUID().uuidString).sqlite")
}

private func removeGamingAdjustmentDatabase(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}

private enum GamingAdjustmentTestError: Error {
    case unavailable
}
