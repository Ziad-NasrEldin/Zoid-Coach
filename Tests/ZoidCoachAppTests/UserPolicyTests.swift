import Foundation
import Testing
@testable import ZoidCoachCore

@Test
func userPolicyKeepsLocalScheduleMeaningAcrossTimeZones() throws {
    let policy = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")

    let data = try JSONEncoder.zoidPolicy.encode(policy)
    let decoded = try JSONDecoder.zoidPolicy.decode(UserPolicy.self, from: data)

    #expect(decoded.schedule.timeZoneIdentifier == "Africa/Cairo")
    #expect(decoded.schedule.nightlyPlanningTime == LocalTime(hour: 22, minute: 30))
    #expect(decoded.schedule.morningConfirmationTime == LocalTime(hour: 8, minute: 0))
    #expect(decoded.schedule.workWindows.first?.start == LocalTime(hour: 9, minute: 0))
    #expect(decoded.schedule.planningCapacityPercent == 70)
}

@Test
func userPolicyValidationReturnsEveryViolationInDeterministicOrder() {
    let invalid = UserPolicy(
        operatingMode: .fullyAutomatic,
        automationPause: AutomationPause(
            isPaused: false,
            resumesAtUTC: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        schedule: SchedulePolicy(
            timeZoneIdentifier: "Not/A-Time-Zone",
            workWindows: [],
            quietHours: DailyTimeWindow(
                start: LocalTime(hour: 23, minute: 0),
                end: LocalTime(hour: 7, minute: 0)
            ),
            nightlyPlanningTime: LocalTime(hour: 22, minute: 30),
            morningConfirmationTime: LocalTime(hour: 8, minute: 0),
            planningCapacityPercent: 101
        ),
        calendar: CalendarSelectionPolicy(
            visibleCalendarIdentifiers: ["work", "work"],
            schedulingCalendarIdentifier: nil
        ),
        privacy: PrivacyPolicy(
            screenshotAnalysisEnabled: true,
            aiProvider: .localOllama,
            remoteEvidencePolicy: .redactedMetadataOnly,
            rawScreenshotRetentionDays: -1,
            extractedTextRetentionDays: 30,
            diagnosticRetentionDays: 14
        ),
        wake: WakePolicyConfiguration(
            isEligible: true,
            window: DailyTimeWindow(
                start: LocalTime(hour: 7, minute: 0),
                end: LocalTime(hour: 7, minute: 0)
            ),
            maximumDailyInterventions: 0
        )
    )

    #expect(invalid.validationViolations().map(\.code) == [
        .resumeDateWhileRunning,
        .invalidTimeZone,
        .missingWorkWindow,
        .invalidCapacityPercent,
        .duplicateCalendarIdentifier,
        .invalidRetention,
        .remotePolicyWithoutRemoteProvider,
        .emptyTimeWindow,
        .invalidWakeBudget
    ])
}

@Test
func planningCapacityUsesConfiguredWorkWindowMinusFixedCommitmentsAtSeventyPercent() throws {
    let policy = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9)))

    #expect(policy.schedule.planningCapacityMinutes(on: monday, fixedCommitmentMinutes: 60) == 336)
}

@Test
func codexCLIAllowsAnExplicitRemoteEvidencePolicy() {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let policy = UserPolicy(
        operatingMode: defaults.operatingMode,
        automationPause: defaults.automationPause,
        schedule: defaults.schedule,
        calendar: defaults.calendar,
        privacy: PrivacyPolicy(
            screenshotAnalysisEnabled: defaults.privacy.screenshotAnalysisEnabled,
            aiProvider: .codexCLI,
            remoteEvidencePolicy: .redactedMetadataOnly,
            rawScreenshotRetentionDays: defaults.privacy.rawScreenshotRetentionDays,
            extractedTextRetentionDays: defaults.privacy.extractedTextRetentionDays,
            diagnosticRetentionDays: defaults.privacy.diagnosticRetentionDays
        ),
        wake: defaults.wake
    )

    #expect(policy.validationViolations().isEmpty)
}
