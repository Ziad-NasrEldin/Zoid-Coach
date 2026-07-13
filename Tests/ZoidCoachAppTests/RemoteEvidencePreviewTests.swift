import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore

@Test
func remoteEvidencePreviewMakesLocalOnlyAndRedactedBoundariesExplicit() {
    let local = RemoteEvidencePreview.representative(for: .localOnly)
    #expect(local.heading == "NO REMOTE PAYLOAD")
    #expect(local.payload == "Nothing is sent.")
    #expect(local.excluded.contains("Screenshots"))

    let redacted = RemoteEvidencePreview.representative(for: .redactedMetadataOnly)
    #expect(redacted.payload.contains("\"id\": \"task-1\""))
    #expect(redacted.payload.contains("\"title\": \"Task 1\""))
    #expect(redacted.payload.contains("\"application\": \"Application 1\""))
    #expect(redacted.payload.contains("reminderPriority"))
    #expect(redacted.payload.contains("recentAlignedMinutes"))
    #expect(redacted.payload.contains("Prepare client proposal") == false)
    #expect(redacted.excluded.contains("Task titles"))
    #expect(redacted.excluded.contains("Application names"))
    #expect(redacted.excluded.contains("Extracted conversation text"))
}

@Test
func privateContentPreviewStillExcludesRawAndSecretEvidence() {
    let preview = RemoteEvidencePreview.representative(for: .explicitPrivateContent)
    #expect(preview.payload.contains("\"title\": \"Prepare client proposal\""))
    #expect(preview.payload.contains("\"application\": \"Writing app\""))
    #expect(preview.excluded.contains("Screenshots"))
    #expect(preview.excluded.contains("URLs"))
    #expect(preview.excluded.contains("Internal task identifiers"))
    #expect(preview.excluded.contains("Credentials"))
}
