import Foundation

public enum OnboardingStep: String, CaseIterable, Codable, Sendable {
    case welcome
    case localPrivacy
    case reminders
    case screenwatch
    case notifications
    case applicationInventory
    case activityClassification
    case schedule
    case gamingPolicy
    case coachingMode
    case deliveryTest
    case firstDailyPlan
}

public enum InitialCoachingMode: String, Codable, Sendable {
    case rulesOnly
    case optionalAI
}

public enum OnboardingAccessDecision: String, Codable, Sendable {
    case granted
    case denied
    case unavailable
    case deferred
}

public struct OnboardingProgress: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public private(set) var version: Int
    public private(set) var currentStep: OnboardingStep
    public private(set) var completedSteps: [OnboardingStep]
    public private(set) var coachingMode: InitialCoachingMode?
    public private(set) var remindersAccess: OnboardingAccessDecision?
    public private(set) var screenwatchAccess: OnboardingAccessDecision?
    public private(set) var notificationAccess: OnboardingAccessDecision?
    public private(set) var finishedAt: Date?

    public init(
        version: Int = Self.schemaVersion,
        currentStep: OnboardingStep = .welcome,
        completedSteps: [OnboardingStep] = [],
        coachingMode: InitialCoachingMode? = nil,
        remindersAccess: OnboardingAccessDecision? = nil,
        screenwatchAccess: OnboardingAccessDecision? = nil,
        notificationAccess: OnboardingAccessDecision? = nil,
        finishedAt: Date? = nil
    ) throws {
        self.version = version
        self.currentStep = currentStep
        self.completedSteps = completedSteps
        self.coachingMode = coachingMode
        self.remindersAccess = remindersAccess
        self.screenwatchAccess = screenwatchAccess
        self.notificationAccess = notificationAccess
        self.finishedAt = finishedAt
        try validate()
    }

    public var isFinished: Bool {
        finishedAt != nil && Set(completedSteps) == Set(OnboardingStep.allCases)
    }

    public mutating func chooseCoachingMode(_ mode: InitialCoachingMode) {
        coachingMode = mode
    }

    public mutating func recordAccessDecision(
        _ decision: OnboardingAccessDecision,
        for step: OnboardingStep
    ) throws {
        switch step {
        case .reminders:
            remindersAccess = decision
        case .screenwatch:
            screenwatchAccess = decision
        case .notifications:
            notificationAccess = decision
        default:
            throw OnboardingProgressError.accessDecisionNotSupported(step)
        }
    }

    public mutating func completeCurrentStep(at date: Date) throws {
        guard !isFinished else { throw OnboardingProgressError.alreadyFinished }
        if currentStep == .coachingMode, coachingMode == nil {
            throw OnboardingProgressError.coachingModeRequired
        }
        if [.reminders, .screenwatch, .notifications].contains(currentStep),
           accessDecision(for: currentStep) == nil {
            throw OnboardingProgressError.accessDecisionRequired(currentStep)
        }
        if !completedSteps.contains(currentStep) {
            completedSteps.append(currentStep)
            completedSteps.sort(by: Self.stepOrder)
        }
        if currentStep == .firstDailyPlan {
            guard Set(completedSteps) == Set(OnboardingStep.allCases) else {
                throw OnboardingProgressError.stepsIncomplete
            }
            finishedAt = date
            return
        }
        guard let index = OnboardingStep.allCases.firstIndex(of: currentStep) else {
            throw OnboardingProgressError.invalidCurrentStep
        }
        currentStep = OnboardingStep.allCases[index + 1]
    }

    public mutating func navigate(to step: OnboardingStep) throws {
        guard !isFinished else { throw OnboardingProgressError.alreadyFinished }
        guard let requested = OnboardingStep.allCases.firstIndex(of: step) else {
            throw OnboardingProgressError.invalidCurrentStep
        }
        let furthest = completedSteps
            .compactMap(OnboardingStep.allCases.firstIndex)
            .max()
            .map { min($0 + 1, OnboardingStep.allCases.count - 1) }
            ?? 0
        guard requested <= furthest else {
            throw OnboardingProgressError.stepNotReachable(step)
        }
        currentStep = step
    }

    public func validate() throws {
        guard version == Self.schemaVersion else {
            throw OnboardingProgressError.unsupportedVersion(version)
        }
        guard Set(completedSteps).count == completedSteps.count else {
            throw OnboardingProgressError.duplicateCompletedStep
        }
        guard completedSteps == completedSteps.sorted(by: Self.stepOrder) else {
            throw OnboardingProgressError.completedStepsOutOfOrder
        }
        guard completedSteps == Array(OnboardingStep.allCases.prefix(completedSteps.count)) else {
            throw OnboardingProgressError.completedStepsNotContiguous
        }
        guard let currentIndex = OnboardingStep.allCases.firstIndex(of: currentStep),
              currentIndex <= min(completedSteps.count, OnboardingStep.allCases.count - 1) else {
            throw OnboardingProgressError.invalidCurrentStep
        }
        if completedSteps.contains(.coachingMode), coachingMode == nil {
            throw OnboardingProgressError.coachingModeRequired
        }
        for step in [OnboardingStep.reminders, .screenwatch, .notifications]
        where completedSteps.contains(step) && accessDecision(for: step) == nil {
            throw OnboardingProgressError.accessDecisionRequired(step)
        }
        let allStepsCompleted = Set(completedSteps) == Set(OnboardingStep.allCases)
        if (finishedAt != nil) != allStepsCompleted {
            throw OnboardingProgressError.stepsIncomplete
        }
        if finishedAt != nil, currentStep != .firstDailyPlan {
            throw OnboardingProgressError.invalidCurrentStep
        }
    }

    private static func stepOrder(_ lhs: OnboardingStep, _ rhs: OnboardingStep) -> Bool {
        guard let left = OnboardingStep.allCases.firstIndex(of: lhs),
              let right = OnboardingStep.allCases.firstIndex(of: rhs) else { return false }
        return left < right
    }

    private func accessDecision(for step: OnboardingStep) -> OnboardingAccessDecision? {
        switch step {
        case .reminders:
            remindersAccess
        case .screenwatch:
            screenwatchAccess
        case .notifications:
            notificationAccess
        default:
            nil
        }
    }
}

public final class OnboardingProgressStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        runtimeEnvironment: RuntimeEnvironment = .current(),
        fileManager: FileManager = .default
    ) {
        fileURL = runtimeEnvironment.applicationSupportRoot
            .appendingPathComponent("Zoid Coach/onboarding-progress.json", isDirectory: false)
        self.fileManager = fileManager
    }

    public func load() throws -> OnboardingProgress {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return try OnboardingProgress()
        }
        do {
            let progress = try JSONDecoder().decode(
                OnboardingProgress.self,
                from: Data(contentsOf: fileURL)
            )
            try progress.validate()
            return progress
        } catch let error as OnboardingProgressError {
            throw error
        } catch {
            throw OnboardingProgressError.unreadableProgress(error.localizedDescription)
        }
    }

    public func save(_ progress: OnboardingProgress) throws {
        try progress.validate()
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(progress).write(to: fileURL, options: .atomic)
    }

    public func reset() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

public enum OnboardingProgressError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case duplicateCompletedStep
    case completedStepsOutOfOrder
    case completedStepsNotContiguous
    case invalidCurrentStep
    case stepNotReachable(OnboardingStep)
    case coachingModeRequired
    case accessDecisionRequired(OnboardingStep)
    case accessDecisionNotSupported(OnboardingStep)
    case stepsIncomplete
    case alreadyFinished
    case unreadableProgress(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Unsupported onboarding progress version: \(version)"
        case .duplicateCompletedStep:
            "Onboarding progress contains a completed step more than once"
        case .completedStepsOutOfOrder:
            "Onboarding progress steps are out of order"
        case .completedStepsNotContiguous:
            "Onboarding progress cannot skip required steps"
        case .invalidCurrentStep:
            "Onboarding progress has an invalid current step"
        case let .stepNotReachable(step):
            "Onboarding step is not reachable yet: \(step.rawValue)"
        case .coachingModeRequired:
            "Choose rules-only coaching or optional AI before continuing"
        case let .accessDecisionRequired(step):
            "Record the access outcome before completing onboarding step: \(step.rawValue)"
        case let .accessDecisionNotSupported(step):
            "Onboarding step does not accept an access decision: \(step.rawValue)"
        case .stepsIncomplete:
            "Onboarding cannot finish before every required step is complete"
        case .alreadyFinished:
            "Onboarding is already complete"
        case let .unreadableProgress(message):
            "Onboarding progress could not be read: \(message)"
        }
    }
}
