import AppKit
import SwiftUI
import ZoidCoachCore

struct TodayPromptInboxLedgerPresentation {
    enum Placement: Equatable {
        case beforeTaskDetail
        case afterTaskDetail
    }

    static func placement(for timeline: PromptInboxTimeline) -> Placement {
        timeline.awaitingResponse.isEmpty ? .afterTaskDetail : .beforeTaskDetail
    }

    static func shouldRefresh(_ timeline: PromptInboxTimeline) -> Bool {
        timeline.isEmpty
    }

    static func actions(for entry: PromptInboxTimelineEntry) -> PromptActionPublicInterface {
        PromptActionPublicInterface(promptID: entry.id, actions: entry.episode.actions)
    }

    static func historyIdentifier(for entry: PromptInboxTimelineEntry) -> String {
        "today.prompt.\(entry.id).history"
    }

    static func historyState(for entry: PromptInboxTimelineEntry) -> String {
        switch entry.episode.state {
        case .responded: entry.isReplay ? "ANSWERED · RETURNED" : "ANSWERED"
        case .timedOut: "EXPIRED"
        case .dismissed: "DISMISSED"
        case .detected, .queued, .presented: "WAITING"
        }
    }
}

struct TodayPromptInboxLedger: View {
    @EnvironmentObject private var model: AppModel
    private let timelineOverride: PromptInboxTimeline?
    private let refreshInboxOverride: (@MainActor () async -> Void)?
    @State private var confirmation: PromptConfirmation?
    @State private var rescheduleRequest: PromptTaskRescheduleRequest?
    @State private var rescheduleDate = TaskRescheduleState().selectedDate
    @State private var rescheduleError: String?
    @State private var blockRequest: PromptTaskBlockRequest?
    @State private var blockForm = PromptTaskBlockFormState()
    @FocusState private var blockReasonIsFocused: Bool

    init(
        timeline: PromptInboxTimeline? = nil,
        refreshInbox: (@MainActor () async -> Void)? = nil
    ) {
        timelineOverride = timeline
        refreshInboxOverride = refreshInbox
    }

    private var timeline: PromptInboxTimeline {
        timelineOverride ?? model.promptInboxTimeline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let status = model.promptInboxStatus {
                Text(status)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.softPaper)
                    .accessibilityIdentifier("today.prompt.action-status")
            }
            if let error = model.promptInboxError {
                HStack(spacing: 12) {
                    Text(error)
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.sealDeep)
                    Spacer()
                    Button("REFRESH") { Task { await model.refreshPromptInbox() } }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        .accessibilityIdentifier("today.prompt-inbox.refresh")
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(Sumi.sealWash)
            }
            if let rescheduleError, rescheduleRequest == nil {
                Text(rescheduleError)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.sealDeep)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.sealWash)
                    .accessibilityIdentifier("today.prompt.reschedule.error")
            }
            if let blockError = blockForm.errorMessage, blockRequest == nil {
                Text(blockError)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.sealDeep)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.sealWash)
                    .accessibilityIdentifier("today.prompt.block.error")
            }
            if timeline.isEmpty, model.promptInboxError == nil {
                Text("No decisions are waiting and no recent coaching choices are recorded yet.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("today.prompt-inbox.empty")
            }
            if !timeline.awaitingResponse.isEmpty {
                sectionLabel("AWAITING YOUR RESPONSE", count: timeline.awaitingResponse.count)
                ForEach(timeline.awaitingResponse) { entry in activeRow(entry) }
            }
            if !timeline.snoozed.isEmpty {
                sectionLabel("SNOOZED", count: timeline.snoozed.count)
                ForEach(timeline.snoozed) { entry in snoozedRow(entry) }
            }
            if !timeline.recent.isEmpty {
                sectionLabel("RECENT DECISIONS", count: timeline.recent.count)
                ForEach(timeline.recent) { entry in historyRow(entry) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.prompt-inbox")
        .onChange(of: model.promptInboxStatus) { _, status in
            guard let status, let application = NSApp else { return }
            NSAccessibility.post(
                element: application,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: status,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
        }
        .confirmationDialog(
            confirmation?.action.title ?? "Confirm this choice",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmation {
                Button(confirmation.action.title, role: confirmation.action.role == .destructive ? .destructive : nil) {
                    model.respondToPrompt(confirmation.episode, action: confirmation.action.kind)
                    self.confirmation = nil
                }
                Button("Cancel", role: .cancel) { self.confirmation = nil }
            }
        } message: {
            Text("This choice is saved once. Today refreshes from the durable result, and an older notification or other surface cannot apply it twice.")
        }
        .sheet(item: $rescheduleRequest) { request in
            promptRescheduleSheet(request)
        }
        .sheet(item: $blockRequest) { request in
            promptBlockSheet(request)
        }
        .task {
            guard TodayPromptInboxLedgerPresentation.shouldRefresh(timeline) else { return }
            if let refreshInboxOverride {
                await refreshInboxOverride()
            } else {
                await model.refreshPromptInbox()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("DECISIONS")
                .font(Sumi.label(9))
                .sumiLabelTracking()
            Spacer()
            Text("\(timeline.awaitingResponse.count) WAITING")
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(Sumi.mist)
        .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)")
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .foregroundStyle(Sumi.muted)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activeRow(_ entry: PromptInboxTimelineEntry) -> some View {
        let presentation = PromptActionPresentation(
            promptID: entry.episode.id,
            pendingPromptID: model.pendingPromptID,
            replayed: entry.isReplay
        )
        let interface = TodayPromptInboxLedgerPresentation.actions(for: entry)
        return VStack(alignment: .leading, spacing: 8) {
            promptHeading(entry, state: presentation.stateLabel)
            Text(entry.episode.summary).font(Sumi.body(12)).foregroundStyle(Sumi.muted)
            if let progressMessage = presentation.progressMessage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progressMessage)
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.prompt.\(entry.id).applying")
            }
            if !interface.taskChangeControls.isEmpty {
                Text("CHANGE THE TASK")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("today.prompt.\(entry.id).task-change-label")
                ForEach(interface.taskChangeControls) { control in
                    promptActionButton(control, episode: entry.episode, presentation: presentation)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !interface.recoveryControls.isEmpty {
                Text("RECOVERY OPTIONS")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("today.prompt.\(entry.id).recovery-label")
                ForEach(interface.recoveryControls) { control in
                    promptActionButton(control, episode: entry.episode, presentation: presentation)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if entry.episode.allowsDismissal {
                Button("DISMISS") { model.dismissPrompt(entry.episode) }
                    .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                    .disabled(presentation.actionsDisabled)
                    .accessibilityIdentifier("today.prompt.\(entry.id).dismiss")
            }
        }
        .promptRow(identifier: "today.prompt.\(entry.id).waiting")
    }

    private func promptActionButton(
        _ control: PromptActionPublicControl,
        episode: PromptEpisode,
        presentation: PromptActionPresentation
    ) -> some View {
        Button { choose(control.action, for: episode) } label: {
            HStack(spacing: 8) {
                Text(control.action.title.uppercased())
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
            .buttonStyle(SumiActionButtonStyle(role: actionRole(control.action.role), size: .compact))
            .disabled(presentation.actionsDisabled)
            .accessibilityHint(control.action.kind == .markBlocked
                ? "Opens a reason sheet. The coaching decision stays waiting until the blocker is saved."
                : "")
            .accessibilityIdentifier(control.accessibilityIdentifier)
    }

    private func snoozedRow(_ entry: PromptInboxTimelineEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            promptHeading(entry, state: "SNOOZED")
            Text(entry.episode.summary).font(Sumi.body(12)).foregroundStyle(Sumi.muted)
            if let availableAt = entry.availableAt {
                Text("Returns \(availableAt.formatted(date: .abbreviated, time: .shortened)).")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
            }
        }
        .promptRow(identifier: "today.prompt.\(entry.id).snoozed")
    }

    private func historyRow(_ entry: PromptInboxTimelineEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            promptHeading(entry, state: TodayPromptInboxLedgerPresentation.historyState(for: entry))
            Text(entry.episode.summary).font(Sumi.body(12)).foregroundStyle(Sumi.muted)
            if let response = entry.response {
                Text("CHOICE · \(response.action.rawValue.replacingOccurrences(of: "_", with: " ").uppercased()) · \(response.respondedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                if response.action == .markBlocked,
                   let reason = PromptTaskBlockedHistoryState.reason(for: entry.episode, in: model.dailyPlan) {
                    Text("BLOCKER · \(reason)")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.prompt.\(entry.id).history.blocked-reason")
                }
            }
        }
        .promptRow(identifier: TodayPromptInboxLedgerPresentation.historyIdentifier(for: entry))
    }

    private func promptHeading(_ entry: PromptInboxTimelineEntry, state: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.episode.title).font(Sumi.body(15)).foregroundStyle(Sumi.ink)
            Spacer(minLength: 12)
            Text(state).font(Sumi.label(8)).sumiLabelTracking().foregroundStyle(Sumi.muted)
        }
    }

    private func choose(_ action: PromptAction, for episode: PromptEpisode) {
        rescheduleError = nil
        blockForm.finishSubmission()
        if action.kind == .rescheduleTask {
            guard let request = PromptTaskRescheduleRequest(episode: episode) else {
                rescheduleError = "This prompt no longer identifies a task that can be rescheduled. Refresh Decisions."
                return
            }
            rescheduleDate = TaskRescheduleState().selectedDate
            rescheduleError = nil
            rescheduleRequest = request
            return
        }
        if action.kind == .markBlocked {
            guard let request = PromptTaskBlockRequest(episode: episode) else {
                blockForm.showError("This prompt no longer identifies a task that can be marked blocked. Refresh Decisions.")
                return
            }
            blockForm.cancel()
            blockRequest = request
            return
        }
        if action.requiresConfirmation || action.role == .destructive {
            confirmation = PromptConfirmation(episode: episode, action: action)
        } else {
            model.respondToPrompt(episode, action: action.kind)
        }
    }

    private func promptRescheduleSheet(_ request: PromptTaskRescheduleRequest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("RESCHEDULE FROM COACHING")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text(request.taskTitle)
                .font(Sumi.display(24))
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose a future planning date. Zoid 666 saves the local plan first, then queues the same Apple Reminders due date. The coaching decision stays open if either step cannot be accepted.")
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker(
                "New planning date",
                selection: $rescheduleDate,
                in: TaskRescheduleState().earliestDate...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .accessibilityIdentifier("today.prompt.reschedule.date")
            if let rescheduleError {
                Text(rescheduleError)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.prompt.reschedule.error")
            }
            HStack {
                Button("CANCEL") { rescheduleRequest = nil }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                Spacer()
                Button(model.pendingPromptID == request.episode.id ? "SAVING" : "CONFIRM NEW DATE") {
                    switch TaskRescheduleState().validated(rescheduleDate) {
                    case let .success(date):
                        Task {
                            if await model.rescheduleTaskFromPrompt(request.episode, until: date) {
                                rescheduleRequest = nil
                            } else {
                                rescheduleError = model.promptInboxError ?? "The task was not rescheduled. The coaching decision is still waiting."
                            }
                        }
                    case let .failure(error):
                        rescheduleError = error.message
                    }
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                .disabled(model.pendingPromptID != nil)
                .accessibilityIdentifier("today.prompt.reschedule.confirm")
            }
        }
        .padding(24)
        .frame(width: 440)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.prompt.reschedule.sheet")
    }

    private func promptBlockSheet(_ request: PromptTaskBlockRequest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("MARK BLOCKED FROM COACHING")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text(request.taskTitle)
                .font(Sumi.display(24))
                .fixedSize(horizontal: false, vertical: true)
            Text("Describe the external dependency or decision that prevents progress. Zoid 666 saves this reason with the task, pauses active work, revises today's objective when needed, and keeps this coaching decision open if the mutation fails.")
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("CHOOSE A COMMON REASON OR WRITE YOUR OWN")
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
            ForEach(PromptTaskBlockReasonSuggestion.allCases) { suggestion in
                Button { blockForm.select(suggestion) } label: {
                    HStack(spacing: 8) {
                        Text(suggestion.title)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .disabled(blockForm.isSubmitting)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHint("Fills the blocker reason with: \(suggestion.reason)")
                    .accessibilityIdentifier("today.prompt.block.suggestion.\(suggestion.rawValue)")
            }
            TextEditor(text: $blockForm.reason)
                .font(Sumi.body(13))
                .frame(height: 104)
                .padding(8)
                .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                .focused($blockReasonIsFocused)
                .accessibilityLabel("What is blocking this task")
                .accessibilityHint("Enter between 3 and 240 characters.")
                .accessibilityIdentifier("today.prompt.block.reason")
            HStack {
                Text("3-240 CHARACTERS REQUIRED")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("today.prompt.block.requirement")
                Spacer()
                Text("\(blockForm.reason.count) / \(PromptTaskBlockReasonState.maximumLength)")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(blockForm.reason.count > PromptTaskBlockReasonState.maximumLength ? Sumi.sealDeep : Sumi.muted)
            }
            if let blockError = blockForm.errorMessage {
                Text(blockError)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.prompt.block.error")
            }
            HStack {
                Button("CANCEL") {
                    blockForm.cancel()
                    blockRequest = nil
                }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .accessibilityIdentifier("today.prompt.block.cancel")
                Spacer()
                Button(blockForm.isSubmitting || model.pendingPromptID == request.episode.id ? "SAVING" : "SAVE BLOCKER") {
                    switch blockForm.beginSubmission() {
                    case let .success(reason):
                        Task {
                            if await model.blockTaskFromPrompt(request.episode, reason: reason) {
                                blockForm.finishSubmission()
                                blockRequest = nil
                            } else {
                                blockForm.finishSubmission(error: model.promptInboxError ?? model.taskCommandError ?? "The blocker was not saved. The coaching decision is still waiting.")
                            }
                        }
                    case .failure:
                        break
                    }
                }
                .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .standard))
                .disabled(blockForm.isSubmitting || model.pendingPromptID != nil)
                .accessibilityIdentifier("today.prompt.block.confirm")
            }
        }
        .padding(24)
        .frame(width: 440)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.prompt.block.sheet")
        .task { blockReasonIsFocused = true }
    }

    private func actionRole(_ role: PromptActionRole) -> SumiActionRole {
        switch role {
        case .primary: .primary
        case .secondary: .quiet
        case .destructive: .destructive
        }
    }
}

private struct PromptConfirmation {
    let episode: PromptEpisode
    let action: PromptAction
}

private extension View {
    func promptRow(identifier: String) -> some View {
        padding(.horizontal, 28)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }
}
