@preconcurrency import EventKit
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

enum AgentPlanDraftResult: Equatable {
    case drafted(itemCount: Int)
    case retainedExisting
    case remindersAccessUnavailable
}

final class AgentReminderPlanner: @unchecked Sendable {
    private let eventStore: EKEventStore
    private let planStore: AutonomousPlanStore
    private let reminderSnapshotStore: ReminderSnapshotStore
    private let taskHistoryStore: TaskHistoryStore
    private let learningStore: LearningAggregateStore
    private let advisor: (any PlanningAdvising)?

    init(
        eventStore: EKEventStore = EKEventStore(),
        planStore: AutonomousPlanStore,
        reminderSnapshotStore: ReminderSnapshotStore,
        taskHistoryStore: TaskHistoryStore,
        learningStore: LearningAggregateStore,
        advisor: (any PlanningAdvising)? = nil
    ) {
        self.eventStore = eventStore
        self.planStore = planStore
        self.reminderSnapshotStore = reminderSnapshotStore
        self.taskHistoryStore = taskHistoryStore
        self.learningStore = learningStore
        self.advisor = advisor
    }

    func draftPlan(
        for day: Date,
        overwriteExisting: Bool = false,
        recentBehavior: [PlanningBehaviorEvidence] = [],
        availableFocusMinutes: Int = 240
    ) async throws -> AgentPlanDraftResult {
        if !overwriteExisting, try planStore.hasPlan(for: day) {
            return .retainedExisting
        }

        let reminders: [AgentReminderSnapshot]
        if hasFullAccess {
            reminders = await incompleteReminders()
        } else {
            reminders = try reminderSnapshotStore.loadIncomplete().map {
                AgentReminderSnapshot(id: $0.id, title: $0.title, dueDate: $0.dueDate, priority: priority(for: $0.priority), project: $0.listName)
            }
        }
        guard !reminders.isEmpty else { return .remindersAccessUnavailable }
        let history = try taskHistoryStore.evidence(for: reminders.map(\.id))
        var candidates = reminders.map {
            let taskHistory = history[$0.id] ?? TaskHistoryEvidence(selectionCount: 0, completionCount: 0, deferralCount: 0)
            let context = EstimateLearningContext(taskType: taskType(for: $0.title), project: $0.project)
            let learnedEstimate = (try? learningStore.learnedEstimate(for: context, fallbackMinutes: 45)) ?? 45
            return PlanningTaskCandidate(
                id: $0.id,
                title: $0.title,
                estimateMinutes: learnedEstimate,
                dueDate: $0.dueDate,
                reminderPriority: $0.priority,
                carryoverDays: max(0, taskHistory.selectionCount - taskHistory.completionCount),
                deferralCount: taskHistory.deferralCount,
                recentAlignedMinutes: 0,
                isBlocked: false
            )
        }
        if let advisor {
            let inputs = candidates.map {
                PlanningAdviceInput(
                    id: $0.id,
                    title: $0.title,
                    dueDate: $0.dueDate,
                    reminderPriority: $0.reminderPriority.rawValue,
                    carryoverDays: $0.carryoverDays,
                    deferralCount: $0.deferralCount,
                    recentAlignedMinutes: $0.recentAlignedMinutes
                )
            }
            if let advice = try? await advisor.advise(on: inputs, recentBehavior: recentBehavior) {
                let byID = Dictionary(uniqueKeysWithValues: advice.map { ($0.id, $0) })
                candidates = candidates.map { candidate in
                    guard let item = byID[candidate.id] else { return candidate }
                    return PlanningTaskCandidate(
                        id: candidate.id,
                        title: candidate.title,
                        estimateMinutes: candidate.estimateMinutes,
                        dueDate: candidate.dueDate,
                        reminderPriority: candidate.reminderPriority,
                        carryoverDays: candidate.carryoverDays,
                        deferralCount: candidate.deferralCount,
                        recentAlignedMinutes: candidate.recentAlignedMinutes,
                        isBlocked: candidate.isBlocked,
                        aiPriorityAdjustment: item.adjustment,
                        aiReason: item.reason
                    )
                }
            }
        }
        let proposal = AutonomousPlanner().plan(
            PlanningInput(
                referenceDate: day,
                availableFocusMinutes: availableFocusMinutes,
                maximumCommitments: 5,
                candidates: candidates
            )
        )
        try planStore.replaceDailyPlan(proposal, for: day)
        return .drafted(itemCount: proposal.items.count)
    }

    func synchronizeReminderSource() async throws -> ReminderSyncResult? {
        guard hasFullAccess else { return nil }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let snapshots: [ReminderSourceSnapshot] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map {
                    ReminderSourceSnapshot(
                        id: $0.calendarItemIdentifier,
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled reminder" : $0.title,
                        dueDate: $0.dueDateComponents.flatMap(Calendar.current.date(from:)),
                        priority: $0.priority,
                        notes: $0.notes,
                        listID: $0.calendar.calendarIdentifier,
                        listName: $0.calendar.title,
                        modificationDate: $0.lastModifiedDate
                    )
                })
            }
        }
        return try reminderSnapshotStore.synchronize(snapshots)
    }

    private func incompleteReminders() async -> [AgentReminderSnapshot] {
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let snapshots = (reminders ?? []).map {
                    AgentReminderSnapshot(
                        id: $0.calendarItemIdentifier,
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled reminder" : $0.title,
                        dueDate: $0.dueDateComponents.flatMap(Calendar.current.date(from:)),
                        priority: self.priority(for: $0.priority),
                        project: $0.calendar.title
                    )
                }
                continuation.resume(returning: snapshots)
            }
        }
    }

    private func priority(for eventKitPriority: Int) -> ReminderPriority {
        ReminderPriority.fromEventKit(eventKitPriority)
    }

    private func taskType(for title: String) -> String? {
        title.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).first.map { $0.lowercased() }
    }

    private var hasFullAccess: Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: true
        default: false
        }
    }
}

private struct AgentReminderSnapshot: Sendable {
    let id: String
    let title: String
    let dueDate: Date?
    let priority: ReminderPriority
    let project: String?
}
