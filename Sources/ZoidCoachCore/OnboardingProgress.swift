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

    public static let version1Sequence: [Self] = [
        .welcome,
        .localPrivacy,
        .reminders,
        .screenwatch,
        .notifications,
        .applicationInventory,
        .activityClassification,
        .schedule,
        .gamingPolicy,
        .coachingMode,
        .deliveryTest,
        .firstDailyPlan,
    ]
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

public struct OnboardingCompletedEffect: Codable, Equatable, Sendable {
    public let step: OnboardingStep
    public let requestID: String
    public let payloadDigest: String
    public let resourceVersion: Int

    public init(
        step: OnboardingStep,
        requestID: String,
        payloadDigest: String,
        resourceVersion: Int
    ) {
        self.step = step
        self.requestID = requestID
        self.payloadDigest = payloadDigest
        self.resourceVersion = resourceVersion
    }
}

public struct OnboardingProgress: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public static var stepSequence: [OnboardingStep] {
        OnboardingStep.version1Sequence
    }

    public private(set) var version: Int
    public private(set) var persistenceRevision: UInt64
    public private(set) var currentStep: OnboardingStep
    public private(set) var completedSteps: [OnboardingStep]
    public private(set) var coachingMode: InitialCoachingMode?
    public private(set) var remindersAccess: OnboardingAccessDecision?
    public private(set) var screenwatchAccess: OnboardingAccessDecision?
    public private(set) var notificationAccess: OnboardingAccessDecision?
    public private(set) var completedEffects: [OnboardingCompletedEffect]
    public private(set) var finishedAt: Date?

    public init(
        version: Int = Self.schemaVersion,
        persistenceRevision: UInt64 = 0,
        currentStep: OnboardingStep = .welcome,
        completedSteps: [OnboardingStep] = [],
        coachingMode: InitialCoachingMode? = nil,
        remindersAccess: OnboardingAccessDecision? = nil,
        screenwatchAccess: OnboardingAccessDecision? = nil,
        notificationAccess: OnboardingAccessDecision? = nil,
        completedEffects: [OnboardingCompletedEffect] = [],
        finishedAt: Date? = nil
    ) throws {
        self.version = version
        self.persistenceRevision = persistenceRevision
        self.currentStep = currentStep
        self.completedSteps = completedSteps
        self.coachingMode = coachingMode
        self.remindersAccess = remindersAccess
        self.screenwatchAccess = screenwatchAccess
        self.notificationAccess = notificationAccess
        self.completedEffects = completedEffects
        self.finishedAt = finishedAt
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case persistenceRevision
        case currentStep
        case completedSteps
        case coachingMode
        case remindersAccess
        case screenwatchAccess
        case notificationAccess
        case completedEffects
        case finishedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        persistenceRevision = try container.decodeIfPresent(
            UInt64.self,
            forKey: .persistenceRevision
        ) ?? 0
        currentStep = try container.decode(OnboardingStep.self, forKey: .currentStep)
        completedSteps = try container.decode([OnboardingStep].self, forKey: .completedSteps)
        coachingMode = try container.decodeIfPresent(InitialCoachingMode.self, forKey: .coachingMode)
        remindersAccess = try Self.decodeAccessDecision(
            from: container,
            key: .remindersAccess,
            step: .reminders,
            completedSteps: completedSteps
        )
        screenwatchAccess = try Self.decodeAccessDecision(
            from: container,
            key: .screenwatchAccess,
            step: .screenwatch,
            completedSteps: completedSteps
        )
        notificationAccess = try Self.decodeAccessDecision(
            from: container,
            key: .notificationAccess,
            step: .notifications,
            completedSteps: completedSteps
        )
        completedEffects = try container.decodeIfPresent(
            [OnboardingCompletedEffect].self,
            forKey: .completedEffects
        ) ?? []
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(persistenceRevision, forKey: .persistenceRevision)
        try container.encode(currentStep, forKey: .currentStep)
        try container.encode(completedSteps, forKey: .completedSteps)
        try container.encodeIfPresent(coachingMode, forKey: .coachingMode)
        try container.encodeIfPresent(remindersAccess, forKey: .remindersAccess)
        try container.encodeIfPresent(screenwatchAccess, forKey: .screenwatchAccess)
        try container.encodeIfPresent(notificationAccess, forKey: .notificationAccess)
        if !completedEffects.isEmpty {
            try container.encode(completedEffects, forKey: .completedEffects)
        }
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
    }

    public var isFinished: Bool {
        finishedAt != nil && completedSteps == Self.stepSequence
    }

    @_spi(OnboardingPersistence)
    public func withPersistenceRevision(_ revision: UInt64) throws -> Self {
        try Self(
            version: version,
            persistenceRevision: revision,
            currentStep: currentStep,
            completedSteps: completedSteps,
            coachingMode: coachingMode,
            remindersAccess: remindersAccess,
            screenwatchAccess: screenwatchAccess,
            notificationAccess: notificationAccess,
            completedEffects: completedEffects,
            finishedAt: finishedAt
        )
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

    public mutating func recordCompletedEffect(_ effect: OnboardingCompletedEffect) throws {
        guard effect.step == currentStep else {
            throw OnboardingProgressError.effectStepMismatch(
                expected: currentStep,
                actual: effect.step
            )
        }
        guard !effect.requestID.isEmpty,
              effect.payloadDigest.count == 64,
              effect.payloadDigest.allSatisfy({ $0.isHexDigit }),
              effect.resourceVersion > 0 else {
            throw OnboardingProgressError.invalidCompletedEffect(effect.step)
        }
        if let existing = completedEffects.first(where: { $0.step == effect.step }) {
            guard existing == effect else {
                throw OnboardingProgressError.conflictingCompletedEffect(effect.step)
            }
            return
        }
        completedEffects.append(effect)
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
            guard completedSteps == Self.stepSequence else {
                throw OnboardingProgressError.stepsIncomplete
            }
            finishedAt = date
            return
        }
        guard let index = Self.stepSequence.firstIndex(of: currentStep) else {
            throw OnboardingProgressError.invalidCurrentStep
        }
        currentStep = Self.stepSequence[index + 1]
    }

    public mutating func navigate(to step: OnboardingStep) throws {
        guard !isFinished else { throw OnboardingProgressError.alreadyFinished }
        guard let requested = Self.stepSequence.firstIndex(of: step) else {
            throw OnboardingProgressError.invalidCurrentStep
        }
        let furthest = completedSteps
            .compactMap(Self.stepSequence.firstIndex)
            .max()
            .map { min($0 + 1, Self.stepSequence.count - 1) }
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
        guard completedSteps == Array(Self.stepSequence.prefix(completedSteps.count)) else {
            throw OnboardingProgressError.completedStepsNotContiguous
        }
        guard let currentIndex = Self.stepSequence.firstIndex(of: currentStep),
              currentIndex <= min(completedSteps.count, Self.stepSequence.count - 1) else {
            throw OnboardingProgressError.invalidCurrentStep
        }
        if completedSteps.contains(.coachingMode), coachingMode == nil {
            throw OnboardingProgressError.coachingModeRequired
        }
        guard Set(completedEffects.map(\.step)).count == completedEffects.count else {
            throw OnboardingProgressError.duplicateCompletedEffect
        }
        for effect in completedEffects {
            guard !effect.requestID.isEmpty,
                  effect.payloadDigest.count == 64,
                  effect.payloadDigest.allSatisfy({ $0.isHexDigit }),
                  effect.resourceVersion > 0 else {
                throw OnboardingProgressError.invalidCompletedEffect(effect.step)
            }
            guard completedSteps.contains(effect.step) || effect.step == currentStep else {
                throw OnboardingProgressError.invalidCompletedEffect(effect.step)
            }
        }
        for step in [OnboardingStep.reminders, .screenwatch, .notifications]
        where completedSteps.contains(step) && accessDecision(for: step) == nil {
            throw OnboardingProgressError.accessDecisionRequired(step)
        }
        let allStepsCompleted = completedSteps == Self.stepSequence
        if (finishedAt != nil) != allStepsCompleted {
            throw OnboardingProgressError.stepsIncomplete
        }
        if finishedAt != nil, currentStep != .firstDailyPlan {
            throw OnboardingProgressError.invalidCurrentStep
        }
    }

    private static func stepOrder(_ lhs: OnboardingStep, _ rhs: OnboardingStep) -> Bool {
        guard let left = Self.stepSequence.firstIndex(of: lhs),
              let right = Self.stepSequence.firstIndex(of: rhs) else { return false }
        return left < right
    }

    private static func decodeAccessDecision(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        step: OnboardingStep,
        completedSteps: [OnboardingStep]
    ) throws -> OnboardingAccessDecision? {
        if let decision = try container.decodeIfPresent(OnboardingAccessDecision.self, forKey: key) {
            return decision
        }
        return completedSteps.contains(step) ? .deferred : nil
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
    case effectStepMismatch(expected: OnboardingStep, actual: OnboardingStep)
    case invalidCompletedEffect(OnboardingStep)
    case conflictingCompletedEffect(OnboardingStep)
    case duplicateCompletedEffect
    @available(*, deprecated, message: "Persistence errors are reported by OnboardingProgressStoreError")
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
        case let .effectStepMismatch(expected, actual):
            "Onboarding effect for \(actual.rawValue) cannot complete \(expected.rawValue)"
        case let .invalidCompletedEffect(step):
            "Onboarding effect receipt is invalid for \(step.rawValue)"
        case let .conflictingCompletedEffect(step):
            "Onboarding effect receipt conflicts for \(step.rawValue)"
        case .duplicateCompletedEffect:
            "Onboarding progress contains duplicate effect receipts"
        case let .unreadableProgress(message):
            "Onboarding progress could not be read: \(message)"
        }
    }
}
