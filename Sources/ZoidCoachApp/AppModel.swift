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
    @Published private(set) var promptEpisodes: [PromptEpisode] = []
    @Published private(set) var actionAudit: [ActionAuditEntry] = []
    @Published private(set) var actionAuditError: String?
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var persistenceMessage: String?
    @Published private(set) var runtimeSafety: AgentRuntimeSafetySnapshot = .writable
    @Published private(set) var captureHealth: AgentCaptureHealthSnapshot?
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
    private(set) var qaOSFixtureAdapter: DeterministicOSFixtureAdapters?
    private var reminderTasksAreAvailable = false

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
        reminderListPolicyLoader: (@Sendable () throws -> ReminderListPolicy)? = nil
    ) {
        let resolvedAgentLaunchService = agentLaunchService
            ?? AgentLaunchService(runtimeEnvironment: runtimeEnvironment)
        todayDashboardXPCClient = TodayDashboardXPCClient(
            runtimeEnvironment: runtimeEnvironment
        )
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
            updateSource(agentLaunchService.inspect())
            updateSource(await notificationService.inspect())
            let screenwatch = await screenwatchReader.inspect()
            updateSource(screenwatch)
            lastCheckAt = Date()
            isCheckingSources = false
        }
    }

    func checkSource(_ sourceID: SourceID) {
        switch sourceID {
        case .screenwatch:
            Task { await refreshScreenwatch() }
        case .reminders:
            Task {
                let result = await remindersService.requestAccessAndInspect()
                updateSource(result)
                if result.state == .healthy {
                    await refreshReminderTasks()
                    selectedSection = .today
                }
            }
        case .calendar:
            Task {
                let result = await calendarService.requestAccessAndInspect()
                updateSource(result)
            }
        case .agent:
            updateSource(agentLaunchService.enableAndInspect())
        case .notifications:
            Task {
                updateSource(await notificationService.requestAccessAndInspect())
            }
        }
    }

    var calendarSelectionAvailability: CalendarSelectionAvailability {
        calendarService.selectionAvailability
    }

    func availableCalendarChoices() throws -> [CalendarChoice] {
        try calendarService.availableCalendars()
    }

    func requestCalendarAccess() async {
        updateSource(await calendarService.requestAccessAndInspect())
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
        Task {
            do {
                todaySnapshot = try await todayDashboardXPCClient.apply(command, taskID: taskID)
            } catch {
                calendarScheduleError = "The background agent is unavailable. Its last saved Today snapshot is still shown."
                todaySnapshot = try? todaySnapshotStore?.load()
            }
        }
    }

    func refreshPromptInbox() async {
        promptEpisodes = (try? await todayDashboardXPCClient.fetchPromptInbox()) ?? []
    }

    func refreshActionAudit() async {
        do {
            actionAudit = try await todayDashboardXPCClient.fetchActionAudit()
            actionAuditError = nil
        } catch {
            actionAuditError = "The automatic action ledger is unavailable. Check Agent source health and retry."
        }
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
        let command = PromptResponseCommand(
            promptID: episode.id,
            action: action,
            actionToken: PromptResponseToken.make(promptID: episode.id, action: action),
            surface: .dashboard
        )
        Task {
            do {
                _ = try await todayDashboardXPCClient.respondToPrompt(command)
                await refreshPromptInbox()
                if action == .editMeeting {
                    reloadMeetingCandidates()
                    selectedSection = .today
                }
            } catch {
                meetingCandidateError = "The prompt could not be resolved through the background agent."
            }
        }
    }

    func addToDailyPlan(_ task: ReminderTask) {
        guard !isLoadingDailyPlan,
              dailyPlan.count < 5,
              !dailyPlan.contains(where: { $0.reminderID == task.id })
        else { return }
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
        dailyPlan.removeAll { $0.reminderID == entry.reminderID }
        recordTaskHistory(entry.reminderID, state: .postponed)
        dailyPlan = dailyPlan.enumerated().map { index, entry in
            DailyPlanEntry(
                reminderID: entry.reminderID,
                rank: index + 1,
                isMainObjective: entry.isMainObjective,
                estimateMinutes: entry.estimateMinutes,
                selectionReason: entry.selectionReason,
                selectionScore: entry.selectionScore
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
                selectionScore: $0.selectionScore
            )
        }
        persistDailyPlan()
    }

    func setEstimate(_ minutes: Int, for entry: DailyPlanEntry) {
        guard !isLoadingDailyPlan else { return }
        dailyPlan = dailyPlan.map {
            DailyPlanEntry(
                reminderID: $0.reminderID,
                rank: $0.rank,
                isMainObjective: $0.isMainObjective,
                estimateMinutes: $0.reminderID == entry.reminderID ? minutes : $0.estimateMinutes,
                selectionReason: $0.selectionReason,
                selectionScore: $0.selectionScore
            )
        }
        persistDailyPlan()
    }

    func generateSuggestedDailyPlan() {
        guard !isLoadingDailyPlan,
              !isGeneratingSuggestedPlan,
              !reminderTasks.isEmpty
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

    func scheduleDailyPlan() {
        guard canIssueExternalActions,
              !isSchedulingDailyPlan,
              !dailyPlan.isEmpty
        else {
            calendarScheduleError = !canIssueExternalActions
                ? externalActionUnavailableMessage
                : "Draft a daily plan before reserving Calendar blocks."
            return
        }

        isSchedulingDailyPlan = true
        calendarScheduleError = nil
        Task {
            do {
                _ = try await todayDashboardXPCClient.apply(.schedulePlan(day: Date()))
                lastActionMessage = "The proposed work blocks were accepted and queued for Apple Calendar."
                await refreshActionAudit()
            } catch {
                calendarScheduleError = "The background agent could not queue Calendar blocks. Check Source health and try again."
            }
            isSchedulingDailyPlan = false
        }
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
                _ = try? await todayDashboardXPCClient.apply(
                    .synchronizeReminderSnapshots([])
                )
                isLoadingReminderTasks = false
                return
            }
            let tasks = reminderListPolicy.filteringExternalTasks(tasks, listID: { $0.listID })
            reminderTasksAreAvailable = true
            reminderTasks = tasks
            _ = try? await todayDashboardXPCClient.apply(
                .synchronizeReminderSnapshots(tasks.map {
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
            )
            reconcileDailyPlan(with: tasks)
        case .unavailable:
            reminderTasksAreAvailable = false
            reminderTasks = []
            reminderTaskError = "Apple Reminders access is unavailable. Connect it from Source health, then refresh tasks."
        }
        isLoadingReminderTasks = false
    }

    private func reloadDailyPlan() async {
        dailyPlan = await eventStore.loadDailyPlan()
        if reminderTasksAreAvailable {
            reconcileDailyPlan(with: reminderTasks)
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

    private func reconcileDailyPlan(with tasks: [ReminderTask]) {
        let incompleteIDs = Set(tasks.map(\.id))
        let reconciledPlan = dailyPlan.filter { incompleteIDs.contains($0.reminderID) }
        guard reconciledPlan != dailyPlan else { return }
        dailyPlan = reconciledPlan.enumerated().map { index, entry in
            DailyPlanEntry(
                reminderID: entry.reminderID,
                rank: index + 1,
                isMainObjective: entry.isMainObjective,
                estimateMinutes: entry.estimateMinutes,
                selectionReason: entry.selectionReason,
                selectionScore: entry.selectionScore
            )
        }
        if !dailyPlan.contains(where: \.isMainObjective), !dailyPlan.isEmpty {
            dailyPlan[0] = DailyPlanEntry(
                reminderID: dailyPlan[0].reminderID,
                rank: dailyPlan[0].rank,
                isMainObjective: true,
                estimateMinutes: dailyPlan[0].estimateMinutes,
                selectionReason: dailyPlan[0].selectionReason,
                selectionScore: dailyPlan[0].selectionScore
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
                selectionScore: $0.selectionScore
            )
        }
        Task {
            do {
                let receipt = try await todayDashboardXPCClient.apply(.replaceDailyPlan(items: items, day: Date()))
                guard receipt.accepted else { throw AppModelPersistenceError.rejected }
                persistenceMessage = nil
            } catch {
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

    private var canIssueExternalActions: Bool {
        let policy = currentPolicy()
        return databaseError == nil && !runtimeSafety.isReadOnly && !policy.automationPause.isPaused && policy.operatingMode != .observe
    }

    private var externalActionUnavailableMessage: String {
        if let databaseError { return databaseError }
        if runtimeSafety.isReadOnly {
            return "Zoid Coach is in read-only safety mode after a database write failure. Repair local storage before issuing Calendar or Reminders actions."
        }
        if currentPolicy().operatingMode == .observe {
            return "Zoid Coach is in Observe mode. Switch to Suggest, Assist, or Autonomous before changing Reminders or Calendar."
        }
        return "Zoid Coach automation is paused. Resume it in Settings before changing Reminders or Calendar."
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
            title: "Zoid Coach Agent",
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
