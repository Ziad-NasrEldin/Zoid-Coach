import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore
import ZoidCoachInfrastructure

@Test
func promptTaskBlockRequestRequiresExplicitActionAndTaskIdentity() throws {
    let valid = promptEpisode(
        id: "valid",
        actions: [.init(kind: .markBlocked, title: "Mark blocked")],
        payload: ["taskID": "task-1", "taskTitle": "Prepare release"]
    )
    let missingTask = promptEpisode(
        id: "missing-task",
        actions: [.init(kind: .markBlocked, title: "Mark blocked")]
    )
    let wrongAction = promptEpisode(
        id: "wrong-action",
        actions: [.init(kind: .pauseTask, title: "Pause")],
        payload: ["taskID": "task-1"]
    )

    let request = try #require(PromptTaskBlockRequest(episode: valid))
    #expect(request.taskID == "task-1")
    #expect(request.taskTitle == "Prepare release")
    #expect(PromptTaskBlockRequest(episode: missingTask) == nil)
    #expect(PromptTaskBlockRequest(episode: wrongAction) == nil)
}

@Test
func promptTaskBlockReasonTrimsMeaningfulCopyAndRejectsUnsafeLengths() throws {
    let state = PromptTaskBlockReasonState()

    #expect(try state.validated("  Waiting for client approval.  ").get() == "Waiting for client approval.")
    #expect(state.validated("no") == .failure(.tooShort))
    #expect(state.validated(String(repeating: "x", count: 241)) == .failure(.tooLong))
    #expect(try state.validated(String(repeating: "x", count: 240)).get().count == 240)
}

@Test
func promptActionReachabilityMovesTaskChangesAheadWithoutDuplicatingActions() throws {
    let original: [PromptAction] = [
        .init(kind: .returnToActiveTask, title: "Return"),
        .init(kind: .startWorkSprint, title: "Sprint"),
        .init(kind: .startBreak, title: "Break"),
        .init(kind: .rescheduleTask, title: "Reschedule", role: .destructive),
        .init(kind: .markBlocked, title: "Mark blocked", role: .destructive),
        .init(kind: .continueIntentionally, title: "Continue")
    ]

    let layout = PromptActionReachabilityLayout(actions: original)

    #expect(layout.taskChangeActions.map(\.kind) == [.rescheduleTask, .markBlocked])
    #expect(layout.recoveryActions.map(\.kind) == [
        .returnToActiveTask,
        .startWorkSprint,
        .startBreak,
        .continueIntentionally
    ])
    #expect(Set((layout.taskChangeActions + layout.recoveryActions).map(\.id)).count == original.count)
    #expect(layout.taskChangeActions.count + layout.recoveryActions.count == original.count)
}

@Test
func promptActionPublicInterfaceMakesEveryChoiceADirectStableControl() throws {
    let original: [PromptAction] = [
        .init(kind: .returnToActiveTask, title: "Return"),
        .init(kind: .startWorkSprint, title: "Sprint", role: .primary),
        .init(kind: .startBreak, title: "Break"),
        .init(kind: .rescheduleTask, title: "Reschedule", role: .destructive),
        .init(kind: .markBlocked, title: "Mark blocked", role: .destructive),
        .init(kind: .continueIntentionally, title: "Continue")
    ]

    let interface = PromptActionPublicInterface(promptID: "qa-block-1", actions: original)

    #expect(interface.presentation == .directButtonList)
    #expect(interface.controls.map(\.action.kind) == [
        .rescheduleTask,
        .markBlocked,
        .returnToActiveTask,
        .startWorkSprint,
        .startBreak,
        .continueIntentionally
    ])
    #expect(interface.controls.map(\.accessibilityIdentifier) == [
        "today.prompt.qa-block-1.action.reschedule_task",
        "today.prompt.qa-block-1.action.mark_blocked",
        "today.prompt.qa-block-1.action.return_to_active_task",
        "today.prompt.qa-block-1.action.start_work_sprint",
        "today.prompt.qa-block-1.action.start_break",
        "today.prompt.qa-block-1.action.continue_intentionally"
    ])
    #expect(Set(interface.controls.map(\.accessibilityIdentifier)).count == original.count)
}

@Test
func todayPromptActionSurfaceDoesNotVirtualizePublicControls() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let activeRowStart = try #require(source.range(of: "private func activeRow"))
    let actionButtonStart = try #require(source.range(of: "private func promptActionButton"))
    let activeRow = source[activeRowStart.lowerBound..<actionButtonStart.lowerBound]

    #expect(!activeRow.contains("LazyVGrid"))
    #expect(activeRow.contains("ForEach(interface.taskChangeControls)"))
    #expect(activeRow.contains("ForEach(interface.recoveryControls)"))
}

@MainActor
@Test
func todayLoadsDelayedPromptTimelineIntoSixDirectRenderedActions() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-prompt-render-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:]
    ).environment
    let model = AppModel(
        runtimeEnvironment: runtime,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: runtime,
            service: PromptRenderNoopAgentRegistration()
        ),
        synchronizeReminderSnapshots: { _ in }
    )
    let episode = promptEpisode(
        id: "qa-block-1",
        actions: [
            .init(kind: .returnToActiveTask, title: "Return"),
            .init(kind: .startWorkSprint, title: "Sprint", role: .primary),
            .init(kind: .startBreak, title: "Break"),
            .init(kind: .rescheduleTask, title: "Reschedule", role: .destructive),
            .init(kind: .markBlocked, title: "Mark blocked", role: .destructive),
            .init(kind: .continueIntentionally, title: "Continue")
        ],
        payload: ["taskID": "task-1", "taskTitle": "Prepare release"]
    )
    let expected = Set(episode.actions.map {
        "today.prompt.qa-block-1.action.\($0.kind.rawValue)"
    })
    let host = NSHostingView(
        rootView: DelayedPromptTodayFixture(
            loadedTimeline: PromptInboxTimeline(
                awaitingResponse: [.init(episode: episode)]
            )
        )
        .environmentObject(model)
    )
    let window = NSWindow(
        contentRect: NSRect(x: 80, y: 80, width: 900, height: 700),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }

    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    var rendered = Set<String>()
    repeat {
        host.layoutSubtreeIfNeeded()
        rendered = Set(promptRenderAXDescendants().compactMap { element in
            guard promptRenderAXString(element, kAXRoleAttribute as CFString) == kAXButtonRole as String
            else { return nil }
            let identifier = promptRenderAXString(element, kAXIdentifierAttribute as CFString)
            return identifier.hasPrefix("today.prompt.qa-block-1.action.") ? identifier : nil
        })
        if rendered == expected { break }
        try await Task.sleep(for: .milliseconds(20))
    } while ContinuousClock.now < deadline

    #expect(rendered == expected)
    withExtendedLifetime(window) {}
}

@MainActor
@Test
func todayPromptPlacementRefreshesOnceAndKeepsResolvedHistoryVisible() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-prompt-placement-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:]
    ).environment
    let model = AppModel(
        runtimeEnvironment: runtime,
        agentLaunchService: AgentLaunchService(
            runtimeEnvironment: runtime,
            service: PromptRenderNoopAgentRegistration()
        ),
        synchronizeReminderSnapshots: { _ in }
    )
    let episode = promptEpisode(
        id: "qa-placement-1",
        actions: [
            .init(kind: .returnToActiveTask, title: "Return"),
            .init(kind: .startWorkSprint, title: "Sprint", role: .primary),
            .init(kind: .startBreak, title: "Break"),
            .init(kind: .rescheduleTask, title: "Reschedule", role: .destructive),
            .init(kind: .markBlocked, title: "Mark blocked", role: .destructive),
            .init(kind: .continueIntentionally, title: "Continue")
        ],
        payload: ["taskID": "task-1", "taskTitle": "Prepare release"]
    )
    let state = PromptPlacementFixtureState(waitingEpisode: episode)
    let host = NSHostingView(
        rootView: PromptConditionalPlacementFixture(state: state)
            .environmentObject(model)
    )
    let window = NSWindow(
        contentRect: NSRect(x: 80, y: 80, width: 900, height: 700),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }

    let waitingIdentifier = "today.prompt.qa-placement-1.action.mark_blocked"
    let waitingDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    repeat {
        host.layoutSubtreeIfNeeded()
        if promptRenderAXDescendants().contains(where: {
            promptRenderAXString($0, kAXIdentifierAttribute as CFString) == waitingIdentifier
        }) { break }
        try await Task.sleep(for: .milliseconds(20))
    } while ContinuousClock.now < waitingDeadline

    #expect(state.refreshCount == 1)
    state.resolveAsBlocked()

    let historyIdentifier = "today.prompt.qa-placement-1.history"
    let historyDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    var historyIsVisible = false
    repeat {
        host.layoutSubtreeIfNeeded()
        historyIsVisible = promptRenderAXDescendants().contains {
            promptRenderAXString($0, kAXIdentifierAttribute as CFString) == historyIdentifier
        }
        if historyIsVisible { break }
        try await Task.sleep(for: .milliseconds(20))
    } while ContinuousClock.now < historyDeadline

    try await Task.sleep(for: .milliseconds(100))
    #expect(historyIsVisible)
    #expect(state.refreshCount == 1)
    withExtendedLifetime(window) {}
}

@Test
func promptBlockFormRejectsEmptyInputAndPreventsDuplicateSubmission() throws {
    var form = PromptTaskBlockFormState()

    #expect(form.beginSubmission() == .failure(.tooShort))
    #expect(form.errorMessage == "Explain the blocker in at least 3 characters.")
    #expect(!form.isSubmitting)

    form.reason = "  Waiting for client approval.  "
    #expect(form.beginSubmission() == .success("Waiting for client approval."))
    #expect(form.isSubmitting)
    #expect(form.beginSubmission() == .failure(.alreadySubmitting))

    form.finishSubmission(error: "The helper is unavailable.")
    #expect(!form.isSubmitting)
    #expect(form.errorMessage == "The helper is unavailable.")

    form.cancel()
    #expect(form == PromptTaskBlockFormState())
}

@Test
func promptBlockFailurePresentationSurvivesInboxRefreshOutcome() {
    let presentation = PromptTaskBlockFailurePresentation(
        taskCommandError: "The blocker was not saved. The last confirmed task and plan state are still shown."
    )

    #expect(presentation.restoring(afterInboxRefreshError: nil) ==
        "The blocker was not saved. The last confirmed task and plan state are still shown.")
    #expect(presentation.restoring(afterInboxRefreshError:
        "Decisions could not be refreshed. The last confirmed inbox remains visible.") ==
        "The blocker was not saved. The last confirmed task and plan state are still shown.")
}

@Test
func promptBlockReasonSuggestionsAreValidAndHistoryFindsThePersistedReason() throws {
    for suggestion in PromptTaskBlockReasonSuggestion.allCases {
        #expect(try PromptTaskBlockReasonState().validated(suggestion.reason).get() == suggestion.reason)
    }

    let episode = promptEpisode(
        id: "blocked-history",
        actions: [.init(kind: .markBlocked, title: "Mark blocked")],
        payload: ["taskID": "task-1", "taskTitle": "Prepare release"]
    )
    let plan = [
        DailyPlanEntry(
            reminderID: "task-1",
            rank: 0,
            isMainObjective: false,
            estimateMinutes: 30,
            blockedReason: "Waiting for client approval."
        )
    ]

    #expect(PromptTaskBlockedHistoryState.reason(for: episode, in: plan) == "Waiting for client approval.")
    #expect(PromptTaskBlockedHistoryState.reason(for: promptEpisode(id: "other", actions: []), in: plan) == nil)
}

private func promptEpisode(
    id: String,
    actions: [PromptAction],
    payload: [String: String] = [:]
) -> PromptEpisode {
    PromptEpisode(
        id: id,
        decisionKey: "block:\(id)",
        type: "GAMING_DRIFT",
        state: .presented,
        title: "Task needs attention",
        summary: "Choose what should happen next.",
        actions: actions,
        payload: payload,
        createdAt: Date()
    )
}

private struct DelayedPromptTodayFixture: View {
    @State private var timeline = PromptInboxTimeline.empty
    let loadedTimeline: PromptInboxTimeline

    var body: some View {
        ScrollView {
            TodayPromptInboxLedger(
                timeline: timeline,
                refreshInbox: { timeline = loadedTimeline }
            )
        }
    }
}

@MainActor
private final class PromptPlacementFixtureState: ObservableObject {
    @Published var timeline = PromptInboxTimeline.empty
    private(set) var refreshCount = 0
    private let waitingEpisode: PromptEpisode

    init(waitingEpisode: PromptEpisode) {
        self.waitingEpisode = waitingEpisode
    }

    func refresh() async {
        refreshCount += 1
        guard refreshCount == 1 else { return }
        timeline = PromptInboxTimeline(
            awaitingResponse: [.init(episode: waitingEpisode)]
        )
    }

    func resolveAsBlocked() {
        let respondedAt = Date()
        let resolvedEpisode = PromptEpisode(
            id: waitingEpisode.id,
            decisionKey: waitingEpisode.decisionKey,
            type: waitingEpisode.type,
            state: .responded,
            title: waitingEpisode.title,
            summary: waitingEpisode.summary,
            actions: waitingEpisode.actions,
            payload: waitingEpisode.payload,
            createdAt: waitingEpisode.createdAt,
            presentedAt: waitingEpisode.presentedAt,
            resolvedAt: respondedAt
        )
        timeline = PromptInboxTimeline(
            recent: [
                .init(
                    episode: resolvedEpisode,
                    response: PromptResponse(
                        id: "response-qa-placement-1",
                        promptID: waitingEpisode.id,
                        action: .markBlocked,
                        actionToken: PromptResponseToken.make(
                            promptID: waitingEpisode.id,
                            action: .markBlocked
                        ),
                        surface: .dashboard,
                        respondedAt: respondedAt
                    )
                )
            ]
        )
    }
}

private struct PromptConditionalPlacementFixture: View {
    @ObservedObject var state: PromptPlacementFixtureState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !state.timeline.awaitingResponse.isEmpty {
                    ledger
                }
                Text("TODAY DETAIL")
                if state.timeline.awaitingResponse.isEmpty {
                    ledger
                }
            }
        }
    }

    private var ledger: some View {
        TodayPromptInboxLedger(
            timeline: state.timeline,
            refreshInbox: state.refresh
        )
    }
}

@MainActor
private final class PromptRenderNoopAgentRegistration: AgentServiceRegistration {
    var status: AgentRegistrationStatus = .notRegistered
    func register() { status = .enabled }
    func unregister() { status = .notRegistered }
}

private func promptRenderAXAttribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &result) == .success else { return nil }
    return result
}

private func promptRenderAXString(_ element: AXUIElement, _ name: CFString) -> String {
    promptRenderAXAttribute(element, name) as? String ?? ""
}

private func promptRenderAXDescendants() -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue = [AXUIElementCreateApplication(getpid())]
    var seen = Set<CFHashCode>()
    while !queue.isEmpty, result.count < 4_000 {
        let element = queue.removeFirst()
        guard seen.insert(CFHash(element)).inserted else { continue }
        result.append(element)
        for attribute in [kAXChildrenAttribute as CFString, kAXWindowsAttribute as CFString] {
            queue.append(contentsOf: promptRenderAXAttribute(element, attribute) as? [AXUIElement] ?? [])
        }
    }
    return result
}
