import Foundation
import ZoidCoachCore

enum DashboardPromptActionOutcome {
    static func successMessage(
        for episode: PromptEpisode,
        action: PromptActionKind,
        activeTaskID: String?
    ) -> String? {
        guard action == .startRecommendedTask,
              let requestedTaskID = episode.payload["taskID"],
              activeTaskID == requestedTaskID else { return nil }
        let title = episode.payload["taskTitle"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else {
            return "The recommended task is active in Today."
        }
        return "\(title) is active in Today."
    }
}
