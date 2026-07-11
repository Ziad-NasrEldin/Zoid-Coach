import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func remoteStructuredProviderRequiresExplicitAuthorizationWhileLoopbackDoesNot() throws {
    #expect(throws: StructuredGenerationError.remoteProcessingNotAuthorized) {
        _ = try HTTPStructuredGenerationProvider(
            providerID: "remote", modelID: "model",
            endpoint: URL(string: "https://models.example.test/generate")!,
            allowsRemoteProcessing: false
        )
    }
    _ = try HTTPStructuredGenerationProvider(
        providerID: "ollama", modelID: "local",
        endpoint: URL(string: "http://127.0.0.1:11434/generate")!,
        allowsRemoteProcessing: false
    )
}

@Test
func auditedStructuredProviderRecordsValidationAndEnforcesDailyBudget() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("structured-audit-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try ModelRunStore(databaseURL: databaseURL)
    let now = Date(timeIntervalSince1970: 1_752_153_600)
    let provider = AuditedStructuredGenerationProvider(
        provider: DeterministicStructuredGenerationProvider(output: Data(#"{"value":1}"#.utf8)),
        store: store,
        dailyRequestBudget: 1,
        now: { now }
    )
    let request = StructuredGenerationRequest(
        schemaName: "test", schemaVersion: 1, promptVersion: 1, prompt: "Return value",
        inputJSON: Data(#"{"input":1}"#.utf8), outputSchemaJSON: Data(#"{"type":"object"}"#.utf8)
    )

    #expect(try await provider.generate(request).json == Data(#"{"value":1}"#.utf8))
    await #expect(throws: StructuredGenerationError.requestBudgetExceeded) { try await provider.generate(request) }
    #expect(try store.requestCount(provider: "rules", since: now.addingTimeInterval(-1)) == 1)
}
