import SwiftUI
import ZoidCoachCore

struct PromptKeyboardShortcut: Equatable, Sendable {
    let key: Character

    var keyEquivalent: KeyEquivalent { KeyEquivalent(key) }
    var eventModifiers: EventModifiers { [.command, .option] }
    var displayLabel: String { "⌥⌘\(String(key).uppercased())" }
    var accessibilityHint: String {
        "Keyboard shortcut Option Command \(String(key).uppercased())."
    }

    static func action(for kind: PromptActionKind) -> PromptKeyboardShortcut? {
        let key: Character
        switch kind {
        case .startRecommendedTask: key = "t"
        case .startShortSprint: key = "s"
        case .startWorkSprint: key = "w"
        case .returnToActiveTask: key = "r"
        case .fiveMoreMinutes: key = "f"
        case .startBreak: key = "b"
        case .continueIntentionally: key = "i"
        case .pauseTask: key = "p"
        case .classifyAsSupportingWork: key = "u"
        case .classifyAsGaming: key = "g"
        case .keepActivityUnknown: key = "n"
        case .rescheduleTask: key = "e"
        case .markBlocked: key = "k"
        case .endWorkday: key = "q"
        case .ignore: key = "x"
        case .acceptPlan, .reviewPlan, .snoozePlanning, .dismissPlanning,
             .workUnplanned, .undoPlanChange, .addMeeting, .editMeeting:
            return nil
        }
        return PromptKeyboardShortcut(key: key)
    }

    static func action(for action: PromptAction) -> PromptKeyboardShortcut? {
        self.action(for: action.kind)
    }

    static let dismiss = PromptKeyboardShortcut(key: "d")

    static func isAvailable(
        promptID: String,
        keyboardPromptID: String?,
        actionsDisabled: Bool
    ) -> Bool {
        !actionsDisabled && promptID == keyboardPromptID
    }
}

extension View {
    @ViewBuilder
    func coachingKeyboardShortcut(_ shortcut: PromptKeyboardShortcut?) -> some View {
        if let shortcut {
            keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
        } else {
            self
        }
    }
}
