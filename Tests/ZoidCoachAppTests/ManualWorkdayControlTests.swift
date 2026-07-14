import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func legacyScheduleDefaultsToScheduledWorkdayControl() throws {
    let schedule = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo").schedule
    let encoded = try JSONEncoder().encode(schedule)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "workdayControlMode")

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(SchedulePolicy.self, from: legacyData)

    #expect(decoded.workdayControlMode == nil)
    #expect(decoded.effectiveWorkdayControlMode == .scheduled)
}

@MainActor
@Test
func manualWorkdaySelectionSurvivesSaveReopenAndMenuRefresh() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-manual-workday-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let initial = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    var draft = SettingsPolicyDraft(policy: initial)
    let originalStart = draft.workStart
    let originalEnd = draft.workEnd
    draft.workdayControlMode = .manual

    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.saveSystemMaintenancePolicy(draft.policy(preserving: initial))
    let reopened = try PolicyStore(databaseURL: databaseURL)
    let current = try #require(reopened.current())

    #expect(current.policy.schedule.effectiveWorkdayControlMode == .manual)
    #expect(current.policy.schedule.workWindows.first?.start == originalStart)
    #expect(current.policy.schedule.workWindows.first?.end == originalEnd)
    #expect(SettingsPolicyDraft(policy: current.policy).workdayControlMode == .manual)

    let controller = MenuBarCoachingPauseController(client: ManualWorkdayPolicyClient(current: current))
    await controller.refresh()

    #expect(controller.usesManualWorkday)
    #expect(controller.workdayControlMode == .manual)
}

@Test
func manualWorkdayControlsOnlyOfferValidStateTransitions() {
    let ready = manualTask(id: "ready", state: .ready)
    let readyState = MenuBarCoachState(snapshot: manualSnapshot(
        rows: [ready],
        recommendation: NextTaskRecommendation(taskID: ready.taskID, sentence: "Start it", reasons: [])
    ))
    #expect(readyState.availableTaskActions.contains(.start))
    #expect(!readyState.availableTaskActions.contains(.endWorkday))

    let active = manualTask(id: "active", state: .active)
    let activeState = MenuBarCoachState(snapshot: manualSnapshot(
        rows: [active],
        activeTask: ActiveTaskSnapshot(taskID: active.taskID, startedAt: nil, elapsedMinutes: 0)
    ))
    #expect(!activeState.availableTaskActions.contains(.start))
    #expect(activeState.availableTaskActions.contains(.endWorkday))

    let ended = manualTask(id: "ended", state: .paused, pauseReason: .endingWorkday)
    let endedState = MenuBarCoachState(snapshot: manualSnapshot(rows: [ended]))
    #expect(endedState.workdayHasEnded)
    #expect(endedState.availableTaskActions.contains(.resume))
    #expect(!endedState.availableTaskActions.contains(.endWorkday))
}

@Test
func settingsConflictResolutionPreservesAnIndependentManualWorkdayChoice() {
    let base = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "Africa/Cairo"))
    var mine = base
    mine.workdayControlMode = .manual
    var current = base
    current.capacityPercent = 60

    let merged = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)

    #expect(merged.safeDraft.workdayControlMode == .manual)
    #expect(merged.safeDraft.capacityPercent == 60)
    #expect(merged.concurrentChanges == ["Planning capacity"])
    #expect(merged.overlappingChanges.isEmpty)
}

@Test
func manualWorkdaySettingsAndMenuExposeStableAccessibilityIdentifiers() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let settings = try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/ZoidCoachApp/Views/SettingsView.swift"),
        encoding: .utf8
    )
    let menu = try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/ZoidCoachApp/MenuBarCoachView.swift"),
        encoding: .utf8
    )

    #expect(settings.contains("settings.schedule.workday-control"))
    #expect(settings.contains("settings.schedule.workday-control.detail"))
    #expect(settings.contains("settings.schedule.fixed-hours"))
    #expect(menu.contains("menu-bar.manual-workday.status"))
    #expect(menu.contains("menu-bar.task.start"))
    #expect(menu.contains("menu-bar.task.end-workday"))
}

private actor ManualWorkdayPolicyClient: MenuBarCoachingPauseClient {
    let current: VersionedUserPolicy

    func loadCurrentPolicy() -> VersionedUserPolicy { current }

    func savePolicyMutation(_ request: PolicyMutationRequest) throws -> AgentMutationReceipt {
        throw ManualWorkdayTestError.unexpectedMutation
    }
}

private enum ManualWorkdayTestError: Error {
    case unexpectedMutation
}

private func manualTask(
    id: String,
    state: TaskExecutionState,
    pauseReason: TaskPauseReason? = nil
) -> TodayTaskRow {
    TodayTaskRow(
        taskID: id,
        title: "Manual workday task",
        estimateMinutes: 30,
        dueDate: nil,
        urgency: .medium,
        state: state,
        latestPauseReason: pauseReason
    )
}

private func manualSnapshot(
    rows: [TodayTaskRow],
    activeTask: ActiveTaskSnapshot? = nil,
    recommendation: NextTaskRecommendation = NextTaskRecommendation(taskID: nil, sentence: "Nothing ready", reasons: [])
) -> TodaySnapshot {
    TodaySnapshot(
        localDate: Date(timeIntervalSince1970: 1_784_026_800),
        timeZoneIdentifier: "Africa/Cairo",
        mainObjective: nil,
        taskRows: rows,
        activeTask: activeTask,
        recommendation: recommendation,
        behavior: BehaviorSummary(),
        coverage: TelemetryCoverage(isLimited: false, explanation: "Fixture coverage", lastObservationAt: nil),
        gaming: GamingStatus(
            budgetMinutes: 60,
            usedMinutes: 0,
            unlockedRemainingMinutes: 0,
            nextUnlockReason: "Complete the task",
            confidenceIsLimited: false
        ),
        sourceFreshnessExplanation: "Fixture sources"
    )
}
