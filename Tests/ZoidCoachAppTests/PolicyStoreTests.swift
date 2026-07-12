import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func policyStoreVersionsChangesAndRollsBackTheActivePolicy() throws {
    let databaseURL = temporaryPolicyDatabaseURL()
    defer { removePolicyDatabaseFiles(at: databaseURL) }
    let clock = Date(timeIntervalSince1970: 1_700_000_000)
    let store = try PolicyStore(databaseURL: databaseURL, now: { clock })

    let first = try store.save(policy(mode: .fullyAutomatic))
    let second = try store.save(policy(mode: .approvalRequired))

    #expect(first.version == 1)
    #expect(second.version == 2)
    #expect(try store.history().map(\.version) == [2, 1])

    let rolledBack = try store.rollback(to: 1)

    #expect(rolledBack.version == 3)
    #expect(rolledBack.policy.operatingMode == .fullyAutomatic)
    #expect(try store.current() == rolledBack)

    let third = try store.save(policy(mode: .suggestionsOnly))
    #expect(third.version == 4)
}

@Test
func policyMutationUsesExpectedVersionAndReplaysTheWinningRequest() throws {
    let databaseURL = temporaryPolicyDatabaseURL()
    defer { removePolicyDatabaseFiles(at: databaseURL) }
    let firstStore = try PolicyStore(databaseURL: databaseURL)
    let secondStore = try PolicyStore(databaseURL: databaseURL)
    let initial = try firstStore.save(policy(mode: .observe))
    let request = PolicyMutationRequest(
        requestID: "settings-policy-v1:001",
        expectedVersion: initial.version,
        policy: policy(mode: .assist),
        origin: .settings
    )

    let first = try firstStore.saveMutation(request)
    let replay = try secondStore.saveMutation(request)

    #expect(first.requestID == replay.requestID)
    #expect(first.payloadDigest == replay.payloadDigest)
    #expect(first.resultingVersion == replay.resultingVersion)
    #expect(!first.replayed)
    #expect(replay.replayed)
    #expect(first.resultingVersion == 2)
    #expect(try firstStore.history().map(\.version) == [2, 1])

    let stale = PolicyMutationRequest(
        requestID: "settings-policy-v1:002",
        expectedVersion: initial.version,
        policy: policy(mode: .autonomous),
        origin: .settings
    )
    #expect(throws: PolicyStoreError.staleVersion(expected: 1, actual: 2)) {
        try secondStore.saveMutation(stale)
    }
    #expect(try firstStore.current()?.policy.operatingMode == .assist)
}

@Test
func policyMutationRejectsAReusedRequestIDWithDifferentPayload() throws {
    let databaseURL = temporaryPolicyDatabaseURL()
    defer { removePolicyDatabaseFiles(at: databaseURL) }
    let store = try PolicyStore(databaseURL: databaseURL)
    let initial = try store.save(policy(mode: .observe))
    let first = try onboardingPolicyRequest(
        flowID: "flow",
        step: .schedule,
        progressRevision: 8,
        expectedVersion: initial.version,
        policy: policy(mode: .assist)
    )
    _ = try store.saveMutation(first)
    let conflicting = PolicyMutationRequest(
        requestID: first.requestID,
        expectedVersion: initial.version,
        policy: policy(mode: .autonomous),
        origin: first.origin
    )

    #expect(throws: PolicyStoreError.idempotencyConflict(first.requestID)) {
        try store.saveMutation(conflicting)
    }
    #expect(try store.history().map(\.version) == [2, 1])
}

@Test
func policyMutationRejectsMalformedAndUnboundRequestsWithoutWriting() throws {
    let databaseURL = temporaryPolicyDatabaseURL()
    defer { removePolicyDatabaseFiles(at: databaseURL) }
    let store = try PolicyStore(databaseURL: databaseURL)
    let candidate = policy(mode: .assist)

    let invalidRequests = [
        (
            PolicyMutationRequest(
                requestID: " ",
                expectedVersion: 0,
                policy: candidate,
                origin: .settings
            ),
            PolicyStoreError.invalidRequest("request_id")
        ),
        (
            PolicyMutationRequest(
                requestID: "settings-policy-v1:negative",
                expectedVersion: -1,
                policy: candidate,
                origin: .settings
            ),
            PolicyStoreError.invalidRequest("expected_version")
        ),
        (
            PolicyMutationRequest(
                requestID: "wrong-prefix",
                expectedVersion: 0,
                policy: candidate,
                origin: .settings
            ),
            PolicyStoreError.invalidRequest("settings_request_id")
        ),
        (
            PolicyMutationRequest(
                requestID: "onboarding-policy-v1:flow:welcome:0:invalid",
                expectedVersion: 0,
                policy: candidate,
                origin: .onboarding(flowID: "flow", step: .welcome, progressRevision: 0)
            ),
            PolicyStoreError.invalidRequest("onboarding_origin")
        ),
        (
            PolicyMutationRequest(
                requestID: "onboarding-policy-v1:flow:schedule:0:wrong-digest",
                expectedVersion: 0,
                policy: candidate,
                origin: .onboarding(flowID: "flow", step: .schedule, progressRevision: 0)
            ),
            PolicyStoreError.invalidRequest("onboarding_request_id")
        ),
    ]

    for (request, expectedError) in invalidRequests {
        #expect(throws: expectedError) {
            try store.saveMutation(request)
        }
    }
    #expect(try store.current() == nil)
    #expect(try store.history().isEmpty)
}

@Test
func operatingModeMigratesLegacyPolicyValuesAndPersistsTheFourRolloutModes() throws {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    #expect(try decoder.decode(OperatingMode.self, from: Data(#""suggestionsOnly""#.utf8)) == .suggest)
    #expect(try decoder.decode(OperatingMode.self, from: Data(#""approvalRequired""#.utf8)) == .assist)
    #expect(try decoder.decode(OperatingMode.self, from: Data(#""fullyAutomatic""#.utf8)) == .autonomous)
    #expect(OperatingMode.allCases == [.observe, .suggest, .assist, .autonomous])
    #expect(String(decoding: try encoder.encode(OperatingMode.observe), as: UTF8.self) == #""observe""#)
    #expect(String(decoding: try encoder.encode(OperatingMode.autonomous), as: UTF8.self) == #""autonomous""#)
}

@Test
func policyStoreResolvesTheClassificationPolicyActiveAtAnObservationTime() throws {
    let databaseURL = temporaryPolicyDatabaseURL()
    defer { removePolicyDatabaseFiles(at: databaseURL) }
    let clock = PolicyTestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let store = try PolicyStore(databaseURL: databaseURL, now: { clock.now })

    _ = try store.save(policy(classifyingSteamAs: .gaming))
    clock.now = Date(timeIntervalSince1970: 1_700_000_600)
    _ = try store.save(policy(classifyingSteamAs: .work))

    let first = try #require(try store.effective(at: Date(timeIntervalSince1970: 1_700_000_300)))
    let second = try #require(try store.effective(at: Date(timeIntervalSince1970: 1_700_000_900)))

    #expect(first.version == 1)
    #expect(first.policy.behavior.choice(for: "Steam") == .gaming)
    #expect(second.version == 2)
    #expect(second.policy.behavior.choice(for: "Steam") == .work)
}

@Test
func gamingPolicyDefaultsAndSurvivesAStoreRestartWithoutResettingOtherPolicy() throws {
    let databaseURL = temporaryPolicyDatabaseURL()
    defer { removePolicyDatabaseFiles(at: databaseURL) }
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")

    do {
        let store = try PolicyStore(databaseURL: databaseURL)
        #expect(try store.currentGamingPolicy() == .balanced)
        _ = try store.save(original)

        let saved = try store.saveGamingPolicy(.firm)

        #expect(saved.version == 2)
        #expect(saved.policy.gaming == .firm)
        #expect(saved.policy.schedule == original.schedule)
        #expect(saved.policy.behavior == original.behavior)
        #expect(saved.policy.capture == original.capture)
    }

    let reopened = try PolicyStore(databaseURL: databaseURL)
    #expect(try reopened.currentGamingPolicy() == .firm)
    #expect(try reopened.current()?.policy.schedule.timeZoneIdentifier == "Africa/Cairo")
}

@Test
func gamingPolicyMutationRoundTripsThroughTheAgentCommandBoundary() async throws {
    let databaseURL = temporaryPolicyDatabaseURL()
    defer { removePolicyDatabaseFiles(at: databaseURL) }
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    let policyStore = try PolicyStore(databaseURL: databaseURL)
    let router = AgentMutationRouter(
        outbox: outbox,
        stateStore: try AgentOwnedStateStore(databaseURL: databaseURL),
        taskHistory: try TaskHistoryStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        planScheduler: AgentPlanScheduler(
            plans: try AutonomousPlanStore(databaseURL: databaseURL),
            reminders: reminders,
            outbox: outbox,
            calendar: EmptyGamingPolicyCalendar()
        ),
        policyStore: policyStore,
        reminderSnapshots: reminders,
        privacyData: try PrivacyDataService(databaseURL: databaseURL)
    )
    let command = AgentMutationCommand.savePolicyMutation(
        PolicyMutationRequest(
            requestID: "settings-policy-v1:gaming-command-round-trip",
            expectedVersion: 0,
            policy: UserPolicy.defaults().replacingGamingPolicy(.flexible),
            origin: .settings
        )
    )
    let encoded = try JSONEncoder().encode(command)

    #expect(try JSONDecoder().decode(AgentMutationCommand.self, from: encoded) == command)
    let first = try await router.apply(command)
    let second = try await router.apply(command)

    #expect(first.accepted)
    #expect(first.policyVersion == 1)
    #expect(second.policyVersion == 1)
    #expect(second.policyMutationReceipt?.replayed == true)
    #expect(try policyStore.currentGamingPolicy() == .flexible)
}

@Test
func staleAndConflictingPolicyMutationsDoNotTripTheDatabaseBreaker() async throws {
    let databaseURL = temporaryPolicyDatabaseURL()
    defer { removePolicyDatabaseFiles(at: databaseURL) }
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    let policyStore = try PolicyStore(databaseURL: databaseURL)
    let breaker = DatabaseWriteCircuitBreaker()
    let router = AgentMutationRouter(
        outbox: outbox,
        stateStore: try AgentOwnedStateStore(databaseURL: databaseURL),
        taskHistory: try TaskHistoryStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        planScheduler: AgentPlanScheduler(
            plans: try AutonomousPlanStore(databaseURL: databaseURL),
            reminders: reminders,
            outbox: outbox,
            calendar: EmptyGamingPolicyCalendar()
        ),
        policyStore: policyStore,
        reminderSnapshots: reminders,
        privacyData: try PrivacyDataService(databaseURL: databaseURL),
        writeCircuitBreaker: breaker
    )
    let winner = try onboardingPolicyRequest(
        flowID: "flow",
        step: .activityClassification,
        progressRevision: 7,
        expectedVersion: 0,
        policy: policy(mode: .assist)
    )
    _ = try await router.apply(.savePolicyMutation(winner))
    let stale = try onboardingPolicyRequest(
        flowID: "flow",
        step: .activityClassification,
        progressRevision: 7,
        expectedVersion: 0,
        policy: policy(mode: .autonomous)
    )

    await #expect(throws: PolicyStoreError.staleVersion(expected: 0, actual: 1)) {
        try await router.apply(.savePolicyMutation(stale))
    }
    #expect(!breaker.snapshot.isTripped)

    let conflict = PolicyMutationRequest(
        requestID: winner.requestID,
        expectedVersion: 0,
        policy: policy(mode: .autonomous),
        origin: winner.origin
    )
    await #expect(throws: PolicyStoreError.idempotencyConflict(winner.requestID)) {
        try await router.apply(.savePolicyMutation(conflict))
    }
    #expect(!breaker.snapshot.isTripped)

    let invalid = PolicyMutationRequest(
        requestID: "not-a-settings-request",
        expectedVersion: 1,
        policy: policy(mode: .observe),
        origin: .settings
    )
    await #expect(throws: PolicyStoreError.invalidRequest("settings_request_id")) {
        try await router.apply(.savePolicyMutation(invalid))
    }
    #expect(!breaker.snapshot.isTripped)
}

private func policy(mode: OperatingMode) -> UserPolicy {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    return UserPolicy(
        operatingMode: mode,
        automationPause: defaults.automationPause,
        schedule: defaults.schedule,
        calendar: defaults.calendar,
        privacy: defaults.privacy,
        wake: defaults.wake
    )
}

private func onboardingPolicyRequest(
    flowID: String,
    step: OnboardingStep,
    progressRevision: UInt64,
    expectedVersion: Int,
    policy: UserPolicy
) throws -> PolicyMutationRequest {
    let digest = try PolicyMutationRequest.canonicalPayloadDigest(for: policy)
    return PolicyMutationRequest(
        requestID: [
            "onboarding-policy-v1",
            flowID,
            step.rawValue,
            String(progressRevision),
            digest,
        ].joined(separator: ":"),
        expectedVersion: expectedVersion,
        policy: policy,
        origin: .onboarding(
            flowID: flowID,
            step: step,
            progressRevision: progressRevision
        )
    )
}

private func policy(classifyingSteamAs choice: AppClassificationChoice) -> UserPolicy {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    return UserPolicy(
        operatingMode: defaults.operatingMode,
        automationPause: defaults.automationPause,
        schedule: defaults.schedule,
        calendar: defaults.calendar,
        privacy: defaults.privacy,
        wake: defaults.wake,
        behavior: BehaviorPolicy(
            workApplications: choice == .work ? ["Steam"] : [],
            gamingApplications: choice == .gaming ? ["Steam"] : []
        )
    )
}

private final class PolicyTestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private struct EmptyGamingPolicyCalendar: CalendarAvailabilitySource {
    func commitments(
        from start: Date,
        through end: Date,
        calendarIdentifiers: [String]
    ) async throws -> [CalendarCommitment] {
        []
    }
}

private func temporaryPolicyDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-policy-\(UUID().uuidString).sqlite")
}

private func removePolicyDatabaseFiles(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
