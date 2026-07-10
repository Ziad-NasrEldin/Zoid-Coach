import SwiftUI
import UniformTypeIdentifiers
import ZoidCoachCore
import ZoidCoachInfrastructure

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 218)

            Divider()

            ScrollView {
                Group {
                    if model.selectedSection == .today {
                        TodayCommandView()
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
        .background(Sumi.paper)
        .preferredColorScheme(.light)
    }
}

private struct TodayCommandView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draggedReminderListID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .foregroundStyle(Sumi.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .disabled(model.isGeneratingSuggestedPlan || model.reminderTasks.isEmpty)
                .accessibilityLabel("Draft today's suggested plan")

                Button {
                    model.scheduleDailyPlan()
                } label: {
                    HStack(spacing: 7) {
                        if model.isSchedulingDailyPlan {
                            ProgressView().controlSize(.small).tint(Sumi.paper)
                        }
                        Text(model.isSchedulingDailyPlan ? "RESERVING" : "RESERVE DAY")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                    }
                    .foregroundStyle(Sumi.paper)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Sumi.ink)
                }
                .buttonStyle(.plain)
                .disabled(model.isSchedulingDailyPlan || model.dailyPlan.isEmpty)
                .accessibilityLabel("Reserve today's plan in Apple Calendar")

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
                    .foregroundStyle(Sumi.paper)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Sumi.seal)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingReminderTasks)
                .accessibilityLabel("Refresh reminders")
            }
            .padding(.horizontal, 28)
            .frame(height: 60)
            .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }

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

            if let calendarError = model.calendarScheduleError {
                Text(calendarError)
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.seal)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.sealWash)
            }

            PromptInboxLedger()
            MeetingCandidateLedger()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("FULL INVENTORY / UNPLANNED REMINDERS")
                        .font(Sumi.label(10))
                        .sumiLabelTracking()
                    Spacer()
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
                    Text("No incomplete reminders are available. Connect Apple Reminders from Source health if access has not been granted.")
                        .font(Sumi.body(14))
                        .foregroundStyle(Sumi.muted)
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

private struct PromptInboxLedger: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !model.promptEpisodes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("DECISIONS")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.ink)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.mist)
                    .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
                ForEach(model.promptEpisodes) { episode in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(episode.title).font(Sumi.body(15)).foregroundStyle(Sumi.ink)
                        Text(episode.summary).font(Sumi.body(12)).foregroundStyle(Sumi.muted)
                        HStack(spacing: 8) {
                            ForEach(episode.actions) { action in
                                Button(action.title.uppercased()) {
                                    model.respondToPrompt(episode, action: action.kind)
                                }
                                .font(Sumi.label(8))
                                .sumiLabelTracking()
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
                }
            }
        }
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
                Text("ZOID COACH - TODAY")
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { primaryAction() } label: {
                Image(systemName: row.state == .completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.state == .completed ? Sumi.seal : Sumi.muted)
            }
            .buttonStyle(.plain)
            .disabled([.completed, .blocked, .rescheduled].contains(row.state))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(Sumi.body(14)).foregroundStyle(Sumi.ink)
                Text("\(row.estimateMinutes)m  ·  \(relativeDeadline(row.dueDate))  ·  \(row.urgency.rawValue.capitalized) urgency  ·  \(row.state.rawValue.capitalized)")
                    .font(Sumi.body(11)).foregroundStyle(Sumi.muted)
            }
            Spacer()
            if row.state == .active {
                Button("PAUSE") { model.applyTaskCommand(.pause, taskID: row.taskID) }
            } else if row.state == .paused {
                Button("RESUME") { model.applyTaskCommand(.resume, taskID: row.taskID) }
            } else if row.state == .ready {
                Button("START") { model.applyTaskCommand(.start, taskID: row.taskID) }
            }
            Menu("MORE") {
                Button("Block task") { model.applyTaskCommand(.block, taskID: row.taskID) }
                Button("Reschedule task") { model.applyTaskCommand(.reschedule, taskID: row.taskID) }
            }
        }
        .font(Sumi.label(8))
        .sumiLabelTracking()
        .padding(.horizontal, 28)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
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
            model.applyTaskCommand(.start, taskID: row.taskID)
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
                    .buttonStyle(.plain)
                    .foregroundStyle(Sumi.ink)
                    .accessibilityLabel("Move \(group.listName) up")
                }
                if let moveDown {
                    Button(action: moveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Sumi.ink)
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
                Text("TODAY'S COMMITMENT")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                Spacer()
                Text(model.isLoadingDailyPlan ? "LOADING PLAN" : "\(entries.count) / 3 SELECTED")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(Sumi.ink)
            .foregroundStyle(Sumi.paper)

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
}

private struct PlannedReminderRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: DailyPlanEntry
    let task: ReminderTask

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

                TimeBlockSelector(
                    selectedMinutes: entry.estimateMinutes,
                    taskTitle: task.title
                ) { minutes in
                    model.setEstimate(minutes, for: entry)
                }

                if let selectionReason = entry.selectionReason {
                    Text(selectionReason)
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.muted)
                }

                HStack(spacing: 14) {
                    Spacer()
                    Button("MAKE MAIN") { model.setMainObjective(entry) }
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .buttonStyle(SumiPressStyle())
                        .foregroundStyle(Sumi.ink)
                        .disabled(entry.isMainObjective)
                    Button("REMOVE") { model.removeFromDailyPlan(entry) }
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .buttonStyle(SumiPressStyle())
                        .foregroundStyle(Sumi.seal)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: entry.isMainObjective)
    }
}

private struct MeetingCandidateLedger: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingCandidate: StoredMeetingCandidate?

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
                            if candidate.requiresClarification {
                                Text("TIME NEEDS REVIEW")
                                    .font(Sumi.label(8))
                                    .sumiLabelTracking()
                                    .foregroundStyle(Sumi.seal)
                            }
                        }
                        Spacer()
                        Button("ADD") { model.addMeetingCandidateToCalendar(candidate) }
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .buttonStyle(SumiPressStyle())
                            .foregroundStyle(Sumi.paper)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(Sumi.ink)
                            .accessibilityLabel("Add detected meeting to Apple Calendar")
                        Button("EDIT") { editingCandidate = candidate }
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .buttonStyle(SumiPressStyle())
                            .foregroundStyle(Sumi.ink)
                            .accessibilityLabel("Edit detected meeting before saving")
                        Button("IGNORE") { model.ignoreMeetingCandidate(candidate) }
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .buttonStyle(SumiPressStyle())
                            .foregroundStyle(Sumi.seal)
                            .accessibilityLabel("Ignore detected meeting")
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
                }
            }
            .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            .sheet(item: $editingCandidate) { candidate in
                MeetingCandidateEditor(candidate: candidate) { title, start, duration, destination in
                    model.saveMeetingCandidate(
                        candidate,
                        title: title,
                        start: start,
                        durationMinutes: duration,
                        destination: destination
                    )
                    editingCandidate = nil
                } onCancel: {
                    editingCandidate = nil
                }
            }
        )
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
        VStack(alignment: .leading, spacing: 18) {
            Text("CONFIRM MEETING")
                .font(Sumi.label(10))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            DatePicker("When", selection: $start)
            Stepper("Duration: \(duration) minutes", value: $duration, in: 15...240, step: 15)
            Picker("Save as", selection: $destination) {
                ForEach(MeetingDestination.allCases) { destination in
                    Text(destination.rawValue).tag(destination)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Button("CANCEL", action: cancel)
                    .buttonStyle(SumiPressStyle())
                    .foregroundStyle(Sumi.ink)
                Spacer()
                Button(destination == .calendar ? "ADD TO CALENDAR" : "CREATE REMINDER") {
                    save(title, start, duration, destination)
                }
                .buttonStyle(SumiPressStyle())
                .foregroundStyle(Sumi.paper)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Sumi.ink)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Sumi.paper)
    }
}

private struct TimeBlockSelector: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selectedMinutes: Int?
    let taskTitle: String
    let select: (Int) -> Void

    private let durations = [15, 30, 45, 60, 90]
    @State private var isChanging = false

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
            }
            Spacer()
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedMinutes)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isChanging)
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

private struct SumiPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

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

            Button("PLAN") {
                model.addToDailyPlan(task)
            }
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .buttonStyle(SumiPressStyle())
            .foregroundStyle(Sumi.paper)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Sumi.ink)
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
                Text("ZOID")
                    .font(Sumi.display(26))
                    .tracking(-0.8)
                Text("COACH / LOCAL COMMAND")
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
                Text("Release 0 · Instrumented foundation")
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
                Text("Instrumented foundation")
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
                .foregroundStyle(Sumi.paper)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Sumi.seal)
            }
            .buttonStyle(.plain)
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
                Text("RELEASE 0 / DAY ONE")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)

                Text("The command center\nis coming online.")
                    .font(Sumi.display(46))
                    .tracking(-1.5)
                    .foregroundStyle(Sumi.ink)

                Text("First we prove that intent, behavior, and intervention can share one reliable local state. Coaching remains in observation mode until the evidence is trustworthy.")
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
        }
    }
}

private struct SourceHealthRow: View {
    @EnvironmentObject private var model: AppModel
    let source: SourceHealth

    var body: some View {
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
            }

            Spacer()

            HealthBadge(state: source.state)

            Button(source.actionTitle.uppercased()) {
                model.checkSource(source.id)
            }
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .buttonStyle(.plain)
                .foregroundStyle(Sumi.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
                .accessibilityLabel(source.actionTitle + " " + source.title)
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
                title: "Local event store",
                copy: "Immutable source and domain events will make every state transition replayable and explainable.",
                state: "NEXT"
            )

            Divider()

            FoundationColumn(
                index: "02",
                title: "Rules before models",
                copy: "Release 1 will classify known work and gaming contexts without a remote or local model dependency.",
                state: "DECIDED"
            )

            Divider()

            FoundationColumn(
                index: "03",
                title: "Seven quiet days",
                copy: "Behavior is observed for one complete week before accountability prompts are allowed.",
                state: "LOCKED"
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
