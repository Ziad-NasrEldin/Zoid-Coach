import SwiftUI
import ApplicationServices
import CoreGraphics
import UniformTypeIdentifiers
import ZoidCoachCore
import ZoidCoachInfrastructure

enum MeetingCandidateCardContext {
    static func text(for candidate: StoredMeetingCandidate) -> String {
        let participants = candidate.participants.isEmpty ? "Participants unknown" : candidate.participants.joined(separator: ", ")
        let place = candidate.location ?? candidate.callLink ?? "No location"
        let evidence = candidate.sourceEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Conversation evidence unavailable"
            : "Encrypted conversation evidence is available in Zoid 666"
        return "\(participants) · \(place) · \(candidate.timezoneIdentifier)\nSource: WhatsApp\n\(evidence)"
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var modalCoordinator = SumiModalCoordinator()
    @State private var editingMeetingCandidate: StoredMeetingCandidate?
    @State private var isCreatingLocalTask = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 218)

                Divider()

                ScrollView {
                    Group {
                        if model.selectedSection == .today {
                            TodayCommandView(
                                editingCandidate: $editingMeetingCandidate,
                                createLocalTask: { isCreatingLocalTask = true }
                            )
                        } else if model.selectedSection == .reviews {
                            DailyReviewView()
                        } else if model.selectedSection == .settings {
                            SettingsView()
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                CommandHeaderView()
                                FoundationHeroView()
                                SourceHealthLedgerView()
                                LocalFoundationView()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Sumi.paper)
            }
            .environmentObject(modalCoordinator)

            if model.calendarPlanApproval.isPresented {
                SumiModalOverlay(dismiss: model.dismissCalendarPlanApproval) {
                    CalendarPlanApprovalSheet()
                }
            } else if isCreatingLocalTask {
                SumiModalOverlay(dismiss: { isCreatingLocalTask = false }) {
                    LocalTaskCreationView {
                        isCreatingLocalTask = false
                        Task {
                            await model.reloadDailyPlan()
                            await model.refreshTodaySnapshot()
                        }
                    } cancel: {
                        isCreatingLocalTask = false
                    }
                }
            } else if let candidate = editingMeetingCandidate {
                SumiModalOverlay(dismiss: {
                    model.deferMeetingCandidateEdit(candidate)
                    editingMeetingCandidate = nil
                }) {
                    MeetingCandidateEditor(candidate: candidate) { title, start, duration, destination in
                        model.saveMeetingCandidate(
                            candidate,
                            title: title,
                            start: start,
                            durationMinutes: duration,
                            destination: destination
                        )
                        editingMeetingCandidate = nil
                    } onCancel: {
                        model.deferMeetingCandidateEdit(candidate)
                        editingMeetingCandidate = nil
                    }
                }
            } else if let request = modalCoordinator.confirmation {
                SumiModalOverlay(dismiss: request.cancel) {
                    SumiConfirmationSheet(
                        eyebrow: request.eyebrow,
                        title: request.title,
                        message: request.message,
                        confirmTitle: request.confirmTitle,
                        confirmRole: request.confirmRole,
                        confirm: request.confirm,
                        cancel: request.cancel
                    )
                }
            }
        }
        .background(Sumi.paper)
        .preferredColorScheme(.light)
        .tint(Sumi.seal)
    }
}

private struct TodayCommandView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var editingCandidate: StoredMeetingCandidate?
    let createLocalTask: () -> Void
    @State private var draggedReminderListID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.runtimeSafety.isReadOnly {
                HStack(alignment: .top, spacing: 10) {
                    Text("READ-ONLY SAFETY MODE")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.paper)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Sumi.sealDeep)
                    Text(model.runtimeSafety.reason ?? "The agent stopped database writes after a persistence failure. Plans remain visible, but external actions are blocked.")
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.sealDeep)
                    Spacer()
                    Button("RECHECK") { Task { await model.refreshRuntimeSafety() } }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Sumi.sealWash)
                .overlay(alignment: .bottom) { Rectangle().fill(Sumi.seal).frame(height: 1) }
            }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY / INBOX")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Text("A deliberate day, grounded in real reminders")
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.muted)
                }

                Spacer()

                Button {
                    model.generateSuggestedDailyPlan()
                } label: {
                    HStack(spacing: 7) {
                        if model.isGeneratingSuggestedPlan {
                            ProgressView().controlSize(.small).tint(Sumi.ink)
                        }
                        Text(model.isGeneratingSuggestedPlan ? "DRAFTING" : "DRAFT TODAY")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                    }
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(model.isGeneratingSuggestedPlan || !model.hasPlanningCandidates)
                .accessibilityLabel("Draft today's suggested plan")

                Button {
                    model.requestCalendarPlanApproval()
                } label: {
                    HStack(spacing: 7) {
                        if model.isSchedulingDailyPlan {
                            ProgressView().controlSize(.small).tint(Sumi.paper)
                        }
                        Text(model.isSchedulingDailyPlan ? "ACCEPTING" : "ACCEPT BLOCKS")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                    }
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                .disabled(model.isSchedulingDailyPlan || !model.planningCapacityState.canApprove)
                .accessibilityLabel("Accept proposed work blocks and reserve them in Apple Calendar")
                .accessibilityHint(model.planningCapacityState.canApprove ? "The plan fits today's focus capacity." : "Resolve the plan capacity warning first.")
                .accessibilityIdentifier("planning-capacity-accept")

                Button {
                    model.refreshReminderTasks()
                } label: {
                    HStack(spacing: 7) {
                        if model.isLoadingReminderTasks {
                            ProgressView().controlSize(.small).tint(Sumi.paper)
                        }
                        Text(model.isLoadingReminderTasks ? "LOADING" : "REFRESH TASKS")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                    }
                }
                .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
                .disabled(model.isLoadingReminderTasks)
                .accessibilityLabel("Refresh reminders")
            }
            .padding(.horizontal, 28)
            .frame(height: 60)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

            PlanningInvitationBanner()

            BaselineObservationView()
                .padding(.horizontal, 28)
                .padding(.vertical, 18)

            if let snapshot = model.todaySnapshot {
                TodayDashboardCommandOverview(snapshot: snapshot)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PLAN BEFORE MOTION")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Text("Three commitments. One clear objective.")
                        .font(Sumi.display(32))
                        .tracking(-0.8)
                        .foregroundStyle(Sumi.ink)
                    Text("The agent is preparing today's command ledger from its local sources.")
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.muted)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                DailyPlanLedger()
            }

            PlanningCapacityPanel()

            if let calendarError = model.calendarScheduleError {
                Text(calendarError)
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.seal)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.sealWash)
            }

            if let taskError = model.taskCommandError {
                Text(taskError)
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.seal)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.sealWash)
                    .accessibilityLabel("Task action failed. \(taskError)")
            }

            TodayPromptInboxLedger()
            MeetingCandidateLedger(editingCandidate: $editingCandidate)
            ReminderCompletionSyncLedger()
            AutomaticActionLedger()
            MacPermissionHealthLedger()

            if model.remindersContinuityState.isOutage {
                RemindersContinuityBanner(createLocalTask: createLocalTask)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("FULL INVENTORY / UNPLANNED TASKS")
                        .font(Sumi.label(10))
                        .sumiLabelTracking()
                    Spacer()
                    Button("NEW LOCAL TASK", action: createLocalTask)
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        .accessibilityHint("Creates a task stored only on this Mac, even when Reminders is unavailable.")
                        .accessibilityIdentifier("create-local-task")
                    Text("\(unplannedTasks.count) AVAILABLE")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.muted)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Sumi.mist)
                .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

                if let error = model.reminderTaskError {
                    Text(error)
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.seal)
                        .padding(28)
                } else if model.isLoadingReminderTasks && model.reminderTasks.isEmpty {
                    ProgressView("Loading your incomplete reminders")
                        .padding(28)
                } else if unplannedTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No incomplete tasks are available. You can create a local task now or connect Apple Reminders from Source health.")
                            .font(Sumi.body(14))
                            .foregroundStyle(Sumi.muted)
                        Button("CREATE LOCAL TASK", action: createLocalTask)
                            .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
                            .accessibilityIdentifier("create-local-task-empty-state")
                    }
                    .padding(28)
                } else {
                    let groups = groupedUnplannedTasks
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        ReminderListGroup(
                            group: group,
                            draggedListID: $draggedReminderListID,
                            moveUp: index > 0 ? {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    model.moveReminderList(group.listID, before: groups[index - 1].listID)
                                }
                            } : nil,
                            moveDown: index < groups.count - 1 ? {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    model.moveReminderList(groups[index + 1].listID, before: group.listID)
                                }
                            } : nil
                        )
                    }
                    ReminderListEndDropTarget(draggedListID: $draggedReminderListID)
                }
            }

            TodaySourceFreshnessFooter()
        }
    }

    private var unplannedTasks: [ReminderTask] {
        if let snapshotRows = model.todaySnapshot?.unplannedReminders {
            return snapshotRows.map {
                ReminderTask(
                    id: $0.reminderID,
                    title: $0.title,
                    listID: $0.listID ?? "agent-unfiled",
                    listName: $0.listName ?? "Unfiled",
                    dueDate: $0.dueDate,
                    priority: $0.priority,
                    notes: nil,
                    modificationDate: nil
                )
            }
        }
        return model.reminderTasks.filter { task in
            !model.dailyPlan.contains { $0.reminderID == task.id }
                && model.isReminderEligibleForToday(task.dueDate)
        }
    }

    private var groupedUnplannedTasks: [ReminderTaskGroup] {
        Dictionary(grouping: unplannedTasks, by: \.listID)
            .compactMap { listID, tasks in
                tasks.first.map { ReminderTaskGroup(listID: listID, listName: $0.listName, tasks: tasks) }
            }
            .sorted { lhs, rhs in
                let leftIndex = model.reminderListOrder.firstIndex(of: lhs.listID) ?? .max
                let rightIndex = model.reminderListOrder.firstIndex(of: rhs.listID) ?? .max
                if leftIndex != rightIndex { return leftIndex < rightIndex }
                return lhs.listName.localizedCaseInsensitiveCompare(rhs.listName) == .orderedAscending
            }
    }
}

private struct RemindersContinuityBanner: View {
    @EnvironmentObject private var model: AppModel
    let createLocalTask: () -> Void

    var body: some View {
        let state = model.remindersContinuityState
        VStack(alignment: .leading, spacing: 10) {
            Text(state.title)
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.sealDeep)
            Text(state.detail)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("NEW LOCAL TASK") {
                    createLocalTask()
                }
                .buttonStyle(SumiActionButtonStyle(role: .accent, size: .compact))
                .accessibilityIdentifier("reminders-continuity-create-local-task")
                Button("OPEN SOURCE HEALTH") {
                    model.selectedSection = .diagnostics
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                .accessibilityIdentifier("reminders-continuity-source-health")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sumi.sealWash)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminders-continuity-banner")
    }
}

private struct ReminderCompletionSyncLedger: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !model.visibleReminderCompletionSyncStates.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("REMINDERS COMPLETION SYNC")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                    Spacer()
                    Text("LOCAL HISTORY PRESERVED")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.muted)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(Sumi.mist)
                .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }

                ForEach(model.visibleReminderCompletionSyncStates, id: \.taskID) { state in
                    HStack(spacing: 12) {
                        Image(systemName: state.phase == .failed || state.phase == .unavailable
                            ? "exclamationmark.arrow.triangle.2.circlepath"
                            : "clock.arrow.circlepath")
                            .foregroundStyle(state.phase == .failed || state.phase == .unavailable ? Sumi.seal : Sumi.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.reminderCompletionTitle(taskID: state.taskID))
                                .font(Sumi.body(13))
                                .foregroundStyle(Sumi.ink)
                            Text(state.detail(localExecutionIsCompleted: true) ?? "Apple Reminders confirmation is still pending.")
                                .font(Sumi.body(11))
                                .foregroundStyle(Sumi.muted)
                        }
                        Spacer()
                        if state.canRetry {
                            Button("RETRY SYNC") {
                                model.retryReminderCompletionSync(taskID: state.taskID)
                            }
                            .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                            .accessibilityIdentifier("today.completion-sync.\(state.taskID).retry")
                            .disabled(model.isAnyTaskCommandPending)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("today.completion-sync.\(state.taskID)")
                }
            }
        }
    }
}

private struct PlanningInvitationBanner: View {
    @EnvironmentObject private var model: AppModel

    private var status: PlanningDayStatus {
        model.todaySnapshot?.planningStatus
            ?? PlanningDayStatus(mode: model.dailyPlan.isEmpty ? .invitation : .planning)
    }

    private var prompt: PromptEpisode? {
        model.promptEpisodes.first { $0.type == "PLAN_READY" }
    }

    var body: some View {
        if status.mode != .planning {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow)
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Text(title)
                        .font(Sumi.display(22))
                        .foregroundStyle(Sumi.ink)
                    Text(detail)
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.muted)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("PLAN NOW") { model.generateSuggestedDailyPlan() }
                        .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                        .disabled(model.isGeneratingSuggestedPlan || !model.hasPlanningCandidates)
                        .accessibilityIdentifier("planning.invitation.plan-now")
                    if status.mode == .invitation, let prompt,
                       prompt.actions.contains(where: { $0.kind == .snoozePlanning }) {
                        Button("SNOOZE 15 MIN") {
                            model.respondToPrompt(prompt, action: .snoozePlanning)
                        }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        .accessibilityIdentifier("planning.invitation.snooze")
                        Button("DISMISS FOR NOW") {
                            model.respondToPrompt(prompt, action: .dismissPlanning)
                        }
                        .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                        .accessibilityIdentifier("planning.invitation.dismiss")
                    }
                    if status.mode != .unplanned {
                        Button("WORK UNPLANNED") { model.skipPlanning() }
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                            .accessibilityIdentifier("planning.invitation.work-unplanned")
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(status.mode == .unplanned ? Sumi.softPaper : Sumi.sealWash)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("planning.invitation.banner")
        }
    }

    private var eyebrow: String {
        switch status.mode {
        case .invitation: "DAY STATE / UNPLANNED"
        case .snoozed: "PLANNING SNOOZED"
        case .dismissed: "PLANNING DISMISSED"
        case .unplanned: "LIMITED UNPLANNED MODE"
        case .planning: "PLANNING"
        }
    }

    private var title: String {
        switch status.mode {
        case .invitation: "Your day is still open."
        case .snoozed: "Planning will return when the snooze ends."
        case .dismissed: "No repeated planning prompts for now."
        case .unplanned: "Work without an approved plan."
        case .planning: "Planning is in progress."
        }
    }

    private var detail: String {
        switch status.mode {
        case .invitation:
            "Make a small plan, start one available task explicitly, or come back later. Drift coaching stays off until you choose."
        case .snoozed, .dismissed:
            if let resumesAt = status.resumesAt {
                "The invitation returns at \(resumesAt.formatted(date: .omitted, time: .shortened)). You can plan or begin unplanned work sooner."
            } else {
                "You can plan or begin unplanned work whenever you are ready."
            }
        case .unplanned:
            "Tasks and behavior totals remain available, but Zoid 666 will not claim that activity violated a plan that does not exist."
        case .planning:
            "Review the proposed commitments before accepting them."
        }
    }
}

private struct AutomaticActionLedger: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AUTOMATIC ACTIONS")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                Spacer()
                Text("AUDITED / REVERSIBLE WHEN SAFE")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(Sumi.mist)
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }

            if let message = model.lastActionMessage {
                Text(message)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.ink)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.sealWash)
            }

            if let error = model.actionAuditError {
                Text(error).font(Sumi.body(12)).foregroundStyle(Sumi.seal).padding(28)
            } else if model.actionAudit.isEmpty {
                Text("No Apple Calendar or Reminders actions have been issued yet.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .padding(28)
            } else {
                ForEach(model.actionAudit.prefix(5)) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.actionType.replacingOccurrences(of: "_", with: " ").uppercased())
                                .font(Sumi.label(9))
                                .sumiLabelTracking()
                            Text("\(entry.state.uppercased()) · \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened)) · attempt \(entry.attemptCount)")
                                .font(Sumi.body(11))
                                .foregroundStyle(Sumi.muted)
                        }
                        Spacer()
                        Text(entry.canUndo ? "REVERSIBLE" : "FINAL")
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .foregroundStyle(entry.canUndo ? Sumi.seal : Sumi.muted)
                        if entry.canUndo {
                            Button("UNDO") { model.undoAction(entry) }
                                .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                                .accessibilityLabel("Undo \(entry.actionType.replacingOccurrences(of: "_", with: " "))")
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
                }
            }
        }
    }
}

private struct MacPermissionHealthLedger: View {
    @State private var refreshToken = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MACOS PERMISSIONS")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Sumi.mist)
                .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
            permissionRow(
                title: "Screen Recording",
                granted: CGPreflightScreenCaptureAccess(),
                detail: "Required for native visual context capture across displays.",
                repair: { _ = CGRequestScreenCaptureAccess(); refreshToken = UUID() }
            )
            permissionRow(
                title: "Accessibility",
                granted: AXIsProcessTrusted(),
                detail: "Required to inspect the active application and support reliable context transitions.",
                repair: {
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    refreshToken = UUID()
                }
            )
            permissionRow(
                title: "Automation",
                granted: nil,
                detail: "Managed per target app by macOS. Calendar and Reminders health rows verify actual access.",
                repair: { openPrivacySettings("Privacy_Automation") }
            )
        }
        .id(refreshToken)
    }

    private func permissionRow(title: String, granted: Bool?, detail: String, repair: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Sumi.body(13)).foregroundStyle(Sumi.ink)
                Text(detail).font(Sumi.body(11)).foregroundStyle(Sumi.muted)
            }
            Spacer()
            Text(granted == true ? "HEALTHY" : granted == false ? "REPAIR REQUIRED" : "VERIFY IN SETTINGS")
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(granted == true ? Sumi.okay : Sumi.seal)
            if granted != true {
                Button(granted == nil ? "OPEN SETTINGS" : "REPAIR", action: repair)
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .accessibilityLabel("Repair \(title) permission")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }

    private func openPrivacySettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct TodaySourceFreshnessFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCE FRESHNESS")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.ink)
            if let sources = model.todaySnapshot?.sources, !sources.isEmpty {
                ForEach(sources) { source in
                    HStack(spacing: 8) {
                        Text(source.sourceID.capitalized).font(Sumi.body(12)).foregroundStyle(Sumi.ink)
                        Spacer()
                        Text(source.state.uppercased()).font(Sumi.label(8)).sumiLabelTracking().foregroundStyle(Sumi.muted)
                        Text(source.detail).font(Sumi.body(11)).foregroundStyle(Sumi.muted)
                    }
                }
            } else {
                ForEach(model.sources) { source in
                    HStack(spacing: 8) {
                        Text(source.title).font(Sumi.body(12)).foregroundStyle(Sumi.ink)
                        Spacer()
                        Text(source.state.rawValue.uppercased()).font(Sumi.label(8)).sumiLabelTracking().foregroundStyle(Sumi.muted)
                        Text(source.detail).font(Sumi.body(11)).foregroundStyle(Sumi.muted)
                        if source.state != .healthy && source.state != .checking {
                            Button(source.actionTitle.uppercased()) { model.checkSource(source.id) }
                                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                                .accessibilityLabel("Repair \(source.title)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }
}

private struct TodayAgentLedger: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ZOID 666 - TODAY")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(snapshot.localDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(Sumi.display(30))
                    .foregroundStyle(Sumi.ink)
                Text(snapshot.mainObjective.map { "Main objective: \($0)" } ?? "No main objective is set yet.")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
                Text(snapshot.activeTask == nil ? snapshot.recommendation.sentence : "Active task: \(activeTitle)")
                    .font(Sumi.body(14))
                    .foregroundStyle(Sumi.ink)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            sectionTitle("TODAY'S PLANNED TASKS")
            ForEach(snapshot.taskRows) { row in
                TodayTaskRowView(row: row)
            }

            sectionTitle("BEHAVIOR SUMMARY")
            HStack(spacing: 20) {
                metric("Working", snapshot.behavior.workMinutes)
                metric("Gaming / distracting", snapshot.behavior.gamingOrDistractingMinutes)
                metric("Idle", snapshot.behavior.idleMinutes)
                if snapshot.behavior.unknownMinutes > 0 { metric("Unknown", snapshot.behavior.unknownMinutes) }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            if snapshot.coverage.isLimited {
                Text(snapshot.coverage.explanation)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }

            sectionTitle("DO THIS NEXT")
            Text(snapshot.recommendation.sentence)
                .font(Sumi.body(14))
                .foregroundStyle(Sumi.ink)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)

            sectionTitle("GAMING BUDGET")
            Text("\(snapshot.gaming.usedMinutes)m used of \(snapshot.gaming.budgetMinutes)m. \(snapshot.gaming.unlockedRemainingMinutes)m remaining.")
                .font(Sumi.body(14))
                .foregroundStyle(Sumi.ink)
                .padding(.horizontal, 28)
                .padding(.top, 12)
            Text(snapshot.gaming.nextUnlockReason)
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
        }
    }

    private var activeTitle: String {
        guard let activeID = snapshot.activeTask?.taskID else { return "" }
        return snapshot.taskRows.first(where: { $0.taskID == activeID })?.title ?? "A task"
    }

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Sumi.label(9))
            .sumiLabelTracking()
            .foregroundStyle(Sumi.ink)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Sumi.mist)
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }

    private func metric(_ label: String, _ minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(minutes)m").font(Sumi.display(20)).foregroundStyle(Sumi.ink)
            Text(label).font(Sumi.label(8)).sumiLabelTracking().foregroundStyle(Sumi.muted)
        }
    }
}

private struct TodayTaskRowView: View {
    @EnvironmentObject private var model: AppModel
    let row: TodayTaskRow
    @State private var isSwitchConfirmationPresented = false
    @State private var isBlockReasonPresented = false
    @State private var blockReason = ""
    @State private var isReschedulePresented = false
    @State private var rescheduleDate = TaskRescheduleState().selectedDate
    @State private var rescheduleError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 12) {
            Button { primaryAction() } label: {
                Image(systemName: completionIcon)
                    .foregroundStyle(completionIconColor)
            }
            .buttonStyle(SumiPressButtonStyle())
            .disabled([.completed, .blocked, .rescheduled].contains(row.state))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(Sumi.body(14)).foregroundStyle(Sumi.ink)
                Text(taskDetail)
                    .font(Sumi.body(11)).foregroundStyle(Sumi.muted)
                if let blockedReason = row.blockedReason, !blockedReason.isEmpty {
                    Text("BLOCKED - \(blockedReason)")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.seal)
                        .accessibilityIdentifier("today.task.\(row.taskID).blocked-reason")
                } else if let deferredUntil = row.deferredUntil, deferredUntil > Date() {
                    Text("DEFERRED UNTIL \(deferredUntil.formatted(date: .abbreviated, time: .shortened))")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.seal)
                        .accessibilityIdentifier("today.task.\(row.taskID).deferred-until")
                } else if row.isOptional == true {
                    Text("OPTIONAL - NOT RESERVED ON CALENDAR")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                        .accessibilityIdentifier("today.task.\(row.taskID).optional")
                }
            }
            Spacer()
            if row.state == .active {
                pauseMenu
            } else if row.state == .paused {
                Button("RESUME") { model.applyTaskCommand(.resume, taskID: row.taskID) }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
            } else if row.state == .ready {
                Button("START") { model.applyTaskCommand(.start, taskID: row.taskID) }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
            }
            SumiDropdown(minimumMenuWidth: 186) {
                SumiSelectorLabel("MORE", systemImage: "ellipsis", size: .compact, showsChevron: false)
            } content: { dismiss in
                SumiDropdownOption("Block task", systemImage: "hand.raised") {
                    blockReason = row.blockedReason ?? ""
                    isBlockReasonPresented = true
                    dismiss()
                }
                if row.state == .paused {
                    SumiDropdownOption("Complete paused task", systemImage: "checkmark.circle") {
                        model.applyTaskCommand(.complete, taskID: row.taskID)
                        dismiss()
                    }
                }
                SumiDropdownDivider()
                SumiDropdownOption("Reschedule task", systemImage: "calendar.badge.clock") {
                    let state = TaskRescheduleState()
                    rescheduleDate = state.selectedDate
                    rescheduleError = nil
                    isReschedulePresented = true
                    dismiss()
                }
            }
            .fixedSize()
        }
        if row.state == .active || row.state == .paused {
            TaskEstimateProgressView(
                progress: TaskEstimateProgress(
                    elapsedMinutes: row.elapsedMinutes,
                    estimateMinutes: row.estimateMinutes
                ),
                compact: true,
                isRunning: row.state == .active,
                identifier: "today.task.\(row.taskID).estimate-progress"
            )
            .padding(.leading, 40)
        }
        if let detail = completionSync.detail(localExecutionIsCompleted: row.state == .completed),
           completionSync.phase != .confirmed {
            HStack(spacing: 10) {
                Image(systemName: completionSync.phase == .failed || completionSync.phase == .unavailable ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(completionSync.phase == .failed || completionSync.phase == .unavailable ? Sumi.seal : Sumi.muted)
                Text(detail)
                    .font(Sumi.body(11))
                    .foregroundStyle(completionSync.phase == .failed || completionSync.phase == .unavailable ? Sumi.seal : Sumi.muted)
                Spacer()
                if completionSync.canRetry {
                    Button("RETRY SYNC") {
                        model.retryReminderCompletionSync(taskID: row.taskID)
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                    .accessibilityIdentifier("today.task.\(row.taskID).retry-reminders-completion")
                    .disabled(model.isAnyTaskCommandPending)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.task.\(row.taskID).reminders-completion-sync")
        }
        }
        .font(Sumi.label(8))
        .sumiLabelTracking()
        .padding(.horizontal, 28)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        .opacity(model.isAnyTaskCommandPending ? 0.55 : 1)
        .disabled(model.isAnyTaskCommandPending)
        .alert("Switch active task?", isPresented: $isSwitchConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Switch and pause current task") {
                model.applyTaskCommand(.start, taskID: row.taskID)
            }
        } message: {
            Text("Zoid 666 will preserve the current task's tracked time, pause it with the reason Switching tasks, and start \"\(row.title)\".")
        }
        .sheet(isPresented: $isBlockReasonPresented) {
            TaskBlockReasonSheet(taskTitle: row.title, reason: $blockReason) {
                guard let entry = model.dailyPlan.first(where: { $0.reminderID == row.taskID }) else { return }
                model.markTaskBlocked(entry, reason: blockReason)
                isBlockReasonPresented = false
            }
        }
        .sheet(isPresented: $isReschedulePresented) {
            VStack(alignment: .leading, spacing: 18) {
                Text("RESCHEDULE TASK")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(row.title)
                    .font(Sumi.display(24))
                Text("Choose the next local planning date. This moves the task out of today's capacity, but it does not change the Apple Reminder due date.")
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
                .accessibilityIdentifier("today.task.\(row.taskID).reschedule-date")
                if let rescheduleError {
                    Text(rescheduleError)
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.sealDeep)
                        .accessibilityIdentifier("today.task.\(row.taskID).reschedule-error")
                }
                HStack {
                    Button("CANCEL") { isReschedulePresented = false }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    Spacer()
                    Button("CONFIRM NEW DATE") {
                        switch TaskRescheduleState().validated(rescheduleDate) {
                        case let .success(date):
                            model.rescheduleTask(row.taskID, until: date)
                            isReschedulePresented = false
                        case let .failure(error):
                            rescheduleError = error.message
                        }
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                    .accessibilityIdentifier("today.task.\(row.taskID).reschedule-confirm")
                }
            }
            .padding(24)
            .frame(width: 440)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.task.\(row.taskID).reschedule-sheet")
        }
    }

    private var completionSync: ReminderCompletionSyncState {
        model.reminderCompletionSyncState(for: row.taskID)
    }

    private var completionIcon: String {
        guard row.state == .completed else { return "circle" }
        return switch completionSync.phase {
        case .pending, .retrying: "clock.arrow.circlepath"
        case .failed, .unavailable: "exclamationmark.circle"
        case .confirmed: "checkmark.circle.fill"
        case .notRequested: "clock.badge.questionmark"
        }
    }

    private var completionIconColor: Color {
        return switch completionSync.phase {
        case .failed, .unavailable: Sumi.seal
        case .confirmed: Sumi.seal
        case .notRequested, .pending, .retrying: Sumi.muted
        }
    }

    private var taskDetail: String {
        let stateLabel = completionSync.statusLabel(localExecutionIsCompleted: row.state == .completed)
            ?? row.state.rawValue.capitalized
        var parts = ["\(row.estimateMinutes)m", relativeDeadline(row.dueDate), "\(row.urgency.rawValue.capitalized) urgency", stateLabel]
        if row.elapsedMinutes > 0 { parts.append("\(row.elapsedMinutes)m tracked") }
        if let reason = row.latestPauseReason {
            parts.append(row.state == .paused ? reason.userFacingLabel : "Last pause: \(reason.userFacingLabel.lowercased())")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var pauseMenu: some View {
        Menu {
            Button("Take a break") { model.applyTaskCommand(.pauseForBreak, taskID: row.taskID) }
            Button("External interruption") { model.applyTaskCommand(.pauseForExternalInterruption, taskID: row.taskID) }
            Button("Done for now") { model.applyTaskCommand(.pauseDoneForNow, taskID: row.taskID) }
            Button("End the workday") { model.applyTaskCommand(.pauseForEndOfDay, taskID: row.taskID) }
        } label: {
            SumiSelectorLabel("PAUSE", systemImage: "pause.fill", size: .compact)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Pause \(row.title)")
        .accessibilityHint("Choose why you are pausing so the reason remains in task history.")
    }

    private func relativeDeadline(_ date: Date?) -> String {
        guard let date else { return "No deadline" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Due today" }
        if calendar.isDateInTomorrow(date) { return "Due tomorrow" }
        if date < Date() { return "Overdue" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func primaryAction() {
        switch row.state {
        case .active:
            model.applyTaskCommand(.complete, taskID: row.taskID)
        case .ready:
            if let activeTaskID = model.todaySnapshot?.activeTask?.taskID, activeTaskID != row.taskID {
                isSwitchConfirmationPresented = true
            } else {
                model.applyTaskCommand(.start, taskID: row.taskID)
            }
        case .paused:
            model.applyTaskCommand(.resume, taskID: row.taskID)
        case .blocked, .completed, .rescheduled:
            break
        }
    }
}

private struct ReminderTaskGroup: Identifiable {
    let listID: String
    let listName: String
    let tasks: [ReminderTask]

    var id: String { listID }
}

private struct ReminderListGroup: View {
    @EnvironmentObject private var model: AppModel
    let group: ReminderTaskGroup
    @Binding var draggedListID: String?
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Sumi.muted)
                    .accessibilityHidden(true)
                Text(group.listName)
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Spacer()
                Text("\(group.tasks.count) TASK\(group.tasks.count == 1 ? "" : "S")")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                if let moveUp {
                    Button(action: moveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                    .accessibilityLabel("Move \(group.listName) up")
                }
                if let moveDown {
                    Button(action: moveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                    .accessibilityLabel("Move \(group.listName) down")
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(isDropTarget ? Sumi.sealWash : Sumi.softPaper)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
            .contentShape(Rectangle())
            .onDrag {
                draggedListID = group.listID
                return NSItemProvider(object: group.listID as NSString)
            }
            .allowingReminderListMoves()
            .onDrop(of: [.text], delegate: ReminderListDropDelegate(
                targetListID: group.listID,
                draggedListID: $draggedListID,
                isDropTarget: $isDropTarget
            ) { listID in
                withAnimation(.easeOut(duration: 0.2)) {
                    model.moveReminderList(listID, before: group.listID)
                }
            })
            .allowsHitTesting(!model.isLoadingReminderListOrder)
            .accessibilityLabel("\(group.listName), \(group.tasks.count) tasks. Drag to reorder this reminder list.")

            ForEach(group.tasks) { task in
                InboxReminderTaskRow(task: task)
            }
        }
    }
}

private struct ReminderListEndDropTarget: View {
    @EnvironmentObject private var model: AppModel
    @Binding var draggedListID: String?
    @State private var isDropTarget = false

    var body: some View {
        Text(isDropTarget ? "DROP TO MOVE LIST LAST" : "DRAG A LIST HERE TO MOVE IT LAST")
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .foregroundStyle(isDropTarget ? Sumi.seal : Sumi.muted)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(isDropTarget ? Sumi.sealWash : Sumi.softPaper)
            .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            .onDrop(of: [.text], delegate: ReminderListDropDelegate(
                draggedListID: $draggedListID,
                isDropTarget: $isDropTarget
            ) { listID in
                withAnimation(.easeOut(duration: 0.2)) {
                    model.moveReminderListToEnd(listID)
                }
            })
            .allowsHitTesting(!model.isLoadingReminderListOrder)
            .accessibilityLabel("Move reminder list to the final position")
    }
}

private struct ReminderListDropDelegate: DropDelegate {
    let targetListID: String?
    @Binding var draggedListID: String?
    @Binding var isDropTarget: Bool
    let moveList: (String) -> Void

    init(
        targetListID: String? = nil,
        draggedListID: Binding<String?>,
        isDropTarget: Binding<Bool>,
        moveList: @escaping (String) -> Void
    ) {
        self.targetListID = targetListID
        _draggedListID = draggedListID
        _isDropTarget = isDropTarget
        self.moveList = moveList
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        isDropTarget = true
    }

    func dropExited(info: DropInfo) {
        isDropTarget = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedListID = nil
            isDropTarget = false
        }

        guard let listID = draggedListID, listID != targetListID else { return false }
        moveList(listID)
        return true
    }
}

private extension View {
    @ViewBuilder
    func allowingReminderListMoves() -> some View {
        if #available(macOS 26.0, *) {
            dragConfiguration(DragConfiguration(allowMove: true))
        } else {
            self
        }
    }
}

private struct DailyPlanLedger: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let entries = model.dailyPlan.sorted { $0.rank < $1.rank }
        let mainObjective = entries.first(where: \.isMainObjective)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PROPOSED WORK BLOCKS")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                Spacer()
                Text(model.isLoadingDailyPlan ? "LOADING PLAN" : "\(entries.count) / 3 PROPOSED")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                    .contentTransition(.numericText())
            }

            if let persistenceMessage = model.persistenceMessage {
                Text(persistenceMessage)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.sealDeep)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.sealWash)
                    .accessibilityLabel("Plan save failed. \(persistenceMessage)")
            }

            HStack(alignment: .top, spacing: 10) {
                Text(planDeliveryLabel)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(planWasDelayed ? Sumi.paper : Sumi.ink)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(planWasDelayed ? Sumi.seal : Sumi.mist)
                Text(planDeliveryExplanation)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }

            VStack(alignment: .leading, spacing: 5) {
                Text("MAIN OBJECTIVE")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(task(for: mainObjective)?.title ?? "Choose the outcome that makes today successful.")
                    .font(Sumi.display(27))
                    .foregroundStyle(mainObjective == nil ? Sumi.muted : Sumi.ink)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Sumi.sealWash)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

            ForEach(entries) { entry in
                if let task = task(for: entry) {
                    PlannedReminderRow(entry: entry, task: task)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity
                        ))
                }
            }

            if entries.count < 3 {
                Text("Select \(3 - entries.count) more reminder\(entries.count == 2 ? "" : "s") from the queue below. Estimates are required before the plan can become active.")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.softPaper)
            }
        }
        .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: entries)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: mainObjective?.id)
    }

    private func task(for entry: DailyPlanEntry?) -> ReminderTask? {
        guard let entry else { return nil }
        return model.reminderTasks.first { $0.id == entry.reminderID }
    }

    private var planWasDelayed: Bool {
        model.todaySnapshot?.sourceFreshnessExplanation.localizedCaseInsensitiveContains("delayed") == true
            || model.todaySnapshot?.sourceFreshnessExplanation.localizedCaseInsensitiveContains("wake") == true
    }

    private var planDeliveryLabel: String {
        planWasDelayed ? "DELAYED / RECOVERED" : "READY FOR REVIEW"
    }

    private var planDeliveryExplanation: String {
        if planWasDelayed {
            return "The overnight run was delayed while the Mac slept. The background agent recovered it after wake; review the evidence before accepting."
        }
        return "Nothing is written to Calendar until you accept. Adjust duration or main objective here, or exclude any proposal."
    }
}

private struct PlanningCapacityPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let state = model.planningCapacityState

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("FOCUS CAPACITY")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(statusColor)
                Spacer()
                Text("\(state.plannedMinutes) MIN PLANNED / \(state.availableMinutes) MIN AVAILABLE")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.ink)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 18) {
                planMetric(
                    label: "FOCUSED WORK",
                    value: "\(state.plannedMinutes) MIN",
                    accessibilityValue: "\(state.plannedMinutes) minutes of focused work planned",
                    identifier: "planning-capacity-focused-work"
                )
                planMetric(
                    label: state.overCapacityMinutes > 0 ? "OVER CAPACITY" : "PLANNED BUFFER",
                    value: "\(state.overCapacityMinutes > 0 ? state.overCapacityMinutes : state.remainingBufferMinutes) MIN",
                    accessibilityValue: state.overCapacityMinutes > 0
                        ? "Plan exceeds focus capacity by \(state.overCapacityMinutes) minutes"
                        : "\(state.remainingBufferMinutes) minutes remain unplanned as buffer",
                    identifier: "planning-capacity-buffer"
                )
            }

            Text(explanation)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !model.planningCapacityUsesCalendar {
                Text("CALENDAR UNAVAILABLE / USING CONFIGURED WORK-WINDOW CAPACITY")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.sealDeep)
                    .accessibilityLabel("Calendar availability could not be read. Capacity uses the configured work window only.")
            }

            if case .overloaded = state.readiness,
               state.suggestedReminderID != nil {
                HStack(alignment: .center, spacing: 12) {
                    Text("SUGGESTED: REMOVE \(suggestedTaskTitle)")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.sealDeep)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("REMOVE SUGGESTED TASK") {
                        model.reduceOverCapacityPlan()
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                    .accessibilityLabel("Reduce plan by removing \(suggestedTaskTitle)")
                    .accessibilityHint("Removes the lowest-ranked proposed task and recalculates capacity immediately.")
                    .accessibilityIdentifier("planning-capacity-reduce")
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planning-capacity-panel")
    }

    private func planMetric(
        label: String,
        value: String,
        accessibilityValue: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
            Text(value)
                .font(Sumi.display(20))
                .foregroundStyle(Sumi.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityValue)
        .accessibilityIdentifier(identifier)
    }

    private var explanation: String {
        switch model.planningCapacityState.readiness {
        case .empty:
            return "Add a task to compare planned work with today's configured focus capacity."
        case let .missingEstimates(count):
            return "Estimate \(count) remaining task\(count == 1 ? "" : "s") so Zoid 666 can tell whether this plan is realistic."
        case let .overloaded(overByMinutes):
            return "This plan is \(overByMinutes) minutes over capacity. Remove the suggested lowest-priority task below, shorten an estimate, or exclude another task before accepting."
        case .realistic:
            return "This revised plan fits today's available focus capacity and is ready to accept."
        }
    }

    private var suggestedTaskTitle: String {
        guard let reminderID = model.planningCapacityState.suggestedReminderID else {
            return "suggested task"
        }
        return model.reminderTasks.first(where: { $0.id == reminderID })?.title
            ?? "lowest-priority task"
    }

    private var statusColor: Color {
        switch model.planningCapacityState.readiness {
        case .overloaded: Sumi.sealDeep
        case .realistic: Sumi.ink
        case .empty, .missingEstimates: Sumi.seal
        }
    }

    private var backgroundColor: Color {
        switch model.planningCapacityState.readiness {
        case .overloaded: Sumi.sealWash
        case .realistic: Sumi.softPaper
        case .empty, .missingEstimates: Sumi.mist
        }
    }
}

struct TaskBlockReasonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let taskTitle: String
    @Binding var reason: String
    let save: () -> Void

    private var normalizedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("WHAT IS BLOCKING THIS TASK?")
                .font(Sumi.display(24))
                .foregroundStyle(Sumi.ink)
            Text(taskTitle)
                .font(Sumi.body(15))
                .foregroundStyle(Sumi.muted)
            Text("Save a concrete local reason so Future You can decide whether to repair, delegate, defer, or remove it.")
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
            TextEditor(text: $reason)
                .font(Sumi.body(14))
                .frame(minHeight: 110)
                .padding(10)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
                .accessibilityIdentifier("task.block.reason")
            HStack {
                Text("\(normalizedReason.count) / 240")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(normalizedReason.count > 240 ? Sumi.seal : Sumi.muted)
                Spacer()
                Button("CANCEL") { dismiss() }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                Button("SAVE BLOCKER") { save() }
                    .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                    .disabled(!(3...240).contains(normalizedReason.count))
                    .accessibilityIdentifier("task.block.save")
            }
        }
        .padding(28)
        .frame(minWidth: 480, idealWidth: 520)
        .background(Sumi.paper)
    }
}

private struct PlannedReminderRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: DailyPlanEntry
    let task: ReminderTask
    @State private var isBlockReasonPresented = false
    @State private var blockReason = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(String(format: "%02d", entry.rank))
                .font(Sumi.label(10))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(task.title)
                        .font(Sumi.body(16))
                        .foregroundStyle(Sumi.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer()
                    if entry.isMainObjective {
                        Text("MAIN")
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.paper)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(Sumi.seal)
                    }
                }

                if let blockedReason = entry.blockedReason, !blockedReason.isEmpty {
                    Text("BLOCKED - \(blockedReason)")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.seal)
                        .accessibilityIdentifier("plan.task.\(entry.reminderID).blocked-reason")
                } else if let deferredUntil = entry.deferredUntil, deferredUntil > Date() {
                    Text("DEFERRED UNTIL \(deferredUntil.formatted(date: .abbreviated, time: .shortened)) - NOT INCLUDED IN CAPACITY")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.seal)
                        .accessibilityIdentifier("plan.task.\(entry.reminderID).deferred-state")
                } else if entry.isOptional {
                    Text("OPTIONAL - NOT INCLUDED IN CAPACITY OR CALENDAR")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                        .accessibilityIdentifier("plan.task.\(entry.reminderID).optional-state")
                }

                TimeBlockSelector(
                    selectedMinutes: entry.estimateMinutes,
                    taskTitle: task.title,
                    taskID: entry.reminderID
                ) { minutes in
                    model.setEstimate(minutes, for: entry)
                }

                if let selectionReason = entry.selectionReason {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("EVIDENCE")
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.seal)
                        Text(selectionReason)
                            .font(Sumi.body(12))
                            .foregroundStyle(Sumi.muted)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("EVIDENCE")
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.seal)
                        Text("Manually selected from Apple Reminders. No ranking claim was made.")
                            .font(Sumi.body(12))
                            .foregroundStyle(Sumi.muted)
                    }
                }

                HStack(spacing: 14) {
                    Button("MOVE UP") { model.moveDailyPlanEntry(entry, by: -1) }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        .disabled(entry.rank <= 1)
                        .accessibilityIdentifier("plan.task.\(entry.reminderID).move-up")
                    Button("MOVE DOWN") { model.moveDailyPlanEntry(entry, by: 1) }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        .disabled(entry.rank >= model.dailyPlan.count)
                        .accessibilityIdentifier("plan.task.\(entry.reminderID).move-down")
                    Spacer()
                    Button("ADJUST: MAKE MAIN") { model.setMainObjective(entry) }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        .disabled(entry.isMainObjective)
                    Button("EXCLUDE") { model.removeFromDailyPlan(entry) }
                        .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                }
                HStack(spacing: 14) {
                    Button(entry.isOptional ? "MAKE COMMITTED" : "MARK OPTIONAL") {
                        model.toggleOptional(entry)
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .disabled(entry.isMainObjective)
                    .accessibilityIdentifier("plan.task.\(entry.reminderID).optional")
                    Button(entry.deferredUntil == nil ? "DEFER TO TOMORROW" : "RETURN TO TODAY") {
                        if entry.deferredUntil == nil {
                            model.deferTaskUntilTomorrow(entry)
                        } else {
                            model.clearTaskDeferral(entry)
                        }
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .accessibilityIdentifier("plan.task.\(entry.reminderID).defer")
                    Button("MARK BLOCKED") {
                        blockReason = entry.blockedReason ?? ""
                        isBlockReasonPresented = true
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                    .accessibilityIdentifier("plan.task.\(entry.reminderID).block")
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: entry.isMainObjective)
        .sheet(isPresented: $isBlockReasonPresented) {
            TaskBlockReasonSheet(taskTitle: task.title, reason: $blockReason) {
                model.markTaskBlocked(entry, reason: blockReason)
                isBlockReasonPresented = false
            }
        }
    }
}

private struct MeetingCandidateLedger: View {
    @EnvironmentObject private var model: AppModel
    @Binding var editingCandidate: StoredMeetingCandidate?

    var body: some View {
        guard !model.meetingCandidates.isEmpty || model.meetingCandidateError != nil else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("MEETING DETECTIONS")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                    Spacer()
                    Text("CONFIRM BEFORE CALENDAR")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.muted)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(Sumi.mist)
                .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }

                if let error = model.meetingCandidateError {
                    Text(error)
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.seal)
                        .padding(28)
                }

                ForEach(model.meetingCandidates) { candidate in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(Sumi.seal)
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(candidate.title)
                                .font(Sumi.body(16))
                            Text(candidate.start.formatted(date: .abbreviated, time: .shortened) + " · \(candidate.durationMinutes) MIN")
                                .font(Sumi.label(8))
                                .sumiLabelTracking()
                                .foregroundStyle(Sumi.muted)
                            Text(MeetingCandidateCardContext.text(for: candidate))
                                .font(Sumi.body(11))
                                .foregroundStyle(Sumi.muted)
                                .textSelection(.enabled)
                            if candidate.requiresClarification {
                                Text("TIME NEEDS REVIEW")
                                    .font(Sumi.label(8))
                                    .sumiLabelTracking()
                                    .foregroundStyle(Sumi.seal)
                            }
                        }
                        Spacer()
                        Button("ADD") { model.addMeetingCandidateToCalendar(candidate) }
                            .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                            .accessibilityLabel("Add detected meeting to Apple Calendar")
                        Button("EDIT") { editingCandidate = candidate }
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                            .accessibilityLabel("Edit detected meeting before saving")
                        Button("IGNORE") { model.ignoreMeetingCandidate(candidate) }
                            .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                            .accessibilityLabel("Ignore detected meeting")
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
                }
            }
            .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            .onAppear { openRequestedEditorIfNeeded() }
            .onChange(of: model.meetingCandidates) { _, _ in openRequestedEditorIfNeeded() }
        )
    }

    private func openRequestedEditorIfNeeded() {
        guard editingCandidate == nil else { return }
        editingCandidate = model.meetingCandidates.first { $0.state == "edit_requested" }
    }

}

private struct MeetingCandidateEditor: View {
    let candidate: StoredMeetingCandidate
    let save: (String, Date, Int, MeetingDestination) -> Void
    let cancel: () -> Void
    @State private var title: String
    @State private var start: Date
    @State private var duration: Int
    @State private var destination: MeetingDestination = .calendar

    init(
        candidate: StoredMeetingCandidate,
        save: @escaping (String, Date, Int, MeetingDestination) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.save = save
        cancel = onCancel
        _title = State(initialValue: candidate.title)
        _start = State(initialValue: candidate.start)
        _duration = State(initialValue: candidate.durationMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("CONFIRM MEETING")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("Review the detected details before saving.")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(Sumi.mist)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

            VStack(alignment: .leading, spacing: 18) {
                SumiTextField("MEETING TITLE", placeholder: "Meeting title", text: $title)
                SumiDateField("WHEN", selection: $start, displayedComponents: [.date, .hourAndMinute])
                SumiStepper(
                    "DURATION",
                    value: $duration,
                    in: 15...240,
                    step: 15,
                    valueLabel: { "\($0) MINUTES" }
                )
                SumiChoiceRail(
                    "SAVE AS",
                    options: MeetingDestination.allCases,
                    selection: $destination,
                    title: { $0.rawValue }
                )
            }
            .padding(24)

            HStack(spacing: 12) {
                Button("CANCEL", action: cancel)
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .large))
                    .keyboardShortcut(.cancelAction)
                Button {
                    save(title, start, duration, destination)
                } label: {
                    Text(destination == .calendar ? "ADD TO CALENDAR" : "CREATE REMINDER")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .large))
                .disabled(!canSave)
            }
            .padding(24)
            .background(Sumi.softPaper)
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        }
        .frame(width: 460)
        .background(Sumi.paper)
        .overlay { Rectangle().stroke(Sumi.ink, lineWidth: 1) }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

}

private struct TimeBlockSelector: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selectedMinutes: Int?
    let taskTitle: String
    let taskID: String
    let select: (Int) -> Void

    private let durations = [15, 30, 45, 60, 90]
    @State private var isChanging = false
    @State private var isEnteringCustom = false
    @State private var customMinutes = ""
    @State private var customError: String?

    var body: some View {
        HStack(spacing: 7) {
            Text(selectedMinutes == nil || isChanging ? "ADD ESTIMATE" : "TIME BLOCK")
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(selectedMinutes == nil ? Sumi.seal : Sumi.muted)

            if let selectedMinutes, !isChanging {
                Label {
                    Text(durationLabel(selectedMinutes))
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                } icon: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Sumi.paper)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Sumi.seal)
                .accessibilityLabel("Time estimate confirmed: \(durationLabel(selectedMinutes))")
                .transition(.scale(scale: 0.9).combined(with: .opacity))

                Button {
                    isChanging = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .background(Sumi.paper)
                        .overlay {
                            Rectangle()
                                .stroke(Sumi.rule, lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                }
                .buttonStyle(SumiPressStyle())
                .foregroundStyle(Sumi.ink)
                .padding(3)
                .contentShape(Rectangle())
                .accessibilityLabel("Change \(taskTitle) estimate from \(durationLabel(selectedMinutes))")
                .help("Change time estimate")
            } else if isEnteringCustom {
                TextField("Minutes", text: $customMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 78)
                    .accessibilityLabel("Custom estimate for \(taskTitle) in minutes")
                    .accessibilityIdentifier("task-estimate-custom-input-\(taskID)")
                    .onSubmit(saveCustomEstimate)
                Button("SAVE", action: saveCustomEstimate)
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                    .accessibilityIdentifier("task-estimate-custom-save-\(taskID)")
                Button("CANCEL") {
                    isEnteringCustom = false
                    isChanging = false
                    customError = nil
                }
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("task-estimate-custom-cancel-\(taskID)")
                if let customError {
                    Text(customError)
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.sealDeep)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("task-estimate-custom-error-\(taskID)")
                }
            } else {
                ForEach(durations, id: \.self) { minutes in
                    Button {
                        select(minutes)
                        isChanging = false
                    } label: {
                        Text(durationLabel(minutes))
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                            .padding(.horizontal, 5)
                            .frame(height: 22)
                    }
                    .buttonStyle(TimeSlotButtonStyle())
                    .accessibilityLabel("Set \(taskTitle) estimate to \(durationLabel(minutes))")
                }
                Button("CUSTOM") {
                    customMinutes = selectedMinutes.map(String.init) ?? ""
                    customError = nil
                    isEnteringCustom = true
                }
                .buttonStyle(TimeSlotButtonStyle())
                .accessibilityLabel("Enter a custom estimate for \(taskTitle)")
                .accessibilityIdentifier("task-estimate-custom-\(taskID)")
            }
            Spacer()
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedMinutes)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isChanging)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isEnteringCustom)
    }

    private func saveCustomEstimate() {
        switch TaskEstimateInput.parse(customMinutes) {
        case let .success(minutes):
            select(minutes)
            isChanging = false
            isEnteringCustom = false
            customError = nil
        case let .failure(error):
            customError = error.message
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        "\(minutes) MIN"
    }
}

private struct TimeSlotButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Sumi.paper : Sumi.ink)
            .background(configuration.isPressed ? Sumi.seal : Sumi.paper)
            .overlay {
                Rectangle().stroke(configuration.isPressed ? Sumi.seal : Sumi.rule, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private typealias SumiPressStyle = SumiPressButtonStyle

private struct InboxReminderTaskRow: View {
    @EnvironmentObject private var model: AppModel
    let task: ReminderTask

    var body: some View {
        HStack(spacing: 14) {
            Button {
                model.completeReminderTask(task)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Sumi.seal)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(SumiPressStyle())
            .accessibilityLabel("Complete \(task.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(Sumi.body(15))
                    .foregroundStyle(Sumi.ink)
                Text(task.listName)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }

            Spacer()

            if let dueLabel = task.dueLabel {
                Text(dueLabel.uppercased())
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
            }

            Button("START") {
                model.startUnplannedTask(task)
            }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            .disabled(model.isAnyTaskCommandPending)
            .accessibilityLabel("Start \(task.title) without planning the day")
            .accessibilityIdentifier("planning.unplanned.start.\(task.id)")

            Button("PLAN") {
                model.addToDailyPlan(task)
            }
            .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
            .disabled(model.dailyPlan.count >= 3 || model.isLoadingDailyPlan)
            .accessibilityLabel("Add \(task.title) to today's plan")
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ZOID 666")
                    .font(Sumi.display(26))
                    .tracking(-0.8)
                Text("LOCAL COMMAND")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 30)

            Text("OPERATIONS")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ForEach(AppSection.allCases) { section in
                Button {
                    model.selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 12, weight: .regular))
                            .frame(width: 16)
                        Text(section.rawValue)
                            .font(Sumi.label(11))
                            .sumiLabelTracking()
                        Spacer()
                    }
                    .foregroundStyle(model.selectedSection == section ? Sumi.paper : Sumi.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(model.selectedSection == section ? Sumi.ink : Sumi.paper)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Sumi.okay)
                        .frame(width: 7, height: 7)
                    Text("LOCAL ONLY")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                }
                Text("Build 8 · Autonomous runtime")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Sumi.softPaper)
        }
        .background(Sumi.paper)
    }
}

private struct CommandHeaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SOURCE HEALTH")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("Autonomous runtime")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
            }

            Spacer()

            Text(model.coachingState.rawValue)
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.paper)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Sumi.ink)

            Button {
                model.runSourceCheck()
            } label: {
                HStack(spacing: 7) {
                    if model.isCheckingSources {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Sumi.paper)
                    }
                    Text(model.isCheckingSources ? "CHECKING" : "RUN SOURCE CHECK")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                }
            }
            .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
            .disabled(model.isCheckingSources)
            .accessibilityLabel("Run source check")
        }
        .padding(.horizontal, 28)
        .frame(height: 72)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sumi.rule).frame(height: 1)
        }
    }
}

private struct FoundationHeroView: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 32) {
            VStack(alignment: .leading, spacing: 14) {
                Text("AUTONOMOUS BUILD / TRUST GATED")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)

                Text("The command center\nis online.")
                    .font(Sumi.display(46))
                    .tracking(-1.5)
                    .foregroundStyle(Sumi.ink)

                Text("Local planning, intervention, and recovery now share one agent-owned state. Automatic Apple writes remain protected until the required planning cycles prove the evidence is trustworthy.")
                    .font(Sumi.body(15))
                    .foregroundStyle(Sumi.muted)
                    .lineSpacing(4)
                    .frame(maxWidth: 610, alignment: .leading)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 5) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(Sumi.body(14))
                    .foregroundStyle(Sumi.ink)
                Text("CAIRO · LOCAL TIME")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 36)
        .background(Sumi.paper)
    }
}

private struct SourceHealthLedgerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("SOURCE LEDGER")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                Spacer()
                Text(model.lastCheckAt.map { "Checked " + $0.formatted(date: .omitted, time: .shortened) } ?? "Awaiting first verified check")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Sumi.mist)
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

            ForEach(model.sources) { source in
                SourceHealthRow(source: source)
            }

            LocalSystemDiagnosticsView()
        }
    }
}

private struct SourceHealthRow: View {
    @EnvironmentObject private var model: AppModel
    let source: SourceHealth

    var body: some View {
        let guidance = SourceRepairGuidance(source: source)
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(source.eyebrow)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(source.title)
                    .font(Sumi.display(20))
            }
            .frame(width: 185, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.detail)
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.ink)
                Text(source.evidence)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                if let impact = guidance.impact {
                    Text(impact)
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.sealDeep)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("source-health-\(source.id.rawValue)-impact")
                }
            }

            Spacer()

            HealthBadge(state: source.state)

            Button(source.actionTitle.uppercased()) {
                model.checkSource(source.id)
            }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .accessibilityLabel(source.actionTitle + " " + source.title)
                .accessibilityHint(guidance.actionHint)
                .accessibilityIdentifier("source-health-\(source.id.rawValue)-repair")
                .disabled(!guidance.canAct)
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 82)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sumi.paleRule).frame(height: 1)
        }
    }
}

private struct HealthBadge: View {
    let state: HealthState

    var body: some View {
        Text(state.rawValue)
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(background)
            .overlay { Rectangle().stroke(border, lineWidth: 1) }
            .accessibilityLabel("Status " + state.rawValue)
    }

    private var background: Color {
        switch state.tone {
        case .okay: Sumi.okay
        case .ink: Sumi.ink
        case .seal: Sumi.seal
        case .muted: Sumi.mist
        }
    }

    private var foreground: Color {
        state.tone == .muted ? Sumi.muted : Sumi.paper
    }

    private var border: Color {
        state.tone == .muted ? Sumi.rule : background
    }
}

private struct LocalFoundationView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FoundationColumn(
                index: "01",
                title: "Persistent local runtime",
                copy: "The signed launch agent keeps ingestion, plans, prompts, and recovery active after the app closes.",
                state: "ONLINE"
            )

            Divider()

            FoundationColumn(
                index: "02",
                title: "Rules before models",
                copy: "Deterministic capacity, collision, idempotency, and policy rules remain available without an AI provider.",
                state: "ENFORCED"
            )

            Divider()

            FoundationColumn(
                index: "03",
                title: "Trust gates",
                copy: "Seven qualifying planning cycles unlock automatic writes; fourteen are required before wake eligibility.",
                state: "PROTECTED"
            )
        }
        .background(Sumi.softPaper)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }
}

private struct FoundationColumn: View {
    let index: String
    let title: String
    let copy: String
    let state: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(index)
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Spacer()
                Text(state)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
            Text(title)
                .font(Sumi.display(19))
            Text(copy)
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
                .lineSpacing(3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
    }
}
