import SwiftUI
import ZoidCoachCore

struct TodayPromptInboxLedger: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmation: PromptConfirmation?
    @State private var rescheduleRequest: PromptTaskRescheduleRequest?
    @State private var rescheduleDate = TaskRescheduleState().selectedDate
    @State private var rescheduleError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
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
            if model.promptInboxTimeline.isEmpty, model.promptInboxError == nil {
                Text("No decisions are waiting and no recent coaching choices are recorded yet.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("today.prompt-inbox.empty")
            }
            if !model.promptInboxTimeline.awaitingResponse.isEmpty {
                sectionLabel("AWAITING YOUR RESPONSE", count: model.promptInboxTimeline.awaitingResponse.count)
                ForEach(model.promptInboxTimeline.awaitingResponse) { entry in activeRow(entry) }
            }
            if !model.promptInboxTimeline.snoozed.isEmpty {
                sectionLabel("SNOOZED", count: model.promptInboxTimeline.snoozed.count)
                ForEach(model.promptInboxTimeline.snoozed) { entry in snoozedRow(entry) }
            }
            if !model.promptInboxTimeline.recent.isEmpty {
                sectionLabel("RECENT DECISIONS", count: model.promptInboxTimeline.recent.count)
                ForEach(model.promptInboxTimeline.recent) { entry in historyRow(entry) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.prompt-inbox")
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
    }

    private var header: some View {
        HStack {
            Text("DECISIONS")
                .font(Sumi.label(9))
                .sumiLabelTracking()
            Spacer()
            Text("\(model.promptInboxTimeline.awaitingResponse.count) WAITING")
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
            HStack(spacing: 8) {
                ForEach(entry.episode.actions) { action in
                    Button(action.title.uppercased()) { choose(action, for: entry.episode) }
                        .buttonStyle(SumiActionButtonStyle(role: actionRole(action.role), size: .compact))
                        .disabled(presentation.actionsDisabled)
                        .accessibilityIdentifier("today.prompt.\(entry.id).action.\(action.kind.rawValue)")
                }
                if entry.episode.allowsDismissal {
                    Button("DISMISS") { model.dismissPrompt(entry.episode) }
                        .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                        .disabled(presentation.actionsDisabled)
                        .accessibilityIdentifier("today.prompt.\(entry.id).dismiss")
                }
            }
        }
        .promptRow(identifier: "today.prompt.\(entry.id).waiting")
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
            promptHeading(entry, state: historyState(entry))
            Text(entry.episode.summary).font(Sumi.body(12)).foregroundStyle(Sumi.muted)
            if let response = entry.response {
                Text("CHOICE · \(response.action.rawValue.replacingOccurrences(of: "_", with: " ").uppercased()) · \(response.respondedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
        }
        .promptRow(identifier: "today.prompt.\(entry.id).history")
    }

    private func promptHeading(_ entry: PromptInboxTimelineEntry, state: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.episode.title).font(Sumi.body(15)).foregroundStyle(Sumi.ink)
            Spacer(minLength: 12)
            Text(state).font(Sumi.label(8)).sumiLabelTracking().foregroundStyle(Sumi.muted)
        }
    }

    private func historyState(_ entry: PromptInboxTimelineEntry) -> String {
        switch entry.episode.state {
        case .responded: entry.isReplay ? "ANSWERED · RETURNED" : "ANSWERED"
        case .timedOut: "EXPIRED"
        case .dismissed: "DISMISSED"
        case .detected, .queued, .presented: "WAITING"
        }
    }

    private func choose(_ action: PromptAction, for episode: PromptEpisode) {
        rescheduleError = nil
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
