import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func settingsRoundTripsConfiguredCoachingLevelWithoutChangingGamingAllowance() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)
    draft.coachingLevel = .accountability

    let saved = draft.policy(preserving: original)

    #expect(saved.gaming.coachingLevel == .accountability)
    #expect(saved.gaming.dailyBudgetMinutes == original.gaming.dailyBudgetMinutes)
    #expect(saved.gaming.priorityTaskRewardMinutes == original.gaming.priorityTaskRewardMinutes)
    #expect(SettingsPolicyDraft(policy: saved).coachingLevel == .accountability)
}

@MainActor
private final class SettingsRefreshRecorder {
    private(set) var count = 0

    func record() { count += 1 }
}

@MainActor
private final class SettingsReminderLoadGate {
    private var continuations: [CheckedContinuation<ReminderListLoad, Never>] = []

    var count: Int { continuations.count }

    func wait() async -> ReminderListLoad {
        await withCheckedContinuation { continuations.append($0) }
    }

    func resume(_ index: Int, with result: ReminderListLoad) {
        continuations[index].resume(returning: result)
    }
}

@Test
func settingsDraftRoundTripsPolicyAndNormalizesLocalOnlyEvidence() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo")
    var draft = SettingsPolicyDraft(policy: original)
    draft.operatingMode = .approvalRequired
    draft.isPaused = true
    draft.capacityPercent = 80
    draft.nightlyPlanningTime = LocalTime(hour: 21, minute: 45)
    draft.morningConfirmationTime = LocalTime(hour: 7, minute: 15)
    draft.visibleCalendarIdentifiers = "work, personal"
    draft.schedulingCalendarIdentifier = "work"
    draft.aiProvider = .localOllama
    draft.remoteEvidencePolicy = .explicitPrivateContent
    draft.rawScreenshotRetentionDays = 7

    let policy = draft.policy(preserving: original)

    #expect(policy.operatingMode == .approvalRequired)
    #expect(policy.automationPause == .pausedIndefinitely)
    #expect(policy.schedule.planningCapacityPercent == 80)
    #expect(policy.schedule.nightlyPlanningTime == LocalTime(hour: 21, minute: 45))
    #expect(policy.schedule.morningConfirmationTime == LocalTime(hour: 7, minute: 15))
    #expect(policy.calendar.visibleCalendarIdentifiers == ["work", "personal"])
    #expect(policy.calendar.schedulingCalendarIdentifier == "work")
    #expect(policy.privacy.remoteEvidencePolicy == .localOnly)
    #expect(policy.privacy.rawScreenshotRetentionDays == 7)
    #expect(policy.validationViolations().isEmpty)
}

@Test
func calendarPickerSelectionsRoundTripWithoutExposingIdentifiersAsInput() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)

    draft.visibleCalendarIdentifierList = ["work-id", "personal-id"]
    draft.schedulingCalendarIdentifierValue = "work-id"

    #expect(draft.visibleCalendarIdentifierList == ["work-id", "personal-id"])
    #expect(draft.schedulingCalendarIdentifierValue == "work-id")

    draft.visibleCalendarIdentifierList = []
    draft.schedulingCalendarIdentifierValue = nil
    let policy = draft.policy(preserving: original)

    #expect(policy.calendar.visibleCalendarIdentifiers.isEmpty)
    #expect(policy.calendar.schedulingCalendarIdentifier == nil)
}

@Test
func reminderListDraftPersistsExplicitChoicesByIdentifier() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)

    draft.setReminderListDecision(true, listID: "work-id")
    draft.setReminderListDecision(false, listID: "personal-id")
    draft.confirmReminderListConfiguration()
    draft.capacityPercent = 85
    let policy = draft.policy(preserving: original)

    #expect(policy.reminderLists.isConfigured)
    #expect(policy.reminderLists.decision(for: "work-id") == true)
    #expect(policy.reminderLists.decision(for: "personal-id") == false)
    #expect(!policy.reminderLists.includes(listID: "new-id"))
    #expect(policy.schedule.planningCapacityPercent == 85)
}

@MainActor
@Test
func policyRollbackRestoresPreviousSettingsAsANewVersion() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-policy-rollback-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    let first = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    _ = try store.save(first)
    var changedDraft = SettingsPolicyDraft(policy: first)
    changedDraft.capacityPercent = 85
    _ = try store.save(changedDraft.policy(preserving: first))
    let controller = SettingsPolicyController(databaseURL: databaseURL) { request in
        let saved = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: saved.resultingVersion,
            policyMutationReceipt: saved
        )
    }

    await controller.rollbackToPreviousPolicy()?.value

    #expect(try store.current()?.version == 3)
    #expect(try store.current()?.policy.schedule.planningCapacityPercent == first.schedule.planningCapacityPercent)
}

@Test
func settingsDraftKeepsWakeDisabledByDefault() {
    let policy = SettingsPolicyDraft(policy: .defaults()).policy(preserving: .defaults())

    #expect(policy.wake.isEligible == false)
    #expect(policy.wake.maximumDailyInterventions == 1)
}

@Test
func settingsDraftPersistsGlobalAppChoicesAndReturnsAppsToAutomatic() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)

    draft.setClassification(.work, for: " Steam ")
    draft.setClassification(.gaming, for: "Xcode")
    draft.setClassification(.automatic, for: "XCODE")
    let policy = draft.policy(preserving: original)

    #expect(policy.behavior.workApplications == ["steam"])
    #expect(policy.behavior.gamingApplications.isEmpty)
    #expect(SettingsPolicyDraft(policy: policy).classification(for: "Steam") == .work)
    #expect(SettingsPolicyDraft(policy: policy).classification(for: "Xcode") == .automatic)
}

@Test
func settingsDraftBulkEditsCommunicationRulesAndCanResetEveryExplicitRule() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)

    draft.setClassifications(.communication, for: ["Slack", "Discord", " slack "])
    draft.setClassifications(.work, for: ["Xcode", "Cursor"])
    draft.setClassifications(.gaming, for: ["Steam"])

    #expect(draft.settingsClassification(for: "Discord") == .communication)
    #expect(draft.behaviorPolicy.communicationApplications == ["discord", "slack"])
    #expect(draft.policy(preserving: original).behavior.classificationOverride(for: "Slack") == .work)

    draft.resetApplicationRules()

    #expect(draft.behaviorPolicy == BehaviorPolicy())
    #expect(draft.settingsClassification(for: "Steam") == .automatic)
}

@Test
func settingsDraftCannotPersistAnUnavailableAIProvider() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)
    draft.aiProvider = .remoteOpenAI
    draft.remoteEvidencePolicy = .explicitPrivateContent

    let policy = draft.policy(preserving: original)

    #expect(policy.privacy.aiProvider == .disabled)
    #expect(policy.privacy.remoteEvidencePolicy == .localOnly)
}

@Test
func settingsDraftPersistsCodexCLIWithRemoteEvidencePolicy() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)
    draft.selectAIProvider(.codexCLI)

    let policy = draft.policy(preserving: original)
    let roundTrippedDraft = SettingsPolicyDraft(policy: policy)

    #expect(policy.privacy.aiProvider == .codexCLI)
    #expect(draft.remoteEvidencePolicy == .redactedMetadataOnly)
    #expect(policy.privacy.remoteEvidencePolicy == .redactedMetadataOnly)
    #expect(policy.validationViolations().isEmpty)
    #expect(roundTrippedDraft.aiProvider == .codexCLI)
    #expect(roundTrippedDraft.remoteEvidencePolicy == .redactedMetadataOnly)

    draft.remoteEvidencePolicy = .localOnly
    let localOnlyPolicy = draft.policy(preserving: original)
    let localOnlyRoundTrip = SettingsPolicyDraft(policy: localOnlyPolicy)
    #expect(localOnlyPolicy.privacy.remoteEvidencePolicy == .localOnly)
    #expect(localOnlyRoundTrip.remoteEvidencePolicy == .localOnly)
}

@Test
func settingsDraftPersistsSelectedCodexModel() {
    let original = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    var draft = SettingsPolicyDraft(policy: original)
    draft.selectAIProvider(.codexCLI)
    draft.codexCLIModel = .gpt55

    let policy = draft.policy(preserving: original)
    let roundTrippedDraft = SettingsPolicyDraft(policy: policy)

    #expect(policy.privacy.codexCLIModel == .gpt55)
    #expect(roundTrippedDraft.codexCLIModel == .gpt55)
}

@Test
func settingsDraftPresentsPersistedUnavailableProviderAsDisabled() {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let remotePolicy = UserPolicy(
        operatingMode: defaults.operatingMode,
        automationPause: defaults.automationPause,
        schedule: defaults.schedule,
        calendar: defaults.calendar,
        privacy: PrivacyPolicy(
            screenshotAnalysisEnabled: true,
            aiProvider: .remoteOpenAI,
            remoteEvidencePolicy: .explicitPrivateContent,
            rawScreenshotRetentionDays: 30,
            extractedTextRetentionDays: 30,
            diagnosticRetentionDays: 14
        ),
        wake: defaults.wake
    )

    let draft = SettingsPolicyDraft(policy: remotePolicy)

    #expect(draft.aiProvider == .disabled)
    #expect(draft.remoteEvidencePolicy == .localOnly)
}

@MainActor
@Test
func oneStepPausePersistsImmediatelyWithoutSavingOtherDraftEdits() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let controller = SettingsPolicyController(databaseURL: databaseURL) { request in
        let saved = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: saved.resultingVersion,
            policyMutationReceipt: saved
        )
    }
    controller.draft.capacityPercent = 95
    controller.draft.setClassification(.work, for: "Steam")

    await controller.setPaused(true)?.value

    let persisted = try #require(store.current()?.policy)
    #expect(persisted.automationPause == .pausedIndefinitely)
    #expect(persisted.schedule.planningCapacityPercent == 70)
    #expect(persisted.behavior.choice(for: "Steam") == .automatic)
    #expect(controller.draft.capacityPercent == 95)
    #expect(controller.draft.classification(for: "Steam") == .work)
}

@MainActor
@Test
func savedAppClassificationLoadsInANewSettingsController() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-app-settings-restart-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let controller = SettingsPolicyController(databaseURL: databaseURL) { request in
        let saved = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: saved.resultingVersion,
            policyMutationReceipt: saved
        )
    }
    controller.draft.setClassification(.gaming, for: "Steam")
    await controller.save()?.value

    let reopened = SettingsPolicyController(databaseURL: databaseURL) { _ in
        throw RestartTestError.unexpectedSave
    }

    #expect(reopened.draft.classification(for: "Steam") == .gaming)
}

@MainActor
@Test
func staleSettingsWindowCannotOverwriteANewerPolicyVersion() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-stale-settings-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let apply: @Sendable (PolicyMutationRequest) async throws -> AgentMutationReceipt = { request in
        let receipt = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: receipt.resultingVersion,
            policyMutationReceipt: receipt
        )
    }
    let first = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    let stale = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    first.draft.capacityPercent = 80
    stale.draft.capacityPercent = 95

    await first.save()?.value
    await stale.save()?.value

    #expect(try store.current()?.policy.schedule.planningCapacityPercent == 80)
    #expect(try store.current()?.version == 2)
    #expect(stale.activeVersion == 2)
    #expect(!stale.hasUnsavedChanges)
    #expect(stale.statusMessage?.contains("won the concurrent save") == true)
    #expect(stale.saveConflict?.winningVersion == 2)
    #expect(stale.saveConflict?.overlappingChanges == ["Planning capacity"])
    #expect(stale.draft.capacityPercent == 80)

    await stale.reapplyMyChanges()?.value

    #expect(try store.current()?.policy.schedule.planningCapacityPercent == 95)
    #expect(try store.current()?.version == 3)
    #expect(stale.activeVersion == 3)
    #expect(!stale.hasUnsavedChanges)
    #expect(stale.saveConflict == nil)
}

@Test
func settingsConflictResolverPreservesIndependentEditsAndCurrentWinners() {
    let base = SettingsPolicyDraft(policy: .defaults(timeZoneIdentifier: "UTC"))
    var mine = base
    mine.capacityPercent = 90
    mine.quietStart = LocalTime(hour: 20, minute: 30)
    var current = base
    current.capacityPercent = 80
    current.screenshotAnalysisEnabled = false

    let result = SettingsPolicyConflictResolver.resolve(
        base: base,
        mine: mine,
        current: current
    )

    #expect(result.safeDraft.capacityPercent == 80)
    #expect(result.safeDraft.quietStart == LocalTime(hour: 20, minute: 30))
    #expect(!result.safeDraft.screenshotAnalysisEnabled)
    #expect(result.retryDraft.capacityPercent == 90)
    #expect(result.retryDraft.quietStart == LocalTime(hour: 20, minute: 30))
    #expect(!result.retryDraft.screenshotAnalysisEnabled)
    #expect(result.overlappingChanges == ["Planning capacity"])
    #expect(result.concurrentChanges == ["Planning capacity", "Screenshot analysis"])
}

@MainActor
@Test
func repeatedConcurrentSettingsChangesRequireAChoiceEveryTimeWithoutDuplicateVersions() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-repeated-settings-conflict-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let apply: @Sendable (PolicyMutationRequest) async throws -> AgentMutationReceipt = { request in
        let receipt = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: receipt.resultingVersion,
            policyMutationReceipt: receipt
        )
    }
    let writer = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    let stale = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    stale.draft.capacityPercent = 95
    writer.draft.capacityPercent = 80
    await writer.save()?.value
    await stale.save()?.value
    #expect(stale.saveConflict?.winningVersion == 2)

    let secondWriter = SettingsPolicyController(databaseURL: databaseURL, savePolicyThroughAgent: apply)
    secondWriter.draft.capacityPercent = 75
    await secondWriter.save()?.value
    await stale.reapplyMyChanges()?.value

    #expect(try store.current()?.version == 3)
    #expect(try store.current()?.policy.schedule.planningCapacityPercent == 75)
    #expect(stale.activeVersion == 3)
    #expect(stale.saveConflict?.winningVersion == 3)
    #expect(stale.saveConflict?.overlappingChanges == ["Planning capacity"])

    stale.keepCurrentWinningValues()
    #expect(stale.saveConflict == nil)
    #expect(stale.draft.capacityPercent == 75)
    #expect(try store.history().map(\.version) == [3, 2, 1])
}

@MainActor
@Test
func staleSettingsReminderListEditSurvivesConflictAndRetriesAgainstTheNewVersion() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-stale-reminder-settings-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let apply: @Sendable (PolicyMutationRequest) async throws -> AgentMutationReceipt = { request in
        let receipt = try store.saveMutation(request)
        return AgentMutationReceipt(
            accepted: true,
            message: "saved",
            policyVersion: receipt.resultingVersion,
            policyMutationReceipt: receipt
        )
    }
    let first = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: apply
    )
    let stale = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: apply
    )
    first.draft.capacityPercent = 80
    stale.setReminderListDecision(true, listID: "  opaque-id  ")

    await first.save()?.value
    await stale.save()?.value

    #expect(stale.activeVersion == 2)
    #expect(stale.hasUnsavedChanges)
    #expect(stale.draft.reminderListPolicy.decision(for: "  opaque-id  ") == true)
    #expect(try store.current()?.policy.reminderLists == .legacyAllLists)

    await stale.save()?.value

    #expect(try store.current()?.version == 3)
    #expect(try store.current()?.policy.reminderLists.isConfigured == true)
    #expect(try store.current()?.policy.reminderLists.decision(for: "  opaque-id  ") == true)
    #expect(try store.current()?.policy.schedule.planningCapacityPercent == 80)
    #expect(!stale.hasUnsavedChanges)
}

@MainActor
@Test
func settingsDoNotAdvanceWithoutAnExactDurableMutationReceipt() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-receipt-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.save(.defaults(timeZoneIdentifier: "UTC"))
    let controller = SettingsPolicyController(databaseURL: databaseURL) { _ in
        AgentMutationReceipt(accepted: true, message: "saved", policyVersion: 2)
    }
    controller.draft.capacityPercent = 95

    await controller.save()?.value

    #expect(try store.current()?.version == 1)
    #expect(controller.activeVersion == 1)
    #expect(controller.hasUnsavedChanges)
    #expect(controller.statusMessage?.contains("did not confirm") == true)
}

@MainActor
@Test
func settingsExposeTypedReminderPermissionAndExplicitEmptyLocalOnlyChoice() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-reminder-recovery-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    _ = try PolicyStore(databaseURL: databaseURL)
        .saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let permission = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { _ in
            AgentMutationReceipt(accepted: false, message: "unused", policyVersion: nil)
        },
        discoverReminderLists: {
            .permissionRequired("Grant Reminders full access.")
        }
    )

    await permission.loadReminderLists()

    #expect(permission.reminderListDiscovery == .permissionRequired(
        "Grant Reminders full access."
    ))

    let empty = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { _ in
            AgentMutationReceipt(accepted: false, message: "unused", policyVersion: nil)
        },
        discoverReminderLists: { .available([]) }
    )
    await empty.loadReminderLists()
    empty.configureReminderListsLocalOnly()

    #expect(empty.reminderListDiscovery == .empty)
    #expect(empty.draft.reminderListPolicy.isConfigured)
    #expect(empty.draft.reminderListPolicy.decisions.allSatisfy { !$0.isIncluded })
    #expect(empty.hasUnsavedChanges)
}

@MainActor
@Test
func alternateSettingsSaveRefreshesChangedReminderPolicyExactlyOnce() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-alternate-refresh-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    let store = try PolicyStore(databaseURL: databaseURL)
    _ = try store.saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let refresh = SettingsRefreshRecorder()
    let controller = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { request in
            let receipt = try store.saveMutation(request)
            return AgentMutationReceipt(
                accepted: true,
                message: "saved",
                policyVersion: receipt.resultingVersion,
                policyMutationReceipt: receipt
            )
        },
        onReminderListPolicySaved: { refresh.record() }
    )
    controller.setReminderListDecision(false, listID: "personal")

    controller.requestWakeChange(false)
    while controller.isSaving { await Task.yield() }

    #expect(refresh.count == 1)
    #expect(try store.current()?.policy.reminderLists.decision(for: "personal") == false)
    #expect(!controller.hasUnsavedChanges)
}

@MainActor
@Test
func settingsPermissionRecheckIgnoresAnOlderInFlightResult() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-coach-settings-reminder-race-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    _ = try PolicyStore(databaseURL: databaseURL)
        .saveSystemMaintenancePolicy(.defaults(timeZoneIdentifier: "UTC"))
    let gate = SettingsReminderLoadGate()
    let controller = SettingsPolicyController(
        databaseURL: databaseURL,
        savePolicyThroughAgent: { _ in
            AgentMutationReceipt(accepted: false, message: "unused", policyVersion: nil)
        },
        discoverReminderLists: { await gate.wait() }
    )
    let first = Task { await controller.loadReminderLists() }
    while gate.count < 1 { await Task.yield() }
    let recheck = Task { await controller.loadReminderLists() }
    while gate.count < 2 { await Task.yield() }

    gate.resume(1, with: .available([
        ReminderListChoice(id: "work", name: "Work")
    ]))
    await recheck.value
    gate.resume(0, with: .permissionRequired("Stale permission state"))
    await first.value

    #expect(controller.reminderListDiscovery == .available([
        ReminderListChoice(id: "work", name: "Work")
    ]))
}

private enum RestartTestError: Error {
    case unexpectedSave
}
