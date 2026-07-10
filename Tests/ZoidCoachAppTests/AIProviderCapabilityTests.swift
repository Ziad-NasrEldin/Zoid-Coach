import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func productionAIProviderCapabilitiesDoNotOfferUnimplementedProviders() {
    let capabilities = AIProviderCapabilities.production

    #expect(capabilities[.localOllama].isSelectable)
    #expect(capabilities[.codexCLI].isSelectable)
    #expect(capabilities[.codexCLI].status == "Remote provider through local Codex CLI")
    #expect(!capabilities[.remoteOpenAI].isSelectable)
    #expect(capabilities[.remoteOpenAI].status == "Not configured in this build")
    #expect(!capabilities[.appleOnDevice].isSelectable)
    #expect(capabilities[.appleOnDevice].status == "On-device adapter is not installed")
}

@Test
func unavailableAIProvidersHaveTruthfulSettingsLabels() {
    let capabilities = AIProviderCapabilities.production

    #expect(capabilities[.remoteOpenAI].settingsLabel == "Remote OpenAI - Not configured in this build")
    #expect(capabilities[.appleOnDevice].settingsLabel == "Apple On-Device - On-device adapter is not installed")
    #expect(capabilities[.localOllama].settingsLabel == "Local Ollama")
    #expect(capabilities[.codexCLI].settingsLabel == "Codex CLI - Remote processing")
}

@Test
func productionProviderSummaryExplainsCodexRemoteTransmission() {
    #expect(
        AIProviderCapabilities.production.settingsSummary
            == "Rules-only and Local Ollama planning stay on this Mac. Codex CLI uses your signed-in OpenAI account and sends only the evidence level selected below. If it is unavailable, rules-only planning continues."
    )
}
