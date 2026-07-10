import ZoidCoachCore

public struct AIProviderCapability: Equatable, Sendable {
    public let isSelectable: Bool
    public let status: String
    public let settingsLabel: String

    public init(isSelectable: Bool, status: String, settingsLabel: String) {
        self.isSelectable = isSelectable
        self.status = status
        self.settingsLabel = settingsLabel
    }
}

public struct AIProviderCapabilities: Sendable {
    public static let production = AIProviderCapabilities()

    public let settingsSummary = "Rules-only planning is available. Local Ollama is supported when its loopback service is running. Remote transmission is not configured in this build."

    public subscript(provider: AIProviderSelection) -> AIProviderCapability {
        switch provider {
        case .disabled:
            AIProviderCapability(isSelectable: true, status: "Rules-only planning", settingsLabel: "Disabled")
        case .localOllama:
            AIProviderCapability(isSelectable: true, status: "Local loopback provider", settingsLabel: "Local Ollama")
        case .appleOnDevice:
            AIProviderCapability(
                isSelectable: false,
                status: "On-device adapter is not installed",
                settingsLabel: "Apple On-Device - On-device adapter is not installed"
            )
        case .remoteOpenAI:
            AIProviderCapability(
                isSelectable: false,
                status: "Not configured in this build",
                settingsLabel: "Remote OpenAI - Not configured in this build"
            )
        }
    }
}
