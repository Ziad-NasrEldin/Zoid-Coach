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

private func temporaryPolicyDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-policy-\(UUID().uuidString).sqlite")
}

private func removePolicyDatabaseFiles(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
