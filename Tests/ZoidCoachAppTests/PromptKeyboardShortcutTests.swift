import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test("return-to-task coaching exposes one discoverable direct shortcut")
func returnToTaskShortcut() throws {
    let shortcut = try #require(PromptKeyboardShortcut.action(for: .returnToActiveTask))

    #expect(shortcut.key == "r")
    #expect(shortcut.displayLabel == "⌥⌘R")
    #expect(shortcut.accessibilityHint == "Keyboard shortcut Option Command R.")
}

@Test("every gaming coaching action and dismissal has a unique mnemonic")
func coachingShortcutsAreCompleteAndUnique() throws {
    let expected: [PromptActionKind: Character] = [
        .startRecommendedTask: "t",
        .startShortSprint: "s",
        .startWorkSprint: "w",
        .returnToActiveTask: "r",
        .fiveMoreMinutes: "f",
        .startBreak: "b",
        .continueIntentionally: "i",
        .pauseTask: "p",
        .classifyAsSupportingWork: "u",
        .classifyAsGaming: "g",
        .keepActivityUnknown: "n",
        .rescheduleTask: "e",
        .markBlocked: "k",
        .endWorkday: "q",
        .ignore: "x",
    ]

    for (kind, key) in expected {
        #expect(PromptKeyboardShortcut.action(for: kind)?.key == key)
    }
    #expect(Set(expected.values).count == expected.count)
    #expect(PromptKeyboardShortcut.dismiss.key == "d")
    #expect(!expected.values.contains(PromptKeyboardShortcut.dismiss.key))
    #expect(PromptKeyboardShortcut.action(for: .acceptPlan) == nil)
}

@Test("destructive coaching shortcuts retain confirmation on the original action")
func destructiveShortcutRetainsConfirmation() throws {
    let action = PromptAction(
        kind: .markBlocked,
        title: "Mark blocked",
        role: .destructive,
        requiresConfirmation: true
    )
    let shortcut = try #require(PromptKeyboardShortcut.action(for: action))

    #expect(shortcut.key == "k")
    #expect(action.requiresConfirmation)
    #expect(action.role == .destructive)
}

@Test("shortcuts target only the first actionable prompt and stop while an action is pending")
func shortcutAvailabilityIsUnambiguous() {
    #expect(PromptKeyboardShortcut.isAvailable(
        promptID: "first",
        keyboardPromptID: "first",
        actionsDisabled: false
    ))
    #expect(!PromptKeyboardShortcut.isAvailable(
        promptID: "second",
        keyboardPromptID: "first",
        actionsDisabled: false
    ))
    #expect(!PromptKeyboardShortcut.isAvailable(
        promptID: "first",
        keyboardPromptID: "first",
        actionsDisabled: true
    ))
    #expect(!PromptKeyboardShortcut.isAvailable(
        promptID: "first",
        keyboardPromptID: nil,
        actionsDisabled: false
    ))
}
