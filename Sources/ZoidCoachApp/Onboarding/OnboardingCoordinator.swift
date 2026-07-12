import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
protocol OnboardingProgressPersisting: AnyObject {
    func load() throws -> OnboardingProgress
    func save(_ progress: OnboardingProgress) throws -> OnboardingProgress
}

extension OnboardingProgressStore: OnboardingProgressPersisting {}

enum OnboardingRoute: Equatable {
    case onboarding
    case today
}

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var progress: OnboardingProgress
    @Published private(set) var route: OnboardingRoute
    @Published private(set) var errorMessage: String?
    @Published private(set) var sourceHealth: [OnboardingStep: SourceHealth] = [:]
    @Published private(set) var inventory: [AppInventoryItem] = []
    @Published private(set) var inventoryMessage = "Applications have not been scanned yet."
    @Published var classifications: [String: AppClassificationChoice] = [:]
    @Published var workStartHour = 9
    @Published var workEndHour = 18
    @Published var quietStartHour = 22
    @Published var quietEndHour = 7
    @Published var gamingPolicy = OnboardingGamingPolicy.balanced
    @Published private(set) var deliveryResult: OnboardingDeliveryResult?
    @Published private(set) var isWorking = false

    private let store: any OnboardingProgressPersisting
    private let now: () -> Date
    private let dependencies: OnboardingDependencies?

    init(
        store: any OnboardingProgressPersisting,
        dependencies: OnboardingDependencies? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
        self.dependencies = dependencies
        do {
            let progress = try store.load()
            self.progress = progress
            route = progress.isFinished ? .today : .onboarding
            errorMessage = nil
        } catch {
            progress = try! OnboardingProgress()
            route = .onboarding
            errorMessage = "Setup progress could not be loaded. \(error.localizedDescription)"
        }
    }

    convenience init(runtimeEnvironment: RuntimeEnvironment = .current()) {
        self.init(
            store: OnboardingProgressStore(runtimeEnvironment: runtimeEnvironment),
            dependencies: .live(runtimeEnvironment: runtimeEnvironment)
        )
    }

    func continueFromCurrentStep() throws {
        var replacement = progress
        try replacement.completeCurrentStep(at: now())
        do {
            progress = try store.save(replacement)
            errorMessage = nil
            if progress.isFinished { route = .today }
        } catch {
            errorMessage = "Setup could not be saved. \(error.localizedDescription)"
            throw error
        }
    }

    func goBack() {
        guard let currentIndex = OnboardingProgress.stepSequence.firstIndex(
            of: progress.currentStep
        ), currentIndex > 0 else { return }
        do {
            var replacement = progress
            try replacement.navigate(to: OnboardingProgress.stepSequence[currentIndex - 1])
            progress = replacement
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exitToToday() {
        route = .today
    }

    func selectCoachingMode(_ mode: InitialCoachingMode) {
        do {
            var replacement = progress
            replacement.chooseCoachingMode(mode)
            progress = try store.save(replacement)
            errorMessage = nil
        } catch {
            errorMessage = "Coaching choice could not be saved. \(error.localizedDescription)"
        }
    }

    func deferAccess(for step: OnboardingStep) {
        recordAccess(.deferred, for: step)
    }

    func requestAccess(for step: OnboardingStep) async {
        guard let dependencies else { return }
        isWorking = true
        defer { isWorking = false }
        let health: SourceHealth
        switch step {
        case .reminders:
            health = await dependencies.requestReminders()
        case .screenwatch:
            health = await dependencies.inspectScreenwatch()
        case .notifications:
            health = await dependencies.requestNotifications()
        default:
            return
        }
        sourceHealth[step] = health
        recordAccess(Self.accessDecision(for: health), for: step)
    }

    func inspectCurrentSource() async {
        guard let dependencies else { return }
        let step = progress.currentStep
        guard [.reminders, .screenwatch, .notifications].contains(step) else { return }
        isWorking = true
        defer { isWorking = false }
        let health: SourceHealth
        switch step {
        case .reminders: health = await dependencies.inspectReminders()
        case .screenwatch: health = await dependencies.inspectScreenwatch()
        case .notifications: health = await dependencies.inspectNotifications()
        default: return
        }
        sourceHealth[step] = health
    }

    func loadApplicationInventory() {
        guard let dependencies else { return }
        let result = dependencies.loadInventory()
        inventory = result.items
        inventoryMessage = result.warning
            ?? "Found \(result.items.count.formatted()) applications. Nothing was classified automatically."
    }

    func setClassification(_ choice: AppClassificationChoice, for application: String) {
        classifications[application] = choice
    }

    func runDeliveryTest() async {
        guard let dependencies else { return }
        isWorking = true
        deliveryResult = await dependencies.testDelivery()
        isWorking = false
    }

    var canContinue: Bool {
        switch progress.currentStep {
        case .reminders:
            progress.remindersAccess != nil
        case .screenwatch:
            progress.screenwatchAccess != nil
        case .notifications:
            progress.notificationAccess != nil
        case .coachingMode:
            progress.coachingMode != nil
        case .deliveryTest:
            deliveryResult != nil || progress.notificationAccess != .granted
        default:
            true
        }
    }

    private func recordAccess(
        _ decision: OnboardingAccessDecision,
        for step: OnboardingStep
    ) {
        do {
            var replacement = progress
            try replacement.recordAccessDecision(decision, for: step)
            progress = try store.save(replacement)
            errorMessage = nil
        } catch {
            errorMessage = "The source decision could not be saved. \(error.localizedDescription)"
        }
    }

    private static func accessDecision(for health: SourceHealth) -> OnboardingAccessDecision {
        switch health.state {
        case .healthy: .granted
        case .attention: .denied
        case .unavailable: .unavailable
        case .checking, .notConnected: .deferred
        }
    }
}

enum OnboardingGamingPolicy: String, CaseIterable, Identifiable {
    case flexible
    case balanced
    case firm

    var id: String { rawValue }
}
