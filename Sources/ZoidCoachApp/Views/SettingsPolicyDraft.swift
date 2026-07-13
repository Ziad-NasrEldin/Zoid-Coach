import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

struct SettingsPolicyDraft: Equatable {
    var operatingMode: OperatingMode
    var isPaused: Bool
    var workStart: LocalTime
    var workEnd: LocalTime
    var quietStart: LocalTime
    var quietEnd: LocalTime
    var nightlyPlanningTime: LocalTime
    var morningConfirmationTime: LocalTime
    var capacityPercent: Int
    var visibleCalendarIdentifiers: String
    var schedulingCalendarIdentifier: String
    var screenshotAnalysisEnabled: Bool
    var aiProvider: AIProviderSelection
    var remoteEvidencePolicy: RemoteEvidencePolicy
    var rawScreenshotRetentionDays: Int
    var extractedTextRetentionDays: Int
    var diagnosticRetentionDays: Int
    var behaviorRecordRetentionDays: Int
    var taskSessionRetentionDays: Int
    var promptRetentionDays: Int
    var reviewRetentionDays: Int
    var codexCLIModel: CodexCLIModel
    var codexCLICustomModelID: String
    var codexCLIReasoningEffort: CodexCLIReasoningEffort
    var wakeEligible: Bool
    var wakeStart: LocalTime
    var wakeEnd: LocalTime
    var maximumDailyWakeInterventions: Int
    var wakeQuietWeekdays: [Weekday]
    var behaviorPolicy: BehaviorPolicy
    var captureMode: CaptureMode
    var captureDisplayIDs: [UInt32]
    var reminderListPolicy: ReminderListPolicy
    var coachingLevel: CoachingLevel
    var gamingDailyBudgetMinutes: Int
    var gamingPriorityTaskRewardMinutes: Int
    var gamingIntentionalOverrideMinutes: Int
    var gamingDailyPromptCap: Int
    var gamingPromptCooldownMinutes: Int

    init(policy: UserPolicy) {
        operatingMode = policy.operatingMode
        isPaused = policy.automationPause.isPaused
        workStart = policy.schedule.workWindows.first?.start ?? LocalTime(hour: 9, minute: 0)
        workEnd = policy.schedule.workWindows.first?.end ?? LocalTime(hour: 18, minute: 0)
        quietStart = policy.schedule.quietHours.start
        quietEnd = policy.schedule.quietHours.end
        nightlyPlanningTime = policy.schedule.nightlyPlanningTime
        morningConfirmationTime = policy.schedule.morningConfirmationTime
        capacityPercent = policy.schedule.planningCapacityPercent
        visibleCalendarIdentifiers = policy.calendar.visibleCalendarIdentifiers.joined(separator: ", ")
        schedulingCalendarIdentifier = policy.calendar.schedulingCalendarIdentifier ?? ""
        screenshotAnalysisEnabled = policy.privacy.screenshotAnalysisEnabled
        let configuredProvider = policy.privacy.aiProvider
        aiProvider = AIProviderCapabilities.production[configuredProvider].isSelectable ? configuredProvider : .disabled
        remoteEvidencePolicy = aiProvider.usesRemoteProcessing ? policy.privacy.remoteEvidencePolicy : .localOnly
        rawScreenshotRetentionDays = policy.privacy.rawScreenshotRetentionDays
        extractedTextRetentionDays = policy.privacy.extractedTextRetentionDays
        diagnosticRetentionDays = policy.privacy.diagnosticRetentionDays
        behaviorRecordRetentionDays = policy.privacy.effectiveBehaviorRecordRetentionDays
        taskSessionRetentionDays = policy.privacy.effectiveTaskSessionRetentionDays
        promptRetentionDays = policy.privacy.effectivePromptRetentionDays
        reviewRetentionDays = policy.privacy.effectiveReviewRetentionDays
        codexCLIModel = policy.privacy.effectiveCodexCLIModel
        codexCLICustomModelID = policy.privacy.codexCLICustomModelID ?? ""
        codexCLIReasoningEffort = policy.privacy.effectiveCodexCLIReasoningEffort
        wakeEligible = policy.wake.isEligible
        wakeStart = policy.wake.window.start
        wakeEnd = policy.wake.window.end
        maximumDailyWakeInterventions = policy.wake.maximumDailyInterventions
        wakeQuietWeekdays = policy.wake.quietWeekdays ?? []
        behaviorPolicy = policy.behavior
        captureMode = policy.capture.mode
        captureDisplayIDs = policy.capture.configuredDisplayIDs
        reminderListPolicy = policy.reminderLists
        coachingLevel = policy.gaming.coachingLevel
        gamingDailyBudgetMinutes = policy.gaming.dailyBudgetMinutes
        gamingPriorityTaskRewardMinutes = policy.gaming.priorityTaskRewardMinutes
        gamingIntentionalOverrideMinutes = policy.gaming.intentionalOverrideMinutes
        gamingDailyPromptCap = policy.gaming.dailyPromptCap
        gamingPromptCooldownMinutes = policy.gaming.promptCooldownMinutes
    }

    func classification(for application: String) -> AppClassificationChoice {
        behaviorPolicy.choice(for: application)
    }

    func settingsClassification(for application: String) -> ApplicationRuleCategory {
        behaviorPolicy.ruleCategory(for: application)
    }

    mutating func setClassification(_ choice: AppClassificationChoice, for application: String) {
        let normalized = BehaviorPolicy.normalize(application)
        var work = behaviorPolicy.workApplications.filter { $0 != normalized }
        var gaming = behaviorPolicy.gamingApplications.filter { $0 != normalized }
        let communication = behaviorPolicy.communicationApplications.filter { $0 != normalized }
        if choice == .work { work.append(normalized) }
        if choice == .gaming { gaming.append(normalized) }
        behaviorPolicy = BehaviorPolicy(
            workApplications: work,
            gamingApplications: gaming,
            communicationApplications: communication
        )
    }

    mutating func setClassifications(_ category: ApplicationRuleCategory, for applications: [String]) {
        let normalized = Set(applications.map(BehaviorPolicy.normalize).filter { !$0.isEmpty })
        var work = behaviorPolicy.workApplications.filter { !normalized.contains($0) }
        var gaming = behaviorPolicy.gamingApplications.filter { !normalized.contains($0) }
        var communication = behaviorPolicy.communicationApplications.filter { !normalized.contains($0) }
        switch category {
        case .automatic:
            break
        case .work:
            work.append(contentsOf: normalized)
        case .communication:
            communication.append(contentsOf: normalized)
        case .gaming:
            gaming.append(contentsOf: normalized)
        }
        behaviorPolicy = BehaviorPolicy(
            workApplications: work,
            gamingApplications: gaming,
            communicationApplications: communication
        )
    }

    mutating func resetApplicationRules() {
        behaviorPolicy = BehaviorPolicy()
    }

    mutating func selectAIProvider(_ provider: AIProviderSelection) {
        let previousProviderUsedRemoteProcessing = aiProvider.usesRemoteProcessing
        aiProvider = provider
        if !provider.usesRemoteProcessing {
            remoteEvidencePolicy = .localOnly
        } else if provider == .codexCLI,
                  !previousProviderUsedRemoteProcessing,
                  remoteEvidencePolicy == .localOnly {
            remoteEvidencePolicy = .redactedMetadataOnly
        }
    }

    mutating func setReminderListDecision(_ isIncluded: Bool, listID: String) {
        var decisions = reminderListPolicy.decisions.filter { $0.listID != listID }
        decisions.append(ReminderListDecision(listID: listID, isIncluded: isIncluded))
        reminderListPolicy = ReminderListPolicy(
            isConfigured: reminderListPolicy.isConfigured,
            decisions: decisions
        )
    }

    mutating func confirmReminderListConfiguration() {
        reminderListPolicy = ReminderListPolicy(
            isConfigured: true,
            decisions: reminderListPolicy.decisions
        )
    }

    mutating func configureReminderListsLocalOnly() {
        reminderListPolicy = ReminderListPolicy(
            isConfigured: true,
            decisions: reminderListPolicy.decisions.map {
                ReminderListDecision(listID: $0.listID, isIncluded: false)
            }
        )
    }

    var visibleCalendarIdentifierList: [String] {
        get {
            visibleCalendarIdentifiers
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            visibleCalendarIdentifiers = newValue.joined(separator: ", ")
        }
    }

    var schedulingCalendarIdentifierValue: String? {
        get {
            let identifier = schedulingCalendarIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            return identifier.isEmpty ? nil : identifier
        }
        set {
            schedulingCalendarIdentifier = newValue ?? ""
        }
    }

    func policy(preserving original: UserPolicy) -> UserPolicy {
        let selectedProvider = AIProviderCapabilities.production[aiProvider].isSelectable ? aiProvider : .disabled
        let identifiers = visibleCalendarIdentifierList
        let schedulingID = schedulingCalendarIdentifierValue
        let workWindows = original.schedule.workWindows.map {
            WeeklyWorkWindow(weekdays: $0.weekdays, start: workStart, end: workEnd)
        }

        return UserPolicy(
            operatingMode: operatingMode,
            automationPause: isPaused ? .pausedIndefinitely : .running,
            schedule: SchedulePolicy(
                timeZoneIdentifier: original.schedule.timeZoneIdentifier,
                workWindows: workWindows,
                quietHours: DailyTimeWindow(start: quietStart, end: quietEnd),
                nightlyPlanningTime: nightlyPlanningTime,
                morningConfirmationTime: morningConfirmationTime,
                planningCapacityPercent: capacityPercent
            ),
            calendar: CalendarSelectionPolicy(
                visibleCalendarIdentifiers: identifiers,
                schedulingCalendarIdentifier: schedulingID
            ),
            privacy: PrivacyPolicy(
                screenshotAnalysisEnabled: screenshotAnalysisEnabled,
                aiProvider: selectedProvider,
                remoteEvidencePolicy: selectedProvider.usesRemoteProcessing ? remoteEvidencePolicy : .localOnly,
                rawScreenshotRetentionDays: rawScreenshotRetentionDays,
                extractedTextRetentionDays: extractedTextRetentionDays,
                diagnosticRetentionDays: diagnosticRetentionDays,
                behaviorRecordRetentionDays: behaviorRecordRetentionDays,
                taskSessionRetentionDays: taskSessionRetentionDays,
                promptRetentionDays: promptRetentionDays,
                reviewRetentionDays: reviewRetentionDays,
                codexCLIModel: codexCLIModel,
                codexCLICustomModelID: codexCLICustomModelID,
                codexCLIReasoningEffort: codexCLIReasoningEffort
            ),
            wake: WakePolicyConfiguration(
                isEligible: wakeEligible,
                window: DailyTimeWindow(start: wakeStart, end: wakeEnd),
                maximumDailyInterventions: maximumDailyWakeInterventions,
                quietWeekdays: wakeQuietWeekdays
            ),
            behavior: behaviorPolicy,
            capture: CapturePolicy(mode: captureMode, configuredDisplayIDs: captureDisplayIDs),
            gaming: GamingPolicy(
                version: original.gaming.version,
                dailyBudgetMinutes: gamingDailyBudgetMinutes,
                priorityTaskRewardMinutes: gamingPriorityTaskRewardMinutes,
                coachingLevel: coachingLevel,
                intentionalOverrideMinutes: gamingIntentionalOverrideMinutes,
                dailyPromptCap: gamingDailyPromptCap,
                promptCooldownMinutes: gamingPromptCooldownMinutes
            ),
            reminderLists: reminderListPolicy
        )
    }

}
