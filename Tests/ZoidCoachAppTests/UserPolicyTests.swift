import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure
@testable import ZoidCoachInfrastructure

@Test
func userPolicyKeepsLocalScheduleMeaningAcrossTimeZones() throws {
    let policy = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")

    let data = try JSONEncoder.zoidPolicy.encode(policy)
    let decoded = try JSONDecoder.zoidPolicy.decode(UserPolicy.self, from: data)

    #expect(decoded.schedule.timeZoneIdentifier == "Africa/Cairo")
    #expect(decoded.schedule.nightlyPlanningTime == LocalTime(hour: 22, minute: 30))
    #expect(decoded.schedule.morningConfirmationTime == LocalTime(hour: 8, minute: 0))
    #expect(decoded.schedule.dailyReviewTime == LocalTime(hour: 18, minute: 0))
    #expect(decoded.schedule.workWindows.first?.start == LocalTime(hour: 9, minute: 0))
    #expect(decoded.schedule.planningCapacityPercent == 70)
}

@Test
func userPolicyDecodesLegacyScheduleWithoutConfiguredReviewTime() throws {
    let encoded = try JSONEncoder.zoidPolicy.encode(UserPolicy.defaults(timeZoneIdentifier: "UTC"))
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var schedule = try #require(object["schedule"] as? [String: Any])
    schedule.removeValue(forKey: "dailyReviewTime")
    object["schedule"] = schedule

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder.zoidPolicy.decode(UserPolicy.self, from: legacyData)

    #expect(decoded.schedule.dailyReviewTime == nil)
    #expect(decoded.validationViolations().isEmpty)
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

@Test
func behaviorPolicyNormalizesExactOverridesAndRejectsConflicts() {
    let policy = BehaviorPolicy(
        workApplications: ["  Xcode  ", "FIGMA"],
        gamingApplications: ["Steam", "xcode"],
        communicationApplications: [" Slack "]
    )

    #expect(policy.workApplications == ["figma", "xcode"])
    #expect(policy.gamingApplications == ["steam", "xcode"])
    #expect(policy.communicationApplications == ["slack"])
    #expect(policy.classificationOverride(for: " xCoDe ") == .work)
    #expect(policy.classificationOverride(for: "SLACK") == .work)
    #expect(policy.ruleCategory(for: "slack") == .communication)

    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let invalid = UserPolicy(
        operatingMode: defaults.operatingMode,
        automationPause: defaults.automationPause,
        schedule: defaults.schedule,
        calendar: defaults.calendar,
        privacy: defaults.privacy,
        wake: defaults.wake,
        behavior: policy
    )

    #expect(invalid.validationViolations().map(\.code) == [.applicationClassificationConflict])
}

@Test
func behaviorPolicyNormalizesPersistedApplicationNamesWhileDecoding() throws {
    let decoded = try JSONDecoder().decode(
        BehaviorPolicy.self,
        from: Data(#"{"workApplications":[" XCODE "],"gamingApplications":["STEAM"]}"#.utf8)
    )

    #expect(decoded.workApplications == ["xcode"])
    #expect(decoded.gamingApplications == ["steam"])
    #expect(decoded.communicationApplications.isEmpty)
}

@Test
func communicationRulesRoundTripAndRemainDistinctWhileCountingAsWork() throws {
    let policy = BehaviorPolicy(
        workApplications: ["Xcode"],
        gamingApplications: ["Steam"],
        communicationApplications: ["Slack", "Discord"]
    )

    let encoded = try JSONEncoder().encode(policy)
    let decoded = try JSONDecoder().decode(BehaviorPolicy.self, from: encoded)

    #expect(decoded == policy)
    #expect(decoded.ruleCategory(for: "Discord") == .communication)
    #expect(decoded.classificationOverride(for: "Discord") == .work)
    #expect(decoded.ruleCategory(for: "Safari") == .automatic)
}

@Test
func behaviorPolicyValidationRejectsBlankAndDuplicateApplications() {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let invalid = UserPolicy(
        operatingMode: defaults.operatingMode,
        automationPause: defaults.automationPause,
        schedule: defaults.schedule,
        calendar: defaults.calendar,
        privacy: defaults.privacy,
        wake: defaults.wake,
        behavior: BehaviorPolicy(
            workApplications: ["", "Xcode", " xcode "],
            gamingApplications: []
        )
    )

    #expect(invalid.validationViolations().map(\.code) == [
        .emptyApplicationClassification,
        .duplicateApplicationClassification
    ])
}

@Test
func versionOnePolicyDecodesWithAutomaticAppClassificationAndUpgradesOnSave() throws {
    let versionOneJSON = try #require(String(data: JSONEncoder.zoidPolicy.encode(UserPolicy.defaults(timeZoneIdentifier: "UTC")), encoding: .utf8))
        .replacingOccurrences(of: #""schemaVersion":5"#, with: #""schemaVersion":1"#)
        .replacingOccurrences(of: #",\"behavior\":{\"gamingApplications\":[],\"workApplications\":[]}"#, with: "")
        .replacingOccurrences(of: #",\"capture\":{\"configuredDisplayIDs\":[],\"mode\":\"legacy\"}"#, with: "")
        .replacingOccurrences(of: #",\"gaming\":{\"dailyBudgetMinutes\":60,\"priorityTaskRewardMinutes\":15,\"version\":1}"#, with: "")
        .replacingOccurrences(of: #",\"reminderLists\":{\"decisions\":[],\"isConfigured\":false}"#, with: "")

    let decoded = try JSONDecoder.zoidPolicy.decode(UserPolicy.self, from: Data(versionOneJSON.utf8))

    #expect(decoded.schemaVersion == 1)
    #expect(decoded.behavior == BehaviorPolicy())
    #expect(decoded.capture == .legacy)
    #expect(decoded.gaming == .balanced)
    #expect(decoded.reminderLists == .legacyAllLists)
    #expect(decoded.upgradedToCurrentSchema().schemaVersion == UserPolicy.schemaVersion)
    #expect(decoded.upgradedToCurrentSchema().behavior == BehaviorPolicy())
    #expect(decoded.upgradedToCurrentSchema().capture == .legacy)
    #expect(decoded.upgradedToCurrentSchema().gaming == .balanced)
}

@Test
func gamingPolicyPresetsMatchTheOnboardingContractAndDefaultsToBalanced() {
    #expect(GamingPolicy.flexible == GamingPolicy(
        dailyBudgetMinutes: 90,
        priorityTaskRewardMinutes: 0
    ))
    #expect(GamingPolicy.balanced == GamingPolicy(
        dailyBudgetMinutes: 60,
        priorityTaskRewardMinutes: 15
    ))
    #expect(GamingPolicy.firm == GamingPolicy(
        dailyBudgetMinutes: 30,
        priorityTaskRewardMinutes: 30
    ))
    #expect(UserPolicy.defaults(timeZoneIdentifier: "UTC").gaming == .balanced)
}

@Test
func gamingPolicyValidationRejectsUnsupportedOrUnboundedValues() {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let invalid = defaults.replacingGamingPolicy(GamingPolicy(
        version: 2,
        dailyBudgetMinutes: 1_441,
        priorityTaskRewardMinutes: 1_442
    ))

    #expect(invalid.validationViolations().map(\.code) == [
        .unsupportedGamingPolicyVersion,
        .invalidGamingBudget,
        .invalidGamingReward,
    ])
}

@Test
func gamingGraceControlsDecodeLegacyDefaultsAndValidateBounds() throws {
    let legacy = try JSONDecoder().decode(
        GamingPolicy.self,
        from: Data(#"{"version":1,"dailyBudgetMinutes":60,"priorityTaskRewardMinutes":15}"#.utf8)
    )
    #expect(legacy.taskStartGraceMinutes == 3)
    #expect(legacy.returnFromIdleGraceMinutes == 1)

    let configured = GamingPolicy(
        taskStartGraceMinutes: 12,
        returnFromIdleGraceMinutes: 4
    )
    let roundTrip = try JSONDecoder().decode(
        GamingPolicy.self,
        from: JSONEncoder().encode(configured)
    )
    #expect(roundTrip.taskStartGraceMinutes == 12)
    #expect(roundTrip.returnFromIdleGraceMinutes == 4)

    let invalid = UserPolicy.defaults(timeZoneIdentifier: "UTC").replacingGamingPolicy(
        GamingPolicy(
            taskStartGraceMinutes: 61,
            returnFromIdleGraceMinutes: 31
        )
    )
    #expect(invalid.validationViolations().contains { $0.field == "gaming.taskStartGraceMinutes" })
    #expect(invalid.validationViolations().contains { $0.field == "gaming.returnFromIdleGraceMinutes" })
    #expect(invalid.validationViolations().filter { $0.code == .invalidGamingGrace }.count == 2)
}

@Test
func capturePolicyNormalizesDisplayIDsAndRoundTripsThroughRuntimeConfiguration() throws {
    let policy = CapturePolicy(mode: .native, configuredDisplayIDs: [42, 7, 42])
    let runtime = NativeCaptureConfiguration(policy: policy, parityPassed: true)

    #expect(policy.configuredDisplayIDs == [7, 42])
    #expect(runtime.mode == .native)
    #expect(runtime.policy == policy)
}

@Test
func reminderListPolicyUsesStableIdentifiersAndExcludesNewListsAfterConfiguration() throws {
    let policy = ReminderListPolicy(
        isConfigured: true,
        decisions: [
            ReminderListDecision(listID: "list-work", isIncluded: true),
            ReminderListDecision(listID: "list-personal", isIncluded: false),
        ]
    )

    #expect(policy.includes(listID: "list-work"))
    #expect(!policy.includes(listID: "list-personal"))
    #expect(!policy.includes(listID: "list-created-later"))
    #expect(policy.decision(for: "list-work") == true)
    #expect(policy.decision(for: "list-personal") == false)
    #expect(policy.decision(for: "renamed-work") == nil)

    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let configured = defaults.replacingReminderListPolicy(policy)
    let decoded = try JSONDecoder.zoidPolicy.decode(
        UserPolicy.self,
        from: JSONEncoder.zoidPolicy.encode(configured)
    )

    #expect(decoded.schemaVersion == 5)
    #expect(decoded.reminderLists == policy)
}

@Test
func versionFourPolicyKeepsLegacyAllListsBehaviorUntilExplicitlyConfigured() throws {
    let current = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let encoded = try #require(String(
        data: JSONEncoder.zoidPolicy.encode(current),
        encoding: .utf8
    ))
    let versionFour = encoded
        .replacingOccurrences(of: #""schemaVersion":5"#, with: #""schemaVersion":4"#)
        .replacingOccurrences(
            of: #",\"reminderLists\":{\"decisions\":[],\"isConfigured\":false}"#,
            with: ""
        )

    let decoded = try JSONDecoder.zoidPolicy.decode(
        UserPolicy.self,
        from: Data(versionFour.utf8)
    )

    #expect(decoded.schemaVersion == 4)
    #expect(!decoded.reminderLists.isConfigured)
    #expect(decoded.reminderLists.includes(listID: "any-existing-list"))
    #expect(decoded.upgradedToCurrentSchema().schemaVersion == 5)
    #expect(decoded.upgradedToCurrentSchema().reminderLists == .legacyAllLists)
}

@Test
func automationPauseChangePreservesConfiguredReminderLists() {
    let configured = UserPolicy.defaults(timeZoneIdentifier: "UTC")
        .replacingReminderListPolicy(ReminderListPolicy(
            isConfigured: true,
            decisions: [ReminderListDecision(listID: "work-id", isIncluded: true)]
        ))

    let paused = configured.replacingAutomationPause(.pausedIndefinitely)

    #expect(paused.automationPause == .pausedIndefinitely)
    #expect(paused.reminderLists == configured.reminderLists)
}

@Test
func reminderListFilteringPreservesOpaqueIDsAndExcludesUnknownListsAfterConfiguration() {
    let opaqueID = "  opaque-list-id  "
    let policy = ReminderListPolicy(
        isConfigured: true,
        decisions: [ReminderListDecision(listID: opaqueID, isIncluded: true)]
    )
    let tasks = [
        (id: "included", listID: opaqueID),
        (id: "trimmed-lookalike", listID: "opaque-list-id"),
        (id: "new-list", listID: "new-list"),
    ]

    let filtered = policy.filteringExternalTasks(tasks, listID: { $0.listID })

    #expect(filtered.map(\.id) == ["included"])
    #expect(!policy.includes(listID: Optional<String>.none))
    #expect(ReminderListPolicy.legacyAllLists.filteringExternalTasks(
        tasks,
        listID: { $0.listID }
    ).map(\.id) == tasks.map(\.id))
}

@Test
func timedAutomationPauseHonorsExactBoundaryAndLegacyCodingShape() throws {
    let startedAt = try #require(ISO8601DateFormatter().date(from: "2026-07-13T10:00:00Z"))
    let pause = AutomationPause.pausedForOneHour(from: startedAt)

    #expect(pause.isActive(at: startedAt.addingTimeInterval(59 * 60 + 59)))
    #expect(!pause.isActive(at: startedAt.addingTimeInterval(60 * 60)))
    #expect(pause.resumesAtUTC == startedAt.addingTimeInterval(60 * 60))

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let encoded = try encoder.encode(pause)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(json["isPaused"] as? Bool == true)
    #expect(json["resumesAtUTC"] != nil)
    #expect(json["pauseRequested"] == nil)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(AutomationPause.self, from: encoded) == pause)
    #expect(try decoder.decode(AutomationPause.self, from: Data("{\"isPaused\":true}".utf8)) == .pausedIndefinitely)
    #expect(try decoder.decode(AutomationPause.self, from: Data("{\"isPaused\":false}".utf8)) == .running)

    let wallClockNow = Date()
    #expect(AutomationPause(isPaused: true, resumesAtUTC: wallClockNow.addingTimeInterval(60)).isPaused)
    #expect(!AutomationPause(isPaused: true, resumesAtUTC: wallClockNow.addingTimeInterval(-1)).isPaused)
}

@Test
func untilTomorrowPauseUsesNextLocalMidnightAcrossTimeZones() throws {
    let startedAt = try #require(ISO8601DateFormatter().date(from: "2026-07-13T20:30:00Z"))
    let timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
    let expectedBoundary = try #require(ISO8601DateFormatter().date(from: "2026-07-13T21:00:00Z"))

    let pause = AutomationPause.pausedUntilTomorrow(from: startedAt, timeZone: timeZone)

    #expect(pause.resumesAtUTC == expectedBoundary)
    #expect(pause.isActive(at: expectedBoundary.addingTimeInterval(-1)))
    #expect(!pause.isActive(at: expectedBoundary))
}
