import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

enum DashboardPromptActionOutcome {
    static func successMessage(
        for episode: PromptEpisode,
        action: PromptActionKind,
        activeTaskID: String?
    ) -> String? {
        if episode.type == PromptNotificationCategory.gamingDrift.rawValue,
           action == .continueIntentionally {
            return "Intentional gaming recorded. Equivalent gaming prompts are paused for your configured override window. Returning to aligned work ends the pause early."
        }
        if episode.type == AmbiguousActivityPromptService.promptType {
            switch action {
            case .classifyAsSupportingWork:
                let taskTitle = episode.payload["taskTitle"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let taskTitle, !taskTitle.isEmpty {
                    return "The observed session is now counted as supporting work for \(taskTitle)."
                }
                return "The observed session is now counted as supporting work for the active task."
            case .classifyAsGaming:
                return "The observed session is now counted as gaming."
            case .keepActivityUnknown:
                return "The observed session remains unknown. Coaching was not changed."
            default:
                return nil
            }
        }
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
