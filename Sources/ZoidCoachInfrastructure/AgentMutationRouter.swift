import CryptoKit
import Foundation
import ZoidCoachCore

public final class AgentMutationRouter: @unchecked Sendable {
    private let outbox: ActionOutboxStore
    private let stateStore: AgentOwnedStateStore
    private let taskHistory: TaskHistoryStore
    private let meetingArchive: ScreenwatchArchive
    private let planScheduler: AgentPlanScheduler
    private let policyStore: PolicyStore
    private let reminderSnapshots: ReminderSnapshotStore
    private let privacyData: PrivacyDataService
    private let writeCircuitBreaker: DatabaseWriteCircuitBreaker
    private let draftPlan: (@Sendable (Date, Bool) async throws -> Int)?

    public init(
        outbox: ActionOutboxStore,
        stateStore: AgentOwnedStateStore,
        taskHistory: TaskHistoryStore,
        meetingArchive: ScreenwatchArchive,
        planScheduler: AgentPlanScheduler,
        policyStore: PolicyStore,
        reminderSnapshots: ReminderSnapshotStore,
        privacyData: PrivacyDataService,
        writeCircuitBreaker: DatabaseWriteCircuitBreaker = DatabaseWriteCircuitBreaker(),
        draftPlan: (@Sendable (Date, Bool) async throws -> Int)? = nil
    ) {
        self.outbox = outbox
        self.stateStore = stateStore
        self.taskHistory = taskHistory
        self.meetingArchive = meetingArchive
        self.planScheduler = planScheduler
        self.policyStore = policyStore
        self.reminderSnapshots = reminderSnapshots
        self.privacyData = privacyData
        self.writeCircuitBreaker = writeCircuitBreaker
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

        case let .schedulePlan(day):
            let versioned = try policyStore.current()
            let policy = versioned?.policy ?? UserPolicy.defaults()
            guard !policy.automationPause.isPaused else { throw AgentMutationRouterError.automationPaused }
            let result = try await planScheduler.enqueueSchedule(
                for: day,
                policy: policy,
                policyVersion: versioned?.version ?? 1
            )
            let total = result.scheduledBlockCount + result.reminderMutationCount + result.obsoleteBlockDeletionCount
            return .init(accepted: true, message: "Queued \(total) Calendar and Reminder updates.")

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
            return .init(accepted: true, message: "Deleted \(count) learned estimate and planner-trust records.")

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

    private func activePolicyVersion() -> Int {
        (try? policyStore.current()?.version) ?? 1
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

    public var errorDescription: String? {
        switch self {
        case .invalidCommand: return "The agent rejected an invalid mutation command."
        case .automationPaused: return "Automation is paused in Settings."
        case .notReversible: return "This action cannot be safely reversed automatically."
        case .unavailable: return "The requested agent capability is unavailable."
        }
    }
}
