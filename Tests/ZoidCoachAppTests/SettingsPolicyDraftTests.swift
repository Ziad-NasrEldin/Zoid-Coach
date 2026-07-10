import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

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
    let controller = SettingsPolicyController(databaseURL: databaseURL) { policy in
        let saved = try store.save(policy)
        return AgentMutationReceipt(accepted: true, message: "saved", policyVersion: saved.version)
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
    let controller = SettingsPolicyController(databaseURL: databaseURL) { policy in
        let saved = try store.save(policy)
        return AgentMutationReceipt(accepted: true, message: "saved", policyVersion: saved.version)
    }
    controller.draft.capacityPercent = 95

    await controller.setPaused(true)?.value

    let persisted = try #require(store.current()?.policy)
    #expect(persisted.automationPause == .pausedIndefinitely)
    #expect(persisted.schedule.planningCapacityPercent == 70)
}
