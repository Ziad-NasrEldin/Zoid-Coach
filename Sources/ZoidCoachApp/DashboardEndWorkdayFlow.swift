import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

protocol DashboardEndWorkdayClient: Sendable {
    func fetchTodaySnapshot() async throws -> TodaySnapshot
    func apply(_ command: TaskActivityCommand, taskID: String) async throws -> TodaySnapshot
}

struct LiveDashboardEndWorkdayClient: DashboardEndWorkdayClient {
    let runtimeEnvironment: RuntimeEnvironment

    func fetchTodaySnapshot() async throws -> TodaySnapshot {
        try await TodayDashboardXPCClient(runtimeEnvironment: runtimeEnvironment).fetchTodaySnapshot()
    }

    func apply(_ command: TaskActivityCommand, taskID: String) async throws -> TodaySnapshot {
        try await TodayDashboardXPCClient(runtimeEnvironment: runtimeEnvironment).apply(command, taskID: taskID)
    }
}

@MainActor
final class DashboardEndWorkdayFlow: ObservableObject {
    @Published private(set) var isEndingWorkday = false
    @Published private(set) var statusMessage: String?

    private let client: any DashboardEndWorkdayClient

    init(
        client: any DashboardEndWorkdayClient = LiveDashboardEndWorkdayClient(
            runtimeEnvironment: .current()
        )
    ) {
        self.client = client
    }

    @discardableResult
    func endWorkday(expectedActiveTaskID: String) async -> Bool {
        guard !isEndingWorkday else { return false }
        isEndingWorkday = true
        statusMessage = nil
        defer { isEndingWorkday = false }

        do {
            let current = try await client.fetchTodaySnapshot()
            guard current.activeTask?.taskID == expectedActiveTaskID else {
                statusMessage = "The active task changed before confirmation. Nothing was ended. Review the refreshed Today state and try again."
                return false
            }

            let updated = try await client.apply(.pauseForEndOfDay, taskID: expectedActiveTaskID)
            guard updated.activeTask?.taskID != expectedActiveTaskID,
                  let task = updated.taskRows.first(where: { $0.taskID == expectedActiveTaskID }),
                  task.state == .paused,
                  task.latestPauseReason == .endingWorkday
            else {
                statusMessage = "The background agent did not confirm the end-of-workday result. Review the refreshed Today state before trying again."
                return false
            }

            statusMessage = "Workday ended. Opening today's review. Tracked time was preserved and the task was not marked complete."
            return true
        } catch {
            statusMessage = "Zoid 666 could not confirm the end-of-workday result. Review the refreshed Today state and check Agent source health before trying again."
            return false
        }
    }
}
