import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func autonomousPlanStoreMakesAnAgentDraftAvailableToTheAppForItsTargetDay() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-autonomous-plan-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try AutonomousPlanStore(databaseURL: databaseURL)
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let proposal = DailyPlanProposal(
        items: [
            PlannedTask(
                taskID: "client-review",
                title: "Send client review",
                rank: 1,
                estimateMinutes: 60,
                reason: "Due within 24 hours",
                score: 700
            )
        ],
        mainObjectiveTaskID: "client-review",
        plannedFocusMinutes: 60,
        availableFocusMinutes: 180
    )

    try store.replaceDailyPlan(proposal, for: day)

    #expect(try store.hasPlan(for: day))
    let scheduleRequests = try PlanScheduleRequestStore(databaseURL: databaseURL)
    let pendingRequest = try scheduleRequests.claimNext()
    let request = try #require(pendingRequest)
    #expect(request.promptID.hasPrefix("automatic-plan:"))
    #expect(request.dayKey.isEmpty == false)
    let reopenedRequests = try PlanScheduleRequestStore(databaseURL: databaseURL)
    try reopenedRequests.recoverInterrupted()
    let recoveredRequest = try reopenedRequests.claimNext()
    #expect(recoveredRequest?.id == request.id)
}

@Test
func autonomousPlanStoreUsesTheConfiguredPolicyTimezoneForOwnership() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-plan-timezone-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-07-10T01:00:00Z"))
    let proposal = DailyPlanProposal(
        items: [PlannedTask(taskID: "timezone-task", title: "Timezone", rank: 1, estimateMinutes: 20, reason: "test", score: 1)],
        mainObjectiveTaskID: "timezone-task",
        plannedFocusMinutes: 20,
        availableFocusMinutes: 60
    )
    let losAngeles = try AutonomousPlanStore(databaseURL: databaseURL, timeZoneIdentifier: { "America/Los_Angeles" })
    try losAngeles.replaceDailyPlan(proposal, for: instant)
    #expect(try losAngeles.hasPlan(for: instant))
    let tokyo = try AutonomousPlanStore(databaseURL: databaseURL, timeZoneIdentifier: { "Asia/Tokyo" })
    #expect(try tokyo.hasPlan(for: instant) == false)
}

@Test
func autonomousPlanStoreCanRestoreThePreviousRevisionAfterAReplan() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("plan-revision-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }
    let store = try AutonomousPlanStore(databaseURL: url)
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let first = DailyPlanProposal(
        items: [PlannedTask(taskID: "first", title: "First", rank: 1, estimateMinutes: 30, reason: "due today", score: 900)],
        mainObjectiveTaskID: "first",
        plannedFocusMinutes: 30,
        availableFocusMinutes: 120
    )
    let second = DailyPlanProposal(
        items: [PlannedTask(taskID: "second", title: "Second", rank: 1, estimateMinutes: 45, reason: "calendar changed", score: 800)],
        mainObjectiveTaskID: "second",
        plannedFocusMinutes: 45,
        availableFocusMinutes: 120
    )
    try store.replaceDailyPlan(first, for: day)
    try store.replaceDailyPlan(second, for: day)
    #expect(try store.loadDailyPlan(for: day).map(\.reminderID) == ["second"])
    #expect(try store.restoreLatestRevision(for: day))
    #expect(try store.loadDailyPlan(for: day).map(\.reminderID) == ["first"])
}

@Test
func atomicPlanInstallRetainsAUsableVisiblePlanWithoutDuplicateIntentOrRevision() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("atomic-plan-retain-\(UUID().uuidString).sqlite")
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let store = try AutonomousPlanStore(databaseURL: url)
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let first = testProposal(id: "first")
    let second = testProposal(id: "second")

    #expect(try store.installDailyPlanIfNoUsablePlan(first, for: day, usableTaskIDs: ["first"]) == .installed(try store.loadDailyPlan(for: day)))
    #expect(try store.installDailyPlanIfNoUsablePlan(second, for: day, usableTaskIDs: ["first", "second"]) == .retained(try store.loadDailyPlan(for: day)))
    #expect(try store.loadDailyPlan(for: day).map(\.reminderID) == ["first"])
    #expect(try !store.restoreLatestRevision(for: day))

    let requests = try PlanScheduleRequestStore(databaseURL: url)
    #expect(try requests.claimNext() != nil)
    #expect(try requests.claimNext() == nil)
}

@Test
func atomicPlanInstallRepairsAnOrphanAndPreservesItAsOneRevision() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("atomic-plan-repair-\(UUID().uuidString).sqlite")
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let store = try AutonomousPlanStore(databaseURL: url)
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    try store.replaceDailyPlan(testProposal(id: "orphan"), for: day)

    let result = try store.installDailyPlanIfNoUsablePlan(testProposal(id: "replacement"), for: day, usableTaskIDs: ["replacement"])

    guard case .installed = result else {
        Issue.record("Expected the orphaned plan to be replaced")
        return
    }
    #expect(try store.loadDailyPlan(for: day).map(\.reminderID) == ["replacement"])
    #expect(try store.restoreLatestRevision(for: day))
    #expect(try store.loadDailyPlan(for: day).map(\.reminderID) == ["orphan"])
    #expect(try !store.restoreLatestRevision(for: day))
}

@Test
func concurrentAtomicPlanInstallsCommitExactlyOnePlan() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("atomic-plan-race-\(UUID().uuidString).sqlite")
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let firstStore = try AutonomousPlanStore(databaseURL: url)
    let secondStore = try AutonomousPlanStore(databaseURL: url)
    let proposal = testProposal(id: "winner")

    let results = try await withThrowingTaskGroup(of: DailyPlanInstallResult.self) { group in
        group.addTask { try firstStore.installDailyPlanIfNoUsablePlan(proposal, for: day, usableTaskIDs: ["winner"]) }
        group.addTask { try secondStore.installDailyPlanIfNoUsablePlan(proposal, for: day, usableTaskIDs: ["winner"]) }
        return try await group.reduce(into: []) { $0.append($1) }
    }

    #expect(results.filter { if case .installed = $0 { true } else { false } }.count == 1)
    #expect(results.filter { if case .retained = $0 { true } else { false } }.count == 1)
    #expect(try firstStore.loadDailyPlan(for: day).map(\.reminderID) == ["winner"])
    #expect(try !firstStore.restoreLatestRevision(for: day))
    let requests = try PlanScheduleRequestStore(databaseURL: url)
    #expect(try requests.claimNext() != nil)
    #expect(try requests.claimNext() == nil)
}

private func testProposal(id: String) -> DailyPlanProposal {
    DailyPlanProposal(
        items: [PlannedTask(taskID: id, title: id, rank: 1, estimateMinutes: 30, reason: "test", score: 1)],
        mainObjectiveTaskID: id,
        plannedFocusMinutes: 30,
        availableFocusMinutes: 60
    )
}
