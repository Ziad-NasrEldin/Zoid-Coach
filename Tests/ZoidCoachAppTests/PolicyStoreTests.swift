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

    #expect(rolledBack.version == 1)
    #expect(rolledBack.policy.operatingMode == .fullyAutomatic)
    #expect(try store.current() == rolledBack)

    let third = try store.save(policy(mode: .suggestionsOnly))
    #expect(third.version == 3)
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

private func temporaryPolicyDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-policy-\(UUID().uuidString).sqlite")
}

private func removePolicyDatabaseFiles(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
