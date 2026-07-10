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
    draft.visibleCalendarIdentifiers = "work, personal"
    draft.schedulingCalendarIdentifier = "work"
    draft.aiProvider = .localOllama
    draft.remoteEvidencePolicy = .explicitPrivateContent
    draft.rawScreenshotRetentionDays = 7

    let policy = draft.policy(preserving: original)

    #expect(policy.operatingMode == .approvalRequired)
    #expect(policy.automationPause == .pausedIndefinitely)
    #expect(policy.schedule.planningCapacityPercent == 80)
    #expect(policy.calendar.visibleCalendarIdentifiers == ["work", "personal"])
    #expect(policy.calendar.schedulingCalendarIdentifier == "work")
    #expect(policy.privacy.remoteEvidencePolicy == .localOnly)
    #expect(policy.privacy.rawScreenshotRetentionDays == 7)
    #expect(policy.validationViolations().isEmpty)
}

@Test
func settingsDraftKeepsWakeDisabledByDefault() {
    let policy = SettingsPolicyDraft(policy: .defaults()).policy(preserving: .defaults())

    #expect(policy.wake.isEligible == false)
    #expect(policy.wake.maximumDailyInterventions == 1)
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
