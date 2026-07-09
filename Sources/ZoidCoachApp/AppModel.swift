import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .diagnostics
    @Published var coachingState: CoachingState = .observation
    @Published var sources: [SourceHealth] = SourceHealth.initial
    @Published var reminderTasks: [ReminderTask] = []
    @Published var dailyPlan: [DailyPlanEntry] = []
    @Published var isLoadingReminderTasks = false
    @Published private(set) var isLoadingDailyPlan = true
    @Published var reminderTaskError: String?
    @Published var lastCheckAt: Date?
    @Published var isCheckingSources = false
    private let screenwatchReader: ScreenwatchReader
    private let remindersService: RemindersService
    private let atollService: AtollService
    private let eventStore: EventStore
    private var reminderTasksAreAvailable = false
    private var planWriteTask: Task<Void, Never>?

    init(
        screenwatchReader: ScreenwatchReader = ScreenwatchReader(),
        remindersService: RemindersService = RemindersService(),
        atollService: AtollService = AtollService(),
        eventStore: EventStore = EventStore()
    ) {
        self.screenwatchReader = screenwatchReader
        self.remindersService = remindersService
        self.atollService = atollService
        self.eventStore = eventStore
        Task {
            await refreshAllSources()
            await refreshReminderTasks()
            await reloadDailyPlan()
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
        Task {
            let completed = await remindersService.completeTask(id: task.id)
            if completed {
                await refreshReminderTasks()
                dailyPlan.removeAll { $0.reminderID == task.id }
                persistDailyPlan()
            } else {
                reminderTaskError = "Could not complete \"\(task.title)\". Refresh and try again."
            }
        }
    }

    func addToDailyPlan(_ task: ReminderTask) {
        guard !isLoadingDailyPlan,
              dailyPlan.count < 3,
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
        persistDailyPlan()
    }

    func removeFromDailyPlan(_ entry: DailyPlanEntry) {
        guard !isLoadingDailyPlan else { return }
        dailyPlan.removeAll { $0.reminderID == entry.reminderID }
        dailyPlan = dailyPlan.enumerated().map { index, entry in
            DailyPlanEntry(
                reminderID: entry.reminderID,
                rank: index + 1,
                isMainObjective: entry.isMainObjective,
                estimateMinutes: entry.estimateMinutes
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
                estimateMinutes: $0.estimateMinutes
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
                estimateMinutes: $0.reminderID == entry.reminderID ? minutes : $0.estimateMinutes
            )
        }
        persistDailyPlan()
    }

    private func refreshAllSources() async {
        let reminders = await remindersService.inspect()
        updateSource(reminders)
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

    private func reconcileDailyPlan(with tasks: [ReminderTask]) {
        let incompleteIDs = Set(tasks.map(\.id))
        let reconciledPlan = dailyPlan.filter { incompleteIDs.contains($0.reminderID) }
        guard reconciledPlan != dailyPlan else { return }
        dailyPlan = reconciledPlan.enumerated().map { index, entry in
            DailyPlanEntry(
                reminderID: entry.reminderID,
                rank: index + 1,
                isMainObjective: entry.isMainObjective,
                estimateMinutes: entry.estimateMinutes
            )
        }
        if !dailyPlan.contains(where: \.isMainObjective), !dailyPlan.isEmpty {
            dailyPlan[0] = DailyPlanEntry(
                reminderID: dailyPlan[0].reminderID,
                rank: dailyPlan[0].rank,
                isMainObjective: true,
                estimateMinutes: dailyPlan[0].estimateMinutes
            )
        }
        persistDailyPlan()
    }

    private func persistDailyPlan() {
        let entries = dailyPlan
        let previousWrite = planWriteTask
        planWriteTask = Task { [eventStore] in
            await previousWrite?.value
            await eventStore.replaceDailyPlan(entries)
        }
    }

    private func updateSource(_ result: SourceHealth) {
        guard let index = sources.firstIndex(where: { $0.id == result.id }) else { return }
        sources[index] = result
        lastCheckAt = Date()
        Task { await eventStore.recordSourceCheck(result) }
    }
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
