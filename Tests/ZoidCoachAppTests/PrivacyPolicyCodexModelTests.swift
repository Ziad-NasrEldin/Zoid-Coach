import Foundation
import Testing
@testable import ZoidCoachCore

@Test
func privacyPolicyDefaultsLegacyPoliciesToGPT56Terra() throws {
    let legacyPolicy = try JSONDecoder().decode(
        PrivacyPolicy.self,
        from: #"{"screenshotAnalysisEnabled":true,"aiProvider":"codexCLI","remoteEvidencePolicy":"redactedMetadataOnly","rawScreenshotRetentionDays":30,"extractedTextRetentionDays":30,"diagnosticRetentionDays":14}"#.data(using: .utf8)!
    )

    #expect(legacyPolicy.codexCLIModel == nil)
    #expect(legacyPolicy.effectiveCodexCLIModel == CodexCLIModel.gpt56Terra)
    #expect(legacyPolicy.effectiveCodexCLIReasoningEffort == .low)
}

@Test
func privacyPolicyUsesCustomCodexModelID() {
    let policy = PrivacyPolicy(
        screenshotAnalysisEnabled: true,
        aiProvider: .codexCLI,
        remoteEvidencePolicy: .redactedMetadataOnly,
        rawScreenshotRetentionDays: 30,
        extractedTextRetentionDays: 30,
        diagnosticRetentionDays: 14,
        codexCLIModel: .custom,
        codexCLICustomModelID: "gpt-5.3-codex",
        codexCLIReasoningEffort: .xhigh
    )

    #expect(policy.effectiveCodexCLIModelID == "gpt-5.3-codex")
    #expect(policy.effectiveCodexCLIReasoningEffort == .xhigh)
}
