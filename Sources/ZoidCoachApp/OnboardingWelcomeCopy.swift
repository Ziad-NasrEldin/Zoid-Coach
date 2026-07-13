import Foundation

enum OnboardingWelcomeCopy {
    static let title = "A quieter way to begin the work that matters."

    static let body = "Zoid 666 is a coach, not a replacement task manager. Apple Reminders remains the system of record for your connected tasks. Zoid 666 connects that intent with what actually happens on this Mac so it can help you choose a realistic next action, notice drift, and recover without shame."

    static let note = "Keep creating, organizing, and editing connected tasks in Reminders. Use Today for your plan, source status, and unanswered coaching choices. Nothing is blocked or punished by default."

    static var accessibilitySummary: String {
        [title, body, note].joined(separator: " ")
    }
}
