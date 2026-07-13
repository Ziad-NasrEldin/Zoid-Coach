import Foundation

public struct StructuredGenerationRequest: Equatable, Sendable {
    public let schemaName: String
    public let schemaVersion: Int
    public let promptVersion: Int
    public let prompt: String
    public let inputJSON: Data
    public let outputSchemaJSON: Data

    public init(schemaName: String, schemaVersion: Int, promptVersion: Int, prompt: String, inputJSON: Data, outputSchemaJSON: Data) {
        self.schemaName = schemaName
        self.schemaVersion = schemaVersion
        self.promptVersion = promptVersion
        self.prompt = prompt
        self.inputJSON = inputJSON
        self.outputSchemaJSON = outputSchemaJSON
    }
}

public struct StructuredGenerationOutput: Equatable, Sendable {
    public let provider: String
    public let model: String
    public let json: Data

    public init(provider: String, model: String, json: Data) {
        self.provider = provider
        self.model = model
        self.json = json
    }
}

public protocol StructuredGenerationProviding: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func generate(_ request: StructuredGenerationRequest) async throws -> StructuredGenerationOutput
}

public enum StructuredGenerationError: LocalizedError, Equatable {
    case remoteProcessingNotAuthorized
    case invalidEndpoint
    case unavailable
    case invalidStructuredOutput
    case requestBudgetExceeded
    case concurrencyLimitReached

    public var errorDescription: String? {
        switch self {
        case .remoteProcessingNotAuthorized: "Remote model processing is disabled by privacy policy."
        case .invalidEndpoint: "The configured model endpoint is not allowed."
        case .unavailable: "The configured structured generation provider is unavailable."
        case .invalidStructuredOutput: "The provider returned invalid structured output."
        case .requestBudgetExceeded: "The configured model request budget has been reached."
        case .concurrencyLimitReached: "The model concurrency limit has been reached."
        }
    }
}
