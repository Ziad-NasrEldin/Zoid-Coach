import Combine
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

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
    @Published var lastCheckAt: Date?
    @Published var isCheckingSources = false
    private let screenwatchReader: ScreenwatchReader
    private let remindersService: RemindersService
    private let calendarService: CalendarService
    private let atollService: AtollService
    private let notificationService: NotificationService
    private let agentLaunchService: AgentLaunchService
    private let eventStore: EventStore
    private let meetingArchive: ScreenwatchArchive?
    private let todaySnapshotStore: TodaySnapshotStore?
    private let policyStore: PolicyStore?
    private let todayDashboardXPCClient = TodayDashboardXPCClient()
    private var reminderTasksAreAvailable = false

    init(
        screenwatchReader: ScreenwatchReader = ScreenwatchReader(),
        remindersService: RemindersService = RemindersService(),
        calendarService: CalendarService = CalendarService(),
        atollService: AtollService = AtollService(),
        notificationService: NotificationService = NotificationService(),
        agentLaunchService: AgentLaunchService = AgentLaunchService(),
        eventStore: EventStore = EventStore(readOnly: true)
    ) {
        self.screenwatchReader = screenwatchReader
        self.remindersService = remindersService
        self.calendarService = calendarService
        self.atollService = atollService
        self.notificationService = notificationService
        self.agentLaunchService = agentLaunchService
        self.eventStore = eventStore
        meetingArchive = try? ScreenwatchArchive(databaseURL: ZoidCoachStorage.databaseURL(), readOnly: true)
        todaySnapshotStore = try? TodaySnapshotStore(databaseURL: ZoidCoachStorage.databaseURL(), readOnly: true)
        policyStore = try? PolicyStore(databaseURL: ZoidCoachStorage.databaseURL(), readOnly: true)
        Task {
            updateSource(agentLaunchService.enableAndInspect())
            await refreshAllSources()
            await refreshReminderTasks()
            await reloadDailyPlan()
            await reloadReminderListOrder()
            reloadMeetingCandidates()
            updateSource(await notificationService.inspect())
            await refreshTodaySnapshot()
            await refreshPromptInbox()
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
            let atoll = await atollService.inspect()
            updateSource(atoll)
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
        case .atoll:
            Task {
                let result = await atollService.authorizeAndPresentTest()
                updateSource(result)
            }
        }
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
        let atoll = await atollService.inspect()
        updateSource(atoll)
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
            meetingCandidates = try meetingArchive.unresolvedMeetingCandidates()
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
            _ = try? await todayDashboardXPCClient.apply(.replaceDailyPlan(items: items, day: Date()))
        }
    }

    private func reloadReminderListOrder() async {
        reminderListOrder = await eventStore.loadReminderListOrder()
        isLoadingReminderListOrder = false
    }

    private func persistReminderListOrder() {
        let order = reminderListOrder
        Task {
            _ = try? await todayDashboardXPCClient.apply(.replaceReminderListOrder(order))
        }
    }

    private func updateSource(_ result: SourceHealth) {
        guard let index = sources.firstIndex(where: { $0.id == result.id }) else { return }
        sources[index] = result
        lastCheckAt = Date()
        let checkedAt = Date()
        Task {
            _ = try? await todayDashboardXPCClient.apply(
                .recordSourceCheck(
                    sourceID: result.id.rawValue,
                    state: result.state.rawValue,
                    detail: result.detail,
                    evidence: result.evidence,
                    checkedAt: checkedAt
                )
            )
        }
    }

    private func recordTaskHistory(_ taskID: String, state: AgentTaskHistoryState) {
        Task {
            _ = try? await todayDashboardXPCClient.apply(
                .recordTaskHistory(taskID: taskID, state: state, occurredAt: Date())
            )
        }
    }

    private func currentPolicy() -> UserPolicy {
        guard let policyStore else { return UserPolicy.defaults() }
        do { return try policyStore.current()?.policy ?? UserPolicy.defaults() }
        catch { return UserPolicy.defaults() }
    }

    private var canIssueExternalActions: Bool {
        databaseError == nil && !currentPolicy().automationPause.isPaused
    }

    private var externalActionUnavailableMessage: String {
        if let databaseError { return databaseError }
        return "Zoid Coach automation is paused. Resume it in Settings before changing Reminders or Calendar."
    }
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
        SourceHealth(
            id: .atoll,
            title: "Atoll",
            eyebrow: "Intervention",
            state: .notConnected,
            detail: "Extension authorization is pending",
            evidence: "Installed app detected in next milestone",
            actionTitle: "Verify"
        )
    ]
}

enum SourceID: String, CaseIterable, Sendable {
    case reminders
    case notifications
    case agent
    case calendar
    case screenwatch
    case atoll
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
