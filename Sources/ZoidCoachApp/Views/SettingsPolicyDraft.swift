import Foundation
import ZoidCoachCore

struct SettingsPolicyDraft: Equatable {
    var operatingMode: OperatingMode
    var isPaused: Bool
    var workStart: LocalTime
    var workEnd: LocalTime
    var quietStart: LocalTime
    var quietEnd: LocalTime
    var capacityPercent: Int
    var visibleCalendarIdentifiers: String
    var schedulingCalendarIdentifier: String
    var screenshotAnalysisEnabled: Bool
    var aiProvider: AIProviderSelection
    var remoteEvidencePolicy: RemoteEvidencePolicy
    var rawScreenshotRetentionDays: Int
    var extractedTextRetentionDays: Int
    var diagnosticRetentionDays: Int
    var wakeEligible: Bool
    var wakeStart: LocalTime
    var wakeEnd: LocalTime
    var maximumDailyWakeInterventions: Int
    var wakeQuietWeekdays: [Weekday]

    init(policy: UserPolicy) {
        operatingMode = policy.operatingMode
        isPaused = policy.automationPause.isPaused
        workStart = policy.schedule.workWindows.first?.start ?? LocalTime(hour: 9, minute: 0)
        workEnd = policy.schedule.workWindows.first?.end ?? LocalTime(hour: 18, minute: 0)
        quietStart = policy.schedule.quietHours.start
        quietEnd = policy.schedule.quietHours.end
        capacityPercent = policy.schedule.planningCapacityPercent
        visibleCalendarIdentifiers = policy.calendar.visibleCalendarIdentifiers.joined(separator: ", ")
        schedulingCalendarIdentifier = policy.calendar.schedulingCalendarIdentifier ?? ""
        screenshotAnalysisEnabled = policy.privacy.screenshotAnalysisEnabled
        aiProvider = policy.privacy.aiProvider
        remoteEvidencePolicy = policy.privacy.remoteEvidencePolicy
        rawScreenshotRetentionDays = policy.privacy.rawScreenshotRetentionDays
        extractedTextRetentionDays = policy.privacy.extractedTextRetentionDays
        diagnosticRetentionDays = policy.privacy.diagnosticRetentionDays
        wakeEligible = policy.wake.isEligible
        wakeStart = policy.wake.window.start
        wakeEnd = policy.wake.window.end
        maximumDailyWakeInterventions = policy.wake.maximumDailyInterventions
        wakeQuietWeekdays = policy.wake.quietWeekdays ?? []
    }

    func policy(preserving original: UserPolicy) -> UserPolicy {
        let identifiers = visibleCalendarIdentifiers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let schedulingID = schedulingCalendarIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
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
                nightlyPlanningTime: original.schedule.nightlyPlanningTime,
                morningConfirmationTime: original.schedule.morningConfirmationTime,
                planningCapacityPercent: capacityPercent
            ),
            calendar: CalendarSelectionPolicy(
                visibleCalendarIdentifiers: identifiers,
                schedulingCalendarIdentifier: schedulingID.isEmpty ? nil : schedulingID
            ),
            privacy: PrivacyPolicy(
                screenshotAnalysisEnabled: screenshotAnalysisEnabled,
                aiProvider: aiProvider,
                remoteEvidencePolicy: aiProvider == .remoteOpenAI ? remoteEvidencePolicy : .localOnly,
                rawScreenshotRetentionDays: rawScreenshotRetentionDays,
                extractedTextRetentionDays: extractedTextRetentionDays,
                diagnosticRetentionDays: diagnosticRetentionDays
            ),
            wake: WakePolicyConfiguration(
                isEligible: wakeEligible,
                window: DailyTimeWindow(start: wakeStart, end: wakeEnd),
                maximumDailyInterventions: maximumDailyWakeInterventions,
                quietWeekdays: wakeQuietWeekdays
            )
        )
    }
}
