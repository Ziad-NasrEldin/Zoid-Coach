import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class EndWorkdayReviewController: ObservableObject {
    @Published private(set) var isEndingWorkday = false
    @Published private(set) var statusMessage: String?

    private let applyCommand: @Sendable (TaskActivityCommand, String) async throws -> Void

    init(
        runtimeEnvironment: RuntimeEnvironment = .current(),
        applyCommand: (@Sendable (TaskActivityCommand, String) async throws -> Void)? = nil
    ) {
        if let applyCommand {
            self.applyCommand = applyCommand
        } else {
            let client = TodayDashboardXPCClient(runtimeEnvironment: runtimeEnvironment)
            self.applyCommand = { command, taskID in
                _ = try await client.apply(command, taskID: taskID)
            }
        }
    }

    @discardableResult
    func endWorkday(taskID: String) async -> Bool {
        guard !isEndingWorkday else { return false }
        isEndingWorkday = true
        statusMessage = nil
        defer { isEndingWorkday = false }
        do {
            try await applyCommand(.pauseForEndOfDay, taskID)
            statusMessage = "Workday ended. Opening today's review."
            return true
        } catch {
            statusMessage = "The workday could not be ended. The active task is unchanged. Check Agent source health and try again."
            return false
        }
    }
}
