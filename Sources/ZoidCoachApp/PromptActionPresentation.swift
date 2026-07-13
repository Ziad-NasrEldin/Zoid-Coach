import Foundation

struct PromptActionPresentation: Equatable, Sendable {
    let isApplying: Bool
    let actionsDisabled: Bool
    let stateLabel: String
    let progressMessage: String?

    init(promptID: String, pendingPromptID: String?, replayed: Bool) {
        isApplying = pendingPromptID == promptID
        actionsDisabled = pendingPromptID != nil
        if isApplying {
            stateLabel = "APPLYING"
            progressMessage = "Saving this choice once, then refreshing every surface from the durable result."
        } else {
            stateLabel = replayed ? "RETURNED" : "WAITING"
            progressMessage = nil
        }
    }
}
