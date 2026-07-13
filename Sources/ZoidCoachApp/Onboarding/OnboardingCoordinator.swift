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

enum OnboardingReminderListDiscovery: Equatable {
    case idle
    case loading
    case available([ReminderListChoice])
    case empty
    case permissionRequired(String)
    case failed(String)
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
    @Published var workStartMinute = 0
    @Published var workEndHour = 18
    @Published var workEndMinute = 0
    @Published var selectedWorkWeekdays: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday]
    @Published var quietStartHour = 22
    @Published var quietStartMinute = 0
    @Published var quietEndHour = 7
    @Published var quietEndMinute = 0
    @Published var gamingPolicy = OnboardingGamingPolicy.balanced
    @Published var screenshotAnalysisEnabled = false
    @Published private(set) var deliveryResult: OnboardingDeliveryResult?
    @Published private(set) var testPrompt: PromptEpisode?
    @Published private(set) var testPromptMessage: String?
    @Published private(set) var testTaskCompleted = false
    @Published private(set) var firstDailyPlanResult: OnboardingFirstDailyPlanResult?
    @Published private(set) var reminderListDiscovery: OnboardingReminderListDiscovery = .idle
    @Published private(set) var isWorking = false

    private let store: any OnboardingProgressPersisting
    private let now: () -> Date
    private let dependencies: OnboardingDependencies?
    private var originalPolicy = UserPolicy.defaults()
    private var policyDraft = SettingsPolicyDraft(policy: .defaults())
    private var activePolicyVersion = 0
    private var policyIsAvailable = true
    private var sourceRequestGeneration = UUID()
    private var deliveryGeneration = UUID()
    private var planGeneration = UUID()
    private var reminderListGeneration = UUID()

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
            testTaskCompleted = progress.deliveryTestTaskCompleted
            route = progress.isFinished ? .today : .onboarding
            errorMessage = nil
        } catch {
            progress = try! OnboardingProgress()
            route = .onboarding
            errorMessage = "Setup progress could not be loaded. \(error.localizedDescription)"
        }
        if let dependencies {
            do {
                let versioned = try dependencies.loadPolicy()
                let policy = versioned?.policy ?? UserPolicy.defaults()
                activePolicyVersion = versioned?.version ?? 0
                originalPolicy = policy
                policyDraft = SettingsPolicyDraft(policy: policy)
                screenshotAnalysisEnabled = versioned?.policy.privacy.screenshotAnalysisEnabled ?? false
                policyDraft.screenshotAnalysisEnabled = screenshotAnalysisEnabled
                workStartHour = policyDraft.workStart.hour
                workStartMinute = policyDraft.workStart.minute
                workEndHour = policyDraft.workEnd.hour
                workEndMinute = policyDraft.workEnd.minute
                selectedWorkWeekdays = policy.schedule.workWindows.first?.weekdays.sorted() ?? Weekday.allCases
                quietStartHour = policyDraft.quietStart.hour
                quietStartMinute = policyDraft.quietStart.minute
                quietEndHour = policyDraft.quietEnd.hour
                quietEndMinute = policyDraft.quietEnd.minute
                gamingPolicy = OnboardingGamingPolicy(policy: policy.gaming)
                for decision in progress.reminderListDecisions {
                    policyDraft.setReminderListDecision(
                        decision.isIncluded,
                        listID: decision.listID
                    )
                }
            } catch {
                policyIsAvailable = false
                errorMessage = "Existing settings could not be loaded. Setup choices will not be applied until local storage recovers. \(error.localizedDescription)"
            }
        }
    }

    convenience init(runtimeEnvironment: RuntimeEnvironment = .current()) {
        self.init(
            store: OnboardingProgressStore(runtimeEnvironment: runtimeEnvironment),
            dependencies: .live(runtimeEnvironment: runtimeEnvironment)
        )
    }

    func continueFromCurrentStep() async throws {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let base = progress
        let applied = try await applyCurrentPolicyEffect(base: base)
        var replacement = progress
        if let applied {
            try replacement.recordCompletedEffect(applied.effect)
        }
        try validateFirstPlanIfNeeded()
        try replacement.completeCurrentStep(at: now())
        do {
            progress = try store.save(replacement)
            if let applied { acceptAppliedPolicy(applied) }
            errorMessage = nil
            if progress.isFinished { route = .today }
        } catch {
            if let current = try? store.load() {
                if let applied,
                   current.completedEffects.contains(applied.effect),
                   current.completedSteps.contains(base.currentStep) {
                    progress = current
                    acceptAppliedPolicy(applied)
                    route = current.isFinished ? .today : .onboarding
                    errorMessage = nil
                    return
                }
                progress = current
                route = current.isFinished ? .today : .onboarding
                errorMessage = "Setup changed in another window. The latest saved step was restored. Review it before continuing."
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

    func resumeSetup() {
        guard !progress.isFinished, !isWorking else { return }
        route = .onboarding
    }

    func selectCoachingMode(_ mode: InitialCoachingMode) {
        guard !isWorking else { return }
        var replacement = progress
        replacement.chooseCoachingMode(mode)
        progress = replacement
        policyDraft.aiProvider = mode == .rulesOnly ? .disabled : .codexCLI
        errorMessage = nil
    }

    func deferAccess(for step: OnboardingStep) {
        if step == .reminders,
           progress.remindersAccess == .granted
            || sourceHealth[.reminders]?.state == .healthy {
            errorMessage = "Reminders is already connected. Choose each list, or explicitly choose local-only planning from the list controls."
            return
        }
        sourceRequestGeneration = UUID()
        if step == .reminders {
            sourceHealth[.reminders] = SourceHealth(
                id: .reminders,
                title: "Apple Reminders",
                eyebrow: "Intent",
                state: .notConnected,
                detail: "Reminders was skipped. Apple tasks will stay unavailable, while local tasks and the rest of setup remain usable.",
                evidence: "No permission dialog will be shown again unless you explicitly choose Request Access.",
                actionTitle: "Use local tasks"
            )
        }
        recordAccess(.deferred, for: step)
    }

    func applicationDidBecomeActive() async {
        guard route == .onboarding,
              [.reminders, .screenwatch, .notifications].contains(progress.currentStep),
              accessDecision(for: progress.currentStep) != nil,
              !isWorking else { return }
        await inspectCurrentSource()
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
        if step == .reminders, result.decision == .granted {
            await loadReminderLists()
        }
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
            if step == .reminders {
                await loadReminderLists()
            }
        }
    }

    func loadReminderLists() async {
        guard let dependencies,
              progress.remindersAccess == .granted else { return }
        let generation = UUID()
        reminderListGeneration = generation
        reminderListDiscovery = .loading
        let result = await dependencies.discoverReminderLists()
        guard reminderListGeneration == generation else { return }
        switch result {
        case let .available(lists):
            reminderListDiscovery = lists.isEmpty ? .empty : .available(lists)
            errorMessage = nil
        case let .permissionRequired(message):
            reminderListDiscovery = .permissionRequired(message)
            errorMessage = "Reminder permission is required before lists can be loaded. \(message)"
        case let .unavailable(message):
            reminderListDiscovery = .failed(message)
            errorMessage = "Reminder lists could not be loaded. \(message)"
        }
    }

    func setReminderListDecision(_ isIncluded: Bool, listID: String) {
        guard case let .available(lists) = reminderListDiscovery,
              lists.contains(where: { $0.id == listID }),
              !isWorking else { return }
        do {
            var replacement = progress
            replacement.setReminderListDecision(isIncluded, listID: listID)
            progress = try store.save(replacement)
            policyDraft.setReminderListDecision(isIncluded, listID: listID)
            errorMessage = nil
        } catch {
            if let latest = try? store.load() {
                progress = latest
            }
            errorMessage = "The Reminder-list choice could not be saved. \(error.localizedDescription)"
        }
    }

    func confirmEmptyReminderListFallback() {
        guard reminderListDiscovery == .empty, !isWorking else { return }
        do {
            var replacement = progress
            replacement.confirmEmptyReminderListFallback()
            progress = try store.save(replacement)
            errorMessage = nil
        } catch {
            errorMessage = "Local fallback could not be confirmed. \(error.localizedDescription)"
        }
    }

    func reminderListDecision(for listID: String) -> Bool? {
        progress.reminderListDecisions.first(where: { $0.listID == listID })?.isIncluded
            ?? policyDraft.reminderListPolicy.decision(for: listID)
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
        let result: OnboardingDeliveryResult
        do {
            let promptResult = try await dependencies.createTestPrompt(progress.flowID)
            testPrompt = promptResult.episode
            testPromptMessage = promptResult.message
            result = .init(
                state: promptResult.delivery == .notification ? .scheduled : .todayFallback,
                message: promptResult.message
            )
        } catch {
            result = await dependencies.testDelivery()
            testPromptMessage = "The canonical prompt could not be created. \(error.localizedDescription)"
        }
        guard deliveryGeneration == generation else {
            isWorking = false
            return
        }
        deliveryResult = result
        isWorking = false
    }

    func completeTestTask() {
        guard !isWorking else { return }
        do {
            var replacement = progress
            replacement.completeDeliveryTestTask()
            progress = try store.save(replacement)
            testTaskCompleted = true
            errorMessage = nil
        } catch {
            errorMessage = "The test-task result could not be saved. \(error.localizedDescription)"
        }
    }

    func restoreTestPrompt() async {
        guard let dependencies, !isWorking else { return }
        do {
            testPrompt = try await dependencies.loadTestPrompt(progress.flowID)
        } catch {
            errorMessage = "The saved setup prompt could not be loaded. \(error.localizedDescription)"
        }
    }

    func respondToTestPrompt(_ action: PromptActionKind) async {
        guard let dependencies,
              let prompt = testPrompt,
              prompt.state.isUnresolved,
              !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            testPrompt = try await dependencies.respondToTestPrompt(PromptResponseCommand(
                promptID: prompt.id,
                action: action,
                actionToken: PromptResponseToken.make(promptID: prompt.id, action: action),
                surface: .loopback
            ))
            testPromptMessage = action == .continueIntentionally
                ? "Prompt resolved. Continue setup when ready."
                : "Prompt resolved. Today remains the fallback for future choices."
            errorMessage = nil
        } catch {
            errorMessage = "The setup prompt could not be resolved. \(error.localizedDescription)"
        }
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
            guard let access = progress.remindersAccess else { return false }
            return access == .granted ? reminderListSelectionIsValid : true
        case .screenwatch:
            return progress.screenwatchAccess != nil
        case .notifications:
            return progress.notificationAccess != nil
        case .coachingMode:
            return progress.coachingMode != nil
        case .deliveryTest:
            return testTaskCompleted
                && testPrompt?.state == .responded
        case .firstDailyPlan:
            return firstDailyPlanResult?.state == .prepared
                && firstDailyPlanResult?.items.isEmpty == false
        case .schedule:
            return scheduleValidationMessage == nil
        default:
            return true
        }
    }

    var scheduleValidationMessage: String? {
        if selectedWorkWeekdays.isEmpty {
            return "Choose at least one work day."
        }
        let workStart = LocalTime(hour: workStartHour, minute: workStartMinute)
        let workEnd = LocalTime(hour: workEndHour, minute: workEndMinute)
        if workStart == workEnd {
            return "Work start and end cannot be the same. Choose a non-empty work window."
        }
        let quietStart = LocalTime(hour: quietStartHour, minute: quietStartMinute)
        let quietEnd = LocalTime(hour: quietEndHour, minute: quietEndMinute)
        if quietStart == quietEnd {
            return "Quiet start and end cannot be the same. Overnight quiet hours are supported."
        }
        return nil
    }

    func toggleWorkWeekday(_ weekday: Weekday) {
        if let index = selectedWorkWeekdays.firstIndex(of: weekday) {
            selectedWorkWeekdays.remove(at: index)
        } else {
            selectedWorkWeekdays.append(weekday)
            selectedWorkWeekdays.sort()
        }
    }

    var scheduleSummary: String {
        let workMode = LocalTime(hour: workEndHour, minute: workEndMinute) < LocalTime(hour: workStartHour, minute: workStartMinute) ? "overnight" : "same-day"
        let quietMode = LocalTime(hour: quietEndHour, minute: quietEndMinute) < LocalTime(hour: quietStartHour, minute: quietStartMinute) ? "overnight" : "same-day"
        return "Work applies on \(selectedWorkWeekdays.count) selected day\(selectedWorkWeekdays.count == 1 ? "" : "s") and is \(workMode). Quiet hours are \(quietMode). Times use \(TimeZone.current.identifier)."
    }

    private var reminderListSelectionIsValid: Bool {
        switch reminderListDiscovery {
        case let .available(lists):
            return !lists.isEmpty && lists.allSatisfy {
                reminderListDecision(for: $0.id) != nil
            }
        case .empty:
            return progress.emptyReminderListFallbackConfirmed
        case .idle, .loading, .permissionRequired, .failed:
            return false
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

    private struct AppliedPolicyEffect {
        let policy: UserPolicy
        let receipt: PolicyMutationReceipt
        let effect: OnboardingCompletedEffect
    }

    private func applyCurrentPolicyEffect(
        base: OnboardingProgress
    ) async throws -> AppliedPolicyEffect? {
        guard let dependencies else { return nil }
        try adoptBootstrapPolicyIfNeeded(base: base, dependencies: dependencies)
        let policy: UserPolicy
        switch base.currentStep {
        case .reminders:
            guard base.remindersAccess == .granted else { return nil }
            guard reminderListSelectionIsValid else {
                throw OnboardingDependencyError.reminderListSelectionRequired
            }
            policyDraft.confirmReminderListConfiguration()
            policy = policyDraft.policy(preserving: originalPolicy)
        case .screenwatch:
            policyDraft.screenshotAnalysisEnabled = screenshotAnalysisEnabled
            policy = policyDraft.policy(preserving: originalPolicy)
        case .activityClassification:
            policy = policyDraft.policy(preserving: originalPolicy)
        case .schedule:
            guard scheduleValidationMessage == nil else {
                throw OnboardingDependencyError.invalidScheduleBoundaries
            }
            policyDraft.workStart = LocalTime(hour: workStartHour, minute: workStartMinute)
            policyDraft.workEnd = LocalTime(hour: workEndHour, minute: workEndMinute)
            policyDraft.quietStart = LocalTime(hour: quietStartHour, minute: quietStartMinute)
            policyDraft.quietEnd = LocalTime(hour: quietEndHour, minute: quietEndMinute)
            let draftedPolicy = policyDraft.policy(preserving: originalPolicy)
            policy = UserPolicy(
                operatingMode: draftedPolicy.operatingMode,
                automationPause: draftedPolicy.automationPause,
                schedule: SchedulePolicy(
                    timeZoneIdentifier: draftedPolicy.schedule.timeZoneIdentifier,
                    workWindows: [WeeklyWorkWindow(
                        weekdays: selectedWorkWeekdays.sorted(),
                        start: policyDraft.workStart,
                        end: policyDraft.workEnd
                    )],
                    quietHours: draftedPolicy.schedule.quietHours,
                    nightlyPlanningTime: draftedPolicy.schedule.nightlyPlanningTime,
                    morningConfirmationTime: draftedPolicy.schedule.morningConfirmationTime,
                    planningCapacityPercent: draftedPolicy.schedule.planningCapacityPercent
                ),
                calendar: draftedPolicy.calendar,
                privacy: draftedPolicy.privacy,
                wake: draftedPolicy.wake,
                behavior: draftedPolicy.behavior,
                capture: draftedPolicy.capture,
                gaming: draftedPolicy.gaming,
                reminderLists: draftedPolicy.reminderLists
            )
        case .gamingPolicy:
            policy = originalPolicy.replacingGamingPolicy(gamingPolicy.policy)
        case .coachingMode:
            policy = policyDraft.policy(preserving: originalPolicy)
        default:
            return nil
        }
        guard policyIsAvailable else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let digest = try PolicyMutationRequest.canonicalPayloadDigest(for: policy)
        let requestID = [
            "onboarding-policy-v1",
            base.flowID,
            base.currentStep.rawValue,
            String(base.persistenceRevision),
            digest,
        ].joined(separator: ":")
        let origin = PolicyMutationOrigin.onboarding(
            flowID: base.flowID,
            step: base.currentStep,
            progressRevision: base.persistenceRevision
        )
        let request = PolicyMutationRequest(
            requestID: requestID,
            expectedVersion: activePolicyVersion,
            policy: policy,
            origin: origin
        )
        do {
            let receipt = try await dependencies.applyPolicyMutation(request)
            guard receipt.requestID == requestID,
                  receipt.payloadDigest == digest,
                  receipt.origin == origin,
                  receipt.resultingVersion > 0 else {
                throw OnboardingDependencyError.invalidPolicyMutationReceipt
            }
            return AppliedPolicyEffect(
                policy: policy,
                receipt: receipt,
                effect: OnboardingCompletedEffect(
                    step: base.currentStep,
                    requestID: receipt.requestID,
                    payloadDigest: receipt.payloadDigest,
                    resourceVersion: receipt.resultingVersion
                )
            )
        } catch {
            errorMessage = "This setup choice could not be applied. \(error.localizedDescription)"
            throw error
        }
    }

    private func adoptBootstrapPolicyIfNeeded(
        base: OnboardingProgress,
        dependencies: OnboardingDependencies
    ) throws {
        guard activePolicyVersion == 0,
              let versioned = try dependencies.loadPolicy(),
              versioned.version > 0 else {
            return
        }

        let selectedAIProvider = policyDraft.aiProvider
        activePolicyVersion = versioned.version
        originalPolicy = versioned.policy
        policyDraft = SettingsPolicyDraft(policy: versioned.policy)
        policyDraft.aiProvider = selectedAIProvider
        policyDraft.screenshotAnalysisEnabled = screenshotAnalysisEnabled

        for decision in base.reminderListDecisions {
            policyDraft.setReminderListDecision(decision.isIncluded, listID: decision.listID)
        }
        for (application, choice) in classifications {
            policyDraft.setClassification(choice, for: application)
        }
    }

    private func acceptAppliedPolicy(_ applied: AppliedPolicyEffect) {
        originalPolicy = applied.policy
        policyDraft = SettingsPolicyDraft(policy: applied.policy)
        activePolicyVersion = applied.receipt.resultingVersion
        gamingPolicy = OnboardingGamingPolicy(policy: applied.policy.gaming)
        screenshotAnalysisEnabled = applied.policy.privacy.screenshotAnalysisEnabled
    }

    private func validateFirstPlanIfNeeded() throws {
        guard progress.currentStep == .firstDailyPlan else { return }
        guard firstDailyPlanResult?.state == .prepared,
              firstDailyPlanResult?.items.isEmpty == false else {
            throw OnboardingDependencyError.firstDailyPlanUnavailable
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
