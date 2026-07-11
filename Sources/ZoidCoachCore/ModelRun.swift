import Foundation

public enum ModelRunValidationState: String, Codable, Sendable {
    case pending
    case validated
    case rejected
    case providerFailure
}

public struct ModelRun: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let provider: String
    public let model: String
    public let schemaVersion: Int
    public let promptVersion: Int
    public let normalizedInputHash: String
    public let validationState: ModelRunValidationState
    public let redactedDiagnostic: String?
    public let startedAtUTC: Date
    public let finishedAtUTC: Date?
    public let durationMilliseconds: Int?

    public init(
        id: String,
        provider: String,
        model: String,
        schemaVersion: Int,
        promptVersion: Int,
        normalizedInputHash: String,
        validationState: ModelRunValidationState,
        redactedDiagnostic: String? = nil,
        startedAtUTC: Date,
        finishedAtUTC: Date? = nil,
        durationMilliseconds: Int? = nil
    ) {
        self.id = id
        self.provider = provider
        self.model = model
        self.schemaVersion = schemaVersion
        self.promptVersion = promptVersion
        self.normalizedInputHash = normalizedInputHash
        self.validationState = validationState
        self.redactedDiagnostic = redactedDiagnostic
        self.startedAtUTC = startedAtUTC
        self.finishedAtUTC = finishedAtUTC
        self.durationMilliseconds = durationMilliseconds
    }
}
