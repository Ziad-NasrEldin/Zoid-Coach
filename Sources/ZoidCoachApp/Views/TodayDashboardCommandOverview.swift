import SwiftUI
import ZoidCoachCore

/// The decision-first surface for Today. The detailed reminder inventory remains
/// in `TodayCommandView`, below this overview, so its existing drag and reorder
/// behavior is preserved.
struct TodayDashboardCommandOverview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let snapshot: TodaySnapshot
    @State private var isUsagePresented = false
    @State private var isPointerOverUsageAnchor = false
    @State private var isPointerOverUsagePanel = false
    @State private var isUsageSelectorActive = false
    @State private var usageDismissTask: Task<Void, Never>?
    @State private var pendingSwitchTask: TodayTaskRow?
    @FocusState private var isUsageFocused: Bool

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
            .background { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            .background(alignment: .top) { Rectangle().fill(Sumi.ink).frame(height: 2) }

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
        .alert("Switch active task?", isPresented: Binding(
            get: { pendingSwitchTask != nil },
            set: { if !$0 { pendingSwitchTask = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingSwitchTask = nil }
            Button("Switch and preserve time") {
                guard let row = pendingSwitchTask else { return }
                pendingSwitchTask = nil
                model.applyTaskCommand(.start, taskID: row.taskID)
            }
        } message: {
            Text("The current task will pause as Switching tasks. Its tracked time will be preserved, and \"\(pendingSwitchTask?.title ?? "the selected task")\" will start.")
        }
    }

    private var focusCommitment: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(primaryFocusHeading)
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
                    detail("Estimate", planEntry(for: row)?.estimateMinutes.map { "\($0)m" } ?? "Choose")
                    detail("Deadline", deadlineLabel(row.dueDate))
                    detail("Urgency", "\(row.urgency.rawValue.capitalized)")
                    if let reason = row.latestPauseReason {
                        detail("Last pause", reason.userFacingLabel.replacingOccurrences(of: "Paused ", with: ""))
                    }
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
                HStack(spacing: 10) {
                    Button(commandLabel(for: row)) { applyPrimaryCommand(to: row) }
                        .buttonStyle(SumiActionButtonStyle(role: .accent, size: .large))
                        .accessibilityLabel("\(commandLabel(for: row).capitalized) \(row.title)")
                    if row.state == .active {
                        pauseMenu(for: row)
                    } else if row.state == .paused {
                        Button("COMPLETE") { model.applyTaskCommand(.complete, taskID: row.taskID) }
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .large))
                            .accessibilityLabel("Complete paused task \(row.title)")
                    }
                }
                .disabled(model.isAnyTaskCommandPending)
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
                Button {
                    presentUsage()
                } label: {
                    ZStack {
                        Circle().fill(isUsagePresented ? Sumi.paper : Color.clear)
                        Circle().stroke(isUsagePresented ? Sumi.seal : Sumi.ink, lineWidth: isUsagePresented ? 2 : 1)
                        Circle()
                            .inset(by: isUsagePresented ? 8 : 11)
                            .stroke(isUsagePresented ? Sumi.seal.opacity(0.35) : Sumi.rule, lineWidth: 1)
                        VStack(spacing: 2) {
                            Text("\(snapshot.behavior.workMinutes)m")
                                .font(Sumi.display(24))
                                .foregroundStyle(Sumi.ink)
                            Text(isUsagePresented ? "VIEWING USE" : "WORKING")
                                .font(Sumi.label(7))
                                .sumiLabelTracking()
                                .foregroundStyle(isUsagePresented ? Sumi.seal : Sumi.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 104, height: 104)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .scaleEffect(isUsagePresented && !reduceMotion ? 1.035 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isUsagePresented)
                .focused($isUsageFocused)
                .onChange(of: isUsageFocused) { _, isFocused in
                    if isFocused { presentUsage() } else { scheduleUsageDismissal() }
                }
                .onHover { isHovering in
                    isPointerOverUsageAnchor = isHovering
                    if isHovering { presentUsage() } else { scheduleUsageDismissal() }
                }
                .help("Show observed app usage percentages")
                .accessibilityLabel("Working time, \(snapshot.behavior.workMinutes) minutes")
                .accessibilityValue(isUsagePresented ? "App usage details shown" : "App usage details hidden")
                .accessibilityHint("Shows app and category percentages while the pointer remains nearby.")
                .popover(isPresented: $isUsagePresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    AppUsagePopover(
                        behavior: snapshot.behavior,
                        selectorActive: $isUsageSelectorActive
                    )
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        isPointerOverUsagePanel = isHovering
                        if isHovering { cancelUsageDismissal() } else { scheduleUsageDismissal() }
                    }
                    .onDisappear {
                        isPointerOverUsagePanel = false
                        isUsageSelectorActive = false
                    }
                }
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

    private func presentUsage() {
        cancelUsageDismissal()
        isUsagePresented = true
    }

    private func scheduleUsageDismissal() {
        cancelUsageDismissal()
        usageDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            guard AppUsagePopoverDismissalPolicy.shouldDismiss(
                isAnchorFocused: isUsageFocused,
                isPointerOverAnchor: isPointerOverUsageAnchor,
                isPointerOverPanel: isPointerOverUsagePanel,
                isSelectorActive: isUsageSelectorActive
            ) else { return }
            isUsagePresented = false
        }
    }

    private func cancelUsageDismissal() {
        usageDismissTask?.cancel()
        usageDismissTask = nil
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
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
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

    private var primaryFocusHeading: String {
        guard let row = primaryFocusRow else { return "MAIN OBJECTIVE" }
        if row.state == .active {
            return "ACTIVE COMMITMENT · \(row.elapsedMinutes) MIN TRACKED"
        }
        if row.state == .paused, let reason = row.latestPauseReason {
            return reason.userFacingLabel.uppercased()
        }
        return "ACTIVE COMMITMENT · \(row.estimateMinutes) MIN ESTIMATE"
    }

    private var plannedRows: [TodayTaskRow] {
        snapshot.taskRows
    }

    private func planEntry(for row: TodayTaskRow) -> DailyPlanEntry? {
        model.dailyPlan.first { $0.reminderID == row.taskID }
    }

    private func isMainObjective(_ row: TodayTaskRow) -> Bool {
        row.isMainObjective
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
        case .ready:
            if let activeTaskID = snapshot.activeTask?.taskID, activeTaskID != row.taskID {
                pendingSwitchTask = row
            } else {
                model.applyTaskCommand(.start, taskID: row.taskID)
            }
        case .blocked, .completed, .rescheduled: break
        }
    }

    private func pauseMenu(for row: TodayTaskRow) -> some View {
        Menu {
            Button("Take a break") { model.applyTaskCommand(.pauseForBreak, taskID: row.taskID) }
            Button("External interruption") { model.applyTaskCommand(.pauseForExternalInterruption, taskID: row.taskID) }
            Button("Done for now") { model.applyTaskCommand(.pauseDoneForNow, taskID: row.taskID) }
            Button("End the workday") { model.applyTaskCommand(.pauseForEndOfDay, taskID: row.taskID) }
            Divider()
            Button("Task is blocked") { model.applyTaskCommand(.block, taskID: row.taskID) }
        } label: {
            SumiSelectorLabel("PAUSE", systemImage: "pause.fill", size: .standard)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Pause \(row.title)")
        .accessibilityHint("Choose a reason. Zoid 666 preserves it in local task history.")
    }
}

enum AppUsagePopoverDismissalPolicy {
    static func shouldDismiss(
        isAnchorFocused: Bool,
        isPointerOverAnchor: Bool,
        isPointerOverPanel: Bool,
        isSelectorActive: Bool
    ) -> Bool {
        !isAnchorFocused && !isPointerOverAnchor && !isPointerOverPanel && !isSelectorActive
    }
}

private struct AppUsagePopover: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let behavior: BehaviorSummary
    @Binding var selectorActive: Bool
    @State private var selectedCategory: AppUsageCategory = .all
    @State private var presentationMode: AppUsagePresentationMode = .applications

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentationMode == .applications ? "OBSERVED APP USE" : "CATEGORY TOTALS")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Text(presentationMode == .applications ? "Since midnight" : "Since midnight · 100%")
                        .font(Sumi.body(16))
                        .foregroundStyle(Sumi.ink)
                        .contentTransition(.interpolate)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    UsagePanelIconButton(
                        systemImage: presentationMode == .applications ? "square.grid.2x2" : "list.bullet",
                        accessibilityLabel: presentationMode == .applications ? "Show category totals" : "Show individual applications"
                    ) {
                        presentationMode = presentationMode == .applications ? .categories : .applications
                    }
                }
            }

            Rectangle().fill(Sumi.ink).frame(height: 1).padding(.top, 12)

            if presentationMode == .applications {
                AppUsageInlineCategorySelector(
                    selection: $selectedCategory,
                    isActive: $selectorActive
                )
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .offset(y: -5)))
            }

            usageList
                .frame(height: presentationMode == .applications ? 195 : 230, alignment: .top)

            Text(footerLabel)
                .font(Sumi.label(7))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)
                .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        }
        .padding(18)
        .frame(width: 300, height: 352, alignment: .topLeading)
        .background(Sumi.paper)
        .overlay { Rectangle().stroke(Sumi.ink, lineWidth: 1) }
        .overlay(alignment: .top) { Rectangle().fill(Sumi.seal).frame(height: 2) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedCategory)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: presentationMode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Observed usage since midnight")
    }

    @ViewBuilder
    private var usageList: some View {
        if displayedItems.isEmpty {
            Text(emptyMessage)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 14)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayedItems) { item in
                        usageRow(item)
                            .transition(.opacity.combined(with: .offset(x: 7)))
                    }
                }
                .id("\(presentationMode.rawValue)-\(selectedCategory.rawValue)")
            }
        }
    }

    private var displayedItems: [UsageDisplayItem] {
        switch presentationMode {
        case .applications:
            let filtered: [AppUsageBreakdown]
            if let classification = selectedCategory.classification {
                filtered = behavior.appUsage.filter { $0.classification == classification }
            } else {
                filtered = behavior.appUsage
            }
            return filtered.map {
                UsageDisplayItem(id: "app-\($0.application)", title: $0.application, observedSeconds: $0.observedSeconds, percentage: $0.percentage)
            }
        case .categories:
            return behavior.categoryUsage.map {
                let category = AppUsageCategory(classification: $0.classification)
                return UsageDisplayItem(id: "category-\($0.classification.rawValue)", title: category.title, observedSeconds: $0.observedSeconds, percentage: $0.percentage)
            }
        }
    }

    private var emptyMessage: String {
        if presentationMode == .categories { return "No categorized activity is available yet." }
        return selectedCategory == .all
            ? "No attributable app time is available yet."
            : "No \(selectedCategory.title.lowercased()) app time was observed."
    }

    private var footerLabel: String {
        if presentationMode == .categories { return "Category shares of all observed time" }
        let percentage = displayedItems.reduce(0) { $0 + $1.percentage }
        if selectedCategory == .all { return "App shares of all observed time" }
        return "\(selectedCategory.title) · \(percentage.formatted(.number.precision(.fractionLength(1))))% of observed time"
    }

    private func usageRow(_ item: UsageDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.title)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(item.percentage.formatted(.number.precision(.fractionLength(1))) + "%")
                    .font(Sumi.label(9))
                    .monospacedDigit()
                    .foregroundStyle(Sumi.ink)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Sumi.paleRule)
                    Rectangle().fill(Sumi.ink).frame(width: proxy.size.width * item.percentage / 100)
                }
            }
            .frame(height: 3)
            Text(durationLabel(item.observedSeconds))
                .font(Sumi.label(7))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.percentage.formatted(.number.precision(.fractionLength(1)))) percent, \(durationLabel(item.observedSeconds))")
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "<1 MIN OBSERVED" }
        return "\(Int((Double(seconds) / 60).rounded())) MIN OBSERVED"
    }
}

private enum AppUsagePresentationMode: String {
    case applications
    case categories
}

private struct UsageDisplayItem: Identifiable {
    let id: String
    let title: String
    let observedSeconds: Int
    let percentage: Double
}

private enum AppUsageCategory: String, CaseIterable, Identifiable {
    case all
    case work
    case gaming
    case distracting
    case idle
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All apps"
        case .work: "Work"
        case .gaming: "Gaming"
        case .distracting: "Distraction"
        case .idle: "Idle"
        case .unknown: "Unclassified"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .work: "briefcase"
        case .gaming: "gamecontroller"
        case .distracting: "eye.slash"
        case .idle: "moon.zzz"
        case .unknown: "questionmark"
        }
    }

    var classification: BehaviorClassification? {
        switch self {
        case .all: nil
        case .work: .work
        case .gaming: .gaming
        case .distracting: .distracting
        case .idle: .idle
        case .unknown: .unknown
        }
    }

    init(classification: BehaviorClassification) {
        switch classification {
        case .work: self = .work
        case .gaming: self = .gaming
        case .distracting: self = .distracting
        case .idle: self = .idle
        case .unknown: self = .unknown
        }
    }
}

private struct AppUsageInlineCategorySelector: View {
    @Binding var selection: AppUsageCategory
    @Binding var isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(AppUsageCategory.allCases) { category in
                Button {
                    isActive = true
                    selection = category
                    isActive = false
                } label: {
                    Image(systemName: category.systemImage)
                        .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selection == category ? Sumi.paper : Sumi.ink)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(selection == category ? Sumi.ink : Sumi.paper)
                    .overlay { Rectangle().stroke(selection == category ? Sumi.ink : Sumi.rule, lineWidth: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(category.title)
                .accessibilityLabel(category.title)
                .accessibilityValue(selection == category ? "Selected" : "Not selected")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter applications by category")
    }
}

private struct UsagePanelIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? Sumi.paper : Sumi.ink)
                .frame(width: 30, height: 30)
                .background(isHovering ? Sumi.seal : Sumi.paper)
                .overlay { Rectangle().stroke(isHovering ? Sumi.seal : Sumi.rule, lineWidth: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
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
                    Text("\(estimateSummary) · \(row.urgency.rawValue.capitalized) urgency · \(row.state.rawValue.capitalized)")
                        .font(Sumi.body(10))
                        .foregroundStyle(Sumi.muted)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if canApplyCommand {
                    Button(commandLabel, action: applyCommand)
                        .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
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
                                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                                .accessibilityLabel("Make \(row.title) the main objective")
                        }
                        Button("REMOVE", action: remove)
                            .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                            .accessibilityLabel("Remove \(row.title) from today's plan")
                    }
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

    private var estimateSummary: String {
        if let entry {
            return entry.estimateMinutes.map { "\($0)m" } ?? "Estimate needed"
        }
        return "\(row.estimateMinutes)m"
    }

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

private typealias TodayCommandPressStyle = SumiPressButtonStyle
