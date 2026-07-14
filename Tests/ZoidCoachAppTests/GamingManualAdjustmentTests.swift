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
            return AgentMutationReceipt(
                accepted: true,
                message: result.replayed
                    ? "This gaming-time adjustment was already saved."
                    : "Added \(result.adjustment.minutes) minutes to today's gaming allowance."
            )
        },
        loadGamingManualAdjustmentMinutes: { adjustmentDay, timeZoneIdentifier in
            try adjustments.netMinutes(
                for: adjustmentDay,
                timeZoneIdentifier: timeZoneIdentifier
            )
        }
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
    #expect(model.gamingManualAdjustmentMessage == "Added 20 minutes to today's gaming allowance.")
    #expect(model.gamingManualAdjustmentError == nil)
    #expect(try adjustments.adjustments(for: day, timeZoneIdentifier: "UTC").map(\.note) == ["Weekend exception"])
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

private func gamingAdjustmentTodaySnapshot(day: Date) -> TodaySnapshot {
    TodaySnapshot(
        localDate: day,
        timeZoneIdentifier: "UTC",
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
