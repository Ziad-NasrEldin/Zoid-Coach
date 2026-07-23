@preconcurrency import EventKit
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

enum AgentPlanDraftResult: Equatable {
    case drafted(itemCount: Int)
    case retainedExisting
    case remindersAccessUnavailable
}

enum AgentReminderAvailabilityDecision: Equatable {
    case draftWithoutSuggestions
    case continueWithEligible(Int)
    case unavailable
}

final class AgentReminderPlanner: @unchecked Sendable {
    private let eventStore: EKEventStore?
    private let fixtureAdapter: DeterministicOSFixtureAdapters?
    private let planStore: AutonomousPlanStore
    private let reminderSnapshotStore: ReminderSnapshotStore
    private let taskHistoryStore: TaskHistoryStore
    private let learningStore: LearningAggregateStore
    private let advisorProvider: @Sendable () -> (any PlanningAdvising)?
    private let reminderListPolicyProvider: @Sendable () throws -> ReminderListPolicy

    init(
        eventStore: EKEventStore? = nil,
        fixtureAdapter: DeterministicOSFixtureAdapters? = nil,
        planStore: AutonomousPlanStore,
        reminderSnapshotStore: ReminderSnapshotStore,
        taskHistoryStore: TaskHistoryStore,
        learningStore: LearningAggregateStore,
        advisorProvider: @escaping @Sendable () -> (any PlanningAdvising)? = { nil },
        reminderListPolicyProvider: @escaping @Sendable () throws -> ReminderListPolicy = {
            .legacyAllLists
        }
    ) {
        self.fixtureAdapter = fixtureAdapter
        self.eventStore = fixtureAdapter == nil ? (eventStore ?? EKEventStore()) : nil
        self.planStore = planStore
        self.reminderSnapshotStore = reminderSnapshotStore
        self.taskHistoryStore = taskHistoryStore
        self.learningStore = learningStore
        self.advisorProvider = advisorProvider
        self.reminderListPolicyProvider = reminderListPolicyProvider
    }

    static func planningAvailabilityDecision(
        sourceAccessAvailable: Bool,
        availableReminderCount: Int,
        eligibleReminderCount: Int
    ) -> AgentReminderAvailabilityDecision {
        precondition(availableReminderCount >= 0)
        precondition(eligibleReminderCount >= 0)
        precondition(eligibleReminderCount <= availableReminderCount)
        if eligibleReminderCount > 0 {
            return .continueWithEligible(eligibleReminderCount)
        }
        return sourceAccessAvailable ? .draftWithoutSuggestions : .unavailable
    }

    func draftPlan(
        for day: Date,
        overwriteExisting: Bool = false,
        recentBehavior: [PlanningBehaviorEvidence] = [],
        availableFocusMinutes: Int = 240
    ) async throws -> AgentPlanDraftResult {
        let storedSnapshots = try reminderSnapshotStore.loadIncomplete()
        let localReminders = storedSnapshots.filter { $0.sourceKind == .local }.map {
            AgentReminderSnapshot(
                id: $0.id, title: $0.title, dueDate: $0.dueDate,
                priority: priority(for: $0.priority), listID: nil,
                project: $0.listName
            )
        }
        let unfilteredExternalReminders: [AgentReminderSnapshot]
        if let fixtureAdapter {
            let fixtureSnapshot = try fixtureAdapter.snapshot()
            let namesByID = Dictionary(uniqueKeysWithValues: fixtureSnapshot.reminderLists.map {
                ($0.id, $0.name)
            })
            unfilteredExternalReminders = fixtureSnapshot.reminders.filter { !$0.isCompleted }.map {
                AgentReminderSnapshot(
                    id: $0.id, title: $0.title, dueDate: $0.dueDate,
                    priority: priority(for: $0.priority), listID: $0.listIdentifier,
                    project: namesByID[$0.listIdentifier] ?? $0.listIdentifier
                )
            }
        } else if hasFullAccess {
            unfilteredExternalReminders = await incompleteReminders()
        } else {
            unfilteredExternalReminders = storedSnapshots.filter {
                $0.sourceKind == .reminders
            }.map {
                AgentReminderSnapshot(
                    id: $0.id, title: $0.title, dueDate: $0.dueDate,
                    priority: priority(for: $0.priority), listID: $0.listID,
                    project: $0.listName
                )
            }
        }
        let reminderListPolicy = try reminderListPolicyProvider()
        let externalReminders = unfilteredExternalReminders.filter {
            reminderListPolicy.includes(listID: $0.listID)
        }
        let reminders = localReminders + externalReminders
        if !overwriteExisting {
            let usableTaskIDs = Set(reminders.compactMap {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.id
            })
            let existing = try planStore.loadDailyPlan(for: day)
            if !existing.isEmpty,
               existing.allSatisfy({ usableTaskIDs.contains($0.reminderID) }),
               existing.filter(\.isMainObjective).count == 1 {
                return .retainedExisting
            }
        }
        switch Self.planningAvailabilityDecision(
            sourceAccessAvailable: fixtureAdapter != nil || hasFullAccess,
            availableReminderCount: localReminders.count + unfilteredExternalReminders.count,
            eligibleReminderCount: reminders.count
        ) {
        case .draftWithoutSuggestions:
            return .drafted(itemCount: 0)
        case .unavailable:
            return .remindersAccessUnavailable
        case .continueWithEligible:
            break
        }
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
        if let advisor = advisorProvider() {
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
        if overwriteExisting {
            try planStore.replaceDailyPlan(proposal, for: day)
            return .drafted(itemCount: proposal.items.count)
        }
        let usableTaskIDs = Set(reminders.compactMap {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.id
        })
        switch try planStore.installDailyPlanIfNoUsablePlan(proposal, for: day, usableTaskIDs: usableTaskIDs) {
        case let .installed(entries):
            return .drafted(itemCount: entries.count)
        case .retained:
            return .retainedExisting
        }
    }

    func synchronizeReminderSource() async throws -> ReminderSyncResult? {
        if let fixtureAdapter {
            let reminderListPolicy = try reminderListPolicyProvider()
            let fixtureSnapshot = try fixtureAdapter.snapshot()
            let namesByID = Dictionary(uniqueKeysWithValues: fixtureSnapshot.reminderLists.map {
                ($0.id, $0.name)
            })
            let externalReminders = fixtureSnapshot.reminders
            let snapshots = reminderListPolicy.filteringExternalTasks(
                externalReminders,
                listID: { $0.listIdentifier }
            ).map {
                ReminderSourceSnapshot(
                    id: $0.id, title: $0.title, dueDate: $0.dueDate,
                    priority: $0.priority, notes: $0.notes,
                    listID: $0.listIdentifier,
                    listName: namesByID[$0.listIdentifier] ?? $0.listIdentifier,
                    modificationDate: nil, isCompleted: $0.isCompleted
                )
            }
            return try reminderSnapshotStore.synchronize(snapshots)
        }
        guard hasFullAccess else { return nil }
        guard let eventStore else { return nil }
        let previouslyIncomplete = Set(try reminderSnapshotStore.loadIncomplete().map(\.id))
        let predicate = eventStore.predicateForReminders(in: nil)
        let reminderListPolicy = try reminderListPolicyProvider()
        let snapshots: [ReminderSourceSnapshot] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let permitted = reminderListPolicy.filteringExternalTasks(
                    reminders ?? [],
                    listID: { $0.calendar.calendarIdentifier }
                )
                continuation.resume(returning: permitted.map {
                    ReminderSourceSnapshot(
                        id: $0.calendarItemIdentifier,
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled reminder" : $0.title,
                        dueDate: $0.dueDateComponents.flatMap(Calendar.current.date(from:)),
                        priority: $0.priority,
                        notes: $0.notes,
                        listID: $0.calendar.calendarIdentifier,
                        listName: $0.calendar.title,
                        modificationDate: $0.lastModifiedDate,
                        isCompleted: $0.isCompleted
                    )
                })
            }
        }
        let result = try reminderSnapshotStore.synchronize(snapshots)
        for snapshot in snapshots where snapshot.isCompleted && previouslyIncomplete.contains(snapshot.id) {
            try taskHistoryStore.record(
                taskID: snapshot.id,
                state: .completed,
                title: snapshot.title,
                sourceKind: snapshot.sourceKind,
                at: snapshot.modificationDate ?? Date()
            )
        }
        return result
    }

    private func incompleteReminders() async -> [AgentReminderSnapshot] {
        guard let eventStore else { return [] }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let snapshots = (reminders ?? []).map {
                    AgentReminderSnapshot(
                        id: $0.calendarItemIdentifier,
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled reminder" : $0.title,
                        dueDate: $0.dueDateComponents.flatMap(Calendar.current.date(from:)),
                        priority: self.priority(for: $0.priority),
                        listID: $0.calendar.calendarIdentifier,
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
        if let fixtureAdapter {
            return (try? fixtureAdapter.permission(.reminders)) == .granted
        }
        return switch EKEventStore.authorizationStatus(for: .reminder) {
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
    let listID: String?
    let project: String?

    init(
        id: String,
        title: String,
        dueDate: Date?,
        priority: ReminderPriority,
        listID: String?,
        project: String?
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.listID = listID
        self.project = project
    }
}
