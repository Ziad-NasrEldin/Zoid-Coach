import Foundation
import Testing
@testable import ZoidCoachApp

@Test
func healthyDatabaseKeepsStorageBackedActionsAvailableWithoutRecoveryPrompt() {
    let presentation = LocalDatabaseAvailabilityPresentation(diagnostic: diagnostic(
        state: .healthy,
        schemaVersion: 49,
        expectedSchemaVersion: 49
    ))

    #expect(presentation.availability == .available)
    #expect(presentation.recoveryPath == .none)
    #expect(presentation.statusLabel == "ACTIONS AVAILABLE")
    #expect(presentation.unavailableActions.isEmpty)
    #expect(presentation.recoveryActionLabel == nil)
    #expect(presentation.recoveryGuidance == nil)
    #expect(!presentation.showsRecoveryAction)
}

@Test
func readableOutdatedSchemaExplainsReadOnlySafetyAndRestartRecovery() {
    let presentation = LocalDatabaseAvailabilityPresentation(diagnostic: diagnostic(
        state: .attention,
        schemaVersion: 48,
        expectedSchemaVersion: 49
    ))

    #expect(presentation.availability == .readOnly)
    #expect(presentation.recoveryPath == .restartToRetryUpgrade)
    #expect(presentation.statusLabel == "READ-ONLY SAFETY")
    #expect(presentation.title.contains("paused"))
    #expect(presentation.detail.contains("will not claim that a change was saved"))
    #expect(presentation.unavailableActions.count == 3)
    #expect(presentation.unavailableActions.contains { $0.contains("start, pause, switch, complete") })
    #expect(presentation.unavailableActions.contains { $0.contains("coaching responses") })
    #expect(presentation.unavailableActions.contains { $0.contains("confirm a review") })
    #expect(presentation.recoveryActionLabel == "RETRY AFTER RESTART")
    #expect(presentation.recoveryGuidance?.contains("Quit and reopen") == true)
    #expect(presentation.recoveryGuidance?.contains("left unchanged") == true)
    #expect(presentation.showsRecoveryAction)
}

@Test(arguments: [LocalDatabaseDiagnosticState.attention, .unavailable])
func unavailableStorageNamesBlockedActionsAndOffersANonDestructiveRetry(
    state: LocalDatabaseDiagnosticState
) {
    let presentation = LocalDatabaseAvailabilityPresentation(diagnostic: diagnostic(
        state: state,
        schemaVersion: nil,
        expectedSchemaVersion: 49
    ))

    #expect(presentation.availability == .unavailable)
    #expect(presentation.recoveryPath == .retryCheckThenRestart)
    #expect(presentation.statusLabel == "ACTIONS UNAVAILABLE")
    #expect(presentation.title.contains("temporarily unavailable"))
    #expect(presentation.unavailableActions.count == 3)
    #expect(presentation.recoveryActionLabel == "RETRY STORAGE CHECK")
    #expect(presentation.recoveryGuidance?.contains("quit and reopen") == true)
    #expect(presentation.recoveryGuidance?.contains("No database repair or deletion") == true)
    #expect(presentation.showsRecoveryAction)
}

@Test
func missingAndUnverifiedStorageUseHonestDistinctCopy() {
    let missing = LocalDatabaseAvailabilityPresentation(diagnostic: diagnostic(
        state: .unavailable,
        schemaVersion: nil,
        expectedSchemaVersion: 49
    ))
    let unverified = LocalDatabaseAvailabilityPresentation(diagnostic: diagnostic(
        state: .attention,
        schemaVersion: nil,
        expectedSchemaVersion: 49
    ))

    #expect(missing.detail.contains("not ready"))
    #expect(missing.detail.contains("safely load or record"))
    #expect(unverified.detail.contains("could not be verified"))
    #expect(unverified.detail.contains("safely read current state or record"))
    #expect(missing.detail != unverified.detail)
}

private func diagnostic(
    state: LocalDatabaseDiagnosticState,
    schemaVersion: Int?,
    expectedSchemaVersion: Int
) -> LocalDatabaseDiagnostic {
    LocalDatabaseDiagnostic(
        state: state,
        detail: "Fixture database state",
        fileName: "zoid.sqlite3",
        sizeBytes: 4_096,
        schemaVersion: schemaVersion,
        expectedSchemaVersion: expectedSchemaVersion,
        lastMigrationAt: nil
    )
}
