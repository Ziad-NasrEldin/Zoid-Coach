import ZoidCoachCore

enum PromptNotificationRelevance: String, Equatable, Sendable {
    case planning
    case meeting
    case wakeIntervention
    case onboarding
    case gamingDrift

    init(category: PromptNotificationCategory) {
        switch category {
        case .planReady, .planChanged:
            self = .planning
        case .meetingCandidate:
            self = .meeting
        case .wakeIntervention:
            self = .wakeIntervention
        case .onboardingTest:
            self = .onboarding
        case .gamingDrift:
            self = .gamingDrift
        }
    }

    func includes(_ category: PromptNotificationCategory) -> Bool {
        Self(category: category) == self
    }

    var categories: Set<PromptNotificationCategory> {
        Set(PromptNotificationCategory.allCases.filter(includes))
    }
}
