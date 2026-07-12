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
        requestID: "settings-save-001",
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
        requestID: "settings-save-002",
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
    let first = PolicyMutationRequest(
        requestID: "onboarding-policy:schedule:8:1",
        expectedVersion: initial.version,
        policy: policy(mode: .assist),
        origin: .onboarding(step: .schedule, progressRevision: 8)
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
    let command = AgentMutationCommand.saveGamingPolicy(.flexible)
    let encoded = try JSONEncoder().encode(command)

    #expect(try JSONDecoder().decode(AgentMutationCommand.self, from: encoded) == command)
    let first = try await router.apply(command)
    let second = try await router.apply(command)

    #expect(first.accepted)
    #expect(first.policyVersion == 1)
    #expect(second.policyVersion == 2)
    #expect(try policyStore.currentGamingPolicy() == .flexible)
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
