import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func productionAIProviderCapabilitiesDoNotOfferUnimplementedProviders() {
    let capabilities = AIProviderCapabilities.production

    #expect(capabilities[.localOllama].isSelectable)
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
}

@Test
func productionProviderSummaryPromisesNoRemoteTransmission() {
    #expect(
        AIProviderCapabilities.production.settingsSummary
            == "Rules-only planning is available. Local Ollama is supported when its loopback service is running. Remote transmission is not configured in this build."
    )
}
