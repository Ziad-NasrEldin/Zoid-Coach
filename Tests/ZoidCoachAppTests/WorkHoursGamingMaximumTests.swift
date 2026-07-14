import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func legacyGamingPolicyKeepsTheNormalAllowanceAllDay() throws {
    let data = Data(#"{"version":1,"dailyBudgetMinutes":60,"priorityTaskRewardMinutes":15}"#.utf8)
    let policy = try JSONDecoder().decode(GamingPolicy.self, from: data)
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: nil)

    #expect(policy.workHoursDailyMaximumMinutes == nil)
    let status = GamingStatusCalculator().status(
        policy: policy,
        gamingMinutes: 10,
        appliedRewardMinutes: 15,
        coverage: coverage,
        isWithinWorkWindow: true
    )
    #expect(status.budgetMinutes == 60)
    #expect(status.earnedMinutes == 15)
    #expect(status.unlockedRemainingMinutes == 65)
}

@Test
func workHoursMaximumCapsBaseAndEarnedGamingWithoutChangingAfterWorkAllowance() {
    let policy = GamingPolicy(
        dailyBudgetMinutes: 60,
        priorityTaskRewardMinutes: 15,
        workHoursDailyMaximumMinutes: 30
    )
    let coverage = TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: nil)

    let duringWork = GamingStatusCalculator().status(
        policy: policy,
        gamingMinutes: 20,
        appliedRewardMinutes: 15,
        coverage: coverage,
        isWithinWorkWindow: true
    )
    #expect(duringWork.budgetMinutes == 30)
    #expect(duringWork.earnedMinutes == 0)
    #expect(duringWork.unlockedRemainingMinutes == 10)
    #expect(duringWork.lockedMinutes == 0)
    #expect(duringWork.nextUnlockReason.contains("capped at 30 minutes"))

    let afterWork = GamingStatusCalculator().status(
        policy: policy,
        gamingMinutes: 20,
        appliedRewardMinutes: 15,
        coverage: coverage,
        isWithinWorkWindow: false
    )
    #expect(afterWork.budgetMinutes == 60)
    #expect(afterWork.earnedMinutes == 15)
    #expect(afterWork.unlockedRemainingMinutes == 55)

    let partialRewardPolicy = GamingPolicy(
        dailyBudgetMinutes: 60,
        priorityTaskRewardMinutes: 15,
        workHoursDailyMaximumMinutes: 70
    )
    let lockedDuringWork = GamingStatusCalculator().status(
        policy: partialRewardPolicy,
        gamingMinutes: 0,
        appliedRewardMinutes: nil,
        coverage: coverage,
        isWithinWorkWindow: true
    )
    #expect(lockedDuringWork.budgetMinutes == 60)
    #expect(lockedDuringWork.lockedMinutes == 10)
}

@Test
func configuredWorkWindowUsesPolicyTimeZoneAndRejectsAnInvalidMaximum() throws {
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    let mondayAtNoonUTC = try #require(ISO8601DateFormatter().date(from: "2026-07-13T09:00:00Z"))
    let mondayAfterWorkUTC = try #require(ISO8601DateFormatter().date(from: "2026-07-13T20:00:00Z"))

    #expect(original.schedule.isWithinWorkWindow(at: mondayAtNoonUTC))
    #expect(!original.schedule.isWithinWorkWindow(at: mondayAfterWorkUTC))

    let invalidGaming = GamingPolicy(
        dailyBudgetMinutes: 60,
        priorityTaskRewardMinutes: 15,
        workHoursDailyMaximumMinutes: 75
    )
    let invalid = UserPolicy(
        operatingMode: original.operatingMode,
        automationPause: original.automationPause,
        schedule: original.schedule,
        calendar: original.calendar,
        privacy: original.privacy,
        wake: original.wake,
        behavior: original.behavior,
        capture: original.capture,
        gaming: invalidGaming,
        reminderLists: original.reminderLists
    )
    #expect(invalid.validationViolations().contains {
        $0.field == "gaming.workHoursDailyMaximumMinutes"
    })
}

@Test
func settingsWorkHoursMaximumSurvivesPolicyStoreReopen() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-work-hours-maximum-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    var draft = SettingsPolicyDraft(policy: original)
    draft.gamingWorkHoursMaximumEnabled = true
    draft.gamingWorkHoursDailyMaximumMinutes = 25

    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.saveSystemMaintenancePolicy(draft.policy(preserving: original))
    let reopened = try PolicyStore(databaseURL: databaseURL)
    let saved = try #require(try reopened.current()?.policy)
    let relaunchedDraft = SettingsPolicyDraft(policy: saved)

    #expect(saved.gaming.workHoursDailyMaximumMinutes == 25)
    #expect(relaunchedDraft.gamingWorkHoursMaximumEnabled)
    #expect(relaunchedDraft.gamingWorkHoursDailyMaximumMinutes == 25)
}

@Test
func disabledWorkHoursMaximumRoundTripsAsNoSeparateCap() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    var draft = SettingsPolicyDraft(policy: original)
    draft.gamingWorkHoursMaximumEnabled = false
    draft.gamingWorkHoursDailyMaximumMinutes = 10

    let saved = draft.policy(preserving: original)

    #expect(saved.gaming.workHoursDailyMaximumMinutes == nil)
}

@Test
func settingsConflictPreservesIndependentWorkHoursMaximumChange() {
    let base = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "Africa/Cairo"))
    var mine = base
    mine.gamingWorkHoursMaximumEnabled = true
    mine.gamingWorkHoursDailyMaximumMinutes = 25
    var current = base
    current.gamingDailyPromptCap = 4

    let merged = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)

    #expect(merged.safeDraft.gamingWorkHoursMaximumEnabled)
    #expect(merged.safeDraft.gamingWorkHoursDailyMaximumMinutes == 25)
    #expect(merged.safeDraft.gamingDailyPromptCap == 4)
    #expect(merged.concurrentChanges == ["Daily coaching prompt cap"])
    #expect(merged.overlappingChanges.isEmpty)
}

@Test
func workHoursMaximumSettingsExposeStableAccessibilityContracts() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/ZoidCoachApp/Views/SettingsView.swift"),
        encoding: .utf8
    )
    let agent = try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift"),
        encoding: .utf8
    )

    #expect(source.contains("settings.gaming.work-hours-maximum-enabled"))
    #expect(source.contains("settings.gaming.work-hours-maximum"))
    #expect(source.contains("settings.gaming.work-hours-maximum-detail"))
    #expect(source.contains("Outside work hours, the normal daily allowance applies."))
    #expect(agent.contains("isWithinWorkWindow: userPolicy.schedule.isWithinWorkWindow(at: now)"))
}

@Test
func menuBarShowsTruthfulActiveAndInactiveWorkHoursMaximumStates() {
    let activeSnapshot = workHoursMenuSnapshot(GamingStatus(
        budgetMinutes: 30,
        earnedMinutes: 0,
        usedMinutes: 20,
        unlockedRemainingMinutes: 10,
        lockedMinutes: 0,
        nextUnlockReason: "Work-hours gaming is capped at 30 minutes.",
        confidenceIsLimited: false
    ))
    let active = MenuBarCoachState(
        snapshot: activeSnapshot,
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: true)
    ).gamingWorkHours

    #expect(active?.maximumLabel == "30 MIN MAXIMUM")
    #expect(active?.status == "Active in the current work window · 10m remaining")
    #expect(active?.isCappedNow == true)

    let inactiveSnapshot = workHoursMenuSnapshot(GamingStatus(
        budgetMinutes: 60,
        earnedMinutes: 15,
        usedMinutes: 20,
        unlockedRemainingMinutes: 55,
        lockedMinutes: 0,
        nextUnlockReason: "Priority-task reward already applied today.",
        confidenceIsLimited: false
    ))
    let inactive = MenuBarCoachState(
        snapshot: inactiveSnapshot,
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: false)
    ).gamingWorkHours

    #expect(inactive?.status == "Not active now · Normal allowance has 55m remaining")
    #expect(inactive?.isCappedNow == false)
}

@Test
func menuBarOmitsWorkHoursMaximumWhenPolicyOrUsableGamingStateIsUnavailable() {
    let enabledSnapshot = workHoursMenuSnapshot(GamingStatus(
        budgetMinutes: 60,
        usedMinutes: 0,
        unlockedRemainingMinutes: 60,
        nextUnlockReason: "Available",
        confidenceIsLimited: false
    ))
    let observationOnly = workHoursMenuSnapshot(GamingStatus(
        budgetMinutes: 0,
        usedMinutes: 20,
        unlockedRemainingMinutes: 0,
        nextUnlockReason: "Observation only",
        confidenceIsLimited: false,
        budgetEnabled: false
    ))

    #expect(MenuBarCoachState(snapshot: enabledSnapshot).gamingWorkHours == nil)
    #expect(MenuBarCoachState(
        snapshot: nil,
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: true)
    ).gamingWorkHours == nil)
    #expect(MenuBarCoachState(
        snapshot: observationOnly,
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: true)
    ).gamingWorkHours == nil)
}

@Test
func menuBarDoesNotClaimAStaleNormalAllowanceIsAlreadyCapped() {
    let staleNormalSnapshot = workHoursMenuSnapshot(GamingStatus(
        budgetMinutes: 60,
        earnedMinutes: 15,
        usedMinutes: 20,
        unlockedRemainingMinutes: 55,
        lockedMinutes: 0,
        nextUnlockReason: "Priority-task reward already applied today.",
        confidenceIsLimited: false
    ))
    let presentation = MenuBarCoachState(
        snapshot: staleNormalSnapshot,
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: true)
    ).gamingWorkHours

    #expect(presentation?.isCappedNow == false)
    #expect(presentation?.status == "Work window is active · Current allowance is awaiting a capped refresh")
}

@Test
func menuBarWorkHoursMaximumExposesStableReadOnlyAccessibilityContracts() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/ZoidCoachApp/MenuBarCoachView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("menu-bar.gaming.work-hours"))
    #expect(source.contains("menu-bar.gaming.work-hours.maximum"))
    #expect(source.contains("menu-bar.gaming.work-hours.status"))
    #expect(!source.contains("menu-bar.gaming.work-hours.toggle"))
}

private func workHoursMenuSnapshot(_ gaming: GamingStatus) -> TodaySnapshot {
    TodaySnapshot(
        localDate: Date(timeIntervalSince1970: 1_800_000_000),
        timeZoneIdentifier: "Africa/Cairo",
        mainObjective: nil,
        taskRows: [],
        activeTask: nil,
        recommendation: .init(taskID: nil, sentence: "Nothing ready", reasons: []),
        behavior: BehaviorSummary(),
        coverage: TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: nil),
        gaming: gaming,
        sourceFreshnessExplanation: "Current",
        sources: []
    )
}
