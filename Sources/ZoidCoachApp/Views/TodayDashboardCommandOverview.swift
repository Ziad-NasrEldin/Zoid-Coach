import SwiftUI
import ZoidCoachCore

/// The decision-first surface for Today. The detailed reminder inventory remains
/// in `TodayCommandView`, below this overview, so its existing drag and reorder
/// behavior is preserved.
struct TodayDashboardCommandOverview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TODAY / ONE DELIBERATE MOVE")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Text(snapshot.localDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(Sumi.display(30))
                        .foregroundStyle(Sumi.ink)
                }
                Spacer(minLength: 20)
                Text("One working surface for the next commitment, its time, and the choices still waiting for you.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .frame(maxWidth: 300, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    focusCommitment
                    behaviorState.frame(width: 270)
                }
                VStack(alignment: .leading, spacing: 0) {
                    focusCommitment
                    behaviorState
                }
            }
            .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            .overlay(alignment: .top) { Rectangle().fill(Sumi.ink).frame(height: 2) }

            HStack(alignment: .top, spacing: 0) {
                dayMap
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                nextDecision.frame(width: 250)
            }
            .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    private var focusCommitment: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(primaryFocusRow == nil ? "MAIN OBJECTIVE" : "ACTIVE COMMITMENT · \(primaryFocusEstimateMinutes) MIN")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text(primaryFocusRow?.title ?? snapshot.mainObjective ?? snapshot.recommendation.sentence)
                .font(Sumi.display(28))
                .tracking(-0.7)
                .foregroundStyle(Sumi.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            if let row = primaryFocusRow {
                HStack(spacing: 14) {
                    detail("Estimate", "\(planEntry(for: row)?.estimateMinutes ?? row.estimateMinutes)m")
                    detail("Deadline", deadlineLabel(row.dueDate))
                    detail("Urgency", "\(row.urgency.rawValue.capitalized)")
                }
                .padding(.top, 12)
                if let entry = planEntry(for: row) {
                    TodayEstimateStrip(
                        selectedMinutes: entry.estimateMinutes,
                        taskTitle: row.title,
                        setEstimate: { model.setEstimate($0, for: entry) }
                    )
                    .padding(.top, 14)
                }
            }
            Spacer(minLength: 22)
            if let row = primaryFocusRow {
                Button(commandLabel(for: row)) { applyPrimaryCommand(to: row) }
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.paper)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Sumi.seal)
                    .buttonStyle(TodayCommandPressStyle())
                    .accessibilityLabel("\(commandLabel(for: row).capitalized) \(row.title)")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 244, alignment: .leading)
        .background(Sumi.softPaper)
        .overlay(alignment: .trailing) { Rectangle().fill(Sumi.rule).frame(width: 1) }
    }

    private var behaviorState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BEHAVIOR, SINCE MIDNIGHT")
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
            ZStack {
                Circle().stroke(Sumi.ink, lineWidth: 1)
                Circle().inset(by: 11).stroke(Sumi.rule, lineWidth: 1)
                VStack(spacing: 2) {
                    Text("\(snapshot.behavior.workMinutes)m")
                        .font(Sumi.display(24))
                        .foregroundStyle(Sumi.ink)
                    Text("WORKING")
                        .font(Sumi.label(7))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.muted)
                }
            }
            .frame(width: 104, height: 104)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            Text(snapshot.coverage.isLimited ? snapshot.coverage.explanation : "Observed activity is current.")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GAMING BUDGET")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                    Text("\(snapshot.gaming.unlockedRemainingMinutes)m")
                        .font(Sumi.display(19))
                }
                Spacer()
                Text(snapshot.gaming.nextUnlockReason)
                    .font(Sumi.body(9))
                    .foregroundStyle(Sumi.muted)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100, alignment: .trailing)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
            .padding(.top, 10)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 244, alignment: .topLeading)
        .background(Sumi.mist)
    }

    private var dayMap: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DAY MAP")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                Spacer()
                Text("\(plannedRows.count) PLANNED BLOCK\(plannedRows.count == 1 ? "" : "S")")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
            .padding(.bottom, 13)
            ForEach(plannedRows) { row in
                TodayPlanTaskRow(
                    row: row,
                    entry: planEntry(for: row),
                    isMainObjective: isMainObjective(row),
                    isRecommended: row.taskID == recommendedRow?.taskID,
                    applyCommand: { applyPrimaryCommand(to: row) },
                    makeMain: { planEntry(for: row).map(model.setMainObjective) },
                    setEstimate: { minutes in
                        if let entry = planEntry(for: row) {
                            model.setEstimate(minutes, for: entry)
                        }
                    },
                    remove: { planEntry(for: row).map(model.removeFromDailyPlan) }
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 228, alignment: .topLeading)
        .background(Sumi.paper)
        .overlay(alignment: .trailing) { Rectangle().fill(Sumi.rule).frame(width: 1) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.dailyPlan)
    }

    private var nextDecision: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DO THIS NEXT")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text(nextDecisionTitle)
                .font(Sumi.display(22))
                .tracking(-0.5)
                .foregroundStyle(Sumi.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
            Text(snapshot.recommendation.sentence)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .padding(.top, 8)
            Spacer(minLength: 14)
            Text(nextReason)
                .font(Sumi.body(10))
                .foregroundStyle(Sumi.ink)
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
            if let row = recommendedRow {
                Button(commandLabel(for: row)) { applyPrimaryCommand(to: row) }
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .overlay { Rectangle().stroke(Sumi.ink, lineWidth: 1) }
                    .buttonStyle(TodayCommandPressStyle())
                    .padding(.top, 14)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 228, alignment: .topLeading)
        .background(Sumi.softPaper)
    }

    private var activeRow: TodayTaskRow? {
        guard let activeID = snapshot.activeTask?.taskID else { return nil }
        return snapshot.taskRows.first { $0.taskID == activeID }
    }

    private var recommendedRow: TodayTaskRow? {
        if let recommendationID = snapshot.recommendation.taskID,
           let task = snapshot.taskRows.first(where: { $0.taskID == recommendationID }) {
            return task
        }
        return activeRow ?? snapshot.taskRows.first(where: { $0.state == .ready })
    }

    private var primaryFocusRow: TodayTaskRow? {
        activeRow
            ?? plannedRows.first(where: isMainObjective)
            ?? recommendedRow
    }

    private var primaryFocusEstimateMinutes: Int {
        guard let row = primaryFocusRow else { return 0 }
        return planEntry(for: row)?.estimateMinutes ?? row.estimateMinutes
    }

    private var plannedRows: [TodayTaskRow] {
        guard !model.dailyPlan.isEmpty else { return snapshot.taskRows }
        let snapshotRows = Dictionary(uniqueKeysWithValues: snapshot.taskRows.map { ($0.taskID, $0) })
        return model.dailyPlan
            .sorted { $0.rank < $1.rank }
            .compactMap { snapshotRows[$0.reminderID] }
    }

    private func planEntry(for row: TodayTaskRow) -> DailyPlanEntry? {
        model.dailyPlan.first { $0.reminderID == row.taskID }
    }

    private func isMainObjective(_ row: TodayTaskRow) -> Bool {
        planEntry(for: row)?.isMainObjective ?? row.isMainObjective
    }

    private var nextDecisionTitle: String {
        guard let row = recommendedRow else { return "No ready planned task remains." }
        switch row.state {
        case .active: return "Continue the active commitment."
        case .paused: return "Resume the planned commitment."
        case .ready: return "Begin the active commitment."
        case .blocked, .completed, .rescheduled: return snapshot.recommendation.sentence
        }
    }

    private var nextReason: String {
        guard let row = recommendedRow else { return "Keep the queue visible, then choose one item when you are ready to plan." }
        return "Why this: it is \(row.isMainObjective ? "the main objective" : "the next available commitment"), already represented in today’s plan."
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Sumi.label(7)).sumiLabelTracking().foregroundStyle(Sumi.muted)
            Text(value).font(Sumi.body(10)).foregroundStyle(Sumi.ink)
        }
    }

    private func deadlineLabel(_ date: Date?) -> String {
        guard let date else { return "None" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func commandLabel(for row: TodayTaskRow) -> String {
        switch row.state {
        case .active: return "COMPLETE FOCUS"
        case .paused: return "RESUME FOCUS"
        case .ready: return "BEGIN FOCUS"
        case .blocked, .completed, .rescheduled: return "VIEW PLAN"
        }
    }

    private func applyPrimaryCommand(to row: TodayTaskRow) {
        switch row.state {
        case .active: model.applyTaskCommand(.complete, taskID: row.taskID)
        case .paused: model.applyTaskCommand(.resume, taskID: row.taskID)
        case .ready: model.applyTaskCommand(.start, taskID: row.taskID)
        case .blocked, .completed, .rescheduled: break
        }
    }
}

private struct TodayPlanTaskRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: TodayTaskRow
    let entry: DailyPlanEntry?
    let isMainObjective: Bool
    let isRecommended: Bool
    let applyCommand: () -> Void
    let makeMain: () -> Void
    let setEstimate: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 14) {
                Text(isMainObjective ? "NOW" : "NEXT")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(Sumi.body(15))
                        .foregroundStyle(Sumi.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Text("\(effectiveEstimateMinutes)m · \(row.urgency.rawValue.capitalized) urgency · \(row.state.rawValue.capitalized)")
                        .font(Sumi.body(10))
                        .foregroundStyle(Sumi.muted)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if canApplyCommand {
                    Button(commandLabel, action: applyCommand)
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.paper)
                        .padding(.horizontal, 9)
                        .frame(height: 27)
                        .background(Sumi.ink)
                        .buttonStyle(TodayCommandPressStyle())
                        .accessibilityLabel("\(commandLabel.capitalized) \(row.title)")
                }
            }

            if let entry {
                VStack(alignment: .leading, spacing: 8) {
                    TodayEstimateStrip(
                        selectedMinutes: entry.estimateMinutes,
                        taskTitle: row.title,
                        setEstimate: setEstimate
                    )
                    HStack(spacing: 14) {
                        if !isMainObjective {
                            Button("MAKE MAIN", action: makeMain)
                                .foregroundStyle(Sumi.ink)
                                .accessibilityLabel("Make \(row.title) the main objective")
                        }
                        Button("REMOVE", action: remove)
                            .foregroundStyle(Sumi.seal)
                            .accessibilityLabel("Remove \(row.title) from today's plan")
                    }
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .buttonStyle(TodayCommandPressStyle())
                }
                .padding(.leading, 50)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(isRecommended ? Sumi.sealWash : Sumi.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: entry)
    }

    private var effectiveEstimateMinutes: Int { entry?.estimateMinutes ?? row.estimateMinutes }

    private var canApplyCommand: Bool {
        ![.blocked, .completed, .rescheduled].contains(row.state)
    }

    private var commandLabel: String {
        switch row.state {
        case .active: return "COMPLETE"
        case .paused: return "RESUME"
        case .ready: return "START"
        case .blocked, .completed, .rescheduled: return "VIEW"
        }
    }
}

private struct TodayEstimateStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selectedMinutes: Int?
    let taskTitle: String
    let setEstimate: (Int) -> Void
    private let options = [15, 30, 45, 60, 90]

    var body: some View {
        HStack(spacing: 6) {
            Text("TIME BLOCK")
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
            ForEach(options, id: \.self) { minutes in
                Button("\(minutes)") { setEstimate(minutes) }
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(selectedMinutes == minutes ? Sumi.paper : Sumi.ink)
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .background(selectedMinutes == minutes ? Sumi.seal : Sumi.paper)
                    .overlay { Rectangle().stroke(selectedMinutes == minutes ? Sumi.seal : Sumi.rule, lineWidth: 1) }
                    .buttonStyle(TodayCommandPressStyle())
                    .accessibilityLabel("Set \(taskTitle) estimate to \(minutes) minutes")
                    .accessibilityValue(selectedMinutes == minutes ? "Selected" : "Not selected")
            }
            if let selectedMinutes {
                Text("\(selectedMinutes) MIN SELECTED")
                    .font(Sumi.label(7))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                    .contentTransition(.numericText())
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedMinutes)
    }
}

private struct TodayCommandPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
