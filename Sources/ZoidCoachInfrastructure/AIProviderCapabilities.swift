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

    public let settingsSummary = "Rules-only and Local Ollama planning stay on this Mac. Codex CLI uses your signed-in OpenAI account and sends only the evidence level selected below. If it is unavailable, rules-only planning continues."

    public subscript(provider: AIProviderSelection) -> AIProviderCapability {
        switch provider {
        case .disabled:
            AIProviderCapability(isSelectable: true, status: "Rules-only planning", settingsLabel: "Disabled")
        case .localOllama:
            AIProviderCapability(isSelectable: true, status: "Local loopback provider", settingsLabel: "Local Ollama")
        case .codexCLI:
            AIProviderCapability(
                isSelectable: true,
                status: "Remote provider through local Codex CLI",
                settingsLabel: "Codex CLI - Remote processing"
            )
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
