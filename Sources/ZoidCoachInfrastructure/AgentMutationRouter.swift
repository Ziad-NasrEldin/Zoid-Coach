import CryptoKit
import Foundation
import ZoidCoachCore

public final class AgentMutationRouter: @unchecked Sendable {
    private let outbox: ActionOutboxStore
    private let stateStore: AgentOwnedStateStore
    private let taskHistory: TaskHistoryStore
    private let meetingArchive: ScreenwatchArchive
    private let planScheduler: AgentPlanScheduler
    private let calendarPlanOperations: CalendarPlanOperationStore?
    private let policyStore: PolicyStore
    private let reminderSnapshots: ReminderSnapshotStore
    private let privacyData: PrivacyDataService
    private let writeCircuitBreaker: DatabaseWriteCircuitBreaker
    private let recommendationFeedback: RecommendationFeedbackStore?
    private let gamingManualAdjustments: GamingManualAdjustmentStore?
    private let draftPlan: (@Sendable (Date, Bool) async throws -> Int)?

    public init(
        outbox: ActionOutboxStore,
        stateStore: AgentOwnedStateStore,
        taskHistory: TaskHistoryStore,
        meetingArchive: ScreenwatchArchive,
        planScheduler: AgentPlanScheduler,
        calendarPlanOperations: CalendarPlanOperationStore? = nil,
        policyStore: PolicyStore,
        reminderSnapshots: ReminderSnapshotStore,
        privacyData: PrivacyDataService,
        writeCircuitBreaker: DatabaseWriteCircuitBreaker = DatabaseWriteCircuitBreaker(),
        recommendationFeedback: RecommendationFeedbackStore? = nil,
        gamingManualAdjustments: GamingManualAdjustmentStore? = nil,
        draftPlan: (@Sendable (Date, Bool) async throws -> Int)? = nil
    ) {
        self.outbox = outbox
        self.stateStore = stateStore
        self.taskHistory = taskHistory
        self.meetingArchive = meetingArchive
        self.planScheduler = planScheduler
        self.calendarPlanOperations = calendarPlanOperations
        self.policyStore = policyStore
        self.reminderSnapshots = reminderSnapshots
        self.privacyData = privacyData
        self.writeCircuitBreaker = writeCircuitBreaker
        self.recommendationFeedback = recommendationFeedback
        self.gamingManualAdjustments = gamingManualAdjustments
        self.draftPlan = draftPlan
    }

    public func apply(_ command: AgentMutationCommand) async throws -> AgentMutationReceipt {
        try writeCircuitBreaker.throwIfTripped()
        do {
            return try await applyWritable(command)
        } catch let error as AgentMutationRouterError {
            throw error
        } catch let error as PolicyStoreError {
            switch error {
            case .staleVersion, .idempotencyConflict, .invalidPolicy, .invalidRequest:
                throw error
            default:
                writeCircuitBreaker.trip(reason: "agent_mutation_write_failed")
                throw error
            }
        } catch let error as ReminderSnapshotStoreError {
            switch error {
            case .invalidLocalTask, .localSourceCollision, .localTaskConflict,
                 .invalidExternalSourceKind, .duplicateOrInvalidExternalSourceID,
                 .invalidStoredSourceKind:
                throw error
            case .openDatabase, .schema, .read, .write:
                writeCircuitBreaker.trip(reason: "agent_mutation_write_failed")
                throw error
            }
        } catch let error as CalendarPlanOperationStoreError {
            switch error {
            case .operationKeyConflict:
                throw error
            case .openDatabase, .read, .write, .receiptConflict:
                writeCircuitBreaker.trip(reason: "calendar_plan_operation_write_failed")
                throw error
            }
        } catch let error as GamingManualAdjustmentStoreError {
            switch error {
            case .invalidRequest, .idempotencyConflict, .removalExceedsManualGrant,
                 .dailyLimitExceeded:
                throw error
            case .openDatabase, .read, .write:
                writeCircuitBreaker.trip(reason: "agent_mutation_write_failed")
                throw error
            }
        } catch {
            writeCircuitBreaker.trip(reason: "agent_mutation_write_failed")
            throw error
        }
    }

    private func applyWritable(_ command: AgentMutationCommand) async throws -> AgentMutationReceipt {
        switch command {
        case let .completeReminder(reminderID):
            let result = try outbox.enqueue(
                type: .completeReminder,
                entityID: reminderID,
                desiredState: .completeReminder,
                planVersion: activePolicyVersion()
            )
            return .init(accepted: true, commandIDs: [result.command.id], message: "Reminder completion queued.")

        case let .rescheduleReminder(reminderID, dueDate):
            guard dueDate > Date(),
                  let reminder = try reminderSnapshots.loadIncomplete().first(where: { $0.id == reminderID }),
                  reminder.sourceKind == .reminders
            else {
                throw AgentMutationRouterError.invalidCommand
            }
            let result = try outbox.enqueue(
                type: .setReminderDueDate,
                entityID: reminderID,
                desiredState: .reminder(ReminderDesiredState(dueDate: dueDate)),
                planVersion: activePolicyVersion(),
                supersedingPending: true
            )
            return .init(
                accepted: true,
                commandIDs: [result.command.id],
                message: "Reminder reschedule queued."
            )

        case let .createLocalTask(task, addToToday, day):
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard task.id.hasPrefix("local:user:"),
                  task.id.count <= 128,
                  !title.isEmpty,
                  title.count <= 240,
                  (5...480).contains(task.estimateMinutes),
                  (notes?.count ?? 0) <= 2_000 else {
                throw AgentMutationRouterError.invalidCommand
            }
            _ = try reminderSnapshots.createLocal(
                ReminderSourceSnapshot(
                    id: task.id,
                    title: title,
                    dueDate: nil,
                    priority: 0,
                    notes: notes?.isEmpty == true ? nil : notes,
                    listID: "local:user",
                    listName: "Local Tasks",
                    modificationDate: day,
                    sourceKind: .local
                )
            )
            if addToToday {
                try stateStore.appendLocalTaskToDailyPlan(
                    taskID: task.id,
                    estimateMinutes: task.estimateMinutes,
                    day: day
                )
            }
            return .init(
                accepted: true,
                message: addToToday
                    ? "Local task created and added to today's plan."
                    : "Local task created."
            )

        case let .replaceDailyPlan(items, day):
            try stateStore.replaceDailyPlan(items, day: day)
            return .init(accepted: true, message: "Daily plan updated by the agent.")

        case let .replaceReminderListOrder(listIDs):
            try stateStore.replaceReminderListOrder(listIDs)
            return .init(accepted: true, message: "Reminder list order updated by the agent.")

        case let .recordTaskHistory(taskID, state, occurredAt):
            guard let historyState = TaskHistoryState(rawValue: state.rawValue) else {
                throw AgentMutationRouterError.invalidCommand
            }
            try taskHistory.record(taskID: taskID, state: historyState, at: occurredAt)
            return .init(accepted: true, message: "Task history recorded.")

        case let .recordRecommendationFeedback(request):
            guard let recommendationFeedback else {
                throw AgentMutationRouterError.invalidCommand
            }
            guard abs(request.occurredAt.timeIntervalSinceNow) <= 5 * 60 else {
                throw AgentMutationRouterError.invalidCommand
            }
            let timeZoneIdentifier = try policyStore.current()?.policy.schedule.timeZoneIdentifier
                ?? TimeZone.current.identifier
            _ = try recommendationFeedback.record(
                request,
                timeZoneIdentifier: timeZoneIdentifier
            )
            return .init(
                accepted: true,
                message: request.kind.confirmationMessage
            )

        case let .recordGamingManualAdjustment(request):
            guard let gamingManualAdjustments else {
                throw AgentMutationRouterError.invalidCommand
            }
            let result = try gamingManualAdjustments.record(request)
            let message: String
            if result.replayed {
                message = "This gaming-time adjustment was already saved."
            } else if result.adjustment.minutes > 0 {
                message = "Added \(result.adjustment.minutes) minutes to today's gaming allowance."
            } else {
                message = "Removed \(abs(result.adjustment.minutes)) manually granted minutes from today's gaming allowance."
            }
            return .init(accepted: true, message: message)

        case let .recordSourceCheck(sourceID, state, detail, evidence, checkedAt):
            try stateStore.recordSourceCheck(
                sourceID: sourceID,
                state: state,
                detail: detail,
                evidence: evidence,
                checkedAt: checkedAt
            )
            return .init(accepted: true, message: "Source health recorded.")

        case let .synchronizeReminderSnapshots(snapshots):
            _ = try reminderSnapshots.synchronize(
                snapshots.map {
                    ReminderSourceSnapshot(
                        id: $0.id,
                        title: $0.title,
                        dueDate: $0.dueDate,
                        priority: $0.priority,
                        notes: $0.notes,
                        listID: $0.listID,
                        listName: $0.listName,
                        modificationDate: $0.modificationDate,
                        isCompleted: $0.isCompleted
                    )
                }
            )
            return .init(accepted: true, message: "Reminder snapshot synchronized.")

        case let .savePolicyMutation(request):
            let receipt = try policyStore.saveMutation(request)
            return .init(
                accepted: true,
                message: receipt.replayed
                    ? "Policy mutation was already durable."
                    : "Policy version \(receipt.resultingVersion) saved by the agent.",
                policyVersion: receipt.resultingVersion,
                policyMutationReceipt: receipt
            )

        case let .schedulePlan(day, operationID):
            if let calendarPlanOperations {
                return try await applyDurableCalendarPlan(
                    day: day,
                    operationID: operationID,
                    operations: calendarPlanOperations
                )
            }
            let versioned = try policyStore.current()
            let policy = versioned?.policy ?? UserPolicy.defaults()
            guard !policy.automationPause.isPaused else { throw AgentMutationRouterError.automationPaused }
            let result = try await planScheduler.enqueueSchedule(
                for: day,
                policy: policy,
                policyVersion: versioned?.version ?? 1
            )
            guard result.unscheduledTaskIDs.isEmpty else {
                return .init(
                    accepted: false,
                    message: "The plan could not fit around current Calendar commitments. No Calendar or Reminder changes were queued."
                )
            }
            let uniqueCommandIDs = Set(result.commandIDs)
            let committedCommands = try uniqueCommandIDs.compactMap { commandID in
                try outbox.command(commandID: commandID).map {
                    AgentPlanCommandRequirement(type: $0.type, entityID: $0.entityID)
                }
            }
            guard uniqueCommandIDs.count == result.commandIDs.count,
                  committedCommands.count == uniqueCommandIDs.count,
                  Self.isCompleteScheduleCommandSet(
                    required: result.requiredCommands,
                    committed: Set(committedCommands)
                  ) else {
                throw AgentMutationRouterError.incompleteScheduleReceipt
            }
            return .init(
                accepted: true,
                commandIDs: result.commandIDs,
                message: result.commandIDs.isEmpty
                    ? "The approved plan already matches Calendar and Reminders."
                    : "Reconciled \(result.commandIDs.count) exact Calendar and Reminder updates."
            )

        case let .resolveMeetingCandidate(candidateID, title, start, durationMinutes, destination):
            guard let candidate = try meetingArchive.meetingCandidate(id: candidateID),
                  durationMinutes > 0,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentMutationRouterError.invalidCommand
            }
            let version = activePolicyVersion()
            let schedulingCalendarIdentifier = try policyStore.current()?.policy.calendar.schedulingCalendarIdentifier
            let result: ActionEnqueueResult
            switch destination {
            case .calendar:
                let fingerprint = meetingFingerprint(candidateID: candidateID, title: title, start: start, durationMinutes: durationMinutes)
                result = try outbox.enqueue(
                    type: .createConfirmedMeeting,
                    entityID: candidate.id,
                    desiredState: .meeting(
                        MeetingDesiredState(
                            title: title,
                            start: start,
                            durationMinutes: durationMinutes,
                            calendarIdentifier: schedulingCalendarIdentifier,
                            candidateFingerprint: fingerprint,
                            participants: candidate.participants,
                            location: candidate.location,
                            callLink: candidate.callLink,
                            timezoneIdentifier: candidate.timezoneIdentifier
                        )
                    ),
                    planVersion: version
                )
                try meetingArchive.updateMeetingCandidate(candidate, state: "calendar_queued")
            case .reminder:
                result = try outbox.enqueue(
                    type: .createReminder,
                    entityID: candidate.id,
                    desiredState: .createReminder(
                        ReminderCreationDesiredState(
                            title: title,
                            dueDate: start,
                            metadataMarker: "meeting-candidate:\(candidate.id)"
                        )
                    ),
                    planVersion: version
                )
                try meetingArchive.updateMeetingCandidate(candidate, state: "reminder_queued")
            }
            return .init(accepted: true, commandIDs: [result.command.id], message: "Meeting action queued.")

        case let .ignoreMeetingCandidate(candidateID):
            guard let candidate = try meetingArchive.meetingCandidate(id: candidateID) else {
                throw AgentMutationRouterError.invalidCommand
            }
            try meetingArchive.updateMeetingCandidate(candidate, state: "ignored")
            return .init(accepted: true, message: "Meeting suggestion ignored.")

        case let .deferMeetingCandidate(candidateID):
            guard let candidate = try meetingArchive.meetingCandidate(id: candidateID) else {
                throw AgentMutationRouterError.invalidCommand
            }
            try meetingArchive.updateMeetingCandidate(candidate, state: "ready_for_confirmation")
            return .init(accepted: true, message: "Meeting edit deferred.")

        case let .undoAction(commandID):
            guard let action = try outbox.command(commandID: commandID) else {
                throw AgentMutationRouterError.invalidCommand
            }
            switch action.state {
            case .pending, .retryableFailure:
                try outbox.cancel(commandID: commandID)
                return .init(accepted: true, message: "Pending action cancelled.")
            case .succeeded:
                guard case let .calendarBlock(block) = action.desiredState else {
                    throw AgentMutationRouterError.notReversible
                }
                let undo = try outbox.enqueue(
                    type: .deleteCalendarBlock,
                    entityID: action.entityID,
                    desiredState: .deleteOwnedCalendarBlock(ownershipToken: block.ownershipToken),
                    planVersion: activePolicyVersion()
                )
                return .init(accepted: true, commandIDs: [undo.command.id], message: "Calendar block removal queued.")
            case .executing, .terminalFailure, .cancelled:
                throw AgentMutationRouterError.notReversible
            }

        case .exportRedactedDiagnostics:
            let url = try privacyData.exportRedactedDiagnostics()
            return .init(accepted: true, message: "Redacted diagnostics exported.", artifactPath: url.path)

        case let .exportRedactedDiagnosticsTo(path):
            let url = try privacyData.exportRedactedDiagnostics(destinationURL: URL(fileURLWithPath: path))
            return .init(accepted: true, message: "Redacted diagnostics exported to the destination you chose.", artifactPath: url.path)

        case let .deleteDataRange(start, end):
            let count = try privacyData.deleteDateRange(start: start, end: end)
            return .init(accepted: true, message: "Deleted \(count) local evidence records in the selected range.")

        case let .deleteBehaviorSession(application, startedAt, endedAt):
            let session = PrivacyBehaviorSession(
                application: application,
                startedAt: startedAt,
                endedAt: endedAt,
                recordCount: 1
            )
            let count = try privacyData.deleteBehaviorSession(session)
            return .init(accepted: true, message: "Deleted \(count) records from the selected \(application) behavior session.")

        case .deleteExtractedConversationText:
            let count = try privacyData.deleteExtractedConversationText()
            return .init(accepted: true, message: "Deleted \(count) extracted conversation records.")

        case .deleteRawBehaviorMetadata:
            let count = try privacyData.deleteRawBehaviorMetadata()
            return .init(accepted: true, message: "Deleted \(count) raw behavior records. Screenwatch source files were not changed.")

        case .deleteAIRequestMetadata:
            let count = try privacyData.deleteAIRequestMetadata()
            return .init(accepted: true, message: "Deleted \(count) local AI request metadata records. Keychain credentials were not changed.")

        case .deleteReviewsAndLearnedRules:
            let count = try privacyData.deleteReviewsAndLearnedRules()
            return .init(
                accepted: true,
                message: ReviewLearningDeletionDisclosure.successMessage(deletedCount: count)
            )

        case .deleteAllUserData:
            let count = try privacyData.deleteAllUserData()
            return .init(accepted: true, message: "Deleted \(count) local Zoid 666 records. Database schema files remain so the app can restart safely.")

        case let .draftPlan(day, overwriteExisting):
            guard let draftPlan else { throw AgentMutationRouterError.unavailable }
            let count = try await draftPlan(day, overwriteExisting)
            return .init(accepted: true, message: "Drafted \(count) commitments through the agent.")
        }
    }

    public func recentActionAudit(limit: Int = 50) throws -> [ActionAuditEntry] {
        try outbox.recentCommands(limit: limit).map { action in
            let reversibleState = action.state == .pending || action.state == .retryableFailure || action.state == .succeeded
            let reversibleType: Bool
            switch action.desiredState {
            case .calendarBlock: reversibleType = true
            default: reversibleType = action.state != .succeeded
            }
            return ActionAuditEntry(
                id: action.id,
                actionType: action.type.rawValue,
                entityID: action.entityID,
                state: action.state.rawValue,
                attemptCount: action.attemptCount,
                createdAt: action.createdAt,
                updatedAt: action.updatedAt,
                canUndo: reversibleState && reversibleType
            )
        }
    }

    public func retryFailedActions(commandIDs: [String]) throws -> [ActionAuditEntry] {
        let identifiers = Array(Set(commandIDs)).sorted()
        guard !identifiers.isEmpty else { throw AgentMutationRouterError.invalidCommand }
        for identifier in identifiers {
            guard let command = try outbox.command(commandID: identifier),
                  command.state == .terminalFailure || command.state == .retryableFailure
            else { throw AgentMutationRouterError.invalidCommand }
        }
        for identifier in identifiers {
            try outbox.retryFailed(commandID: identifier)
        }
        return try recentActionAudit()
    }

    private func applyDurableCalendarPlan(
        day: Date,
        operationID: UUID,
        operations: CalendarPlanOperationStore
    ) async throws -> AgentMutationReceipt {
        let normalizedDay = Date(timeIntervalSince1970: day.timeIntervalSince1970.rounded(.down))
        let operation: CalendarPlanOperation
        if let existing = try operations.load(id: operationID) {
            try operations.validate(
                existing,
                requestFingerprint: existing.requestFingerprint,
                normalizedDay: normalizedDay
            )
            operation = existing
        } else {
            let versioned = try policyStore.current()
            let policy = versioned?.policy ?? UserPolicy.defaults()
            guard !policy.automationPause.isPaused else {
                throw AgentMutationRouterError.automationPaused
            }
            let prepared = try await planScheduler.prepareSchedule(
                for: normalizedDay,
                policy: policy,
                policyVersion: versioned?.version ?? 1
            )
            operation = try operations.begin(
                id: operationID,
                requestFingerprint: prepared.requestFingerprint,
                normalizedDay: normalizedDay,
                preparedSchedule: prepared
            )
        }

        if let receipt = operation.receipt {
            return receipt
        }

        let prepared = operation.preparedSchedule
        if !prepared.unscheduledTaskIDs.isEmpty || prepared.commands.isEmpty {
            let message = prepared.commands.isEmpty
                ? "The reviewed daily plan is no longer available. Nothing was written. Draft or review the current plan before confirming again."
                : "The reviewed plan no longer fits the available Calendar window. Nothing was written. Review updated availability before confirming again."
            let receipt = AgentMutationReceipt(
                accepted: false,
                message: message
            )
            try operations.finish(
                id: operationID,
                requestFingerprint: operation.requestFingerprint,
                receipt: receipt
            )
            return receipt
        }

        let result: AgentPlanSchedulingResult
        do {
            result = try planScheduler.enqueuePreparedSchedule(prepared)
        } catch {
            try? operations.recordPendingFailure(
                id: operationID,
                requestFingerprint: operation.requestFingerprint,
                diagnostic: error.localizedDescription
            )
            throw error
        }

        let uniqueCommandIDs = Set(result.commandIDs)
        let committedCommands = try uniqueCommandIDs.compactMap { commandID in
            try outbox.command(commandID: commandID).map {
                AgentPlanCommandRequirement(type: $0.type, entityID: $0.entityID)
            }
        }
        guard uniqueCommandIDs.count == result.commandIDs.count,
              committedCommands.count == uniqueCommandIDs.count,
              Self.isCompleteScheduleCommandSet(
                required: prepared.requiredCommands,
                committed: Set(committedCommands)
              ) else {
            throw AgentMutationRouterError.incompleteScheduleReceipt
        }

        let receipt = AgentMutationReceipt(
            accepted: true,
            commandIDs: result.commandIDs,
            message: result.commandIDs.isEmpty
                ? "The approved plan already matches Calendar and Reminders."
                : "Reconciled \(result.commandIDs.count) exact Calendar and Reminder updates."
        )
        try operations.finish(
            id: operationID,
            requestFingerprint: operation.requestFingerprint,
            receipt: receipt
        )
        return receipt
    }

    private func activePolicyVersion() -> Int {
        (try? policyStore.current()?.version) ?? 1
    }

    public static func isCompleteScheduleCommandSet(
        required: Set<AgentPlanCommandRequirement>,
        committed: Set<AgentPlanCommandRequirement>
    ) -> Bool {
        required == committed
    }

    private func meetingFingerprint(candidateID: String, title: String, start: Date, durationMinutes: Int) -> String {
        let value = "\(candidateID)|\(title.lowercased())|\(start.timeIntervalSince1970)|\(durationMinutes)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum AgentMutationRouterError: LocalizedError {
    case invalidCommand
    case automationPaused
    case notReversible
    case unavailable
    case incompleteScheduleReceipt

    public var errorDescription: String? {
        switch self {
        case .invalidCommand: return "The agent rejected an invalid mutation command."
        case .automationPaused: return "Automation is paused in Settings."
        case .notReversible: return "This action cannot be safely reversed automatically."
        case .unavailable: return "The requested agent capability is unavailable."
        case .incompleteScheduleReceipt: return "The Calendar write result is incomplete. Zoid 666 will reconcile the exact approved command set before claiming success."
        }
    }
}
