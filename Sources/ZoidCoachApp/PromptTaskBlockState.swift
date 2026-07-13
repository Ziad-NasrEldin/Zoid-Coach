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

        var message: String {
            switch self {
            case .tooShort: "Explain the blocker in at least 3 characters."
            case .tooLong: "Keep the blocker to 240 characters or fewer."
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
