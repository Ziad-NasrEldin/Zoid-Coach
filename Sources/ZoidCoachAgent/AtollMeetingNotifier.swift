import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

struct AtollMeetingNotifier {
    func present(_ candidate: StoredMeetingCandidate) async {
        await AtollMeetingPromptRuntime.shared.present(candidateID: candidate.id)
    }
}

struct AtollPromptNotifier {
    func present(_ episode: PromptEpisode) async {
        await AtollMeetingPromptRuntime.shared.present(episode: episode)
    }
}

private actor AtollMeetingPromptRuntime {
    static let shared = AtollMeetingPromptRuntime()

    private var bridge: AtollPromptBridge?
    private var promptStore: PromptInboxStore?

    func present(candidateID: String) async {
        do {
            let store: PromptInboxStore
            let promptBridge: AtollPromptBridge
            if let existingStore = promptStore, let existingBridge = bridge {
                store = existingStore
                promptBridge = existingBridge
            } else {
                let databaseURL = ZoidCoachStorage.databaseURL()
                let archive = try ScreenwatchArchive(databaseURL: databaseURL)
                let createdStore = try PromptInboxStore(databaseURL: databaseURL)
                let outbox = try ActionOutboxStore(databaseURL: databaseURL)
                let createdBridge = AtollPromptBridge(
                    promptStore: createdStore,
                    effectRouter: PromptResponseEffectRouter(
                        outbox: outbox,
                        meetingArchive: archive,
                        planUndoRequests: try PlanUndoRequestStore(databaseURL: databaseURL)
                    )
                )
                promptStore = createdStore
                bridge = createdBridge
                store = createdStore
                promptBridge = createdBridge
            }
            guard let episode = try store.unresolved().first(where: { $0.payload["candidateID"] == candidateID }) else { return }
            try await promptBridge.present(episode)
        } catch {
            // Notification and dashboard surfaces remain available when Atoll is unavailable.
        }
    }


    func present(episode: PromptEpisode) async {
        do {
            let promptBridge: AtollPromptBridge
            if let bridge {
                promptBridge = bridge
            } else {
                let databaseURL = ZoidCoachStorage.databaseURL()
                let archive = try ScreenwatchArchive(databaseURL: databaseURL)
                let createdStore = try PromptInboxStore(databaseURL: databaseURL)
                let outbox = try ActionOutboxStore(databaseURL: databaseURL)
                let createdBridge = AtollPromptBridge(
                    promptStore: createdStore,
                    effectRouter: PromptResponseEffectRouter(
                        outbox: outbox,
                        meetingArchive: archive,
                        planUndoRequests: try PlanUndoRequestStore(databaseURL: databaseURL)
                    )
                )
                promptStore = createdStore
                bridge = createdBridge
                promptBridge = createdBridge
            }
            try await promptBridge.present(episode)
        } catch {
            // Notification and dashboard surfaces remain available when Atoll is unavailable.
        }
    }
}
