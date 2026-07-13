import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func defaultCoachingPauseDurationDefaultsToIndefiniteAndRoundTripsThroughSettings() throws {
    let policy = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    let encoded = try JSONEncoder().encode(policy.schedule)
    var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacyObject.removeValue(forKey: "defaultCoachingPauseDuration")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacySchedule = try JSONDecoder().decode(SchedulePolicy.self, from: legacyData)

    #expect(legacySchedule.effectiveDefaultCoachingPauseDuration == .indefinitely)

    var draft = SettingsPolicyDraft(policy: policy)
    draft.defaultCoachingPauseDuration = .oneHour
    let saved = draft.policy(preserving: policy)

    #expect(saved.schedule.effectiveDefaultCoachingPauseDuration == .oneHour)
    #expect(SettingsPolicyDraft(policy: saved).defaultCoachingPauseDuration == .oneHour)
    #expect(saved.validationViolations().isEmpty)
}

@Test
func defaultCoachingPauseDurationSurvivesAnIndependentSettingsConflict() {
    let policy = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    let base = SettingsPolicyDraft(policy: policy)
    var mine = base
    mine.defaultCoachingPauseDuration = .untilTomorrow
    var current = base
    current.capacityPercent = 55

    let merged = SettingsPolicyConflictResolver.resolve(base: base, mine: mine, current: current)

    #expect(merged.safeDraft.defaultCoachingPauseDuration == .untilTomorrow)
    #expect(merged.safeDraft.capacityPercent == 55)
    #expect(merged.concurrentChanges == ["Planning capacity"])
    #expect(merged.overlappingChanges.isEmpty)
}

@MainActor
@Test
func menuBarQuickPauseUsesTheLatestConfiguredDurationWithoutRestart() async throws {
    let now = Date(timeIntervalSince1970: 1_784_026_800)
    let expectations: [(CoachingPauseDuration, Date?, String)] = [
        (.oneHour, now.addingTimeInterval(60 * 60), "for one hour"),
        (.untilTomorrow, Date(timeIntervalSince1970: 1_784_062_800), "until tomorrow"),
        (.indefinitely, nil, "indefinitely"),
    ]

    for (duration, expectedResumeDate, pausePhrase) in expectations {
        let policy = policy(defaultPauseDuration: duration)
        let client = DefaultPauseRecordingClient(current: VersionedUserPolicy(
            version: 4,
            policy: policy,
            createdAtUTC: now,
            isActive: true
        ))
        let controller = MenuBarCoachingPauseController(
            client: client,
            makeRequestID: { "system-policy-v1:menu-bar-coaching-pause:\(duration.rawValue)" },
            now: { now }
        )

        await controller.refresh()
        #expect(controller.defaultPauseDuration == duration)
        #expect(controller.runningDetail.contains(duration.selectionDescription))
        #expect(controller.pauseActionAccessibilityLabel == "Pause coaching \(pausePhrase)")

        await controller.setPaused(true)

        let request = try #require(await client.requests.first)
        #expect(request.policy.automationPause.isActive(at: now))
        #expect(request.policy.automationPause.resumesAtUTC == expectedResumeDate)
        #expect(controller.statusMessage?.contains(pausePhrase) == true)
        #expect(request.policy.schedule.effectiveDefaultCoachingPauseDuration == duration)
    }
}

private actor DefaultPauseRecordingClient: MenuBarCoachingPauseClient {
    var current: VersionedUserPolicy
    private(set) var requests: [PolicyMutationRequest] = []

    init(current: VersionedUserPolicy) {
        self.current = current
    }

    func loadCurrentPolicy() -> VersionedUserPolicy { current }

    func savePolicyMutation(_ request: PolicyMutationRequest) throws -> AgentMutationReceipt {
        requests.append(request)
        let resultingVersion = current.version + 1
        let receipt = PolicyMutationReceipt(
            requestID: request.requestID,
            payloadDigest: try PolicyMutationRequest.canonicalPayloadDigest(for: request.policy),
            expectedVersion: request.expectedVersion,
            resultingVersion: resultingVersion,
            origin: request.origin,
            replayed: false
        )
        current = VersionedUserPolicy(
            version: resultingVersion,
            policy: request.policy,
            createdAtUTC: Date(timeIntervalSince1970: TimeInterval(resultingVersion)),
            isActive: true
        )
        return AgentMutationReceipt(
            accepted: true,
            message: "Saved",
            policyVersion: resultingVersion,
            policyMutationReceipt: receipt
        )
    }
}

private func policy(defaultPauseDuration: CoachingPauseDuration) -> UserPolicy {
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    let schedule = original.schedule
    return UserPolicy(
        operatingMode: original.operatingMode,
        automationPause: original.automationPause,
        schedule: SchedulePolicy(
            timeZoneIdentifier: schedule.timeZoneIdentifier,
            workWindows: schedule.workWindows,
            quietHours: schedule.quietHours,
            nightlyPlanningTime: schedule.nightlyPlanningTime,
            morningConfirmationTime: schedule.morningConfirmationTime,
            planningCapacityPercent: schedule.planningCapacityPercent,
            defaultCoachingPauseDuration: defaultPauseDuration
        ),
        calendar: original.calendar,
        privacy: original.privacy,
        wake: original.wake,
        behavior: original.behavior,
        capture: original.capture,
        gaming: original.gaming,
        reminderLists: original.reminderLists
    )
}
