import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func settingsAIRequestBudgetsRoundTripAndMergeIndependently() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var mine = SettingsPolicyDraft(policy: original)
    mine.aiDailyRequestBudget = 40
    mine.aiMonthlyRequestBudget = 600

    let saved = mine.policy(preserving: original)
    #expect(saved.privacy.effectiveAIDailyRequestBudget == 40)
    #expect(saved.privacy.effectiveAIMonthlyRequestBudget == 600)
    #expect(SettingsPolicyDraft(policy: saved).aiDailyRequestBudget == 40)
    #expect(SettingsPolicyDraft(policy: saved).aiMonthlyRequestBudget == 600)
    #expect(saved.validationViolations().isEmpty)

    let base = SettingsPolicyDraft(policy: original)
    var current = base
    current.aiDailyRequestBudget = 75
    let merged = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)
    #expect(merged.safeDraft.aiDailyRequestBudget == 75)
    #expect(merged.safeDraft.aiMonthlyRequestBudget == 600)
    #expect(merged.concurrentChanges == ["AI daily request budget"])
    #expect(merged.overlappingChanges == ["AI daily request budget"])
}

@Test
func settingsScreenwatchIngestionPauseRoundTripsAndMergesIndependently() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var mine = SettingsPolicyDraft(policy: original)
    mine.screenwatchIngestionEnabled = false
    let saved = mine.policy(preserving: original)

    #expect(!saved.capture.ingestionEnabled)
    #expect(!SettingsPolicyDraft(policy: saved).screenwatchIngestionEnabled)

    let base = SettingsPolicyDraft(policy: original)
    var current = base
    current.capacityPercent = 55
    let merged = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)

    #expect(!merged.safeDraft.screenwatchIngestionEnabled)
    #expect(merged.safeDraft.capacityPercent == 55)
    #expect(merged.concurrentChanges == ["Planning capacity"])
    #expect(merged.overlappingChanges.isEmpty)
}

@Test
func settingsRoundTripsConfiguredCoachingLevelAndGamingAllowance() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)
    draft.maximumInterventionLevel = .accountability
    draft.gamingDailyBudgetMinutes = 95
    draft.gamingPriorityTaskRewardMinutes = 25
    draft.gamingIntentionalOverrideMinutes = 25
    draft.gamingDailyPromptCap = 4
    draft.gamingPromptCooldownMinutes = 35
    draft.gamingTaskStartGraceMinutes = 12
    draft.gamingReturnFromIdleGraceMinutes = 4

    let saved = draft.policy(preserving: original)

    #expect(saved.gaming.coachingLevel == .accountability)
    #expect(saved.gaming.dailyBudgetMinutes == 95)
    #expect(saved.gaming.priorityTaskRewardMinutes == 25)
    #expect(saved.gaming.intentionalOverrideMinutes == 25)
    #expect(saved.gaming.dailyPromptCap == 4)
    #expect(saved.gaming.promptCooldownMinutes == 35)
    #expect(saved.gaming.taskStartGraceMinutes == 12)
    #expect(saved.gaming.returnFromIdleGraceMinutes == 4)
    #expect(SettingsPolicyDraft(policy: saved).coachingLevel == .accountability)
    #expect(SettingsPolicyDraft(policy: saved).maximumInterventionLevel == .accountability)
    #expect(SettingsPolicyDraft(policy: saved).gamingDailyBudgetMinutes == 95)
    #expect(SettingsPolicyDraft(policy: saved).gamingPriorityTaskRewardMinutes == 25)
    #expect(SettingsPolicyDraft(policy: saved).gamingIntentionalOverrideMinutes == 25)
    #expect(SettingsPolicyDraft(policy: saved).gamingDailyPromptCap == 4)
    #expect(SettingsPolicyDraft(policy: saved).gamingPromptCooldownMinutes == 35)
    #expect(SettingsPolicyDraft(policy: saved).gamingTaskStartGraceMinutes == 12)
    #expect(SettingsPolicyDraft(policy: saved).gamingReturnFromIdleGraceMinutes == 4)

    let beforeCompletion = GamingStatusCalculator().status(
        policy: saved.gaming,
        gamingMinutes: 20,
        rewardApplied: false,
        coverage: TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: Date())
    )
    #expect(beforeCompletion.budgetMinutes == 95)
    #expect(beforeCompletion.unlockedRemainingMinutes == 75)
    #expect(beforeCompletion.nextUnlockReason.contains("one priority task"))

    let afterCompletion = GamingStatusCalculator().status(
        policy: saved.gaming,
        gamingMinutes: 20,
        rewardApplied: true,
        coverage: TelemetryCoverage(isLimited: false, explanation: "Current", lastObservationAt: Date())
    )
    #expect(afterCompletion.unlockedRemainingMinutes == 100)
    #expect(afterCompletion.nextUnlockReason.contains("already applied"))
}

@Test
func maximumInterventionLevelIsAnExplicitAliasForThePersistedCoachingCeiling() {
    var draft = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "UTC"))

    draft.maximumInterventionLevel = .accountability
    #expect(draft.coachingLevel == .accountability)

    draft.maximumInterventionLevel = .gentle
    #expect(draft.coachingLevel == .gentle)
    #expect(draft.policy(preserving: .defaults(timeZoneIdentifier: "UTC")).gaming.coachingLevel == .gentle)
}

@Test
func settingsRoundTripsGamingObservationModeWithoutDiscardingConfiguredValues() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)
    draft.gamingBudgetEnabled = false
    draft.gamingDailyBudgetMinutes = 95
    draft.gamingPriorityTaskRewardMinutes = 25

    let saved = draft.policy(preserving: original)
    #expect(!saved.gaming.budgetEnabled)
    #expect(saved.gaming.dailyBudgetMinutes == 95)
    #expect(saved.gaming.priorityTaskRewardMinutes == 25)
    #expect(!SettingsPolicyDraft(policy: saved).gamingBudgetEnabled)
}

@Test
func settingsConflictResolverPreservesConcurrentCoachingLevelChoice() {
    let base = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "UTC"))
    var mine = base
    mine.coachingLevel = .accountability
    var current = base
    current.capacityPercent = 55

    let result = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)

    #expect(result.safeDraft.coachingLevel == .accountability)
    #expect(result.safeDraft.capacityPercent == 55)
    #expect(result.overlappingChanges.isEmpty)
}

@Test
func settingsTimeZoneRoundTripsAndParticipatesInConflictResolution() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    var draft = SettingsPolicyDraft(policy: original)
    draft.timeZoneIdentifier = "America/Los_Angeles"

    let saved = draft.policy(preserving: original)
    #expect(saved.schedule.timeZoneIdentifier == "America/Los_Angeles")
    #expect(SettingsPolicyDraft(policy: saved).timeZoneIdentifier == "America/Los_Angeles")
    #expect(saved.validationViolations().isEmpty)

    let base = SettingsPolicyDraft(policy: original)
    var mine = base
    mine.timeZoneIdentifier = "America/Los_Angeles"
    var current = base
    current.capacityPercent = 55

    let independent = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)
    #expect(independent.safeDraft.timeZoneIdentifier == "America/Los_Angeles")
    #expect(independent.safeDraft.capacityPercent == 55)
    #expect(independent.overlappingChanges.isEmpty)

    current.timeZoneIdentifier = "Asia/Tokyo"
    let overlap = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)
    #expect(overlap.safeDraft.timeZoneIdentifier == "Asia/Tokyo")
    #expect(overlap.retryDraft.timeZoneIdentifier == "America/Los_Angeles")
    #expect(overlap.overlappingChanges == ["Time zone"])
}

@Test
func changingPolicyTimeZonePreservesHistoricalEventInstantsAcrossRestart() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-settings-time-zone-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let completedAt = try #require(ISO8601DateFormatter().date(from: "2026-07-13T21:45:00Z"))

    let history = try TaskHistoryStore(databaseURL: databaseURL)
    try history.record(
        taskID: "time-zone-history",
        state: .completed,
        title: "Keep the original instant",
        sourceKind: .local,
        at: completedAt
    )

    let policyStore = try PolicyStore(databaseURL: databaseURL)
    _ = try policyStore.saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "Africa/Cairo"))
    var draft = SettingsPolicyDraft(policy: try #require(policyStore.current()?.policy))
    draft.timeZoneIdentifier = "America/Los_Angeles"
    _ = try policyStore.saveSystemMaintenancePolicy(
        draft.policy(preserving: try #require(policyStore.current()?.policy))
    )

    let reopenedPolicy = try PolicyStore(databaseURL: databaseURL)
    let reopenedHistory = try TaskHistoryStore(databaseURL: databaseURL)
    #expect(try reopenedPolicy.current()?.policy.schedule.timeZoneIdentifier == "America/Los_Angeles")
    let entry = try #require(reopenedHistory.completedEntries(for: completedAt).first)
    #expect(entry.completedAt == completedAt)
    #expect(entry.title == "Keep the original instant")
}

@Test
func settingsConflictResolverPreservesIndependentGamingAllowanceAndFlagsOverlap() {
    let base = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "UTC"))
    var mine = base
    mine.gamingDailyBudgetMinutes = 75
    mine.gamingPriorityTaskRewardMinutes = 20
    mine.gamingIntentionalOverrideMinutes = 25
    mine.gamingDailyPromptCap = 4
    mine.gamingPromptCooldownMinutes = 35
    mine.gamingTaskStartGraceMinutes = 12
    mine.gamingReturnFromIdleGraceMinutes = 4
    var current = base
    current.capacityPercent = 55

    let independent = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)
    #expect(independent.safeDraft.gamingDailyBudgetMinutes == 75)
    #expect(independent.safeDraft.gamingPriorityTaskRewardMinutes == 20)
    #expect(independent.safeDraft.gamingIntentionalOverrideMinutes == 25)
    #expect(independent.safeDraft.gamingDailyPromptCap == 4)
    #expect(independent.safeDraft.gamingPromptCooldownMinutes == 35)
    #expect(independent.safeDraft.gamingTaskStartGraceMinutes == 12)
    #expect(independent.safeDraft.gamingReturnFromIdleGraceMinutes == 4)
    #expect(independent.safeDraft.capacityPercent == 55)
    #expect(independent.overlappingChanges.isEmpty)

    current.gamingDailyBudgetMinutes = 30
    let overlapping = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)
    #expect(overlapping.safeDraft.gamingDailyBudgetMinutes == 30)
    #expect(overlapping.retryDraft.gamingDailyBudgetMinutes == 75)
    #expect(overlapping.overlappingChanges == ["Gaming daily budget"])

    current.gamingIntentionalOverrideMinutes = 90
    let overrideOverlap = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)
    #expect(overrideOverlap.safeDraft.gamingIntentionalOverrideMinutes == 90)
    #expect(overrideOverlap.retryDraft.gamingIntentionalOverrideMinutes == 25)
    #expect(overrideOverlap.overlappingChanges.contains("Intentional gaming override"))

    current.gamingDailyPromptCap = 2
    current.gamingPromptCooldownMinutes = 90
    current.gamingTaskStartGraceMinutes = 6
    current.gamingReturnFromIdleGraceMinutes = 2
    let limitsOverlap = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)
    #expect(limitsOverlap.safeDraft.gamingDailyPromptCap == 2)
    #expect(limitsOverlap.retryDraft.gamingDailyPromptCap == 4)
    #expect(limitsOverlap.safeDraft.gamingPromptCooldownMinutes == 90)
    #expect(limitsOverlap.retryDraft.gamingPromptCooldownMinutes == 35)
    #expect(limitsOverlap.safeDraft.gamingTaskStartGraceMinutes == 6)
    #expect(limitsOverlap.retryDraft.gamingTaskStartGraceMinutes == 12)
    #expect(limitsOverlap.safeDraft.gamingReturnFromIdleGraceMinutes == 2)
    #expect(limitsOverlap.retryDraft.gamingReturnFromIdleGraceMinutes == 4)
}

@MainActor
private final class SettingsRefreshRecorder {
    private(set) var count = 0

    func record() { count += 1 }
}

@MainActor
private final class SettingsReminderLoadGate {
    private var continuations: [CheckedContinuation<ReminderListLoad, Never>] = []

    var count: Int { continuations.count }

    func wait() async -> ReminderListLoad {
        await withCheckedContinuation { continuations.append($0) }
    }

    func resume(_ index: Int, with result: ReminderListLoad) {
        continuations[index].resume(returning: result)
    }
}

@Test
func settingsDraftRoundTripsPolicyAndNormalizesLocalOnlyEvidence() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    var draft = SettingsPolicyDraft(policy: original)
    draft.operatingMode = .approvalRequired
    draft.isPaused = true
    draft.capacityPercent = 80
    draft.nightlyPlanningTime = LocalTime(hour: 21, minute: 45)
    draft.morningConfirmationTime = LocalTime(hour: 7, minute: 15)
    draft.dailyReviewTime = LocalTime(hour: 19, minute: 30)
    draft.workWeekdays = [.monday, .wednesday, .saturday]
    draft.visibleCalendarIdentifiers = "work, personal"
    draft.schedulingCalendarIdentifier = "work"
    draft.aiProvider = .localOllama
    draft.remoteEvidencePolicy = .explicitPrivateContent
    draft.rawScreenshotRetentionDays = 7

    let policy = draft.policy(preserving: original)

    #expect(policy.operatingMode == .approvalRequired)
    #expect(policy.automationPause == .pausedIndefinitely)
    #expect(policy.schedule.planningCapacityPercent == 80)
    #expect(policy.schedule.nightlyPlanningTime == LocalTime(hour: 21, minute: 45))
    #expect(policy.schedule.morningConfirmationTime == LocalTime(hour: 7, minute: 15))
    #expect(policy.schedule.dailyReviewTime == LocalTime(hour: 19, minute: 30))
    #expect(policy.schedule.workWindows == [WeeklyWorkWindow(
        weekdays: [.monday, .wednesday, .saturday],
        start: LocalTime(hour: 9, minute: 0),
        end: LocalTime(hour: 18, minute: 0)
    )])
    #expect(policy.calendar.visibleCalendarIdentifiers == ["work", "personal"])
    #expect(policy.calendar.schedulingCalendarIdentifier == "work")
    #expect(policy.privacy.remoteEvidencePolicy == .localOnly)
    #expect(policy.privacy.rawScreenshotRetentionDays == 7)
    #expect(policy.validationViolations().isEmpty)
}

@Test
func settingsDraftRequiresOneWorkdayAndKeepsSelectionSorted() {
    var draft = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "UTC"))
    draft.workWeekdays = [.monday]

    draft.toggleWorkWeekday(.monday)
    #expect(draft.workWeekdays == [.monday])

    draft.toggleWorkWeekday(.saturday)
    draft.toggleWorkWeekday(.sunday)
    #expect(draft.workWeekdays == [.sunday, .monday, .saturday])

    draft.toggleWorkWeekday(.monday)
    #expect(draft.workWeekdays == [.sunday, .saturday])
}

@Test
func settingsDraftPreservesMultipleWorkWindowDayGroupsUntilSelectionChanges() {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let original = UserPolicy(
        operatingMode: defaults.operatingMode,
        automationPause: defaults.automationPause,
        schedule: SchedulePolicy(
            timeZoneIdentifier: "UTC",
            workWindows: [
                WeeklyWorkWindow(
                    weekdays: [.monday, .tuesday],
                    start: LocalTime(hour: 9, minute: 0),
                    end: LocalTime(hour: 17, minute: 0)
                ),
                WeeklyWorkWindow(
                    weekdays: [.saturday],
                    start: LocalTime(hour: 10, minute: 0),
                    end: LocalTime(hour: 14, minute: 0)
                )
            ],
            quietHours: defaults.schedule.quietHours,
            nightlyPlanningTime: defaults.schedule.nightlyPlanningTime,
            morningConfirmationTime: defaults.schedule.morningConfirmationTime,
            dailyReviewTime: defaults.schedule.dailyReviewTime,
            planningCapacityPercent: defaults.schedule.planningCapacityPercent
        ),
        calendar: defaults.calendar,
        privacy: defaults.privacy,
        wake: defaults.wake,
        behavior: defaults.behavior,
        capture: defaults.capture,
        gaming: defaults.gaming,
        reminderLists: defaults.reminderLists
    )
    var draft = SettingsPolicyDraft(policy: original)
    draft.workStart = LocalTime(hour: 8, minute: 30)
    draft.workEnd = LocalTime(hour: 16, minute: 30)

    let unchangedDays = draft.policy(preserving: original)
    #expect(unchangedDays.schedule.workWindows.map(\.weekdays) == [[.monday, .tuesday], [.saturday]])
    #expect(unchangedDays.schedule.workWindows.allSatisfy {
        $0.start == LocalTime(hour: 8, minute: 30) && $0.end == LocalTime(hour: 16, minute: 30)
    })

    draft.toggleWorkWeekday(.wednesday)
    let changedDays = draft.policy(preserving: original)
    #expect(changedDays.schedule.workWindows == [WeeklyWorkWindow(
        weekdays: [.monday, .tuesday, .wednesday, .saturday],
        start: LocalTime(hour: 8, minute: 30),
        end: LocalTime(hour: 16, minute: 30)
    )])
}

@Test
func settingsConflictResolverTreatsWorkingDaysAsAnIndependentPolicyChoice() {
    let base = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "UTC"))
    var mine = base
    mine.workWeekdays = [.monday, .tuesday, .wednesday]
    var current = base
    current.capacityPercent = 85

    let independent = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)
    #expect(independent.safeDraft.workWeekdays == mine.workWeekdays)
    #expect(independent.safeDraft.capacityPercent == 85)
    #expect(independent.overlappingChanges.isEmpty)

    current.workWeekdays = [.friday, .saturday]
    let overlap = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)
    #expect(overlap.safeDraft.workWeekdays == [.friday, .saturday])
    #expect(overlap.retryDraft.workWeekdays == mine.workWeekdays)
    #expect(overlap.overlappingChanges == ["Working days"])
}

@Test
func savedWorkingDaysDriveTheNextScheduledReviewWithoutAnAppRestart() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-workdays-runtime-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-13T10:00:00Z"))
    let store = try PolicyStore(databaseURL: databaseURL, now: { now })
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    _ = try store.saveSystemMaintenancePolicy(original)
    var draft = SettingsPolicyDraft(policy: original)
    draft.workWeekdays = [.tuesday]
    let savedPolicy = draft.policy(preserving: original)
    _ = try store.saveMutation(PolicyMutationRequest(
        requestID: "settings-policy-v1:settings-workdays-runtime",
        expectedVersion: 1,
        policy: savedPolicy,
        origin: .settings
    ))
    let currentValue = try store.current()
    let current = try #require(currentValue)
    let outbox = try ActionOutboxStore(databaseURL: databaseURL, now: { now })

    let resultValue = try ReviewReminderService(outbox: outbox).reconcile(
        policy: current.policy,
        policyVersion: current.version,
        now: now
    )
    let result = try #require(resultValue)

    #expect(current.policy.schedule.workWindows.first?.weekdays == [.tuesday])
    #expect(result.daily.command.entityID == "daily-review:2026-07-14")
}

@Test
func calendarPickerSelectionsRoundTripWithoutExposingIdentifiersAsInput() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)

    draft.visibleCalendarIdentifierList = ["work-id", "personal-id"]
    draft.schedulingCalendarIdentifierValue = "work-id"

    #expect(draft.visibleCalendarIdentifierList == ["work-id", "personal-id"])
    #expect(draft.schedulingCalendarIdentifierValue == "work-id")

    draft.visibleCalendarIdentifierList = []
    draft.schedulingCalendarIdentifierValue = nil
    let policy = draft.policy(preserving: original)

    #expect(policy.calendar.visibleCalendarIdentifiers.isEmpty)
    #expect(policy.calendar.schedulingCalendarIdentifier == nil)
}

@Test
func reminderListDraftPersistsExplicitChoicesByIdentifier() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)

    draft.setReminderListDecision(true, listID: "work-id")
    draft.setReminderListDecision(false, listID: "personal-id")
    draft.confirmReminderListConfiguration()
    draft.capacityPercent = 85
    let policy = draft.policy(preserving: original)

    #expect(policy.reminderLists.isConfigured)
    #expect(policy.reminderLists.decision(for: "work-id") == true)
    #expect(policy.reminderLists.decision(for: "personal-id") == false)
    #expect(!policy.reminderLists.includes(listID: "new-id"))
    #expect(policy.schedule.planningCapacityPercent == 85)
}

@MainActor
@Test
func policyRollbackRestoresPreviousSettingsAsANewVersion() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-policy-rollback-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    let first = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    _ = try store.save(first)
    var changedDraft = SettingsPolicyDraft(policy: first)
    changedDraft.capacityPercent = 85
    _ = try store.save(changedDraft.policy(preserving: first))
    let controller = SettingsPolicyController(databaseURL: databaseURL) { request in
        let saved = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: saved.resultingVersion,
            policyMutationReceipt: saved
        )
    }

    await controller.rollbackToPreviousPolicy()?.value

    #expect(try store.current()?.version == 3)
    #expect(try store.current()?.policy.schedule.planningCapacityPercent == first.schedule.planningCapacityPercent)
}

@MainActor
@Test
func timeZonePlanDayMoveRequiresExplicitConfirmationBeforeSaving() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-time-zone-confirmation-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let referenceDate = try #require(ISO8601DateFormatter().date(from: "2026-07-14T00:30:00Z"))
    let warning = TimeZonePlanMoveWarning(
        sourceTimeZoneIdentifier: "UTC",
        destinationTimeZoneIdentifier: "America/Los_Angeles",
        sourceDayKey: "2026-07-14",
        destinationDayKey: "2026-07-13",
        taskCount: 2,
        referenceDate: referenceDate
    )
    let controller = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { request in
            let saved = try store.saveMutation(request)
            return AgentMutationReceipt(
                accepted: true,
                message: "saved",
                policyVersion: saved.resultingVersion,
                policyMutationReceipt: saved
            )
        },
        inspectTimeZonePlanMove: { _, _, _ in warning }
    )
    controller.draft.timeZoneIdentifier = "America/Los_Angeles"

    #expect(controller.save(now: referenceDate) == nil)
    #expect(controller.timeZonePlanMoveConfirmation == warning)
    #expect(try store.current()?.version == 1)
    controller.cancelTimeZonePlanMove()
    #expect(controller.draft.timeZoneIdentifier == "America/Los_Angeles")
    #expect(try store.current()?.policy.schedule.timeZoneIdentifier == "UTC")

    #expect(controller.save(now: referenceDate) == nil)
    await controller.confirmTimeZonePlanMove()?.value

    #expect(controller.timeZonePlanMoveConfirmation == nil)
    #expect(try store.current()?.version == 2)
    #expect(try store.current()?.policy.schedule.timeZoneIdentifier == "America/Los_Angeles")
}

@MainActor
@Test
func timeZoneChangeSavesDirectlyWhenNoPlanMovesLocalDay() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-time-zone-no-plan-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let controller = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { request in
            let saved = try store.saveMutation(request)
            return AgentMutationReceipt(
                accepted: true,
                message: "saved",
                policyVersion: saved.resultingVersion,
                policyMutationReceipt: saved
            )
        },
        inspectTimeZonePlanMove: { _, _, _ in nil }
    )
    controller.draft.timeZoneIdentifier = "Europe/London"

    await controller.save()?.value

    #expect(controller.timeZonePlanMoveConfirmation == nil)
    #expect(try store.current()?.policy.schedule.timeZoneIdentifier == "Europe/London")
}

@MainActor
@Test
func timeZoneChangeFailsClosedWhenTheCurrentPlanCannotBeInspected() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-time-zone-inspection-error-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let controller = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { _ in throw TimeZonePlanMoveInspectorError.inspectPlan },
        inspectTimeZonePlanMove: { _, _, _ in throw TimeZonePlanMoveInspectorError.inspectPlan }
    )
    controller.draft.timeZoneIdentifier = "America/Los_Angeles"

    #expect(controller.save() == nil)
    #expect(try store.current()?.version == 1)
    #expect(controller.statusMessage?.contains("not saved") == true)
    #expect(controller.statusMessage?.contains("could not be checked") == true)
}

@MainActor
@Test
func confirmedTimeZonePlanDayMovePreservesPolicyAndHistoricalPlanAfterRelaunch() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-time-zone-relaunch-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let referenceDate = try #require(ISO8601DateFormatter().date(from: "2026-07-14T00:30:00Z"))
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let sourcePlanStore = try AutonomousPlanStore(databaseURL: databaseURL, timeZoneIdentifier: { "UTC" })
    try sourcePlanStore.replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: "preserved", title: "Preserve the plan", rank: 1, estimateMinutes: 30, reason: "due", score: 1)],
            mainObjectiveTaskID: "preserved",
            plannedFocusMinutes: 30,
            availableFocusMinutes: 60
        ),
        for: referenceDate
    )
    let savePolicy: @Sendable (PolicyMutationRequest) async throws -> AgentMutationReceipt = { request in
        let saved = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: saved.resultingVersion,
            policyMutationReceipt: saved
        )
    }
    let controller = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: savePolicy
    )
    controller.draft.timeZoneIdentifier = "America/Los_Angeles"

    #expect(controller.save(now: referenceDate) == nil)
    let warning = try #require(controller.timeZonePlanMoveConfirmation)
    #expect(warning.taskCount == 1)
    controller.cancelTimeZonePlanMove()
    #expect(try store.current()?.policy.schedule.timeZoneIdentifier == "UTC")
    #expect(try sourcePlanStore.loadDailyPlan(for: referenceDate).map(\.reminderID) == ["preserved"])

    #expect(controller.save(now: referenceDate) == nil)
    await controller.confirmTimeZonePlanMove()?.value
    let relaunched = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: savePolicy
    )
    let destinationPlanStore = try AutonomousPlanStore(
        databaseURL: databaseURL,
        timeZoneIdentifier: { "America/Los_Angeles" }
    )

    #expect(try store.current()?.policy.schedule.timeZoneIdentifier == "America/Los_Angeles")
    #expect(relaunched.draft.timeZoneIdentifier == "America/Los_Angeles")
    #expect(try sourcePlanStore.loadDailyPlan(for: referenceDate).map(\.reminderID) == ["preserved"])
    #expect(try destinationPlanStore.loadDailyPlan(for: referenceDate).isEmpty)
}

@Test
func settingsDraftKeepsWakeDisabledByDefault() {
    let policy = SettingsPolicyDraft(policy: .defaults()).policy(preserving: .defaults())

    #expect(policy.wake.isEligible == false)
    #expect(policy.wake.maximumDailyInterventions == 1)
}

@Test
func settingsDraftPersistsGlobalAppChoicesAndReturnsAppsToAutomatic() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)

    draft.setClassification(.work, for: " Steam ")
    draft.setClassification(.gaming, for: "Xcode")
    draft.setClassification(.automatic, for: "XCODE")
    let policy = draft.policy(preserving: original)

    #expect(policy.behavior.workApplications == ["steam"])
    #expect(policy.behavior.gamingApplications.isEmpty)
    #expect(SettingsPolicyDraft(policy: policy).classification(for: "Steam") == .work)
    #expect(SettingsPolicyDraft(policy: policy).classification(for: "Xcode") == .automatic)
}

@Test
func settingsDraftBulkEditsCommunicationRulesAndCanResetEveryExplicitRule() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)

    draft.setClassifications(.communication, for: ["Slack", "Discord", " slack "])
    draft.setClassifications(.work, for: ["Xcode", "Cursor"])
    draft.setClassifications(.gaming, for: ["Steam"])

    #expect(draft.settingsClassification(for: "Discord") == .communication)
    #expect(draft.behaviorPolicy.communicationApplications == ["discord", "slack"])
    #expect(draft.policy(preserving: original).behavior.classificationOverride(for: "Slack") == .work)

    draft.resetApplicationRules()

    #expect(draft.behaviorPolicy == BehaviorPolicy())
    #expect(draft.settingsClassification(for: "Steam") == .automatic)
}

@Test
func settingsDraftCannotPersistAnUnavailableAIProvider() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)
    draft.aiProvider = .remoteOpenAI
    draft.remoteEvidencePolicy = .explicitPrivateContent

    let policy = draft.policy(preserving: original)

    #expect(policy.privacy.aiProvider == .disabled)
    #expect(policy.privacy.remoteEvidencePolicy == .localOnly)
}

@Test
func settingsDraftPersistsCodexCLIWithRemoteEvidencePolicy() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)
    draft.selectAIProvider(.codexCLI)

    let policy = draft.policy(preserving: original)
    let roundTrippedDraft = SettingsPolicyDraft(policy: policy)

    #expect(policy.privacy.aiProvider == .codexCLI)
    #expect(draft.remoteEvidencePolicy == .redactedMetadataOnly)
    #expect(policy.privacy.remoteEvidencePolicy == .redactedMetadataOnly)
    #expect(policy.validationViolations().isEmpty)
    #expect(roundTrippedDraft.aiProvider == .codexCLI)
    #expect(roundTrippedDraft.remoteEvidencePolicy == .redactedMetadataOnly)

    draft.remoteEvidencePolicy = .localOnly
    let localOnlyPolicy = draft.policy(preserving: original)
    let localOnlyRoundTrip = SettingsPolicyDraft(policy: localOnlyPolicy)
    #expect(localOnlyPolicy.privacy.remoteEvidencePolicy == .localOnly)
    #expect(localOnlyRoundTrip.remoteEvidencePolicy == .localOnly)
}

@Test
func settingsDraftPersistsSelectedCodexModel() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)
    draft.selectAIProvider(.codexCLI)
    draft.codexCLIModel = .gpt55

    let policy = draft.policy(preserving: original)
    let roundTrippedDraft = SettingsPolicyDraft(policy: policy)

    #expect(policy.privacy.codexCLIModel == .gpt55)
    #expect(roundTrippedDraft.codexCLIModel == .gpt55)
}

@Test
func settingsDraftPresentsPersistedUnavailableProviderAsDisabled() {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let remotePolicy = UserPolicy(
        operatingMode: defaults.operatingMode,
        automationPause: defaults.automationPause,
        schedule: defaults.schedule,
        calendar: defaults.calendar,
        privacy: PrivacyPolicy(
            screenshotAnalysisEnabled: true,
            aiProvider: .remoteOpenAI,
            remoteEvidencePolicy: .explicitPrivateContent,
            rawScreenshotRetentionDays: 30,
            extractedTextRetentionDays: 30,
            diagnosticRetentionDays: 14
        ),
        wake: defaults.wake
    )

    let draft = SettingsPolicyDraft(policy: remotePolicy)

    #expect(draft.aiProvider == .disabled)
    #expect(draft.remoteEvidencePolicy == .localOnly)
}

@MainActor
@Test
func oneStepPausePersistsImmediatelyWithoutSavingOtherDraftEdits() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let controller = SettingsPolicyController(databaseURL: databaseURL) { request in
        let saved = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: saved.resultingVersion,
            policyMutationReceipt: saved
        )
    }
    controller.draft.capacityPercent = 95
    controller.draft.setClassification(.work, for: "Steam")

    await controller.setPaused(true)?.value

    let persisted = try #require(store.current()?.policy)
    #expect(persisted.automationPause == .pausedIndefinitely)
    #expect(persisted.schedule.planningCapacityPercent == 70)
    #expect(persisted.behavior.choice(for: "Steam") == .automatic)
    #expect(controller.draft.capacityPercent == 95)
    #expect(controller.draft.classification(for: "Steam") == .work)
}

@MainActor
@Test
func savedAppClassificationLoadsInANewSettingsController() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-app-settings-restart-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let controller = SettingsPolicyController(databaseURL: databaseURL) { request in
        let saved = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: saved.resultingVersion,
            policyMutationReceipt: saved
        )
    }
    controller.draft.setClassification(.gaming, for: "Steam")
    await controller.save()?.value

    let reopened = SettingsPolicyController(databaseURL: databaseURL) { _ in
        throw RestartTestError.unexpectedSave
    }

    #expect(reopened.draft.classification(for: "Steam") == .gaming)
}

@Test
func settingsDraftPreservesAnExactTimedPauseBoundary() throws {
    let boundary = try #require(ISO8601DateFormatter().date(from: "2099-07-13T11:00:00Z"))
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
        .replacingAutomationPause(AutomationPause(isPaused: true, resumesAtUTC: boundary))

    let draft = SettingsPolicyDraft(policy: original)
    let roundTripped = draft.policy(preserving: original)

    #expect(draft.isPaused)
    #expect(draft.automationPause.resumesAtUTC == boundary)
    #expect(roundTripped.automationPause == original.automationPause)
}

@MainActor
@Test
func timedPauseChoicesPersistImmediatelyAndResumeWithoutSavingOtherEdits() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-timed-pause-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "Africa/Cairo"))
    let controller = SettingsPolicyController(databaseURL: databaseURL) { request in
        let saved = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: saved.resultingVersion,
            policyMutationReceipt: saved
        )
    }
    controller.draft.capacityPercent = 95
    let oneHourStart = try #require(ISO8601DateFormatter().date(from: "2026-07-13T10:00:00Z"))

    await controller.pauseForOneHour(now: oneHourStart)?.value

    var persisted = try #require(store.current()?.policy)
    #expect(persisted.automationPause.resumesAtUTC == oneHourStart.addingTimeInterval(60 * 60))
    #expect(controller.draft.capacityPercent == 95)
    #expect(persisted.schedule.planningCapacityPercent == 70)

    let evening = try #require(ISO8601DateFormatter().date(from: "2026-07-13T20:30:00Z"))
    let localMidnight = try #require(ISO8601DateFormatter().date(from: "2026-07-13T21:00:00Z"))
    await controller.pauseUntilTomorrow(now: evening)?.value

    persisted = try #require(store.current()?.policy)
    #expect(persisted.automationPause.resumesAtUTC == localMidnight)

    await controller.setPaused(false)?.value

    persisted = try #require(store.current()?.policy)
    #expect(persisted.automationPause == .running)
    #expect(controller.draft.capacityPercent == 95)
}

@MainActor
@Test
func staleSettingsWindowCannotOverwriteANewerPolicyVersion() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-stale-settings-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let apply: @Sendable (PolicyMutationRequest) async throws -> AgentMutationReceipt = { request in
        let receipt = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: receipt.resultingVersion,
            policyMutationReceipt: receipt
        )
    }
    let first = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    let stale = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    first.draft.capacityPercent = 80
    stale.draft.capacityPercent = 95

    await first.save()?.value
    await stale.save()?.value

    #expect(try store.current()?.policy.schedule.planningCapacityPercent == 80)
    #expect(try store.current()?.version == 2)
    #expect(stale.activeVersion == 2)
    #expect(!stale.hasUnsavedChanges)
    #expect(stale.statusMessage?.contains("won the concurrent save") == true)
    #expect(stale.saveConflict?.winningVersion == 2)
    #expect(stale.saveConflict?.overlappingChanges == ["Planning capacity"])
    #expect(stale.draft.capacityPercent == 80)

    await stale.reapplyMyChanges()?.value

    #expect(try store.current()?.policy.schedule.planningCapacityPercent == 95)
    #expect(try store.current()?.version == 3)
    #expect(stale.activeVersion == 3)
    #expect(!stale.hasUnsavedChanges)
    #expect(stale.saveConflict == nil)
}

@Test
func settingsConflictResolverPreservesIndependentEditsAndCurrentWinners() {
    let base = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "UTC"))
    var mine = base
    mine.capacityPercent = 90
    mine.quietStart = LocalTime(hour: 20, minute: 30)
    var current = base
    current.capacityPercent = 80
    current.screenshotAnalysisEnabled = false

    let result = SettingsPolicyConflictResolver.resolve(
        base: base,
        mine: mine,
        current: current
    )

    #expect(result.safeDraft.capacityPercent == 80)
    #expect(result.safeDraft.quietStart == LocalTime(hour: 20, minute: 30))
    #expect(!result.safeDraft.screenshotAnalysisEnabled)
    #expect(result.retryDraft.capacityPercent == 90)
    #expect(result.retryDraft.quietStart == LocalTime(hour: 20, minute: 30))
    #expect(!result.retryDraft.screenshotAnalysisEnabled)
    #expect(result.overlappingChanges == ["Planning capacity"])
    #expect(result.concurrentChanges == ["Planning capacity", "Screenshot analysis"])
}

@MainActor
@Test
func repeatedConcurrentSettingsChangesRequireAChoiceEveryTimeWithoutDuplicateVersions() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-repeated-settings-conflict-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let apply: @Sendable (PolicyMutationRequest) async throws -> AgentMutationReceipt = { request in
        let receipt = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: receipt.resultingVersion,
            policyMutationReceipt: receipt
        )
    }
    let writer = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    let stale = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    stale.draft.capacityPercent = 95
    writer.draft.capacityPercent = 80
    await writer.save()?.value
    await stale.save()?.value
    #expect(stale.saveConflict?.winningVersion == 2)

    let secondWriter = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    secondWriter.draft.capacityPercent = 75
    await secondWriter.save()?.value
    await stale.reapplyMyChanges()?.value

    #expect(try store.current()?.version == 3)
    #expect(try store.current()?.policy.schedule.planningCapacityPercent == 75)
    #expect(stale.activeVersion == 3)
    #expect(stale.saveConflict?.winningVersion == 3)
    #expect(stale.saveConflict?.overlappingChanges == ["Planning capacity"])

    stale.keepCurrentWinningValues()
    #expect(stale.saveConflict == nil)
    #expect(stale.draft.capacityPercent == 75)
    #expect(try store.history().map(\.version) == [3, 2, 1])
}

@MainActor
@Test
func staleSettingsReminderListEditSurvivesConflictAndRetriesAgainstTheNewVersion() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-stale-reminder-settings-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let apply: @Sendable (PolicyMutationRequest) async throws -> AgentMutationReceipt = { request in
        let receipt = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: receipt.resultingVersion,
            policyMutationReceipt: receipt
        )
    }
    let first = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: apply
    )
    let stale = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: apply
    )
    first.draft.capacityPercent = 80
    stale.setReminderListDecision(true, listID: "  opaque-id  ")

    await first.save()?.value
    await stale.save()?.value

    #expect(stale.activeVersion == 2)
    #expect(stale.hasUnsavedChanges)
    #expect(stale.draft.reminderListPolicy.decision(for: "  opaque-id  ") == true)
    #expect(try store.current()?.policy.reminderLists == .legacyAllLists)

    await stale.save()?.value

    #expect(try store.current()?.version == 3)
    #expect(try store.current()?.policy.reminderLists.isConfigured == true)
    #expect(try store.current()?.policy.reminderLists.decision(for: "  opaque-id  ") == true)
    #expect(try store.current()?.policy.schedule.planningCapacityPercent == 80)
    #expect(!stale.hasUnsavedChanges)
}

@MainActor
@Test
func settingsDoNotAdvanceWithoutAnExactDurableMutationReceipt() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-receipt-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let controller = SettingsPolicyController(databaseURL: databaseURL) { _ in
        AgentMutationReceipt(accepted: true, message: "saved", policyVersion: 2)
    }
    controller.draft.capacityPercent = 95

    await controller.save()?.value

    #expect(try store.current()?.version == 1)
    #expect(controller.activeVersion == 1)
    #expect(controller.hasUnsavedChanges)
    #expect(controller.statusMessage?.contains("did not confirm") == true)
}

@MainActor
@Test
func settingsExposeTypedReminderPermissionAndExplicitEmptyLocalOnlyChoice() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-reminder-recovery-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    _ = try PolicyStore(databaseURL: databaseURL)
        .saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let permission = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { _ in
            AgentMutationReceipt(accepted: false, message: "unused", policyVersion: nil)
        },
        discoverReminderLists: {
            .permissionRequired("Grant Reminders full access.")
        }
    )

    await permission.loadReminderLists()

    #expect(permission.reminderListDiscovery == .permissionRequired(
        "Grant Reminders full access."
    ))

    let empty = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { _ in
            AgentMutationReceipt(accepted: false, message: "unused", policyVersion: nil)
        },
        discoverReminderLists: { .available([]) }
    )
    await empty.loadReminderLists()
    empty.configureReminderListsLocalOnly()

    #expect(empty.reminderListDiscovery == .empty)
    #expect(empty.draft.reminderListPolicy.isConfigured)
    #expect(empty.draft.reminderListPolicy.decisions.allSatisfy { !$0.isIncluded })
    #expect(empty.hasUnsavedChanges)
}

@MainActor
@Test
func alternateSettingsSaveRefreshesChangedReminderPolicyExactlyOnce() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-alternate-refresh-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let refresh = SettingsRefreshRecorder()
    let controller = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { request in
            let receipt = try store.saveMutation(request)
            return AgentMutationReceipt(
                accepted: true,
                message: "saved",
                policyVersion: receipt.resultingVersion,
                policyMutationReceipt: receipt
            )
        },
        onReminderListPolicySaved: { refresh.record() }
    )
    controller.setReminderListDecision(false, listID: "personal")

    controller.requestWakeChange(false)
    while controller.isSaving { await Task.yield() }

    #expect(refresh.count == 1)
    #expect(try store.current()?.policy.reminderLists.decision(for: "personal") == false)
    #expect(!controller.hasUnsavedChanges)
}

@MainActor
@Test
func settingsPermissionRecheckIgnoresAnOlderInFlightResult() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-reminder-race-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    _ = try PolicyStore(databaseURL: databaseURL)
        .saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let gate = SettingsReminderLoadGate()
    let controller = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { _ in
            AgentMutationReceipt(accepted: false, message: "unused", policyVersion: nil)
        },
        discoverReminderLists: { await gate.wait() }
    )
    let first = Task { await controller.loadReminderLists() }
    while gate.count < 1 { await Task.yield() }
    let recheck = Task { await controller.loadReminderLists() }
    while gate.count < 2 { await Task.yield() }

    gate.resume(1, with: .available([
        ReminderListChoice(id: "work", name: "Work")
    ]))
    await recheck.value
    gate.resume(0, with: .permissionRequired("Stale permission state"))
    await first.value

    #expect(controller.reminderListDiscovery == .available([
        ReminderListChoice(id: "work", name: "Work")
    ]))
}

private enum RestartTestError: Error {
    case unexpectedSave
}
