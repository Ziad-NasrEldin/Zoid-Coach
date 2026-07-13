import AppKit
import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

private enum SettingsPolicyPersistenceError: LocalizedError {
    case invalidMutationReceipt
    case concurrentChange

    var errorDescription: String? {
        switch self {
        case .invalidMutationReceipt:
            "The agent did not confirm a durable settings update."
        case .concurrentChange:
            "A newer policy was saved while these settings were open."
        }
    }
}

@MainActor
final class SettingsPolicyController: ObservableObject {
    @Published var draft: SettingsPolicyDraft
    @Published private(set) var activeVersion: Int?
    @Published private(set) var policyHistory: [VersionedUserPolicy] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var isSaving = false
    @Published private(set) var reminderListDiscovery: OnboardingReminderListDiscovery = .idle
    @Published private(set) var saveConflict: SettingsPolicySaveConflict?
    @Published private(set) var timeZonePlanMoveConfirmation: TimeZonePlanMoveWarning?

    private let store: PolicyStore?
    private let savePolicyThroughAgent: @Sendable (PolicyMutationRequest) async throws -> AgentMutationReceipt
    private var persistedPolicy: UserPolicy
    private let discoverReminderLists: @MainActor () async -> ReminderListLoad
    private var onReminderListPolicySaved: @MainActor @Sendable () -> Void
    private var reminderListLoadGeneration = UUID()
    private let inspectTimeZonePlanMove: @Sendable (String, String, Date) throws -> TimeZonePlanMoveWarning?
    private var confirmedTimeZonePlanMove: TimeZonePlanMoveWarning?

    init(
        databaseURL: URL? = nil,
        runtimeEnvironment: RuntimeEnvironment = .current(),
        savePolicyThroughAgent: (@Sendable (PolicyMutationRequest) async throws -> AgentMutationReceipt)? = nil,
        discoverReminderLists: (@MainActor () async -> ReminderListLoad)? = nil,
        inspectTimeZonePlanMove: (@Sendable (String, String, Date) throws -> TimeZonePlanMoveWarning?)? = nil,
        onReminderListPolicySaved: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.onReminderListPolicySaved = onReminderListPolicySaved
        if let discoverReminderLists {
            self.discoverReminderLists = discoverReminderLists
        } else if runtimeEnvironment.packageMode == .qa,
                  let adapter = try? QAFixtureOSComposition.makeAuthorizedAdapter(
                      runtimeEnvironment: runtimeEnvironment
                  ) {
            let reminders = QAFixtureRemindersService(adapter: adapter)
            self.discoverReminderLists = { await reminders.discoverLists() }
        } else if runtimeEnvironment.packageMode == .qa {
            self.discoverReminderLists = {
                .unavailable("The signed QA Reminder fixture could not be loaded.")
            }
        } else {
            let reminders = RemindersService()
            self.discoverReminderLists = { await reminders.discoverLists() }
        }
        if let savePolicyThroughAgent {
            self.savePolicyThroughAgent = savePolicyThroughAgent
        } else {
            let client = TodayDashboardXPCClient(runtimeEnvironment: runtimeEnvironment)
            self.savePolicyThroughAgent = { try await client.savePolicyMutation($0) }
        }
        store = try? PolicyStore(
            databaseURL: databaseURL ?? runtimeEnvironment.databaseURL,
            readOnly: true
        )
        let resolvedDatabaseURL = databaseURL ?? runtimeEnvironment.databaseURL
        self.inspectTimeZonePlanMove = inspectTimeZonePlanMove ?? { source, destination, date in
            try TimeZonePlanMoveInspector(databaseURL: resolvedDatabaseURL).warning(
                from: source,
                to: destination,
                at: date
            )
        }
        let current = try? store?.current()
        let policy = current?.policy ?? UserPolicy.defaults()
        persistedPolicy = policy
        draft = SettingsPolicyDraft(policy: policy)
        activeVersion = current?.version
        policyHistory = (try? store?.history()) ?? []
        if store == nil {
            statusMessage = "Policy storage is unavailable. Settings are read-only until local storage recovers."
        }
    }

    var isReadOnly: Bool { store == nil }

    var policyTimeZone: TimeZone {
        TimeZone(identifier: persistedPolicy.schedule.timeZoneIdentifier) ?? .current
    }

    var hasUnsavedChanges: Bool {
        draft.policy(preserving: persistedPolicy) != persistedPolicy
    }

    var previousPolicyVersion: Int? {
        policyHistory.first(where: { $0.version != activeVersion })?.version
    }

    func loadReminderLists() async {
        let generation = UUID()
        reminderListLoadGeneration = generation
        reminderListDiscovery = .loading
        let result = await discoverReminderLists()
        guard reminderListLoadGeneration == generation else { return }
        switch result {
        case let .available(lists): reminderListDiscovery = lists.isEmpty ? .empty : .available(lists)
        case let .permissionRequired(message): reminderListDiscovery = .permissionRequired(message)
        case let .unavailable(message): reminderListDiscovery = .failed(message)
        }
    }

    func setReminderListPolicySavedHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) {
        onReminderListPolicySaved = handler
    }

    func setReminderListDecision(_ isIncluded: Bool, listID: String) {
        draft.setReminderListDecision(isIncluded, listID: listID)
        draft.confirmReminderListConfiguration()
    }

    func configureReminderListsLocalOnly() {
        draft.configureReminderListsLocalOnly()
    }

    @discardableResult
    func save(now: Date = Date()) -> Task<Void, Never>? {
        guard store != nil else { return nil }
        let policy = draft.policy(preserving: persistedPolicy)
        do {
            if let warning = try inspectTimeZonePlanMove(
                persistedPolicy.schedule.timeZoneIdentifier,
                policy.schedule.timeZoneIdentifier,
                now
            ), confirmedTimeZonePlanMove != warning {
                timeZonePlanMoveConfirmation = warning
                confirmedTimeZonePlanMove = nil
                statusMessage = "Confirm the local-day change before these settings are saved."
                return nil
            }
        } catch {
            timeZonePlanMoveConfirmation = nil
            confirmedTimeZonePlanMove = nil
            statusMessage = "Settings were not saved: \(error.localizedDescription)"
            return nil
        }
        timeZonePlanMoveConfirmation = nil
        confirmedTimeZonePlanMove = nil
        isSaving = true
        return Task {
            do {
                try await persist(policy, conflictDraft: draft)
            } catch {
                if saveConflict == nil {
                    statusMessage = "Settings were not saved: \(error.localizedDescription)"
                }
            }
            isSaving = false
        }
    }

    @discardableResult
    func confirmTimeZonePlanMove() -> Task<Void, Never>? {
        guard let warning = timeZonePlanMoveConfirmation else { return nil }
        confirmedTimeZonePlanMove = warning
        timeZonePlanMoveConfirmation = nil
        return save(now: warning.referenceDate)
    }

    func cancelTimeZonePlanMove() {
        timeZonePlanMoveConfirmation = nil
        confirmedTimeZonePlanMove = nil
        statusMessage = "The time-zone change was not saved. Your edits remain available to review."
    }

    func keepCurrentWinningValues() {
        saveConflict = nil
        statusMessage = hasUnsavedChanges
            ? "Current winning values are preserved. Review and save the remaining non-conflicting edits when ready."
            : "Current policy v\(activeVersion ?? 0) remains saved."
    }

    @discardableResult
    func reapplyMyChanges() -> Task<Void, Never>? {
        guard let conflict = saveConflict else { return nil }
        draft = conflict.retryDraft
        saveConflict = nil
        statusMessage = "Reapplying your changes against policy v\(activeVersion ?? conflict.winningVersion)."
        return save()
    }

    @discardableResult
    func setPaused(_ paused: Bool) -> Task<Void, Never>? {
        setAutomationPause(paused ? .pausedIndefinitely : .running)
    }

    @discardableResult
    func pauseForOneHour(now: Date = Date()) -> Task<Void, Never>? {
        setAutomationPause(.pausedForOneHour(from: now))
    }

    @discardableResult
    func pauseUntilTomorrow(now: Date = Date()) -> Task<Void, Never>? {
        setAutomationPause(.pausedUntilTomorrow(from: now, timeZone: policyTimeZone))
    }

    @discardableResult
    private func setAutomationPause(_ pause: AutomationPause) -> Task<Void, Never>? {
        guard store != nil else { return nil }
        var pendingDraft = draft
        pendingDraft.automationPause = pause
        var pauseOnlyDraft = SettingsPolicyDraft(policy: persistedPolicy)
        pauseOnlyDraft.automationPause = pause
        isSaving = true
        let policy = pauseOnlyDraft.policy(preserving: persistedPolicy)
        return Task {
            do {
                try await persist(policy, restoring: pendingDraft)
            } catch {
                statusMessage = "The coaching pause was not updated: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    func requestWakeChange(_ enabled: Bool) {
        draft.wakeEligible = enabled
        if !enabled { save() }
    }

    @discardableResult
    func rollbackToPreviousPolicy() -> Task<Void, Never>? {
        guard let target = policyHistory.first(where: { $0.version != activeVersion }) else { return nil }
        isSaving = true
        return Task {
            do {
                try await persist(target.policy)
                statusMessage = "Restored the settings from policy v\(target.version) as a new audited version."
            } catch {
                statusMessage = "Policy rollback failed: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    func openDataFolder() {
        NSWorkspace.shared.open(ZoidCoachStorage.databaseURL().deletingLastPathComponent())
    }

    private func persist(
        _ policy: UserPolicy,
        restoring pendingDraft: SettingsPolicyDraft? = nil,
        conflictDraft: SettingsPolicyDraft? = nil
    ) async throws {
        let policy = policy.upgradedToCurrentSchema()
        let basePolicy = persistedPolicy
        let reminderListPolicyChanged = policy.reminderLists != basePolicy.reminderLists
        let request = PolicyMutationRequest(
            requestID: "settings-policy-v1:\(UUID().uuidString)",
            expectedVersion: activeVersion ?? 0,
            policy: policy,
            origin: .settings
        )
        let agentReceipt: AgentMutationReceipt
        do {
            agentReceipt = try await savePolicyThroughAgent(request)
        } catch {
            if let conflictDraft,
               reconcileConcurrentChange(
                   expectedVersion: request.expectedVersion,
                   basePolicy: basePolicy,
                   localDraft: conflictDraft
               ) {
                throw SettingsPolicyPersistenceError.concurrentChange
            }
            refreshPersistedPolicyPreservingDraft()
            throw error
        }
        let digest = try PolicyMutationRequest.canonicalPayloadDigest(for: policy)
        guard agentReceipt.accepted,
              let receipt = agentReceipt.policyMutationReceipt,
              receipt.requestID == request.requestID,
              receipt.payloadDigest == digest,
              receipt.expectedVersion == request.expectedVersion,
              receipt.origin == request.origin,
              receipt.resultingVersion > 0,
              agentReceipt.policyVersion == receipt.resultingVersion else {
            throw SettingsPolicyPersistenceError.invalidMutationReceipt
        }
        persistedPolicy = policy
        draft = pendingDraft ?? SettingsPolicyDraft(policy: policy)
        activeVersion = receipt.resultingVersion
        policyHistory = (try? store?.history()) ?? policyHistory
        statusMessage = agentReceipt.message
        saveConflict = nil
        if reminderListPolicyChanged { onReminderListPolicySaved() }
    }

    private func reconcileConcurrentChange(
        expectedVersion: Int,
        basePolicy: UserPolicy,
        localDraft: SettingsPolicyDraft
    ) -> Bool {
        guard let current = try? store?.current(), current.version != expectedVersion else { return false }
        let merge = SettingsPolicyConflictResolver.resolve(
            base: SettingsPolicyDraft(policy: basePolicy),
            mine: localDraft,
            current: SettingsPolicyDraft(policy: current.policy)
        )
        persistedPolicy = current.policy
        activeVersion = current.version
        policyHistory = (try? store?.history()) ?? policyHistory
        draft = merge.safeDraft
        saveConflict = SettingsPolicySaveConflict(
            winningVersion: current.version,
            concurrentChanges: merge.concurrentChanges,
            overlappingChanges: merge.overlappingChanges,
            safeDraft: merge.safeDraft,
            retryDraft: merge.retryDraft
        )
        let overlap = merge.overlappingChanges.isEmpty
            ? "Your independent edits remain ready to save."
            : "Choose whether to keep the current values or deliberately reapply yours."
        statusMessage = "Policy v\(current.version) won the concurrent save. \(overlap)"
        return true
    }

    private func refreshPersistedPolicyPreservingDraft() {
        guard let current = try? store?.current() else { return }
        persistedPolicy = current.policy
        activeVersion = current.version
        policyHistory = (try? store?.history()) ?? policyHistory
    }
}
