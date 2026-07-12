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
    @Published private(set) var screenwatchSetupStatus: ScreenwatchSetupStatus?
    @Published private(set) var inventory: [AppInventoryItem] = []
    @Published private(set) var inventoryMessage = "Applications have not been scanned yet."
    @Published var classifications: [String: AppClassificationChoice] = [:]
    @Published var workStartHour = 9
    @Published var workEndHour = 18
    @Published var quietStartHour = 22
    @Published var quietEndHour = 7
    @Published var gamingPolicy = OnboardingGamingPolicy.balanced
    @Published private(set) var deliveryResult: OnboardingDeliveryResult?
    @Published private(set) var testTaskCompleted = false
    @Published private(set) var firstDailyPlanResult: OnboardingFirstDailyPlanResult?
    @Published private(set) var isWorking = false

    private let store: any OnboardingProgressPersisting
    private let now: () -> Date
    private let dependencies: OnboardingDependencies?
    private var originalPolicy = UserPolicy.defaults()
    private var policyDraft = SettingsPolicyDraft(policy: .defaults())
    private var policyIsAvailable = true
    private var sourceRequestGeneration = UUID()
    private var deliveryGeneration = UUID()
    private var planGeneration = UUID()

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
        if let dependencies {
            do {
                let policy = try dependencies.loadPolicy()
                originalPolicy = policy
                policyDraft = SettingsPolicyDraft(policy: policy)
                workStartHour = policyDraft.workStart.hour
                workEndHour = policyDraft.workEnd.hour
                quietStartHour = policyDraft.quietStart.hour
                quietEndHour = policyDraft.quietEnd.hour
            } catch {
                policyIsAvailable = false
                errorMessage = "Existing settings could not be loaded. Setup choices will not be applied until local storage recovers. \(error.localizedDescription)"
            }
            if let gamingPolicy = try? dependencies.loadGamingPolicy() {
                self.gamingPolicy = OnboardingGamingPolicy(policy: gamingPolicy)
            }
        }
    }

    convenience init(runtimeEnvironment: RuntimeEnvironment = .current()) {
        self.init(
            store: OnboardingProgressStore(runtimeEnvironment: runtimeEnvironment),
            dependencies: .live(runtimeEnvironment: runtimeEnvironment)
        )
    }

    func continueFromCurrentStep() throws {
        try persistCurrentConfigurationIfNeeded()
        var replacement = progress
        try replacement.completeCurrentStep(at: now())
        do {
            progress = try store.save(replacement)
            errorMessage = nil
            if progress.isFinished { route = .today }
        } catch {
            if let current = try? store.load() {
                progress = current
                route = current.isFinished ? .today : .onboarding
                errorMessage = "Setup changed in another window. The latest saved step was restored. Try again."
            } else {
                errorMessage = "Setup could not be saved. \(error.localizedDescription)"
            }
            throw error
        }
    }

    func exitToToday() {
        guard !isWorking else { return }
        route = .today
    }

    func selectCoachingMode(_ mode: InitialCoachingMode) {
        do {
            var replacement = progress
            replacement.chooseCoachingMode(mode)
            progress = try store.save(replacement)
            policyDraft.aiProvider = mode == .rulesOnly ? .disabled : .codexCLI
            try persistPolicy()
            errorMessage = nil
        } catch {
            errorMessage = "Coaching choice could not be saved. \(error.localizedDescription)"
        }
    }

    func deferAccess(for step: OnboardingStep) {
        sourceRequestGeneration = UUID()
        recordAccess(.deferred, for: step)
    }

    func requestAccess(for step: OnboardingStep) async {
        guard let dependencies, !isWorking else { return }
        let generation = UUID()
        sourceRequestGeneration = generation
        isWorking = true
        defer { isWorking = false }
        let result: OnboardingAccessRequestResult
        switch step {
        case .reminders:
            result = await dependencies.requestReminders()
        case .screenwatch:
            let status = await dependencies.inspectScreenwatchSetup()
            screenwatchSetupStatus = status
            let health = Self.sourceHealth(for: status)
            result = .init(
                health: health,
                decision: status.health == .healthy ? .granted : .unavailable
            )
        case .notifications:
            result = await dependencies.requestNotifications()
        default:
            return
        }
        guard sourceRequestGeneration == generation else { return }
        sourceHealth[step] = result.health
        recordAccess(result.decision, for: step)
    }

    func inspectCurrentSource() async {
        guard let dependencies, !isWorking else { return }
        let step = progress.currentStep
        guard [.reminders, .screenwatch, .notifications].contains(step) else { return }
        isWorking = true
        defer { isWorking = false }
        let generation = UUID()
        sourceRequestGeneration = generation
        let health: SourceHealth
        switch step {
        case .reminders: health = await dependencies.inspectReminders()
        case .screenwatch:
            let status = await dependencies.inspectScreenwatchSetup()
            screenwatchSetupStatus = status
            health = Self.sourceHealth(for: status)
        case .notifications: health = await dependencies.inspectNotifications()
        default: return
        }
        guard sourceRequestGeneration == generation else { return }
        sourceHealth[step] = health
        if health.state == .healthy, accessDecision(for: step) != nil {
            recordAccess(.granted, for: step)
        }
    }

    func selectScreenwatchDirectory(_ url: URL) async {
        guard let dependencies, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let status = try await dependencies.selectScreenwatchDirectory(url)
            screenwatchSetupStatus = status
            let health = Self.sourceHealth(for: status)
            sourceHealth[.screenwatch] = health
            recordAccess(status.health == .healthy ? .granted : .unavailable, for: .screenwatch)
        } catch {
            errorMessage = "The Screenwatch folder could not be used. \(error.localizedDescription)"
        }
    }

    func useDefaultScreenwatchDirectory() async {
        guard let dependencies, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let status = await dependencies.useDefaultScreenwatchDirectory()
        screenwatchSetupStatus = status
        sourceHealth[.screenwatch] = Self.sourceHealth(for: status)
    }

    func openSystemSettings(for step: OnboardingStep) {
        guard dependencies?.openSystemSettings(step) == true else {
            errorMessage = "System Settings could not be opened. Open Privacy & Security manually and repair \(step.rawValue) access."
            return
        }
        errorMessage = nil
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
        policyDraft.setClassification(choice, for: application)
    }

    func runDeliveryTest() async {
        guard let dependencies, !isWorking else { return }
        let generation = UUID()
        deliveryGeneration = generation
        isWorking = true
        let result = await dependencies.testDelivery()
        guard deliveryGeneration == generation else {
            isWorking = false
            return
        }
        deliveryResult = result
        isWorking = false
    }

    func completeTestTask() {
        guard !isWorking else { return }
        testTaskCompleted = true
    }

    func prepareFirstDailyPlan() async {
        guard let dependencies, !isWorking else { return }
        let generation = UUID()
        planGeneration = generation
        isWorking = true
        let result = await dependencies.prepareFirstDailyPlan()
        guard planGeneration == generation else {
            isWorking = false
            return
        }
        firstDailyPlanResult = result
        if result.state != .prepared || result.items.isEmpty {
            errorMessage = result.message
        } else {
            errorMessage = nil
        }
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
            testTaskCompleted
                && (progress.notificationAccess != .granted
                    || [.delivered, .scheduled].contains(deliveryResult?.state))
        case .firstDailyPlan:
            firstDailyPlanResult?.state == .prepared
                && firstDailyPlanResult?.items.isEmpty == false
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

    private func accessDecision(for step: OnboardingStep) -> OnboardingAccessDecision? {
        switch step {
        case .reminders: progress.remindersAccess
        case .screenwatch: progress.screenwatchAccess
        case .notifications: progress.notificationAccess
        default: nil
        }
    }

    private static func sourceHealth(for status: ScreenwatchSetupStatus) -> SourceHealth {
        let state: HealthState
        switch status.health {
        case .healthy: state = .healthy
        case .stale, .malformed: state = .attention
        case .missing, .bookmarkUnavailable, .accessUnavailable, .unsafePath: state = .unavailable
        }
        return SourceHealth(
            id: .screenwatch,
            title: "Screenwatch",
            eyebrow: "Behavior",
            state: state,
            detail: status.summary,
            evidence: status.evidence,
            actionTitle: status.repair.rawValue
        )
    }

    private func persistCurrentConfigurationIfNeeded() throws {
        switch progress.currentStep {
        case .activityClassification:
            try persistPolicy()
        case .schedule:
            policyDraft.workStart = LocalTime(hour: workStartHour, minute: 0)
            policyDraft.workEnd = LocalTime(hour: workEndHour, minute: 0)
            policyDraft.quietStart = LocalTime(hour: quietStartHour, minute: 0)
            policyDraft.quietEnd = LocalTime(hour: quietEndHour, minute: 0)
            try persistPolicy()
        case .gamingPolicy:
            guard let dependencies else { return }
            do {
                try dependencies.saveGamingPolicy(gamingPolicy.policy)
                errorMessage = nil
            } catch {
                errorMessage = "The gaming boundary could not be saved. \(error.localizedDescription)"
                throw error
            }
        case .firstDailyPlan:
            guard firstDailyPlanResult?.state == .prepared,
                  firstDailyPlanResult?.items.isEmpty == false else {
                throw OnboardingDependencyError.firstDailyPlanUnavailable
            }
        default:
            break
        }
    }

    private func persistPolicy() throws {
        guard let dependencies else { return }
        guard policyIsAvailable else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let policy = policyDraft.policy(preserving: originalPolicy)
        do {
            try dependencies.savePolicy(policy)
            originalPolicy = policy
            errorMessage = nil
        } catch {
            errorMessage = "This setup choice could not be applied. \(error.localizedDescription)"
            throw error
        }
    }
}

enum OnboardingGamingPolicy: String, CaseIterable, Identifiable {
    case flexible
    case balanced
    case firm

    var id: String { rawValue }

    init(policy: GamingPolicy) {
        if policy.dailyBudgetMinutes >= 90 {
            self = .flexible
        } else if policy.dailyBudgetMinutes <= 30 {
            self = .firm
        } else {
            self = .balanced
        }
    }

    var policy: GamingPolicy {
        switch self {
        case .flexible:
            GamingPolicy(dailyBudgetMinutes: 90, priorityTaskRewardMinutes: 0)
        case .balanced:
            GamingPolicy(dailyBudgetMinutes: 60, priorityTaskRewardMinutes: 15)
        case .firm:
            GamingPolicy(dailyBudgetMinutes: 30, priorityTaskRewardMinutes: 30)
        }
    }
}
