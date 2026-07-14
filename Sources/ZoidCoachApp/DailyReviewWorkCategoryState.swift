import Foundation
import ZoidCoachCore

struct DailyReviewWorkCategory: Identifiable, Equatable, Sendable {
    let category: WorkCategory
    let minutes: Int

    var id: WorkCategory { category }
    var title: String { category.title }
    var explanation: String { category.explanation }
    var accessibilityIdentifier: String { "reviews.work-category.\(category.rawValue)" }
    var accessibilityLabel: String {
        "\(title), \(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}

struct DailyReviewWorkCategoryState: Equatable, Sendable {
    let categories: [DailyReviewWorkCategory]
    let workMinutes: Int
    let uncategorizedMinutes: Int

    init(sessions: [DailyReviewSession]) {
        let classifier = WorkCategoryClassifier()
        var minutes = Dictionary(uniqueKeysWithValues: WorkCategory.allCases.map { ($0, 0) })

        for session in sessions where session.classification == .work {
            let applications = session.applications
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let recognizedApplications = applications.compactMap { classifier.category(for: $0) }
            let recognizedCategories = Set(recognizedApplications)
            let category: WorkCategory = applications.isEmpty
                || recognizedApplications.count != applications.count
                || recognizedCategories.count != 1
                ? .uncategorized
                : recognizedCategories.first ?? .uncategorized
            minutes[category, default: 0] += session.durationMinutes
        }

        categories = WorkCategory.allCases.map {
            DailyReviewWorkCategory(category: $0, minutes: minutes[$0, default: 0])
        }
        workMinutes = categories.reduce(0) { $0 + $1.minutes }
        uncategorizedMinutes = minutes[.uncategorized, default: 0]
    }

    var hasWork: Bool { workMinutes > 0 }

    var detail: String {
        if !hasWork {
            return "No corrected work sessions were observed for this review day. No category was invented."
        }
        if uncategorizedMinutes == workMinutes {
            return "Work was observed, but the application evidence does not identify one safe category. No category was guessed."
        }
        if uncategorizedMinutes > 0 {
            return "\(uncategorizedMinutes) work minute\(uncategorizedMinutes == 1 ? " remains" : "s remain") Uncategorized because ambiguous application evidence is never guessed."
        }
        return "Corrected work sessions are grouped only when their application evidence identifies one safe category."
    }
}
