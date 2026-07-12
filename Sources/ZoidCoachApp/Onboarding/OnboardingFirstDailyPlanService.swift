import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class OnboardingFirstDailyPlanService {
    private let remindersService: any RemindersServicing
    private let reminderStore: ReminderSnapshotStore
    private let planStore: AutonomousPlanStore
    private let taskHistoryStore: TaskHistoryStore
    private let learningStore: LearningAggregateStore
    private let todayAgent: TodayDashboardAgent
    private let now: @Sendable () -> Date
    private let timeZoneIdentifier: @Sendable () -> String
    private let planningCapacityMinutes: @Sendable (Date) -> Int
    private let reminderListPolicy: @Sendable () -> ReminderListPolicy

    init(
        databaseURL: URL,
        remindersService: any RemindersServicing,
        now: @escaping @Sendable () -> Date = { Date() },
        planningCapacityOverride: (@Sendable (Date) -> Int)? = nil
    ) throws {
        let policyStore = try PolicyStore(databaseURL: databaseURL)
        let timeZoneIdentifier: @Sendable () -> String = {
            (try? policyStore.current()?.policy.schedule.timeZoneIdentifier) ?? TimeZone.current.identifier
        }
        self.remindersService = remindersService
        reminderStore = try ReminderSnapshotStore(databaseURL: databaseURL)
        planStore = try AutonomousPlanStore(databaseURL: databaseURL, timeZoneIdentifier: timeZoneIdentifier)
        taskHistoryStore = try TaskHistoryStore(databaseURL: databaseURL)
        learningStore = try LearningAggregateStore(databaseURL: databaseURL)
        todayAgent = try TodayDashboardAgent(databaseURL: databaseURL)
        self.now = now
        self.timeZoneIdentifier = timeZoneIdentifier
        reminderListPolicy = {
            (try? policyStore.current()?.policy.reminderLists) ?? .legacyAllLists
        }
        planningCapacityMinutes = planningCapacityOverride ?? { date in
            let schedule = (try? policyStore.current()?.policy.schedule)
                ?? UserPolicy.defaults(timeZoneIdentifier: timeZoneIdentifier()).schedule
            return schedule.planningCapacityMinutes(on: date)
        }
    }

    func prepare() async -> OnboardingFirstDailyPlanResult {
        do {
            let referenceDate = now()
            let explicitlySelectedTaskIDs = Set(try planStore.loadDailyPlan(for: referenceDate).map(\.reminderID))
            if let prepared = try persistedPreparedResult(at: referenceDate, message: "Your existing Today plan is ready.") {
                return prepared
            }

            let planningTasks: [ReminderSourceSnapshot]
            let preparationMessage: String
            switch await remindersService.fetchIncompleteTasks() {
            case let .available(tasks):
                let policy = reminderListPolicy()
                let snapshots = policy.filteringExternalTasks(
                    tasks,
                    listID: { $0.listID }
                ).map(Self.snapshot(from:))
                _ = try reminderStore.synchronize(snapshots, observedAt: referenceDate)
                if let prepared = try persistedPreparedResult(at: referenceDate, message: "Your existing Today plan is ready.") {
                    return prepared
                }
                planningTasks = snapshots.filter {
                    Self.isUsable($0)
                        && isEligibleForToday($0, at: referenceDate, explicitlySelectedTaskIDs: explicitlySelectedTaskIDs)
                }
                preparationMessage = policy.isConfigured && policy.decisions.allSatisfy({ !$0.isIncluded })
                    ? "All Reminders lists are excluded, so a durable local starter plan was prepared. You can change the list policy in Settings."
                    : "Your first Today plan was prepared from Reminders."
            case .unavailable:
                planningTasks = []
                preparationMessage = "Reminders is unavailable, so a durable local starter plan was prepared. You can connect Reminders later."
            }

            let proposal: DailyPlanProposal
            let successMessage: String
            if planningTasks.isEmpty {
                let localTask = localFallbackTask(for: referenceDate)
                _ = try reminderStore.upsertLocal(localTask, observedAt: referenceDate)
                proposal = Self.proposal(
                    for: [localTask],
                    history: [:],
                    learningStore: learningStore,
                    referenceDate: referenceDate,
                    availableFocusMinutes: max(15, planningCapacityMinutes(referenceDate))
                )
                successMessage = preparationMessage == "Your first Today plan was prepared from Reminders."
                    ? "No eligible reminders were found for Today, so a durable local starter plan was prepared."
                    : preparationMessage
            } else {
                let history = try taskHistoryStore.evidence(for: planningTasks.map(\.id))
                let reminderProposal = Self.proposal(
                    for: planningTasks,
                    history: history,
                    learningStore: learningStore,
                    referenceDate: referenceDate,
                    availableFocusMinutes: planningCapacityMinutes(referenceDate)
                )
                if reminderProposal.items.isEmpty {
                    return .init(
                        state: .unavailable,
                        items: [],
                        message: "The eligible reminders exceed today's configured planning capacity. Adjust the work window or task estimates before approval."
                    )
                } else {
                    proposal = reminderProposal
                    successMessage = preparationMessage
                }
            }

            let usableTaskIDs = Set(try reminderStore.loadIncomplete().filter(Self.isUsable).map(\.id))
            _ = try planStore.installDailyPlanIfNoUsablePlan(proposal, for: referenceDate, usableTaskIDs: usableTaskIDs)
            return try persistedPreparedResult(at: referenceDate, message: successMessage) ?? .init(
                state: .failed,
                items: [],
                message: "The first plan could not be verified in Today. Setup was not advanced."
            )
        } catch {
            return .init(
                state: .failed,
                items: [],
                message: "The first Today plan could not be prepared: \(error.localizedDescription)"
            )
        }
    }

    private func persistedPreparedResult(at date: Date, message: String) throws -> OnboardingFirstDailyPlanResult? {
        let snapshot = try todayAgent.snapshot(now: date)
        let rows = snapshot.taskRows
        let persistedPlan = try planStore.loadDailyPlan(for: date)
        guard !rows.isEmpty,
              rows.count == persistedPlan.count,
              rows.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              rows.filter(\.isMainObjective).count == 1
        else { return nil }
        return .init(
            state: .prepared,
            items: rows.map {
                OnboardingFirstPlanItem(
                    id: $0.taskID,
                    title: $0.title,
                    estimateMinutes: $0.estimateMinutes,
                    isMainObjective: $0.isMainObjective
                )
            },
            message: message
        )
    }

    private func localFallbackTask(for date: Date) -> ReminderSourceSnapshot {
        ReminderSourceSnapshot(
            id: "zoid-local:onboarding:\(dayKey(for: date)):main",
            title: "Choose today's main objective",
            dueDate: nil,
            priority: 0,
            notes: "Created locally during onboarding. Replace this with a specific objective when ready.",
            listID: "zoid-local",
            listName: "Zoid Coach",
            sourceKind: .local
        )
    }

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier()) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func isEligibleForToday(
        _ task: ReminderSourceSnapshot,
        at date: Date,
        explicitlySelectedTaskIDs: Set<String>
    ) -> Bool {
        // UserPolicy has no configured Today-list identifier yet.
        // Do not infer that policy from a mutable list display name or ordering.
        if explicitlySelectedTaskIDs.contains(task.id) {
            return true
        }
        guard let dueDate = task.dueDate else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier()) ?? .current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else {
            return false
        }
        return dueDate < tomorrow
    }

    private static func snapshot(from task: ReminderTask) -> ReminderSourceSnapshot {
        ReminderSourceSnapshot(
            id: task.id,
            title: task.title,
            dueDate: task.dueDate,
            priority: task.priority,
            notes: task.notes,
            listID: task.listID,
            listName: task.listName,
            modificationDate: task.modificationDate
        )
    }

    private static func isUsable(_ task: ReminderSourceSnapshot) -> Bool {
        !task.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !task.isCompleted
    }

    private static func proposal(
        for tasks: [ReminderSourceSnapshot],
        history: [String: TaskHistoryEvidence],
        learningStore: LearningAggregateStore,
        referenceDate: Date,
        availableFocusMinutes: Int
    ) -> DailyPlanProposal {
        let candidates = tasks.map { task in
            let taskHistory = history[task.id] ?? TaskHistoryEvidence(selectionCount: 0, completionCount: 0, deferralCount: 0)
            let context = EstimateLearningContext(
                taskType: task.title.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).first.map { $0.lowercased() },
                project: task.listName
            )
            let fallbackEstimate = task.sourceKind == .local ? 15 : 45
            let estimate = (try? learningStore.learnedEstimate(for: context, fallbackMinutes: fallbackEstimate)) ?? fallbackEstimate
            return PlanningTaskCandidate(
                id: task.id,
                title: task.title,
                estimateMinutes: estimate,
                dueDate: task.dueDate,
                reminderPriority: ReminderPriority.fromEventKit(task.priority),
                carryoverDays: max(0, taskHistory.selectionCount - taskHistory.completionCount),
                deferralCount: taskHistory.deferralCount,
                recentAlignedMinutes: 0,
                isBlocked: false
            )
        }
        return AutonomousPlanner().plan(
            PlanningInput(
                referenceDate: referenceDate,
                availableFocusMinutes: availableFocusMinutes,
                maximumCommitments: 3,
                candidates: candidates
            )
        )
    }
}
