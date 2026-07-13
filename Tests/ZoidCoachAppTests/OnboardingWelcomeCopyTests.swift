import Testing
@testable import ZoidCoachApp

@Test
func welcomeExplicitlyPositionsZoidAsCoachAndRemindersAsSystemOfRecord() {
    #expect(OnboardingWelcomeCopy.body.contains("Zoid 666 is a coach, not a replacement task manager"))
    #expect(OnboardingWelcomeCopy.body.contains("Apple Reminders remains the system of record"))
    #expect(OnboardingWelcomeCopy.note.contains("Keep creating, organizing, and editing connected tasks in Reminders"))
}

@Test
func welcomeAccessibilitySummaryRetainsPositioningAndDefaultSafetyBoundary() {
    let summary = OnboardingWelcomeCopy.accessibilitySummary

    #expect(summary.contains(OnboardingWelcomeCopy.title))
    #expect(summary.contains("coach, not a replacement task manager"))
    #expect(summary.contains("system of record"))
    #expect(summary.contains("Nothing is blocked or punished by default"))
}
