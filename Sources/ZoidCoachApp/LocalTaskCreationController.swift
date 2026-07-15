import Combine
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

protocol LocalTaskMutationSubmitting: Sendable {
    func createLocalTask(_ task: AgentLocalTask, addToToday: Bool, day: Date) async throws -> AgentMutationReceipt
}

extension TodayDashboardXPCClient: LocalTaskMutationSubmitting {
    func createLocalTask(_ task: AgentLocalTask, addToToday: Bool, day: Date) async throws -> AgentMutationReceipt {
        try await apply(.createLocalTask(task: task, addToToday: addToToday, day: day))
    }
}

@MainActor
final class LocalTaskCreationController: ObservableObject {
    @Published var title = ""
    @Published var notes = ""
    @Published var estimateMinutes = 30
    @Published var addToToday = true
    @Published var isTechnicalTask = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasPendingRetry = false

    private let client: any LocalTaskMutationSubmitting
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String
    private var pendingTaskID: String?
    private var pendingDay: Date?
    private var pendingTask: AgentLocalTask?

    init(
        client: any LocalTaskMutationSubmitting = TodayDashboardXPCClient(runtimeEnvironment: .current()),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { "local:user:\(UUID().uuidString.lowercased())" }
    ) {
        self.client = client
        self.now = now
        self.makeID = makeID
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= 240
            && notes.count <= 2_000
            && (5...480).contains(estimateMinutes)
            && !isSaving
    }

    @discardableResult
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let taskID = pendingTaskID ?? makeID()
        pendingTaskID = taskID
        let day = pendingDay ?? now()
        pendingDay = day
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = pendingTask ?? AgentLocalTask(
            id: taskID,
            title: trimmedTitle,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            estimateMinutes: estimateMinutes,
            declaredContext: isTechnicalTask ? .technical : nil
        )
        pendingTask = task
        do {
            let receipt = try await client.createLocalTask(
                task,
                addToToday: addToToday,
                day: day
            )
            guard receipt.accepted else { throw LocalTaskCreationError.rejected }
            pendingTaskID = nil
            pendingDay = nil
            pendingTask = nil
            hasPendingRetry = false
            return true
        } catch {
            hasPendingRetry = true
            errorMessage = "The result could not be confirmed. Try again to safely resend this exact draft, or cancel and check Today before creating another task."
            return false
        }
    }
}

private enum LocalTaskCreationError: Error {
    case rejected
}
