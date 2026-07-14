import Foundation

struct ScreenwatchRepairActionPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case firstSelection
        case expiredAccess
        case accessDenied
        case unavailableFolder
        case unsafeFolder
        case connectedFolder
        case recheck
        case useDefaultLocation
    }

    let state: State
    let primaryTitle: String
    let accessibilityHint: String
    let explanation: String

    init(status: ScreenwatchSetupStatus?) {
        switch Self.state(for: status) {
        case .firstSelection:
            state = .firstSelection
            primaryTitle = "CHOOSE FOLDER"
            accessibilityHint = "Opens the folder picker to select the direct Screenwatch days folder."
            explanation = "Choose the direct days folder for the first connection. Zoid 666 validates local records without showing captured titles, URLs, screenshots, or record contents."
        case .expiredAccess:
            state = .expiredAccess
            primaryTitle = "REAUTHORIZE FOLDER"
            accessibilityHint = "Opens the folder picker to renew access to the previously chosen Screenwatch days folder."
            explanation = "Folder access expired. Choose the same direct days folder again to renew local access. Captured titles, URLs, screenshots, and record contents are never shown."
        case .accessDenied:
            state = .accessDenied
            primaryTitle = "REAUTHORIZE FOLDER"
            accessibilityHint = "Opens the folder picker to restore permission for the previously chosen Screenwatch days folder."
            explanation = "The chosen folder could not be accessed. Choose the same direct days folder again to restore permission, or choose another available folder. Captured titles, URLs, screenshots, and record contents are never shown."
        case .unavailableFolder:
            state = .unavailableFolder
            let needsReauthorization = status?.repair == .reauthorizeFolder
            primaryTitle = needsReauthorization ? "REAUTHORIZE FOLDER" : "CHOOSE AVAILABLE FOLDER"
            accessibilityHint = needsReauthorization
                ? "Opens the folder picker to replace or reauthorize the unavailable Screenwatch days folder."
                : "Opens the folder picker to replace the unavailable Screenwatch days folder."
            explanation = "The current folder is unavailable. Choose an available direct days folder to restore local access without showing captured titles, URLs, screenshots, or record contents."
        case .unsafeFolder:
            state = .unsafeFolder
            primaryTitle = status?.repair == .reauthorizeFolder
                ? "REAUTHORIZE FOLDER"
                : "CHOOSE SAFE FOLDER"
            accessibilityHint = "Opens the folder picker to select a direct, non-symbolic Screenwatch days folder."
            explanation = "The current path cannot be used safely. Choose a direct, non-symbolic days folder. Validation never shows captured titles, URLs, screenshots, or record contents."
        case .connectedFolder:
            state = .connectedFolder
            let isAlternate = status?.source == .alternateFolder
            primaryTitle = isAlternate ? "CHANGE FOLDER" : "CHOOSE FOLDER"
            accessibilityHint = isAlternate
                ? "Opens the folder picker to replace the connected Screenwatch days folder."
                : "Opens the folder picker to choose an alternate Screenwatch days folder."
            explanation = "Folder access is working. Choose another direct days folder only if Screenwatch moved. Validation never shows captured titles, URLs, screenshots, or record contents."
        case .recheck:
            state = .recheck
            primaryTitle = status?.source == .alternateFolder ? "CHANGE FOLDER" : "CHOOSE FOLDER"
            accessibilityHint = "Opens the folder picker to select a different Screenwatch days folder."
            explanation = "Recheck after Screenwatch records activity today, or choose a different direct days folder. Captured titles, URLs, screenshots, and record contents are never shown."
        case .useDefaultLocation:
            state = .useDefaultLocation
            primaryTitle = "CHANGE FOLDER"
            accessibilityHint = "Opens the folder picker to select a valid Screenwatch days folder."
            explanation = "Return Screenwatch to its expected location or choose its current direct days folder. Validation never shows captured titles, URLs, screenshots, or record contents."
        }
    }

    private static func state(for status: ScreenwatchSetupStatus?) -> State {
        guard let status else { return .firstSelection }

        if status.health == .bookmarkUnavailable {
            return .expiredAccess
        }
        if status.health == .accessUnavailable {
            return status.repair == .reauthorizeFolder ? .accessDenied : .unavailableFolder
        }
        if status.health == .unsafePath {
            return .unsafeFolder
        }
        if status.health == .missing, status.source == .alternateFolder {
            return .unavailableFolder
        }
        if status.repair == .none, status.health == .healthy {
            return .connectedFolder
        }

        switch status.repair {
        case .none, .chooseFolder:
            return .firstSelection
        case .reauthorizeFolder:
            return .accessDenied
        case .recheck:
            return .recheck
        case .useDefaultLocation:
            return .useDefaultLocation
        }
    }
}
