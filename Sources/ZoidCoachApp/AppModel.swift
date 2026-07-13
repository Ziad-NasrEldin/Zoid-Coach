import Combine
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
struct AppOSServiceFactory {
    let reminders: () -> any RemindersServicing
    let calendar: () -> any CalendarServicing
    let notifications: () -> any NotificationServicing

    static let live = Self(
        reminders: { RemindersService() },
        calendar: { CalendarService() },
        notifications: { NotificationService() }
    )
}

@MainActor
struct AppMeetingEvidenceCipherFactory {
    let production: (RuntimeEnvironment) throws -> any EvidenceCiphering
    let qa: (RuntimeEnvironment) throws -> any EvidenceCiphering

    static let live = Self(
        production: { try LocalEvidenceCipher(runtimeEnvironment: $0) },
        qa: { try LocalEvidenceCipher(runtimeEnvironment: $0) }
    )

    func makeCipher(for runtimeEnvironment: RuntimeEnvironment) throws -> any EvidenceCiphering {
        switch runtimeEnvironment.mode {
        case .production:
            try production(runtimeEnvironment)
        case .qa:
            try qa(runtimeEnvironment)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .today
    @Published var coachingState: CoachingState = .observation
    @Published var sources: [SourceHealth] = SourceHealth.initial
    @Published var reminderTasks: [ReminderTask] = []
    @Published var dailyPlan: [DailyPlanEntry] = []
    @Published private(set) var meetingCandidates: [StoredMeetingCandidate] = []
    @Published var reminderListOrder: [String] = []
    @Published var isLoadingReminderTasks = false
    @Published private(set) var isGeneratingSuggestedPlan = false
    @Published private(set) var isSchedulingDailyPlan = false
    @Published private(set) var isLoadingDailyPlan = true
    @Published private(set) var isLoadingReminderListOrder = true
    @Published var reminderTaskError: String?
    @Published var meetingCandidateError: String?
    @Published var calendarScheduleError: String?
    @Published private(set) var databaseError: String?
    @Published private(set) var todaySnapshot: TodaySnapshot?
    @Published private(set) var pendingTaskCommandIDs: Set<String> = []
    @Published private(set) var taskCommandError: String?
    @Published private(set) var promptEpisodes: [PromptEpisode] = []
    @Published private(set) var promptInboxTimeline: PromptInboxTimeline = .empty
    @Published private(set) var promptInboxError: String?
    @Published private(set) var pendingPromptID: String?
    @Published private(set) var actionAudit: [ActionAuditEntry] = []
    @Published private(set) var actionAuditError: String?
    @Published private(set) var reminderCompletionSyncStates: [String: ReminderCompletionSyncState] = [:]
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var persistenceMessage: String?
    @Published private(set) var runtimeSafety: AgentRuntimeSafetySnapshot = .writable
    @Published private(set) var captureHealth: AgentCaptureHealthSnapshot?
    @Published private(set) var planningCapacityUsesCalendar = false
    @Published private(set) var planningFixedCommitmentMinutes = 0
    @Published private(set) var calendarPlanApproval = CalendarPlanApprovalState()
    @Published var lastCheckAt: Date?
    @Published var isCheckingSources = false
    private let screenwatchReader: ScreenwatchReader
    private let remindersService: any RemindersServicing
    private let calendarService: any CalendarServicing
    private let notificationService: any NotificationServicing
    private let agentLaunchService: AgentLaunchService
    private let eventStore: EventStore
    private let meetingArchive: ScreenwatchArchive?
    private let meetingEvidenceCipherFactory: () throws -> any EvidenceCiphering
    private let todaySnapshotStore: TodaySnapshotStore?
    private let policyStore: PolicyStore?
    private let reminderListPolicyLoader: @Sendable () throws -> ReminderListPolicy
    private let todayDashboardXPCClient: TodayDashboardXPCClient
    private let synchronizeReminderSnapshots: @Sendable ([AgentReminderSnapshot]) async throws -> Void
    private var dailyPlanPersistenceTask: Task<Void, Never>?
    private var dailyPlanPersistenceRevision = 0
    private let retryReminderCompletion: @Sendable (String) async throws -> Void
    private let fetchReminderCompletionSync: @Sendable (String) async throws -> ReminderCompletionSyncState
    private(set) var qaOSFixtureAdapter: DeterministicOSFixtureAdapters?
    private var reminderTasksAreAvailable = false
    private var sourceChecksInFlight: Set<SourceID> = []

    init(
        runtimeEnvironment: RuntimeEnvironment = .current(),
        screenwatchReader: ScreenwatchReader? = nil,
        screenwatchSourceRepository: ScreenwatchSourceRepository? = nil,
        remindersService: (any RemindersServicing)? = nil,
        calendarService: (any CalendarServicing)? = nil,
        notificationService: (any NotificationServicing)? = nil,
        liveServiceFactory: AppOSServiceFactory = .live,
        meetingEvidenceCipherFactory: AppMeetingEvidenceCipherFactory = .live,
        agentLaunchService: AgentLaunchService? = nil,
        eventStore: EventStore? = nil,
        reminderListPolicyLoader: (@Sendable () throws -> ReminderListPolicy)? = nil,
        synchronizeReminderSnapshots: (@Sendable ([AgentReminderSnapshot]) async throws -> Void)? = nil,
        retryReminderCompletion: (@Sendable (String) async throws -> Void)? = nil,
        fetchReminderCompletionSync: (@Sendable (String) async throws -> ReminderCompletionSyncState)? = nil
    ) {
        let resolvedAgentLaunchService = agentLaunchService
            ?? AgentLaunchService(runtimeEnvironment: runtimeEnvironment)
        let resolvedTodayDashboardXPCClient = TodayDashboardXPCClient(
            runtimeEnvironment: runtimeEnvironment
        )
        todayDashboardXPCClient = resolvedTodayDashboardXPCClient
        self.synchronizeReminderSnapshots = synchronizeReminderSnapshots ?? { snapshots in
            _ = try await resolvedTodayDashboardXPCClient.apply(
                .synchronizeReminderSnapshots(snapshots)
            )
        }
        self.retryReminderCompletion = retryReminderCompletion ?? { taskID in
            _ = try await resolvedTodayDashboardXPCClient.retryReminderCompletion(taskID: taskID)
        }
        self.fetchReminderCompletionSync = fetchReminderCompletionSync ?? { taskID in
            try await resolvedTodayDashboardXPCClient.fetchReminderCompletionSync(taskID: taskID)
        }
        if let screenwatchReader {
            self.screenwatchReader = screenwatchReader
        } else {
            let repository = screenwatchSourceRepository
                ?? ScreenwatchSourceRepository(runtimeEnvironment: runtimeEnvironment)
            let source: Result<ScreenwatchDirectoryLease, Error> = Result {
                try repository.resolveCanonicalSource()
            }
            self.screenwatchReader = ScreenwatchReader(canonicalSource: source)
        }
        if case .qa = runtimeEnvironment.mode {
            let adapter: DeterministicOSFixtureAdapters?
            let fixtureFailureDetail: String
            do {
                adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
                    runtimeEnvironment: runtimeEnvironment
                )
                fixtureFailureDetail = "QA fixture composition is unavailable"
            } catch {
                adapter = nil
                fixtureFailureDetail = "QA fixture startup failed: \(error.localizedDescription)"
            }
            qaOSFixtureAdapter = adapter
            self.remindersService = remindersService.flatMap { $0.isProductionAdapter ? nil : $0 }
                ?? adapter.map(QAFixtureRemindersService.init)
                ?? DisabledQARemindersService(detail: fixtureFailureDetail)
            self.calendarService = calendarService.flatMap { $0.isProductionAdapter ? nil : $0 }
                ?? adapter.map(QAFixtureCalendarService.init)
                ?? DisabledQACalendarService(detail: fixtureFailureDetail)
            self.notificationService = notificationService.flatMap { $0.isProductionAdapter ? nil : $0 }
                ?? adapter.map(QAFixtureNotificationService.init)
                ?? DisabledQANotificationService(detail: fixtureFailureDetail)
        } else {
            qaOSFixtureAdapter = nil
            self.remindersService = remindersService ?? liveServiceFactory.reminders()
            self.calendarService = calendarService ?? liveServiceFactory.calendar()
            self.notificationService = notificationService ?? liveServiceFactory.notifications()
        }
        self.agentLaunchService = resolvedAgentLaunchService
        self.eventStore = eventStore ?? EventStore(databaseURL: runtimeEnvironment.databaseURL, readOnly: true)
        self.meetingEvidenceCipherFactory = {
            try meetingEvidenceCipherFactory.makeCipher(for: runtimeEnvironment)
        }
        meetingArchive = try? ScreenwatchArchive(databaseURL: runtimeEnvironment.databaseURL, readOnly: true)
        todaySnapshotStore = try? TodaySnapshotStore(databaseURL: runtimeEnvironment.databaseURL, readOnly: true)
        let resolvedPolicyStore = try? PolicyStore(
            databaseURL: runtimeEnvironment.databaseURL,
            readOnly: true
        )
        policyStore = resolvedPolicyStore
        self.reminderListPolicyLoader = reminderListPolicyLoader ?? {
            guard let resolvedPolicyStore else {
                throw AppModelPolicyError.policyStoreUnavailable
            }
            return try resolvedPolicyStore.current()?.policy.reminderLists
                ?? .legacyAllLists
        }
        Task {
            updateSource(resolvedAgentLaunchService.enableAndInspect())
            await refreshAllSources()
            await refreshReminderTasks()
            await reloadDailyPlan()
            await reloadReminderListOrder()
            reloadMeetingCandidates()
            updateSource(await self.notificationService.inspect())
            await refreshTodaySnapshot()
            await refreshPromptInbox()
            await refreshActionAudit()
            await refreshRuntimeSafety()
            await refreshCaptureHealth()
        }
    }

    func runSourceCheck() {
        guard !isCheckingSources else { return }

        isCheckingSources = true
        sources = sources.map { source in
            var copy = source
            copy.state = .checking
            copy.detail = "Inspecting local source"
            return copy
        }

        Task {
            try? await Task.sleep(for: .milliseconds(320))
            let reminders = await remindersService.inspect()
            updateSource(reminders)
            let calendar = await calendarService.inspect()
            updateSource(calendar)
            refreshPlanningCapacity()
            updateSource(agentLaunchService.inspect())
            updateSource(await notificationService.inspect())
            let screenwatch = await screenwatchReader.inspect()
            updateSource(screenwatch)
            lastCheckAt = Date()
            isCheckingSources = false
        }
    }

    func checkSource(_ sourceID: SourceID) {
        guard sourceChecksInFlight.insert(sourceID).inserted else { return }
        markSourceChecking(sourceID)
        switch sourceID {
        case .screenwatch:
            Task {
                defer { sourceChecksInFlight.remove(sourceID) }
                await refreshScreenwatch()
            }
        case .reminders:
            Task {
                defer { sourceChecksInFlight.remove(sourceID) }
                let result = await remindersService.requestAccessAndInspect()
                updateSource(result)
                if result.state == .healthy {
                    await refreshReminderTasks()
                    selectedSection = .today
                }
            }
        case .calendar:
            Task {
                defer { sourceChecksInFlight.remove(sourceID) }
                let result = await calendarService.requestAccessAndInspect()
                updateSource(result)
                refreshPlanningCapacity()
            }
        case .agent:
            updateSource(agentLaunchService.enableAndInspect())
            sourceChecksInFlight.remove(sourceID)
        case .notifications:
            Task {
                defer { sourceChecksInFlight.remove(sourceID) }
                updateSource(await notificationService.requestAccessAndInspect())
            }
        }
    }

    private func markSourceChecking(_ sourceID: SourceID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].state = .checking
        sources[index].detail = "Checking the current connection and repair path"
    }

    var calendarSelectionAvailability: CalendarSelectionAvailability {
        calendarService.selectionAvailability
    }

    func availableCalendarChoices() throws -> [CalendarChoice] {
        try calendarService.availableCalendars()
    }

    func requestCalendarAccess() async {
        updateSource(await calendarService.requestAccessAndInspect())
        refreshPlanningCapacity()
    }

    func refreshQAFixtureState() async {
        guard qaOSFixtureAdapter != nil else { return }
        await refreshAllSources()
        await refreshReminderTasks()
    }

    func refreshReminderTasks() {
        guard !isLoadingReminderTasks else { return }
        isLoadingReminderTasks = true
        reminderTaskError = nil

        Task {
            await refreshReminderTasks()
        }
    }

    func completeReminderTask(_ task: ReminderTask) {
        guard canIssueExternalActions else {
            reminderTaskError = externalActionUnavailableMessage
            return
        }
        Task {
            do {
                _ = try await todayDashboardXPCClient.apply(.completeReminder(reminderID: task.id))
                await refreshReminderTasks()
                dailyPlan.removeAll { $0.reminderID == task.id }
                persistDailyPlan()
            } catch {
                reminderTaskError = "Could not complete \"\(task.title)\". Refresh and try again."
            }
        }
    }

    func refreshTodaySnapshot() async {
        do {
            todaySnapshot = try await todayDashboardXPCClient.fetchTodaySnapshot()
        } catch {
            todaySnapshot = try? todaySnapshotStore?.load()
        }
    }

    func applyTaskCommand(_ command: TaskActivityCommand, taskID: String) {
        guard pendingTaskCommandIDs.isEmpty else { return }
        pendingTaskCommandIDs.insert(taskID)
        taskCommandError = nil
        Task {
            defer { pendingTaskCommandIDs.remove(taskID) }
            do {
                todaySnapshot = try await todayDashboardXPCClient.apply(command, taskID: taskID)
                lastActionMessage = taskCommandConfirmation(command)
                if command == .complete {
                    await refreshActionAudit()
                    await monitorReminderCompletionSync(taskID: taskID)
                }
            } catch {
                taskCommandError = "The task change could not be saved. The last confirmed state is still shown. Try again after checking Agent source health."
                todaySnapshot = try? todaySnapshotStore?.load()
            }
        }
    }

    func startSprint(taskID: String, durationMinutes: Int) {
        guard pendingTaskCommandIDs.isEmpty else { return }
        guard (1...240).contains(durationMinutes) else {
            taskCommandError = "Choose a sprint from 1 to 240 minutes."
            return
        }
        pendingTaskCommandIDs.insert(taskID)
        taskCommandError = nil
        Task {
            defer { pendingTaskCommandIDs.remove(taskID) }
            do {
                todaySnapshot = try await todayDashboardXPCClient.startSprint(taskID: taskID, durationMinutes: durationMinutes)
                lastActionMessage = "\(durationMinutes)-minute sprint started."
            } catch {
                taskCommandError = error.localizedDescription
                todaySnapshot = try? todaySnapshotStore?.load()
            }
        }
    }

    var isAnyTaskCommandPending: Bool {
        pendingTaskCommandIDs.isEmpty == false
    }

    func reminderCompletionSyncState(for taskID: String) -> ReminderCompletionSyncState {
        reminderCompletionSyncStates[taskID]
            ?? ReminderCompletionSyncState(taskID: taskID, audit: actionAudit)
    }

    var visibleReminderCompletionSyncStates: [ReminderCompletionSyncState] {
        reminderCompletionSyncStates.values
            .filter { $0.phase != .notRequested && $0.phase != .confirmed }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    func reminderCompletionTitle(taskID: String) -> String {
        reminderCompletionSyncState(for: taskID).taskTitle
            ?? reminderTasks.first(where: { $0.id == taskID })?.title
            ?? "Reminder task"
    }

    func retryReminderCompletionSync(taskID: String) {
        let state = reminderCompletionSyncState(for: taskID)
        guard state.canRetry, pendingTaskCommandIDs.isEmpty else { return }
        pendingTaskCommandIDs.insert(taskID)
        taskCommandError = nil
        Task {
            defer { pendingTaskCommandIDs.remove(taskID) }
            do {
                try await retryReminderCompletion(taskID)
                lastActionMessage = "Completion retry queued for Apple Reminders."
                await refreshActionAudit()
                await monitorReminderCompletionSync(taskID: taskID)
            } catch {
                taskCommandError = "The completion retry could not be queued. Your local task and history are unchanged. Check Reminders access and try again."
            }
        }
    }

    private func monitorReminderCompletionSync(taskID: String) async {
        for _ in 0..<20 {
            let phase = reminderCompletionSyncState(for: taskID).phase
            guard phase == .pending || phase == .retrying else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await refreshActionAudit()
        }
    }

    private func refreshReminderCompletionSyncStates() async {
        let auditTaskIDs = actionAudit
            .filter { $0.actionType == ActionCommandType.completeReminder.rawValue }
            .map(\.entityID)
        let taskIDs = Set(reminderTasks.map(\.id) + auditTaskIDs)
        for taskID in taskIDs {
            let auditState = ReminderCompletionSyncState(taskID: taskID, audit: actionAudit)
            reminderCompletionSyncStates[taskID] = (try? await fetchReminderCompletionSync(taskID)) ?? auditState
        }
    }

    private func taskCommandConfirmation(_ command: TaskActivityCommand) -> String {
        switch command {
        case .start: "Task started."
        case .startSprint10: "10-minute recovery sprint started."
        case .startSprint20: "20-minute work sprint started."
        case .startSprint25: "25-minute focus sprint started."
        case .continueOpenEnded: "Sprint ended. The task is continuing without a timer."
        case .resume: "Task resumed."
        case .pause: "Task paused."
        case .pauseForBreak: "Task paused for a break."
        case .pauseForExternalInterruption: "Task paused for an external interruption."
        case .pauseDoneForNow: "Task paused. It will remain ready to resume later."
        case .pauseForEndOfDay: "Task paused for the end of the workday."
        case .complete: "Task completion is queued for Reminders sync."
        case .block: "Task marked blocked."
        case .reschedule: "Task marked for replanning."
        }
    }

    func refreshPromptInbox() async {
        do {
            let timeline = try await todayDashboardXPCClient.fetchPromptInboxTimeline()
            promptInboxTimeline = timeline
            promptEpisodes = timeline.awaitingResponse.map(\.episode)
            promptInboxError = nil
        } catch {
            promptInboxError = "Decisions could not be refreshed. The last confirmed inbox remains visible."
        }
    }

    func refreshActionAudit() async {
        do {
            actionAudit = try await todayDashboardXPCClient.fetchActionAudit()
            actionAuditError = nil
        } catch {
            actionAuditError = "The automatic action ledger is unavailable. Check Agent source health and retry."
        }
        await refreshReminderCompletionSyncStates()
    }

    func refreshRuntimeSafety() async {
        do {
            runtimeSafety = try await todayDashboardXPCClient.fetchRuntimeSafety()
            if runtimeSafety.isReadOnly {
                persistenceMessage = "READ-ONLY SAFETY MODE: \(runtimeSafety.reason ?? "The agent stopped database writes after a persistence failure.") External actions are blocked."
            }
        } catch {
            persistenceMessage = "Agent write safety could not be verified. External changes may be unavailable until Source health recovers."
        }
    }

    func refreshCaptureHealth() async {
        do {
            captureHealth = try await todayDashboardXPCClient.fetchCaptureHealth()
        } catch {
            captureHealth = nil
            persistenceMessage = "Native capture health could not be verified. Legacy Screenwatch remains the active source."
        }
    }

    func undoAction(_ entry: ActionAuditEntry) {
        guard entry.canUndo else { return }
        Task {
            do {
                let receipt = try await todayDashboardXPCClient.apply(.undoAction(commandID: entry.id))
                lastActionMessage = receipt.message
                await refreshActionAudit()
                await refreshTodaySnapshot()
            } catch {
                lastActionMessage = "The background agent could not undo this action. No local plan data was changed."
            }
        }
    }

    func reloadMeetingCandidatesForForegroundActivation() {
        reloadMeetingCandidates()
    }

    func respondToPrompt(_ episode: PromptEpisode, action: PromptActionKind) {
        guard pendingPromptID == nil else { return }
        let command = PromptResponseCommand(
            promptID: episode.id,
            action: action,
            actionToken: PromptResponseToken.make(promptID: episode.id, action: action),
            surface: .dashboard
        )
        pendingPromptID = episode.id
        promptInboxError = nil
        Task {
            defer { pendingPromptID = nil }
            do {
                _ = try await todayDashboardXPCClient.respondToPrompt(command)
                await refreshPromptInbox()
                await refreshTodaySnapshot()
                if action == .editMeeting {
                    reloadMeetingCandidates()
                    selectedSection = .today
                }
            } catch {
                await refreshPromptInbox()
                promptInboxError = "That decision changed before the action completed. The current inbox has been refreshed."
            }
        }
    }

    func dismissPrompt(_ episode: PromptEpisode) {
        guard pendingPromptID == nil else { return }
        pendingPromptID = episode.id
        promptInboxError = nil
        Task {
            defer { pendingPromptID = nil }
            do {
                _ = try await todayDashboardXPCClient.dismissPrompt(episode.id)
                await refreshPromptInbox()
            } catch {
                await refreshPromptInbox()
                promptInboxError = "That decision changed before dismissal completed. The current inbox has been refreshed."
            }
        }
    }

    func startUnplannedTask(_ task: ReminderTask) {
        guard pendingTaskCommandIDs.isEmpty else { return }
        pendingTaskCommandIDs.insert(task.id)
        taskCommandError = nil
        Task {
            defer { pendingTaskCommandIDs.remove(task.id) }
            do {
                todaySnapshot = try await todayDashboardXPCClient.startUnplannedTask(task.id)
                lastActionMessage = "Unplanned work started. Zoid 666 will track this task without claiming that it violates a plan."
                await refreshPromptInbox()
            } catch {
                taskCommandError = error.localizedDescription
                todaySnapshot = try? todaySnapshotStore?.load()
            }
        }
    }

    func skipPlanning() {
        guard pendingTaskCommandIDs.isEmpty else { return }
        Task {
            do {
                todaySnapshot = try await todayDashboardXPCClient.skipPlanning()
                lastActionMessage = "Planning is skipped for now. You can still start any available task or return to planning later."
                await refreshPromptInbox()
            } catch {
                taskCommandError = "Unplanned mode could not be saved. The previous day state is still shown."
            }
        }
    }

    func addToDailyPlan(_ task: ReminderTask) {
        guard !isLoadingDailyPlan,
              dailyPlan.count < 5,
              !dailyPlan.contains(where: { $0.reminderID == task.id })
        else { return }
        calendarScheduleError = nil
        dailyPlan.append(
            DailyPlanEntry(
                reminderID: task.id,
                rank: (dailyPlan.map(\.rank).max() ?? 0) + 1,
                isMainObjective: dailyPlan.isEmpty,
                estimateMinutes: nil
            )
        )
        recordTaskHistory(task.id, state: .selected)
        persistDailyPlan()
    }

    func removeFromDailyPlan(_ entry: DailyPlanEntry) {
        guard !isLoadingDailyPlan else { return }
        calendarScheduleError = nil
        dailyPlan.removeAll { $0.reminderID == entry.reminderID }
        recordTaskHistory(entry.reminderID, state: .postponed)
        dailyPlan = dailyPlan.enumerated().map { index, entry in
            DailyPlanEntry(
                reminderID: entry.reminderID,
                rank: index + 1,
                isMainObjective: entry.isMainObjective,
                estimateMinutes: entry.estimateMinutes,
                selectionReason: entry.selectionReason,
                selectionScore: entry.selectionScore,
                isOptional: entry.isOptional,
                blockedReason: entry.blockedReason,
                deferredUntil: entry.deferredUntil
            )
        }
        if !dailyPlan.contains(where: \.isMainObjective), !dailyPlan.isEmpty {
            setMainObjective(dailyPlan[0])
        } else {
            persistDailyPlan()
        }
    }

    func setMainObjective(_ entry: DailyPlanEntry) {
        guard !isLoadingDailyPlan else { return }
        dailyPlan = dailyPlan.map {
            DailyPlanEntry(
                reminderID: $0.reminderID,
                rank: $0.rank,
                isMainObjective: $0.reminderID == entry.reminderID,
                estimateMinutes: $0.estimateMinutes,
                selectionReason: $0.selectionReason,
                selectionScore: $0.selectionScore,
                isOptional: $0.isOptional,
                blockedReason: $0.blockedReason,
                deferredUntil: $0.deferredUntil
            )
        }
        persistDailyPlan()
    }

    func setEstimate(_ minutes: Int, for entry: DailyPlanEntry) {
        guard !isLoadingDailyPlan else { return }
        calendarScheduleError = nil
        dailyPlan = dailyPlan.map {
            DailyPlanEntry(
                reminderID: $0.reminderID,
                rank: $0.rank,
                isMainObjective: $0.isMainObjective,
                estimateMinutes: $0.reminderID == entry.reminderID ? minutes : $0.estimateMinutes,
                selectionReason: $0.selectionReason,
                selectionScore: $0.selectionScore,
                isOptional: $0.isOptional,
                blockedReason: $0.blockedReason,
                deferredUntil: $0.deferredUntil
            )
        }
        persistDailyPlan()
    }

    func moveDailyPlanEntry(_ entry: DailyPlanEntry, by offset: Int) {
        guard !isLoadingDailyPlan, offset != 0 else { return }
        var ordered = dailyPlan.sorted { $0.rank < $1.rank }
        guard let sourceIndex = ordered.firstIndex(where: { $0.reminderID == entry.reminderID }) else { return }
        let destinationIndex = sourceIndex + offset
        guard ordered.indices.contains(destinationIndex) else { return }
        ordered.swapAt(sourceIndex, destinationIndex)
        dailyPlan = ordered.enumerated().map { index, item in
            revisedPlanEntry(item, rank: index + 1)
        }
        persistDailyPlan()
    }

    func toggleOptional(_ entry: DailyPlanEntry) {
        guard !isLoadingDailyPlan else { return }
        let willBecomeOptional = !entry.isOptional
        guard !(willBecomeOptional && entry.isMainObjective) else {
            persistenceMessage = "Choose another main objective before marking this task optional."
            return
        }
        dailyPlan = dailyPlan.map {
            $0.reminderID == entry.reminderID
                ? revisedPlanEntry($0, isOptional: willBecomeOptional)
                : $0
        }
        persistDailyPlan()
    }

    func deferTask(_ entry: DailyPlanEntry, until date: Date) {
        guard !isLoadingDailyPlan, date > Date() else {
            persistenceMessage = "Choose a future time for this deferred task."
            return
        }
        dailyPlan = dailyPlan.map {
            $0.reminderID == entry.reminderID
                ? revisedPlanEntry($0, isMainObjective: false, deferredUntil: date)
                : $0
        }
        if !dailyPlan.contains(where: { $0.isMainObjective }),
           let replacement = dailyPlan
            .sorted(by: { $0.rank < $1.rank })
            .first(where: { !$0.isOptional && !($0.deferredUntil.map { $0 > Date() } ?? false) }) {
            dailyPlan = dailyPlan.map {
                $0.reminderID == replacement.reminderID
                    ? revisedPlanEntry($0, isMainObjective: true)
                    : $0
            }
        }
        persistDailyPlan()
    }

    func deferTaskUntilTomorrow(_ entry: DailyPlanEntry) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
            ?? Date().addingTimeInterval(24 * 60 * 60)
        deferTask(entry, until: tomorrow)
    }

    func rescheduleTask(_ taskID: String, until date: Date) {
        guard let entry = dailyPlan.first(where: { $0.reminderID == taskID }) else {
            persistenceMessage = "This task is no longer in today's plan. Refresh before rescheduling it."
            return
        }
        deferTask(entry, until: date)
    }

    func clearTaskDeferral(_ entry: DailyPlanEntry) {
        guard !isLoadingDailyPlan else { return }
        dailyPlan = dailyPlan.map {
            $0.reminderID == entry.reminderID
                ? revisedPlanEntry($0, deferredUntil: .some(nil))
                : $0
        }
        persistDailyPlan()
    }

    func markTaskBlocked(_ entry: DailyPlanEntry, reason: String) {
        markTaskBlocked(taskID: entry.reminderID, reason: reason)
    }

    func markTaskBlocked(taskID: String, reason: String) {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...240).contains(normalizedReason.count) else {
            taskCommandError = "Explain the blocker in 3 to 240 characters."
            return
        }
        guard pendingTaskCommandIDs.isEmpty else { return }
        pendingTaskCommandIDs.insert(taskID)
        taskCommandError = nil
        Task {
            defer { pendingTaskCommandIDs.remove(taskID) }
            do {
                todaySnapshot = try await todayDashboardXPCClient.blockTask(
                    taskID: taskID,
                    reason: normalizedReason
                )
                await reloadDailyPlan()
                lastActionMessage = "Task marked blocked with its reason saved locally."
            } catch {
                taskCommandError = "The blocker was not saved. The last confirmed task and plan state are still shown."
                await reloadDailyPlan()
                todaySnapshot = try? todaySnapshotStore?.load()
            }
        }
    }

    private func revisedPlanEntry(
        _ entry: DailyPlanEntry,
        rank: Int? = nil,
        isMainObjective: Bool? = nil,
        isOptional: Bool? = nil,
        blockedReason: String?? = nil,
        deferredUntil: Date?? = nil
    ) -> DailyPlanEntry {
        DailyPlanEntry(
            reminderID: entry.reminderID,
            rank: rank ?? entry.rank,
            isMainObjective: isMainObjective ?? entry.isMainObjective,
            estimateMinutes: entry.estimateMinutes,
            selectionReason: entry.selectionReason,
            selectionScore: entry.selectionScore,
            isOptional: isOptional ?? entry.isOptional,
            blockedReason: blockedReason ?? entry.blockedReason,
            deferredUntil: deferredUntil ?? entry.deferredUntil
        )
    }

    func generateSuggestedDailyPlan() {
        guard !isLoadingDailyPlan,
              !isGeneratingSuggestedPlan,
              hasPlanningCandidates
        else { return }

        isGeneratingSuggestedPlan = true
        Task {
            do {
                _ = try await todayDashboardXPCClient.apply(.draftPlan(day: Date(), overwriteExisting: true))
                await reloadDailyPlan()
                await refreshTodaySnapshot()
            } catch {
                calendarScheduleError = "The background agent could not draft a plan. Check Agent source health and retry."
            }
            isGeneratingSuggestedPlan = false
        }
    }

    var hasPlanningCandidates: Bool {
        !reminderTasks.isEmpty || todaySnapshot?.unplannedReminders?.isEmpty == false
    }

    var planningCapacityState: PlanningCapacityState {
        let schedule = currentPolicy().schedule
        return PlanningCapacityState(
            entries: dailyPlan,
            availableMinutes: schedule.planningCapacityMinutes(
                on: Date(),
                fixedCommitmentMinutes: planningFixedCommitmentMinutes
            )
        )
    }

    func isReminderEligibleForToday(_ dueDate: Date?, referenceDate: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: currentPolicy().schedule.timeZoneIdentifier) ?? .current
        return TodayReminderEligibility.isVisible(
            dueDate: dueDate,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    var remindersContinuityState: RemindersContinuityState {
        let reminderHealth = sources.first(where: { $0.id == .reminders })?.state ?? .notConnected
        let rows = todaySnapshot?.taskRows ?? []
        return RemindersContinuityState(
            isOutage: reminderHealth != .healthy && reminderHealth != .checking,
            plannedTaskCount: rows.count,
            plannedEstimateMinutes: rows.reduce(0) { $0 + $1.estimateMinutes },
            hasActiveSession: todaySnapshot?.activeTask != nil
        )
    }

    func reduceOverCapacityPlan() {
        guard let reminderID = planningCapacityState.suggestedReminderID,
              let entry = dailyPlan.first(where: { $0.reminderID == reminderID })
        else { return }
        removeFromDailyPlan(entry)
    }

    func scheduleDailyPlan() {
        guard canIssueExternalActions,
              !isSchedulingDailyPlan,
              planningCapacityState.canApprove
        else {
            if !canIssueExternalActions {
                calendarScheduleError = externalActionUnavailableMessage
            } else {
                switch planningCapacityState.readiness {
                case .empty:
                    calendarScheduleError = "Draft a daily plan before reserving Calendar blocks."
                case let .missingEstimates(count):
                    calendarScheduleError = "Estimate the remaining \(count) task\(count == 1 ? "" : "s") before accepting this plan."
                case let .overloaded(overByMinutes):
                    calendarScheduleError = "Reduce the plan by at least \(overByMinutes) minutes before accepting it."
                case .realistic:
                    calendarScheduleError = nil
                }
            }
            return
        }

        isSchedulingDailyPlan = true
        calendarPlanApproval.writeState = .queueing
        calendarScheduleError = nil
        Task {
            do {
                let receipt = try await todayDashboardXPCClient.apply(.schedulePlan(day: Date()))
                guard receipt.accepted else {
                    calendarPlanApproval.writeState = .reviewing
                    calendarScheduleError = receipt.message
                    isSchedulingDailyPlan = false
                    return
                }
                calendarPlanApproval.queued(commandIDs: receipt.commandIDs)
                lastActionMessage = receipt.message
                await refreshActionAudit()
                reconcileCalendarPlanApproval()
            } catch {
                calendarScheduleError = "The background agent could not queue Calendar blocks. Check Source health and try again."
                calendarPlanApproval.writeState = .reviewing
            }
            isSchedulingDailyPlan = false
        }
    }

    func requestCalendarPlanApproval() {
        guard planningCapacityState.canApprove else {
            scheduleDailyPlan()
            return
        }
        calendarScheduleError = nil
        var titlesByReminderID = Dictionary(uniqueKeysWithValues: reminderTasks.map { ($0.id, $0.title) })
        for row in todaySnapshot?.taskRows ?? [] {
            titlesByReminderID[row.taskID] = row.title
        }
        calendarPlanApproval.begin(
            entries: dailyPlan,
            titlesByReminderID: titlesByReminderID,
            availableMinutes: planningCapacityState.availableMinutes,
            fixedCommitmentMinutes: planningFixedCommitmentMinutes,
            usesCalendarAvailability: planningCapacityUsesCalendar
        )
    }

    func dismissCalendarPlanApproval() {
        guard !isSchedulingDailyPlan else { return }
        calendarPlanApproval.dismiss()
    }

    func recheckCalendarPlanWrite() {
        Task {
            await refreshActionAudit()
            reconcileCalendarPlanApproval()
        }
    }

    private func reconcileCalendarPlanApproval() {
        calendarPlanApproval.reconcile(with: actionAudit)
    }

    func addMeetingCandidateToCalendar(_ candidate: StoredMeetingCandidate) {
        saveMeetingCandidate(
            candidate,
            title: candidate.title,
            start: candidate.start,
            durationMinutes: candidate.durationMinutes,
            destination: .calendar
        )
    }

    func saveMeetingCandidate(
        _ candidate: StoredMeetingCandidate,
        title: String,
        start: Date,
        durationMinutes: Int,
        destination: MeetingDestination
    ) {
        guard canIssueExternalActions else {
            meetingCandidateError = externalActionUnavailableMessage
            return
        }
        Task {
            do {
                let target: AgentMeetingDestination = destination == .calendar ? .calendar : .reminder
                _ = try await todayDashboardXPCClient.apply(
                    .resolveMeetingCandidate(
                        candidateID: candidate.id,
                        title: title,
                        start: start,
                        durationMinutes: durationMinutes,
                        destination: target
                    )
                )
                lastActionMessage = destination == .calendar
                    ? "The confirmed meeting was queued for Apple Calendar."
                    : "The confirmed meeting was queued for Apple Reminders."
                await refreshActionAudit()
                reloadMeetingCandidates()
            } catch {
                meetingCandidateError = "The background agent could not queue this meeting action. Check Source health and try again."
            }
        }
    }

    func ignoreMeetingCandidate(_ candidate: StoredMeetingCandidate) {
        Task {
            do {
                _ = try await todayDashboardXPCClient.apply(.ignoreMeetingCandidate(candidateID: candidate.id))
                reloadMeetingCandidates()
            } catch {
                meetingCandidateError = "Could not dismiss this meeting suggestion through the background agent."
            }
        }
    }

    func deferMeetingCandidateEdit(_ candidate: StoredMeetingCandidate) {
        Task {
            do {
                _ = try await todayDashboardXPCClient.apply(.deferMeetingCandidate(candidateID: candidate.id))
                reloadMeetingCandidates()
            } catch {
                meetingCandidateError = "Could not defer this meeting edit through the background agent."
            }
        }
    }

    func moveReminderList(_ listID: String, before destinationID: String) {
        let knownListIDs = Set(reminderTasks.map(\.listID))
        guard !isLoadingReminderListOrder,
              listID != destinationID,
              knownListIDs.contains(listID),
              knownListIDs.contains(destinationID)
        else { return }
        var order = reminderListOrder
        if !order.contains(listID) { order.append(listID) }
        if !order.contains(destinationID) { order.append(destinationID) }
        order.removeAll { $0 == listID }
        let destinationIndex = order.firstIndex(of: destinationID) ?? order.endIndex
        order.insert(listID, at: destinationIndex)
        reminderListOrder = order
        persistReminderListOrder()
    }

    func moveReminderListToEnd(_ listID: String) {
        guard !isLoadingReminderListOrder,
              Set(reminderTasks.map(\.listID)).contains(listID)
        else { return }
        var order = reminderListOrder
        if !order.contains(listID) { order.append(listID) }
        order.removeAll { $0 == listID }
        order.append(listID)
        reminderListOrder = order
        persistReminderListOrder()
    }

    private func refreshAllSources() async {
        let reminders = await remindersService.inspect()
        updateSource(reminders)
        let calendar = await calendarService.inspect()
        updateSource(calendar)
        refreshPlanningCapacity()
        updateSource(agentLaunchService.inspect())
        updateSource(await notificationService.inspect())
        let screenwatch = await screenwatchReader.inspect()
        updateSource(screenwatch)
        lastCheckAt = Date()
    }

    private func refreshScreenwatch() async {
        let result = await screenwatchReader.inspect()
        updateSource(result)
        lastCheckAt = Date()
    }

    private func refreshReminderTasks() async {
        switch await remindersService.fetchIncompleteTasks() {
        case let .available(tasks):
            let reminderListPolicy: ReminderListPolicy
            do {
                reminderListPolicy = try reminderListPolicyLoader()
            } catch {
                reminderTasksAreAvailable = false
                reminderTasks = []
                reminderTaskError = "Reminder tasks are hidden because the saved list policy could not be verified. Repair local storage, then refresh."
                isLoadingReminderTasks = false
                return
            }
            let tasks = reminderListPolicy.filteringExternalTasks(tasks, listID: { $0.listID })
            reminderTasksAreAvailable = true
            reminderTasks = tasks
            try? await synchronizeReminderSnapshots(tasks.map {
                    AgentReminderSnapshot(
                        id: $0.id,
                        title: $0.title,
                        dueDate: $0.dueDate,
                        priority: $0.priority,
                        notes: $0.notes,
                        listID: $0.listID,
                        listName: $0.listName,
                        modificationDate: $0.modificationDate
                    )
                })
            await reconcileDailyPlan(with: tasks)
        case .unavailable:
            reminderTasksAreAvailable = false
            reminderTasks = []
            reminderTaskError = "Apple Reminders access is unavailable. Connect it from Source health, then refresh tasks."
        }
        isLoadingReminderTasks = false
    }

    func reloadDailyPlan() async {
        dailyPlan = await eventStore.loadDailyPlan()
        if reminderTasksAreAvailable {
            await reconcileDailyPlan(with: reminderTasks)
        }
        isLoadingDailyPlan = false
    }

    private func reloadMeetingCandidates() {
        guard let meetingArchive else {
            meetingCandidates = []
            return
        }
        do {
            meetingCandidates = try meetingArchive.unresolvedMeetingCandidates(
                cipherFactory: meetingEvidenceCipherFactory
            )
            meetingCandidateError = nil
        } catch {
            meetingCandidates = []
            meetingCandidateError = "Meeting suggestions could not be loaded."
        }
    }

    private func reconcileDailyPlan(with tasks: [ReminderTask]) async {
        let incompleteIDs = Set(tasks.map(\.id))
            .union(await eventStore.loadIncompleteLocalTaskIDs())
        let reconciledPlan = dailyPlan.filter { incompleteIDs.contains($0.reminderID) }
        guard reconciledPlan != dailyPlan else { return }
        dailyPlan = reconciledPlan.enumerated().map { index, entry in
            DailyPlanEntry(
                reminderID: entry.reminderID,
                rank: index + 1,
                isMainObjective: entry.isMainObjective,
                estimateMinutes: entry.estimateMinutes,
                selectionReason: entry.selectionReason,
                selectionScore: entry.selectionScore,
                isOptional: entry.isOptional,
                blockedReason: entry.blockedReason,
                deferredUntil: entry.deferredUntil
            )
        }
        if !dailyPlan.contains(where: \.isMainObjective), !dailyPlan.isEmpty {
            dailyPlan[0] = DailyPlanEntry(
                reminderID: dailyPlan[0].reminderID,
                rank: dailyPlan[0].rank,
                isMainObjective: true,
                estimateMinutes: dailyPlan[0].estimateMinutes,
                selectionReason: dailyPlan[0].selectionReason,
                selectionScore: dailyPlan[0].selectionScore,
                isOptional: dailyPlan[0].isOptional,
                blockedReason: dailyPlan[0].blockedReason,
                deferredUntil: dailyPlan[0].deferredUntil
            )
        }
        persistDailyPlan()
    }

    private func persistDailyPlan() {
        let items = dailyPlan.map {
            AgentPlanItem(
                reminderID: $0.reminderID,
                rank: $0.rank,
                isMainObjective: $0.isMainObjective,
                estimateMinutes: $0.estimateMinutes,
                selectionReason: $0.selectionReason,
                selectionScore: $0.selectionScore,
                isOptional: $0.isOptional,
                blockedReason: $0.blockedReason,
                deferredUntil: $0.deferredUntil
            )
        }
        dailyPlanPersistenceRevision += 1
        let revision = dailyPlanPersistenceRevision
        let previousPersistence = dailyPlanPersistenceTask
        dailyPlanPersistenceTask = Task { [weak self] in
            await previousPersistence?.value
            guard let self else { return }
            do {
                let receipt = try await todayDashboardXPCClient.apply(.replaceDailyPlan(items: items, day: Date()))
                guard receipt.accepted else { throw AppModelPersistenceError.rejected }
                if revision == dailyPlanPersistenceRevision {
                    persistenceMessage = nil
                }
            } catch {
                guard revision == dailyPlanPersistenceRevision else { return }
                persistenceMessage = "The plan change was not saved. The last durable plan has been restored."
                await reloadDailyPlan()
            }
        }
    }

    private func reloadReminderListOrder() async {
        reminderListOrder = await eventStore.loadReminderListOrder()
        isLoadingReminderListOrder = false
    }

    private func persistReminderListOrder() {
        let order = reminderListOrder
        Task {
            do {
                let receipt = try await todayDashboardXPCClient.apply(.replaceReminderListOrder(order))
                guard receipt.accepted else { throw AppModelPersistenceError.rejected }
                persistenceMessage = nil
            } catch {
                persistenceMessage = "The list order was not saved. The last durable order has been restored."
                await reloadReminderListOrder()
            }
        }
    }

    private func updateSource(_ result: SourceHealth) {
        guard let index = sources.firstIndex(where: { $0.id == result.id }) else { return }
        sources[index] = result
        lastCheckAt = Date()
        let checkedAt = Date()
        Task {
            do {
                let receipt = try await todayDashboardXPCClient.apply(.recordSourceCheck(
                    sourceID: result.id.rawValue,
                    state: result.state.rawValue,
                    detail: result.detail,
                    evidence: result.evidence,
                    checkedAt: checkedAt
                ))
                guard receipt.accepted else { throw AppModelPersistenceError.rejected }
            } catch {
                persistenceMessage = "Source health was checked, but its audit record was not saved."
            }
        }
    }

    private func recordTaskHistory(_ taskID: String, state: AgentTaskHistoryState) {
        Task {
            do {
                let receipt = try await todayDashboardXPCClient.apply(
                    .recordTaskHistory(taskID: taskID, state: state, occurredAt: Date())
                )
                guard receipt.accepted else { throw AppModelPersistenceError.rejected }
            } catch {
                persistenceMessage = "The plan was saved, but its learning-history record was not. No learning claim will be shown for this edit."
            }
        }
    }

    private func currentPolicy() -> UserPolicy {
        guard let policyStore else { return UserPolicy.defaults() }
        do { return try policyStore.current()?.policy ?? UserPolicy.defaults() }
        catch { return UserPolicy.defaults() }
    }

    private func refreshPlanningCapacity() {
        let schedule = currentPolicy().schedule
        let workIntervals = schedule.workIntervals(on: Date())
        guard let start = workIntervals.map(\.start).min(),
              let end = workIntervals.map(\.end).max()
        else {
            planningFixedCommitmentMinutes = 0
            planningCapacityUsesCalendar = false
            return
        }
        do {
            let visibleCalendarIDs = Set(currentPolicy().calendar.visibleCalendarIdentifiers)
            let commitments = try calendarService.commitments(from: start, through: end)
                .filter { visibleCalendarIDs.isEmpty || visibleCalendarIDs.contains($0.calendarIdentifier) }
            planningFixedCommitmentMinutes = PlanningCapacityCalculator().occupiedMinutes(
                workIntervals: workIntervals,
                commitments: commitments,
                visibleCalendarIdentifiers: visibleCalendarIDs
            )
            planningCapacityUsesCalendar = true
        } catch {
            planningFixedCommitmentMinutes = 0
            planningCapacityUsesCalendar = false
        }
    }

    private var canIssueExternalActions: Bool {
        let policy = currentPolicy()
        return databaseError == nil && !runtimeSafety.isReadOnly && !policy.automationPause.isPaused && policy.operatingMode != .observe
    }

    private var externalActionUnavailableMessage: String {
        if let databaseError { return databaseError }
        if runtimeSafety.isReadOnly {
            return "Zoid 666 is in read-only safety mode after a database write failure. Repair local storage before issuing Calendar or Reminders actions."
        }
        if currentPolicy().operatingMode == .observe {
            return "Zoid 666 is in Observe mode. Switch to Suggest, Assist, or Autonomous before changing Reminders or Calendar."
        }
        return "Zoid 666 automation is paused. Resume it in Settings before changing Reminders or Calendar."
    }
}

private enum AppModelPolicyError: Error {
    case policyStoreUnavailable
}

private enum AppModelPersistenceError: Error {
    case rejected
}

enum MeetingDestination: String, CaseIterable, Identifiable {
    case calendar = "Calendar"
    case reminder = "Reminder"

    var id: String { rawValue }
}

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case diagnostics = "Source health"
    case reviews = "Reviews"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: "checklist"
        case .diagnostics: "waveform.path.ecg"
        case .reviews: "doc.text.magnifyingglass"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum CoachingState: String {
    case observation = "Observation week"
    case accountability = "Level 2 coaching"
    case paused = "Coaching paused"
}

struct SourceHealth: Identifiable, Equatable, Sendable {
    let id: SourceID
    let title: String
    let eyebrow: String
    var state: HealthState
    var detail: String
    let evidence: String
    let actionTitle: String

    static let initial: [SourceHealth] = [
        SourceHealth(
            id: .reminders,
            title: "Apple Reminders",
            eyebrow: "Intent",
            state: .notConnected,
            detail: "Permission has not been requested",
            evidence: "EventKit adapter scaffolded",
            actionTitle: "Connect"
        ),
        SourceHealth(
            id: .notifications,
            title: "macOS Notifications",
            eyebrow: "Escalation",
            state: .notConnected,
            detail: "Notification permission has not been requested",
            evidence: "Required for morning plans and wake alerts",
            actionTitle: "Connect"
        ),
        SourceHealth(
            id: .agent,
            title: "Zoid 666 Agent",
            eyebrow: "Autonomy",
            state: .notConnected,
            detail: "Background planning has not been enabled",
            evidence: "The packaged app can register its overnight agent",
            actionTitle: "Enable"
        ),
        SourceHealth(
            id: .calendar,
            title: "Apple Calendar",
            eyebrow: "Capacity",
            state: .notConnected,
            detail: "Permission has not been requested",
            evidence: "EventKit scheduler is ready to connect",
            actionTitle: "Connect"
        ),
        SourceHealth(
            id: .screenwatch,
            title: "Screenwatch",
            eyebrow: "Behavior",
            state: .checking,
            detail: "Looking for today’s JSONL stream",
            evidence: "Expected at ~/screenwatch/days",
            actionTitle: "Inspect"
        ),
    ]
}

enum SourceID: String, CaseIterable, Sendable {
    case reminders
    case notifications
    case agent
    case calendar
    case screenwatch
}

enum HealthState: String, Sendable {
    case healthy = "Healthy"
    case checking = "Checking"
    case attention = "Attention"
    case notConnected = "Not connected"
    case unavailable = "Unavailable"

    var tone: HealthTone {
        switch self {
        case .healthy: .okay
        case .checking: .ink
        case .attention, .notConnected: .seal
        case .unavailable: .muted
        }
    }
}

enum HealthTone: Sendable {
    case okay
    case ink
    case seal
    case muted
}
