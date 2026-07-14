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
    #expect(lockedDuringWork.earnedMinutes == 0)
    #expect(lockedDuringWork.lockedMinutes == 10)
    #expect(lockedDuringWork.unlockedRemainingMinutes == 60)
    #expect(lockedDuringWork.workHoursMaximumEvaluation == .init(
        configuredMaximumMinutes: 70,
        isApplied: true
    ))
}

@Test
func configuredWorkWindowUsesPolicyTimeZoneAndAcceptsATotalAllowanceMaximum() throws {
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    let mondayAtNoonUTC = try #require(ISO8601DateFormatter().date(from: "2026-07-13T09:00:00Z"))
    let mondayAfterWorkUTC = try #require(ISO8601DateFormatter().date(from: "2026-07-13T20:00:00Z"))

    #expect(original.schedule.isWithinWorkWindow(at: mondayAtNoonUTC))
    #expect(!original.schedule.isWithinWorkWindow(at: mondayAfterWorkUTC))

    let partialRewardGaming = GamingPolicy(
        dailyBudgetMinutes: 60,
        priorityTaskRewardMinutes: 15,
        workHoursDailyMaximumMinutes: 70
    )
    let valid = UserPolicy(
        operatingMode: original.operatingMode,
        automationPause: original.automationPause,
        schedule: original.schedule,
        calendar: original.calendar,
        privacy: original.privacy,
        wake: original.wake,
        behavior: original.behavior,
        capture: original.capture,
        gaming: partialRewardGaming,
        reminderLists: original.reminderLists
    )
    #expect(!valid.validationViolations().contains {
        $0.field == "gaming.workHoursDailyMaximumMinutes"
    })

    let invalid = policyReplacingGaming(
        original,
        GamingPolicy(
            dailyBudgetMinutes: 60,
            priorityTaskRewardMinutes: 15,
            workHoursDailyMaximumMinutes: 1_441
        )
    )
    #expect(invalid.validationViolations().contains {
        $0.field == "gaming.workHoursDailyMaximumMinutes"
    })
}

@Test
func workWindowUsesStartDayForTheAfterMidnightHalfOfAnOvernightWindow() throws {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo").schedule
    let schedule = SchedulePolicy(
        timeZoneIdentifier: "Africa/Cairo",
        workWindows: [WeeklyWorkWindow(
            weekdays: [.monday],
            start: LocalTime(hour: 23, minute: 0),
            end: LocalTime(hour: 7, minute: 0)
        )],
        quietHours: defaults.quietHours,
        nightlyPlanningTime: defaults.nightlyPlanningTime,
        morningConfirmationTime: defaults.morningConfirmationTime,
        dailyReviewTime: defaults.dailyReviewTime,
        planningCapacityPercent: defaults.planningCapacityPercent,
        defaultCoachingPauseDuration: defaults.defaultCoachingPauseDuration
    )
    let mondayLate = try #require(ISO8601DateFormatter().date(from: "2026-07-13T20:30:00Z"))
    let tuesdayEarly = try #require(ISO8601DateFormatter().date(from: "2026-07-13T22:30:00Z"))
    let tuesdayAfter = try #require(ISO8601DateFormatter().date(from: "2026-07-14T05:30:00Z"))

    #expect(schedule.isWithinWorkWindow(at: mondayLate))
    #expect(schedule.isWithinWorkWindow(at: tuesdayEarly))
    #expect(!schedule.isWithinWorkWindow(at: tuesdayAfter))
    let interval = try #require(schedule.workIntervals(on: mondayLate).first)
    #expect(interval.end.timeIntervalSince(interval.start) == 8 * 60 * 60)

    let policy = policyReplacingSchedule(.defaults(timeZoneIdentifier: "Africa/Cairo"), schedule)
    #expect(!policy.validationViolations().contains { $0.code == .invalidWorkWindow })

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-overnight-work-window-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.saveSystemMaintenancePolicy(policy)
    let reopened = try #require(try PolicyStore(databaseURL: databaseURL).current()?.policy)
    #expect(reopened.schedule.workWindows == schedule.workWindows)
    #expect(reopened.schedule.isWithinWorkWindow(at: tuesdayEarly))
}

@Test
func cyclicOverlapValidationDetectsTheAfterMidnightHalfWithoutRejectingTouchingEdges() {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    func policy(secondStart: LocalTime) -> UserPolicy {
        policyReplacingSchedule(defaults, SchedulePolicy(
            timeZoneIdentifier: "Africa/Cairo",
            workWindows: [
                WeeklyWorkWindow(
                    weekdays: [.monday],
                    start: LocalTime(hour: 23, minute: 0),
                    end: LocalTime(hour: 7, minute: 0)
                ),
                WeeklyWorkWindow(
                    weekdays: [.tuesday],
                    start: secondStart,
                    end: LocalTime(hour: 8, minute: 0)
                ),
            ],
            quietHours: defaults.schedule.quietHours,
            nightlyPlanningTime: defaults.schedule.nightlyPlanningTime,
            morningConfirmationTime: defaults.schedule.morningConfirmationTime,
            dailyReviewTime: defaults.schedule.dailyReviewTime,
            planningCapacityPercent: defaults.schedule.planningCapacityPercent,
            defaultCoachingPauseDuration: defaults.schedule.defaultCoachingPauseDuration
        ))
    }

    #expect(policy(secondStart: LocalTime(hour: 6, minute: 0)).validationViolations().contains {
        $0.code == .overlappingWorkWindows
    })
    #expect(!policy(secondStart: LocalTime(hour: 7, minute: 0)).validationViolations().contains {
        $0.code == .overlappingWorkWindows
    })
}

@Test
func workWindowUsesThePolicyTimeZoneAcrossADaylightSavingTransition() throws {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "Europe/London").schedule
    let schedule = SchedulePolicy(
        timeZoneIdentifier: "Europe/London",
        workWindows: [WeeklyWorkWindow(
            weekdays: [.sunday],
            start: LocalTime(hour: 0, minute: 0),
            end: LocalTime(hour: 4, minute: 0)
        )],
        quietHours: defaults.quietHours,
        nightlyPlanningTime: defaults.nightlyPlanningTime,
        morningConfirmationTime: defaults.morningConfirmationTime,
        dailyReviewTime: defaults.dailyReviewTime,
        planningCapacityPercent: defaults.planningCapacityPercent,
        defaultCoachingPauseDuration: defaults.defaultCoachingPauseDuration
    )
    let afterSpringForward = try #require(ISO8601DateFormatter().date(from: "2026-03-29T01:30:00Z"))
    #expect(schedule.isWithinWorkWindow(at: afterSpringForward))
}

@Test
func legacyGamingStatusDecodesWithoutWorkHoursEvaluationProvenance() throws {
    let data = Data(#"{"budgetMinutes":60,"usedMinutes":20,"unlockedRemainingMinutes":40,"nextUnlockReason":"Available","confidenceIsLimited":false}"#.utf8)
    let decoded = try JSONDecoder().decode(GamingStatus.self, from: data)
    #expect(decoded.workHoursMaximumEvaluation == nil)
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
func settingsAllowsTheTotalAllowanceMaximumAcrossTheFullDailyRange() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    var draft = SettingsPolicyDraft(policy: original)
    draft.gamingDailyBudgetMinutes = 60
    draft.gamingPriorityTaskRewardMinutes = 15
    draft.gamingWorkHoursMaximumEnabled = true
    draft.gamingWorkHoursDailyMaximumMinutes = 1_440

    let saved = draft.policy(preserving: original)

    #expect(saved.gaming.workHoursDailyMaximumMinutes == 1_440)
    #expect(!saved.validationViolations().contains {
        $0.field == "gaming.workHoursDailyMaximumMinutes"
    })
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
    let drift = try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift"),
        encoding: .utf8
    )
    let conflict = try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift"),
        encoding: .utf8
    )

    #expect(source.contains("settings.gaming.work-hours-maximum-enabled"))
    #expect(source.contains("settings.gaming.work-hours-maximum"))
    #expect(source.contains("settings.gaming.work-hours-maximum-detail"))
    #expect(source.contains("the total daily allowance, including base and unlocked rewards"))
    #expect(source.contains("in: 0...1_440"))
    #expect(agent.contains("isWithinWorkWindow: userPolicy.schedule.isWithinWorkWindow(at: now)"))
    #expect(drift.contains("policy.schedule.isWithinWorkWindow(at: date)"))
    #expect(conflict.contains("Work-hours gaming maximum enabled"))
    #expect(conflict.contains("Work-hours gaming maximum minutes"))
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
        confidenceIsLimited: false,
        workHoursMaximumEvaluation: .init(configuredMaximumMinutes: 30, isApplied: true)
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
        confidenceIsLimited: false,
        workHoursMaximumEvaluation: .init(configuredMaximumMinutes: 30, isApplied: false)
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
        confidenceIsLimited: false,
        workHoursMaximumEvaluation: .init(configuredMaximumMinutes: 30, isApplied: false)
    ))
    let presentation = MenuBarCoachState(
        snapshot: staleNormalSnapshot,
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: true)
    ).gamingWorkHours

    #expect(presentation?.isCappedNow == false)
    #expect(presentation?.status == "Current allowance is awaiting a work-hours policy refresh")
}

@Test
func menuBarWaitsForRefreshWhenLeavingWorkHoursOrChangingTheMaximum() {
    let staleCappedSnapshot = workHoursMenuSnapshot(GamingStatus(
        budgetMinutes: 30,
        usedMinutes: 20,
        unlockedRemainingMinutes: 10,
        nextUnlockReason: "Work-hours gaming is capped at 30 minutes.",
        confidenceIsLimited: false,
        workHoursMaximumEvaluation: .init(configuredMaximumMinutes: 30, isApplied: true)
    ))

    let leaving = MenuBarCoachState(
        snapshot: staleCappedSnapshot,
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: false)
    ).gamingWorkHours
    #expect(leaving?.isAwaitingRefresh == true)
    #expect(leaving?.status == "Current allowance is awaiting a work-hours policy refresh")

    let changedMaximum = MenuBarCoachState(
        snapshot: staleCappedSnapshot,
        gamingWorkHoursContext: .init(maximumMinutes: 40, isWithinWorkWindow: true)
    ).gamingWorkHours
    #expect(changedMaximum?.isAwaitingRefresh == true)
    #expect(changedMaximum?.maximumLabel == "40 MIN MAXIMUM")
}

@Test
func menuBarOmitsDisabledMaximumOnlyAfterAProvenanceMatchedRefresh() {
    let refreshed = workHoursMenuSnapshot(GamingStatus(
        budgetMinutes: 60,
        usedMinutes: 0,
        unlockedRemainingMinutes: 60,
        nextUnlockReason: "Available",
        confidenceIsLimited: false,
        workHoursMaximumEvaluation: .init(configuredMaximumMinutes: nil, isApplied: false)
    ))
    #expect(MenuBarCoachState(
        snapshot: refreshed,
        gamingWorkHoursContext: .init(maximumMinutes: nil, isWithinWorkWindow: false)
    ).gamingWorkHours == nil)
}

@Test
func menuBarUsesTheManualAdjustedAuthoritativeGamingStatus() {
    let raw = GamingStatus(
        budgetMinutes: 60,
        earnedMinutes: 15,
        usedMinutes: 20,
        unlockedRemainingMinutes: 55,
        nextUnlockReason: "Priority-task reward already applied today.",
        confidenceIsLimited: false,
        workHoursMaximumEvaluation: .init(configuredMaximumMinutes: 30, isApplied: false)
    )
    let adjusted = raw.applyingManualAdjustment(10)
    let presentation = MenuBarCoachState(
        snapshot: workHoursMenuSnapshot(raw),
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: false),
        authoritativeGamingStatus: adjusted,
        gamingStatusIsConfirmed: true
    ).gamingWorkHours

    #expect(presentation?.remainingMinutes == 65)
    #expect(presentation?.status == "Not active now · Normal allowance has 65m remaining")
}

@Test
func menuBarWaitsWhenTheAuthoritativeGamingStatusIsNotConfirmedFresh() {
    let status = GamingStatus(
        budgetMinutes: 30,
        usedMinutes: 20,
        unlockedRemainingMinutes: 10,
        nextUnlockReason: "Work-hours gaming is capped at 30 minutes.",
        confidenceIsLimited: false,
        workHoursMaximumEvaluation: .init(configuredMaximumMinutes: 30, isApplied: true)
    )
    let presentation = MenuBarCoachState(
        snapshot: workHoursMenuSnapshot(status),
        gamingWorkHoursContext: .init(maximumMinutes: 30, isWithinWorkWindow: true),
        authoritativeGamingStatus: status,
        gamingStatusIsConfirmed: false
    ).gamingWorkHours

    #expect(presentation?.isAwaitingRefresh == true)
    #expect(presentation?.status == "Current allowance is awaiting a work-hours policy refresh")
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
    #expect(source.contains("authoritativeGamingStatus: appModel.todaySnapshot?.gaming"))
    #expect(source.contains("controller.syncPresentation == .confirmed"))
}

@Test
func workHoursMaximumProbeSelectsTheRequestedSurfaceAndScansPrivacyRecursively() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repositoryRoot.appendingPathComponent(
            "Scripts/zc-029-010-work-hours-gaming-maximum-ax-probe.swift"
        ),
        encoding: .utf8
    )

    #expect(!source.contains("windows.first(where:"))
    #expect(source.contains("usesApplicationRoot(mode)"))
    #expect(source.contains("settings.gaming.work-hours-maximum-enabled"))
    #expect(source.contains("today.gaming.status"))
    #expect(source.contains("menu-bar.gaming.work-hours"))
    #expect(source.contains("privacyViolation(in: elements.flatMap(strings))"))
    #expect(source.contains("runSelfTest"))
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

private func policyReplacingSchedule(_ policy: UserPolicy, _ schedule: SchedulePolicy) -> UserPolicy {
    UserPolicy(
        operatingMode: policy.operatingMode,
        automationPause: policy.automationPause,
        schedule: schedule,
        calendar: policy.calendar,
        privacy: policy.privacy,
        wake: policy.wake,
        behavior: policy.behavior,
        capture: policy.capture,
        gaming: policy.gaming,
        reminderLists: policy.reminderLists
    )
}

private func policyReplacingGaming(_ policy: UserPolicy, _ gaming: GamingPolicy) -> UserPolicy {
    UserPolicy(
        operatingMode: policy.operatingMode,
        automationPause: policy.automationPause,
        schedule: policy.schedule,
        calendar: policy.calendar,
        privacy: policy.privacy,
        wake: policy.wake,
        behavior: policy.behavior,
        capture: policy.capture,
        gaming: gaming,
        reminderLists: policy.reminderLists
    )
}
