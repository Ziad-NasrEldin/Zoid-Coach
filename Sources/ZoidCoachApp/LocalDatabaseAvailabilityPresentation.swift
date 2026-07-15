import Foundation

enum LocalDatabaseActionAvailability: Equatable, Sendable {
    case available
    case readOnly
    case unavailable
}

enum LocalDatabaseRecoveryPath: Equatable, Sendable {
    case none
    case restartToRetryUpgrade
    case retryCheckThenRestart
}

struct LocalDatabaseAvailabilityPresentation: Equatable, Sendable {
    let availability: LocalDatabaseActionAvailability
    let recoveryPath: LocalDatabaseRecoveryPath
    let statusLabel: String
    let title: String
    let detail: String
    let unavailableActions: [String]
    let recoveryActionLabel: String?
    let recoveryGuidance: String?

    init(diagnostic: LocalDatabaseDiagnostic) {
        switch diagnostic.state {
        case .healthy:
            availability = .available
            recoveryPath = .none
            statusLabel = "ACTIONS AVAILABLE"
            title = "Planning, task, coaching, and review changes are available."
            detail = "The local database passed its integrity check on the current schema."
            unavailableActions = []
            recoveryActionLabel = nil
            recoveryGuidance = nil

        case .attention where diagnostic.schemaVersion != nil:
            availability = .readOnly
            recoveryPath = .restartToRetryUpgrade
            statusLabel = "READ-ONLY SAFETY"
            title = "Changes are paused while the local schema is out of date."
            detail = "This diagnostics screen can still inspect storage facts, but Zoid 666 will not claim that a change was saved until migration succeeds."
            unavailableActions = Self.mutationActions
            recoveryActionLabel = "RETRY AFTER RESTART"
            recoveryGuidance = "Quit and reopen Zoid 666 to retry the local migration, then return here and check again. The database is left unchanged if verification still fails."

        case .attention, .unavailable:
            availability = .unavailable
            recoveryPath = .retryCheckThenRestart
            statusLabel = "ACTIONS UNAVAILABLE"
            title = "Storage-backed actions are temporarily unavailable."
            detail = diagnostic.state == .unavailable
                ? "The local database is not ready, so Zoid 666 cannot safely load or record durable changes yet."
                : "The local database could not be verified, so Zoid 666 cannot safely read current state or record durable changes."
            unavailableActions = Self.mutationActions
            recoveryActionLabel = "RETRY STORAGE CHECK"
            recoveryGuidance = "Check again now. If storage is still unavailable, quit and reopen Zoid 666, then retry. No database repair or deletion is performed by this check."
        }
    }

    var showsRecoveryAction: Bool {
        recoveryPath != .none
    }

    private static let mutationActions = [
        "Plan, start, pause, switch, complete, or reschedule tasks",
        "Save settings, coaching responses, or gaming adjustments",
        "Correct, note, skip, or confirm a review"
    ]
}
