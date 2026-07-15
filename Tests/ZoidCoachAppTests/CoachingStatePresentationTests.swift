import Testing
@testable import ZoidCoachApp

@Suite("Today coaching status presentation")
struct CoachingStatePresentationTests {
    @Test("accountability coaching is active without a recovery instruction")
    func activeCoaching() {
        let presentation = CoachingStatePresentation(state: .accountability)

        #expect(presentation.statusLabel == "COACHING ACTIVE")
        #expect(presentation.explanation.contains("prompts and suggestions"))
        #expect(presentation.explanation.contains("activity observation continue"))
        #expect(presentation.pauseReason == nil)
        #expect(presentation.recoveryHint == nil)
        #expect(!presentation.accessibilityLabel.contains("PAUSED"))
    }

    @Test("observation week is limited without claiming observation stopped")
    func observationOnly() {
        let presentation = CoachingStatePresentation(state: .observation)

        #expect(presentation.statusLabel == "OBSERVATION ONLY")
        #expect(presentation.explanation.contains("without behavior coaching prompts"))
        #expect(presentation.explanation.contains("activity observation continue"))
        #expect(presentation.pauseReason == nil)
        #expect(presentation.recoveryHint == nil)
        #expect(!presentation.accessibilityLabel.contains("COACHING ACTIVE"))
        #expect(!presentation.accessibilityLabel.contains("COACHING PAUSED"))
    }

    @Test("paused coaching names the boundary and only actionable recovery")
    func pausedCoaching() {
        let presentation = CoachingStatePresentation(state: .paused)

        #expect(presentation.statusLabel == "COACHING PAUSED")
        #expect(presentation.explanation.contains("coaching prompts and automated coaching actions are paused"))
        #expect(presentation.explanation.contains("Task tracking and activity observation continue"))
        #expect(presentation.pauseReason == nil)
        #expect(presentation.recoveryHint == "Resume coaching in Settings when you want coaching prompts again.")
        #expect(!presentation.accessibilityLabel.contains("COACHING ACTIVE"))
    }

    @Test("every current state has complete privacy-safe accessible copy")
    func completeAccessibleCopy() {
        let presentations = [
            CoachingStatePresentation(state: .observation),
            CoachingStatePresentation(state: .accountability),
            CoachingStatePresentation(state: .paused)
        ]

        #expect(presentations.count == 3)
        for presentation in presentations {
            #expect(!presentation.statusLabel.isEmpty)
            #expect(!presentation.explanation.isEmpty)
            #expect(presentation.accessibilityLabel.contains(presentation.statusLabel))
            #expect(presentation.accessibilityLabel.contains(presentation.explanation))
            #expect(!presentation.accessibilityLabel.contains(".."))
            #expect(!presentation.accessibilityLabel.localizedCaseInsensitiveContains("private-window-title"))
            #expect(!presentation.accessibilityLabel.localizedCaseInsensitiveContains("secret"))
            #expect(!presentation.accessibilityLabel.localizedCaseInsensitiveContains("screenshot"))
        }
    }
}
