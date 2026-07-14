import Foundation
import ZoidCoachCore

struct PromptTaskBlockRequest: Identifiable {
    let episode: PromptEpisode
    let taskID: String
    let taskTitle: String

    var id: String { episode.id }

    init?(episode: PromptEpisode) {
        guard episode.actions.contains(where: { $0.kind == .markBlocked }),
              let taskID = episode.payload["taskID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !taskID.isEmpty
        else { return nil }
        self.episode = episode
        self.taskID = taskID
        taskTitle = episode.payload["taskTitle"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? episode.payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "the selected task"
    }
}

struct PromptTaskBlockReasonState: Equatable, Sendable {
    static let minimumLength = 3
    static let maximumLength = 240

    func validated(_ reason: String) -> Result<String, ValidationError> {
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= Self.minimumLength else { return .failure(.tooShort) }
        guard normalized.count <= Self.maximumLength else { return .failure(.tooLong) }
        return .success(normalized)
    }

    enum ValidationError: Error, Equatable {
        case tooShort
        case tooLong
        case alreadySubmitting

        var message: String {
            switch self {
            case .tooShort: "Explain the blocker in at least 3 characters."
            case .tooLong: "Keep the blocker to 240 characters or fewer."
            case .alreadySubmitting: "The blocker is already being saved."
            }
        }
    }
}

enum PromptTaskBlockReasonSuggestion: String, CaseIterable, Identifiable, Sendable {
    case approval
    case information
    case externalDependency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approval: "WAITING FOR APPROVAL"
        case .information: "WAITING FOR INFORMATION"
        case .externalDependency: "EXTERNAL DEPENDENCY"
        }
    }

    var reason: String {
        switch self {
        case .approval: "Waiting for approval."
        case .information: "Waiting for required information."
        case .externalDependency: "Waiting for an external dependency."
        }
    }
}

struct PromptTaskBlockFormState: Equatable, Sendable {
    var reason = ""
    private(set) var errorMessage: String?
    private(set) var isSubmitting = false

    mutating func select(_ suggestion: PromptTaskBlockReasonSuggestion) {
        guard !isSubmitting else { return }
        reason = suggestion.reason
        errorMessage = nil
    }

    mutating func beginSubmission() -> Result<String, PromptTaskBlockReasonState.ValidationError> {
        guard !isSubmitting else {
            errorMessage = PromptTaskBlockReasonState.ValidationError.alreadySubmitting.message
            return .failure(.alreadySubmitting)
        }
        let result = PromptTaskBlockReasonState().validated(reason)
        switch result {
        case .success:
            errorMessage = nil
            isSubmitting = true
        case let .failure(error):
            errorMessage = error.message
        }
        return result
    }

    mutating func finishSubmission(error: String? = nil) {
        isSubmitting = false
        errorMessage = error
    }

    mutating func showError(_ message: String) {
        isSubmitting = false
        errorMessage = message
    }

    mutating func cancel() {
        self = Self()
    }
}

struct PromptActionReachabilityLayout: Equatable, Sendable {
    let taskChangeActions: [PromptAction]
    let recoveryActions: [PromptAction]

    init(actions: [PromptAction]) {
        taskChangeActions = actions.filter(Self.isTaskChange)
        recoveryActions = actions.filter { !Self.isTaskChange($0) }
    }

    private static func isTaskChange(_ action: PromptAction) -> Bool {
        action.kind == .rescheduleTask || action.kind == .markBlocked
    }
}

enum PromptActionControlPresentation: Equatable, Sendable {
    case directButtonList
}

struct PromptActionPublicControl: Identifiable, Equatable, Sendable {
    let action: PromptAction
    let accessibilityIdentifier: String

    var id: String { accessibilityIdentifier }
}

struct PromptActionPublicInterface: Equatable, Sendable {
    let presentation: PromptActionControlPresentation = .directButtonList
    let taskChangeControls: [PromptActionPublicControl]
    let recoveryControls: [PromptActionPublicControl]

    var controls: [PromptActionPublicControl] { taskChangeControls + recoveryControls }

    init(promptID: String, actions: [PromptAction]) {
        let layout = PromptActionReachabilityLayout(actions: actions)
        taskChangeControls = Self.controls(for: layout.taskChangeActions, promptID: promptID)
        recoveryControls = Self.controls(for: layout.recoveryActions, promptID: promptID)
    }

    private static func controls(for actions: [PromptAction], promptID: String) -> [PromptActionPublicControl] {
        actions.map { action in
            PromptActionPublicControl(
                action: action,
                accessibilityIdentifier: "today.prompt.\(promptID).action.\(action.kind.rawValue)"
            )
        }
    }
}

enum PromptTaskBlockedHistoryState {
    static func reason(for episode: PromptEpisode, in plan: [DailyPlanEntry]) -> String? {
        guard let taskID = episode.payload["taskID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !taskID.isEmpty,
              let reason = plan.first(where: { $0.reminderID == taskID })?.blockedReason?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty
        else { return nil }
        return reason
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
