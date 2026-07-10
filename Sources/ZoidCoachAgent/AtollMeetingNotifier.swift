import Foundation
import OSLog
import ZoidCoachCore
import ZoidCoachInfrastructure

struct AtollMeetingNotifier {
    func present(_ candidate: StoredMeetingCandidate) async {
        await AtollMeetingPromptRuntime.shared.present(candidateID: candidate.id)
    }
}

struct AtollPromptNotifier {
    func present(_ episode: PromptEpisode) async -> Bool {
        await AtollMeetingPromptRuntime.shared.present(episode: episode)
    }
}

actor AtollCommandCenterRuntime {
    static let shared = AtollCommandCenterRuntime()
    private let logger = Logger(subsystem: "com.ziadnasreldin.ZoidCoach", category: "AtollCommandCenter")
    private var bridge: AtollCommandCenterBridge?
    private var presentationTask: Task<Void, Never>?

    func start(_ bridge: AtollCommandCenterBridge) async {
        presentationTask?.cancel()
        self.bridge = bridge
        presentationTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                do {
                    try await bridge.present()
                    await AtollCommandCenterRuntime.shared.recordPresentation()
                    try await Task.sleep(for: .seconds(1_200))
                } catch {
                    await AtollCommandCenterRuntime.shared.recordFailure(error)
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        }
    }

    private func recordPresentation() {
        logger.info("A-Toll command center presented")
    }

    private func recordFailure(_ error: Error) {
        logger.error("A-Toll command center presentation failed: \(error.localizedDescription, privacy: .public)")
    }
}

private actor AtollMeetingPromptRuntime {
    static let shared = AtollMeetingPromptRuntime()

    private var promptStore: PromptInboxStore?
    private var activeBridges: [String: AtollPromptBridge] = [:]
    private var cleanupTasks: [String: Task<Void, Never>] = [:]

    func present(candidateID: String) async {
        do {
            let store: PromptInboxStore
            if let existingStore = promptStore {
                store = existingStore
            } else {
                let databaseURL = ZoidCoachStorage.databaseURL()
                let createdStore = try PromptInboxStore(databaseURL: databaseURL)
                promptStore = createdStore
                store = createdStore
            }
            guard let episode = try store.unresolved().first(where: { $0.payload["candidateID"] == candidateID }) else { return }
            _ = await present(episode: episode)
        } catch {
            // Notification and dashboard surfaces remain available when Atoll is unavailable.
        }
    }


    func present(episode: PromptEpisode) async -> Bool {
        do {
            if activeBridges[episode.id] != nil { return true }
            let databaseURL = ZoidCoachStorage.databaseURL()
            let store = try promptStore ?? PromptInboxStore(databaseURL: databaseURL)
            promptStore = store
            let promptBridge = AtollPromptBridge(
                promptStore: store,
                effectRouter: PromptResponseEffectRouter(
                    outbox: try ActionOutboxStore(databaseURL: databaseURL),
                    meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
                    planUndoRequests: try PlanUndoRequestStore(databaseURL: databaseURL),
                    planScheduleRequests: try PlanScheduleRequestStore(databaseURL: databaseURL),
                    promptStore: store,
                    schedulingCalendarIdentifier: {
                        try PolicyStore(databaseURL: databaseURL).current()?.policy.calendar.schedulingCalendarIdentifier
                    }
                )
            )
            activeBridges[episode.id] = promptBridge
            Task.detached(priority: .userInitiated) {
                do {
                    try await promptBridge.present(episode)
                } catch {
                    await AtollMeetingPromptRuntime.shared.removeBridge(promptID: episode.id)
                }
            }
            let lifetime = min(max(30, episode.expiresAt?.timeIntervalSinceNow ?? 10 * 60), 10 * 60)
            cleanupTasks[episode.id]?.cancel()
            cleanupTasks[episode.id] = Task.detached(priority: .utility) {
                try? await Task.sleep(for: .seconds(lifetime))
                guard !Task.isCancelled else { return }
                await AtollMeetingPromptRuntime.shared.removeBridge(promptID: episode.id)
            }
            return true
        } catch {
            // Notification and dashboard surfaces remain available when Atoll is unavailable.
            return false
        }
    }

    private func removeBridge(promptID: String) async {
        cleanupTasks.removeValue(forKey: promptID)?.cancel()
        guard let bridge = activeBridges.removeValue(forKey: promptID) else { return }
        await bridge.stop()
    }
}
