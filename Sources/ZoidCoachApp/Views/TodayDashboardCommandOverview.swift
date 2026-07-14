import SwiftUI
import ZoidCoachCore

/// The decision-first surface for Today. The detailed reminder inventory remains
/// in `TodayCommandView`, below this overview, so its existing drag and reorder
/// behavior is preserved.
struct TodayDashboardCommandOverview: View {
    @EnvironmentObject private var model: AppModel
    @SumiReduceMotion private var reduceMotion
    let snapshot: TodaySnapshot
    @State private var isUsagePresented = false
    @State private var isBehaviorEvidencePresented = false
    @State private var isPointerOverUsageAnchor = false
    @State private var isPointerOverUsagePanel = false
    @State private var isUsageSelectorActive = false
    @State private var usageDismissTask: Task<Void, Never>?
    @State private var pendingSwitchTask: TodayTaskRow?
    @State private var customSprintTask: TodayTaskRow?
    @State private var offlineWorkTask: TodayTaskRow?
    @State private var blockReasonTask: TodayTaskRow?
    @State private var blockReason = ""
    @State private var gamingAdjustmentPresentation: GamingManualAdjustmentPresentation?
    @FocusState private var isUsageFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayDayStateHeader(
                date: snapshot.localDate,
                presentation: .resolve(snapshot: snapshot)
            )

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
        .sheet(item: $customSprintTask) { row in
            CustomSprintDurationSheet(
                taskTitle: row.title,
                isPending: model.isAnyTaskCommandPending,
                cancel: { customSprintTask = nil },
                start: { durationMinutes in
                    customSprintTask = nil
                    model.startSprint(taskID: row.taskID, durationMinutes: durationMinutes)
                }
            )
        }
        .sheet(item: $offlineWorkTask) { row in
            ActiveOfflineWorkSheet(task: row)
        }
        .sheet(item: $blockReasonTask) { row in
            TaskBlockReasonSheet(taskTitle: row.title, reason: $blockReason) {
                blockReasonTask = nil
                model.markTaskBlocked(taskID: row.taskID, reason: blockReason)
            }
        }
        .sheet(isPresented: $isBehaviorEvidencePresented) {
            BehaviorEvidenceSheet(snapshot: snapshot)
                .environmentObject(model)
        }
        .sheet(item: $gamingAdjustmentPresentation) { presentation in
            GamingManualAdjustmentSheet(
                currentManualMinutes: presentation.currentManualMinutes,
                isSaving: model.isSavingGamingManualAdjustment,
                cancel: { gamingAdjustmentPresentation = nil },
                save: { minutes, note in
                    gamingAdjustmentPresentation = nil
                    model.recordGamingManualAdjustment(
                        minutes: minutes,
                        note: note,
                        presentation: presentation
                    )
                }
            )
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
                if let activeCommitment = ActiveCommitmentPresentation(task: row) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(activeCommitment.modeLabel)
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.sealDeep)
                        Text(activeCommitment.detail)
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(activeCommitment.accessibilitySummary)
                    .accessibilityIdentifier("today.active-commitment.timing-mode")
                }
                HStack(spacing: 14) {
                    detail("Estimate", planEntry(for: row)?.estimateMinutes.map { "\($0)m" } ?? "Choose")
                    detail("Deadline", deadlineLabel(row.dueDate))
                    detail("Urgency", "\(row.urgency.rawValue.capitalized)")
                    if let reason = row.completionReason {
                        detail("Completion", reason.userFacingLabel)
                    }
                    if let reason = row.latestPauseReason {
                        detail("Last pause", reason.userFacingLabel.replacingOccurrences(of: "Paused ", with: ""))
                    }
                }
                .padding(.top, 12)
                if row.state == .active || row.state == .paused {
                    TaskEstimateProgressView(
                        progress: TaskEstimateProgress(
                            elapsedMinutes: row.elapsedMinutes,
                            estimateMinutes: row.estimateMinutes
                        ),
                        isRunning: row.state == .active,
                        identifier: "today.focus.estimate-progress"
                    )
                    .padding(.top, 14)
                }
                if let comparison = row.activeTimeComparison {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            detail("Task elapsed", "\(comparison.elapsedMinutes)m")
                            detail("Observed aligned", "\(comparison.observedAlignedMinutes)m")
                        }
                        Text(comparison.evidenceExplanation)
                            .font(Sumi.body(10))
                            .foregroundStyle(Sumi.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 14)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(comparison.accessibilitySummary)
                    .accessibilityIdentifier("today.focus.active-time-comparison")
                }
                if row.state == .active, let context = snapshot.activeTaskContext {
                    ActiveTaskContextPanel(assessment: context)
                        .padding(.top, 14)
                }
                if let sprint = row.sprint {
                    SprintCommitmentPanel(sprint: sprint, taskID: row.taskID)
                        .padding(.top, 14)
                } else if row.state == .ready || row.state == .active {
                    sprintStartMenu(for: row)
                        .padding(.top, 14)
                }
                if let entry = planEntry(for: row) {
                    TodayEstimateStrip(
                        selectedMinutes: entry.estimateMinutes,
                        isUnknown: entry.estimateIsUncertain,
                        taskTitle: row.title,
                        taskID: row.taskID,
                        setEstimate: { model.setEstimate($0, for: entry) },
                        setUnknown: { model.setEstimateUnknown(for: entry) }
                    )
                    .padding(.top, 14)
                    if let suggestion = row.learnedEstimateSuggestion {
                        LearnedEstimateSuggestionView(
                            taskID: row.taskID,
                            taskTitle: row.title,
                            suggestion: suggestion,
                            currentEstimateMinutes: entry.estimateIsUncertain ? nil : entry.estimateMinutes,
                            useSuggestion: { model.setEstimate($0, for: entry) }
                        )
                        .padding(.top, 10)
                    }
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
                    if row.state == .active || row.state == .paused {
                        Button("ADD AWAY WORK") { offlineWorkTask = row }
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .large))
                            .help("Record intentional work completed away from this Mac")
                            .accessibilityLabel("Add away-from-Mac work for \(row.title)")
                            .accessibilityIdentifier("today.focus.offline-work.\(row.taskID)")
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
                .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.2), value: isUsagePresented)
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
                Button("VIEW ALL ACTIVITY") {
                    isBehaviorEvidencePresented = true
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityHint("Shows separate behavior totals, uncertainty, source limits, and correction actions.")
                .accessibilityIdentifier("today.behavior-evidence.open")
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.gaming.budgetEnabled ? "GAMING BUDGET" : "GAMING OBSERVED")
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                        Text(gamingAllowanceHeadline)
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
                if snapshot.gaming.budgetEnabled {
                    if model.gamingManualAdjustmentLedgerError == nil {
                        Text(snapshot.gaming.allowanceBreakdown)
                            .font(Sumi.body(9))
                            .foregroundStyle(Sumi.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("today.gaming.breakdown")
                    }
                    Text(GamingStatus.meaningfulSessionExplanation)
                        .font(Sumi.body(9))
                        .foregroundStyle(Sumi.muted)
                    Button("ADJUST MANUAL TIME") {
                        gamingAdjustmentPresentation = GamingManualAdjustmentPresentation(
                            localDate: snapshot.localDate,
                            timeZoneIdentifier: snapshot.timeZoneIdentifier,
                            currentManualMinutes: snapshot.gaming.manualAdjustmentMinutes
                        )
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .disabled(
                        model.runtimeSafety.isReadOnly
                            || model.isSavingGamingManualAdjustment
                            || model.gamingManualAdjustmentLedgerError != nil
                    )
                    .accessibilityLabel("Adjust manually granted gaming time")
                    .accessibilityHint("Add time to today's allowance or remove time that you manually granted earlier today.")
                    .accessibilityIdentifier("today.gaming.manual-adjustment.open")
                    if let ledgerError = model.gamingManualAdjustmentLedgerError {
                        Text(ledgerError)
                            .font(Sumi.body(9))
                            .foregroundStyle(Sumi.seal)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("today.gaming.manual-adjustment.unavailable")
                    } else if !model.gamingManualAdjustments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("MANUAL ADJUSTMENT HISTORY")
                                .font(Sumi.label(8))
                                .sumiLabelTracking()
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 7) {
                                    ForEach(Array(model.gamingManualAdjustments.reversed())) { adjustment in
                                        GamingManualAdjustmentLedgerRow(adjustment: adjustment)
                                    }
                                }
                            }
                            .frame(maxHeight: 132)
                        }
                        .padding(.top, 4)
                        .accessibilityIdentifier("today.gaming.manual-adjustment.history")
                    }
                    if let message = model.gamingManualAdjustmentMessage {
                        Text(message)
                            .font(Sumi.body(9))
                            .foregroundStyle(Sumi.okay)
                            .accessibilityIdentifier("today.gaming.manual-adjustment.success")
                    }
                    if let error = model.gamingManualAdjustmentError {
                        Text(error)
                            .font(Sumi.body(9))
                            .foregroundStyle(Sumi.seal)
                            .accessibilityIdentifier("today.gaming.manual-adjustment.error")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 244, alignment: .topLeading)
            .background(Sumi.mist)
    }

    private func presentUsage() {
        cancelUsageDismissal()
        isUsagePresented = true
    }

    private var gamingAllowanceHeadline: String {
        guard snapshot.gaming.budgetEnabled else {
            return "\(snapshot.gaming.usedMinutes)m"
        }
        guard model.gamingManualAdjustmentLedgerError == nil else {
            return "Allowance unavailable"
        }
        return "\(snapshot.gaming.unlockedRemainingMinutes)m left"
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
                    gaming: snapshot.gaming,
                    planCount: model.dailyPlan.count,
                    isMainObjective: isMainObjective(row),
                    isRecommended: row.taskID == recommendedRow?.taskID,
                    applyCommand: { applyPrimaryCommand(to: row) },
                    makeMain: { planEntry(for: row).map(model.setMainObjective) },
                    setEstimate: { minutes in
                        if let entry = planEntry(for: row) {
                            model.setEstimate(minutes, for: entry)
                        }
                    },
                    setUnknown: {
                        if let entry = planEntry(for: row) {
                            model.setEstimateUnknown(for: entry)
                        }
                    },
                    moveUp: { planEntry(for: row).map { model.moveDailyPlanEntry($0, by: -1) } },
                    moveDown: { planEntry(for: row).map { model.moveDailyPlanEntry($0, by: 1) } },
                    toggleOptional: { planEntry(for: row).map(model.toggleOptional) },
                    toggleDeferral: {
                        guard let entry = planEntry(for: row) else { return }
                        if entry.deferredUntil == nil {
                            model.deferTaskUntilTomorrow(entry)
                        } else {
                            model.clearTaskDeferral(entry)
                        }
                    },
                    markBlocked: { reason in
                        model.markTaskBlocked(taskID: row.taskID, reason: reason)
                    },
                    remove: { planEntry(for: row).map(model.removeFromDailyPlan) }
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 228, alignment: .topLeading)
        .background(Sumi.paper)
        .overlay(alignment: .trailing) { Rectangle().fill(Sumi.rule).frame(width: 1) }
        .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.22), value: model.dailyPlan)
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
            Text(recommendationSentence)
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
                if row.state == .ready,
                   let sprintMinutes = recommendedSprintMinutes {
                    Button("START \(sprintMinutes)-MINUTE SPRINT") {
                        model.startSprint(taskID: row.taskID, durationMinutes: sprintMinutes)
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                    .disabled(model.isAnyTaskCommandPending)
                    .padding(.top, 14)
                    .accessibilityLabel("Start a \(sprintMinutes)-minute sprint for \(row.title)")
                    .accessibilityHint("Starts a bounded sprint that fits the available time. The task stays incomplete when the sprint ends.")
                    .accessibilityIdentifier("today.recommendation.start-sprint")
                } else {
                    Button(commandLabel(for: row)) { applyPrimaryCommand(to: row) }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                        .disabled(model.isAnyTaskCommandPending)
                        .padding(.top, 14)
                }
                if row.state == .ready,
                   snapshot.recommendation.taskID == row.taskID {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECOMMEND SOMETHING ELSE")
                            .font(Sumi.label(7))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.muted)
                        feedbackButton("NOT NOW", kind: .notNow, row: row)
                        feedbackButton("WRONG PRIORITY", kind: .wrongPriority, row: row)
                        feedbackButton("TOO LARGE", kind: .tooLarge, row: row)
                    }
                    .padding(.top, 12)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("today.recommendation.feedback")
                }
            }
            if model.pendingRecommendationFeedbackTaskID != nil {
                ProgressView("Saving feedback")
                    .controlSize(.small)
                    .padding(.top, 8)
                    .accessibilityIdentifier("today.recommendation.feedback.progress")
            }
            if let message = model.recommendationFeedbackMessage {
                Text(message)
                    .font(Sumi.body(10))
                    .foregroundStyle(Sumi.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityIdentifier("today.recommendation.feedback.status")
            }
            if let error = model.recommendationFeedbackError {
                Text(error)
                    .font(Sumi.body(10))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityIdentifier("today.recommendation.feedback.error")
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
        return activeRow
    }

    private var recommendedSprintMinutes: Int? {
        guard let row = recommendedRow else { return nil }
        return RecommendationSprintPresentation.durationMinutes(
            estimateMinutes: row.estimateMinutes,
            availableMinutes: model.planningCapacityState.availableMinutes
        )
    }

    private var recommendationSentence: String {
        guard let row = recommendedRow,
              let sprintMinutes = recommendedSprintMinutes else {
            return snapshot.recommendation.sentence
        }
        return RecommendationSprintPresentation.sentence(
            taskTitle: row.title,
            sprintMinutes: sprintMinutes,
            availableMinutes: model.planningCapacityState.availableMinutes
        )
    }

    private var primaryFocusRow: TodayTaskRow? {
        activeRow
            ?? plannedRows.first(where: isMainObjective)
            ?? recommendedRow
    }

    private var primaryFocusHeading: String {
        guard let row = primaryFocusRow else { return "MAIN OBJECTIVE" }
        if let reason = row.completionReason {
            return reason.userFacingLabel.uppercased()
        }
        if let activeCommitment = ActiveCommitmentPresentation(task: row) {
            return activeCommitment.dashboardHeading
        }
        if row.state == .paused, let reason = row.latestPauseReason {
            return reason.userFacingLabel.uppercased()
        }
        if let entry = planEntry(for: row) {
            if entry.estimateIsUncertain {
                return "ACTIVE COMMITMENT · UNKNOWN · ~\(PlanningCapacityState.unknownEstimatePlaceholderMinutes) MIN PLACEHOLDER"
            }
            guard let estimateMinutes = entry.estimateMinutes else {
                return "ACTIVE COMMITMENT · ESTIMATE NEEDED"
            }
            return "ACTIVE COMMITMENT · \(estimateMinutes) MIN ESTIMATE"
        }
        return "ACTIVE COMMITMENT · \(row.estimateMinutes) MIN ESTIMATE"
    }

    private var plannedRows: [TodayTaskRow] {
        guard !model.isLoadingDailyPlan else { return snapshot.taskRows }
        return TodayPlanPresentation.rows(
            snapshotRows: snapshot.taskRows,
            livePlan: model.dailyPlan,
            reminders: model.reminderTasks
        )
    }

    private func planEntry(for row: TodayTaskRow) -> DailyPlanEntry? {
        model.dailyPlan.first { $0.reminderID == row.taskID }
    }

    private func isMainObjective(_ row: TodayTaskRow) -> Bool {
        TodayPlanMainObjectiveState.resolve(
            snapshotIsMainObjective: row.isMainObjective,
            livePlanEntry: planEntry(for: row)
        )
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

    private func feedbackButton(
        _ title: String,
        kind: RecommendationFeedbackKind,
        row: TodayTaskRow
    ) -> some View {
        Button(title) {
            model.recordRecommendationFeedback(
                kind,
                taskID: row.taskID,
                recommendationSentence: snapshot.recommendation.sentence
            )
        }
        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
        .disabled(model.pendingRecommendationFeedbackTaskID != nil)
        .accessibilityHint(kind.confirmationMessage)
        .accessibilityIdentifier("today.recommendation.feedback.\(kind.rawValue)")
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
            Button("Task is blocked") {
                blockReason = row.blockedReason ?? ""
                blockReasonTask = row
            }
        } label: {
            SumiSelectorLabel("PAUSE", systemImage: "pause.fill", size: .standard)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Pause \(row.title)")
        .accessibilityHint("Choose a reason. Zoid 666 preserves it in local task history.")
    }

    private func sprintStartMenu(for row: TodayTaskRow) -> some View {
        Menu {
            Button("10-minute recovery sprint") { model.applyTaskCommand(.startSprint10, taskID: row.taskID) }
            Button("20-minute work sprint") { model.applyTaskCommand(.startSprint20, taskID: row.taskID) }
            Button("25-minute focus sprint") { model.applyTaskCommand(.startSprint25, taskID: row.taskID) }
            Divider()
            Button("Custom duration…") { customSprintTask = row }
        } label: {
            SumiSelectorLabel("START A BOUNDED SPRINT", systemImage: "timer", size: .standard)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isAnyTaskCommandPending)
        .accessibilityIdentifier("today.sprint.start.\(row.taskID)")
        .accessibilityHint("Choose a time boundary. The task will stay incomplete when the sprint ends.")
    }
}

private struct GamingManualAdjustmentSheet: View {
    @State private var form: GamingManualAdjustmentForm
    let isSaving: Bool
    let cancel: () -> Void
    let save: (Int, String?) -> Void

    init(
        currentManualMinutes: Int,
        isSaving: Bool,
        cancel: @escaping () -> Void,
        save: @escaping (Int, String?) -> Void
    ) {
        _form = State(initialValue: GamingManualAdjustmentForm(
            currentManualMinutes: currentManualMinutes
        ))
        self.isSaving = isSaving
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("GAMING ALLOWANCE")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text("Adjust manually granted time")
                .font(Sumi.display(25))
                .foregroundStyle(Sumi.ink)
            Text("Observed gaming stays unchanged. This only changes today's manual allowance, and every change is saved as a separate local ledger entry.")
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Adjustment", selection: $form.direction) {
                ForEach(GamingManualAdjustmentDirection.allCases) { direction in
                    Text(direction.label).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("today.gaming.manual-adjustment.direction")

            Stepper(value: $form.minutes, in: 5...240, step: 5) {
                Text("\(form.minutes) minutes")
                    .font(Sumi.body(13))
            }
            .accessibilityIdentifier("today.gaming.manual-adjustment.minutes")

            TextField("Optional reason", text: $form.note)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("today.gaming.manual-adjustment.note")

            if form.currentManualMinutes > 0 {
                Text("Currently manually granted: \(form.currentManualMinutes) minutes")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
            }
            if let validation = form.validationMessage {
                Text(validation)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.seal)
                    .accessibilityIdentifier("today.gaming.manual-adjustment.validation")
            }

            HStack {
                Button("Cancel", action: cancel)
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isSaving ? "SAVING" : form.direction == .add ? "ADD TIME" : "REMOVE TIME") {
                    guard let signedMinutes = form.signedMinutes else { return }
                    save(signedMinutes, form.normalizedNote)
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                .disabled(!form.canSubmit || isSaving)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("today.gaming.manual-adjustment.save")
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct GamingManualAdjustmentLedgerRow: View {
    let adjustment: GamingManualAdjustment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(adjustment.minutes > 0 ? "+\(adjustment.minutes)m" : "\(adjustment.minutes)m")
                .font(Sumi.label(8))
                .foregroundStyle(adjustment.minutes > 0 ? Sumi.okay : Sumi.seal)
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(adjustment.note ?? (adjustment.minutes > 0 ? "Manual grant" : "Manual removal"))
                    .font(Sumi.body(9))
                    .foregroundStyle(Sumi.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(adjustment.recordedAt.formatted(date: .omitted, time: .shortened))
                    .font(Sumi.body(8))
                    .foregroundStyle(Sumi.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(adjustment.minutes > 0 ? "Added" : "Removed") \(adjustment.minutes.magnitude) minutes, "
                + "\(adjustment.note ?? "No note"), \(adjustment.recordedAt.formatted(date: .omitted, time: .shortened))"
        )
        .accessibilityIdentifier("today.gaming.manual-adjustment.entry.\(adjustment.id)")
    }
}

private struct ActiveTaskContextPanel: View {
    let assessment: ActiveTaskContextAssessment

    private var symbolName: String {
        switch assessment.state {
        case .aligned: "checkmark.circle"
        case .uncertain: "questionmark.circle"
        case .mismatched: "arrow.triangle.branch"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Sumi.seal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(assessment.state.title.uppercased())
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.ink)
                Text(assessment.explanation)
                    .font(Sumi.body(10))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sumi.paper)
        .overlay { Rectangle().stroke(Sumi.paleRule, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.focus.context-assessment")
    }
}

private struct CustomSprintDurationSheet: View {
    let taskTitle: String
    let isPending: Bool
    let cancel: () -> Void
    let start: (Int) -> Void
    @State private var durationText = "30"

    private var durationMinutes: Int? {
        guard let value = Int(durationText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...240).contains(value)
        else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("CUSTOM SPRINT")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text(taskTitle)
                .font(Sumi.display(24))
                .foregroundStyle(Sumi.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose 1 to 240 minutes. When the timer reaches zero, the task stays active until you complete, pause, or continue it.")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
            SumiTextField("DURATION IN MINUTES", placeholder: "30", text: $durationText)
                .accessibilityIdentifier("today.sprint.custom.duration")
            if durationMinutes == nil {
                Text("Enter a whole number from 1 to 240.")
                    .font(Sumi.body(10))
                    .foregroundStyle(Sumi.seal)
                    .accessibilityIdentifier("today.sprint.custom.error")
            }
            HStack {
                Button("CANCEL", action: cancel)
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                Spacer()
                Button("START SPRINT") {
                    guard let durationMinutes else { return }
                    start(durationMinutes)
                }
                .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
                .disabled(durationMinutes == nil || isPending)
                .accessibilityIdentifier("today.sprint.custom.start")
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Sumi.paper)
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

private struct SprintCommitmentPanel: View {
    @EnvironmentObject private var model: AppModel
    let sprint: SprintSnapshot
    let taskID: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = sprint.remainingSeconds(at: context.date)
            let hasEnded = remaining == 0 && sprint.isBounded
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(statusTitle(hasEnded: hasEnded))
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(hasEnded ? Sumi.seal : Sumi.muted)
                    Spacer()
                    Text(sprint.state == .continuedOpenEnded ? "OPEN" : timeLabel(remaining))
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(Sumi.ink)
                        .monospacedDigit()
                        .accessibilityLabel(timerAccessibilityLabel(remaining: remaining, hasEnded: hasEnded))
                }
                Text(statusExplanation(hasEnded: hasEnded))
                    .font(Sumi.body(10))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if hasEnded {
                    Button("CONTINUE OPEN-ENDED") {
                        model.applyTaskCommand(.continueOpenEnded, taskID: taskID)
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .disabled(model.isAnyTaskCommandPending)
                    .accessibilityIdentifier("today.sprint.continue.\(taskID)")
                }
            }
            .padding(12)
            .background(Sumi.mist)
            .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.sprint.status.\(taskID)")
        }
    }

    private func timeLabel(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func timerAccessibilityLabel(remaining: Int, hasEnded: Bool) -> String {
        if sprint.state == .continuedOpenEnded { return "Open-ended continuation" }
        if hasEnded { return "Sprint complete" }
        return "\(remaining / 60) minutes and \(remaining % 60) seconds remaining"
    }

    private func statusTitle(hasEnded: Bool) -> String {
        if sprint.state == .continuedOpenEnded { return "OPEN-ENDED CONTINUATION" }
        if sprint.state == .paused { return "SPRINT PAUSED" }
        return hasEnded ? "SPRINT COMPLETE" : "BOUNDED SPRINT"
    }

    private func statusExplanation(hasEnded: Bool) -> String {
        if sprint.state == .continuedOpenEnded {
            return "The sprint boundary ended. Work is continuing without a timer, and the task remains incomplete."
        }
        if hasEnded {
            return "The time boundary ended. Your task is still active and was not marked complete."
        }
        return "\(sprint.durationMinutes) minutes, with pause and restart-safe timing. Completing the sprint never completes the task automatically."
    }
}

private struct AppUsagePopover: View {
    @SumiReduceMotion private var reduceMotion
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
                .transition(SumiMotion.transition(
                    reduceMotion: reduceMotion,
                    normal: .opacity.combined(with: .offset(y: -5))
                ))
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
        .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.2), value: selectedCategory)
        .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.2), value: presentationMode)
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
                            .transition(SumiMotion.transition(
                                reduceMotion: reduceMotion,
                                normal: .opacity.combined(with: .offset(x: 7))
                            ))
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

struct TodayPlanMainObjectiveState {
    static func resolve(
        snapshotIsMainObjective: Bool,
        livePlanEntry: DailyPlanEntry?
    ) -> Bool {
        livePlanEntry?.isMainObjective ?? snapshotIsMainObjective
    }
}

struct TodayPlanGamingUnlockControlState: Equatable, Sendable {
    private let presentation: GamingUnlockConditionPresentation
    let isMainObjective: Bool

    init(gaming: GamingStatus, isMainObjective: Bool) {
        presentation = GamingUnlockConditionPresentation(gaming: gaming)
        self.isMainObjective = isMainObjective
    }

    var conditionLabel: String? {
        presentation.conditionLabel(isMainObjective: isMainObjective)
    }

    var makeMainTitle: String {
        presentation.isConfigurable ? presentation.makeMainTitle(isMainObjective: false) : "MAKE MAIN"
    }

    var requiresConfirmation: Bool {
        presentation.isConfigurable && !isMainObjective
    }

    var accessibilityHint: String {
        requiresConfirmation
            ? "Moves both today's main objective and the one-time gaming reward condition to this task."
            : "Makes this task today's main objective."
    }

    func confirmationMessage(taskTitle: String) -> String {
        presentation.confirmationMessage(taskTitle: taskTitle)
    }
}

private struct TodayPlanTaskRow: View {
    @SumiReduceMotion private var reduceMotion
    let row: TodayTaskRow
    let entry: DailyPlanEntry?
    let gaming: GamingStatus
    let planCount: Int
    let isMainObjective: Bool
    let isRecommended: Bool
    let applyCommand: () -> Void
    let makeMain: () -> Void
    let setEstimate: (Int) -> Void
    let setUnknown: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let toggleOptional: () -> Void
    let toggleDeferral: () -> Void
    let markBlocked: (String) -> Void
    let remove: () -> Void
    @State private var isBlockReasonPresented = false
    @State private var blockReason = ""
    @State private var isGamingUnlockConfirmationPresented = false

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
                    if let blockedReason = entry.blockedReason, !blockedReason.isEmpty {
                        Text("BLOCKED - \(blockedReason)")
                            .font(Sumi.body(10))
                            .foregroundStyle(Sumi.seal)
                            .accessibilityIdentifier("today.plan.\(row.taskID).blocked-reason")
                    } else if let deferredUntil = entry.deferredUntil, deferredUntil > Date() {
                        Text("DEFERRED UNTIL \(deferredUntil.formatted(date: .abbreviated, time: .shortened)) - NOT INCLUDED IN CAPACITY OR CALENDAR")
                            .font(Sumi.body(10))
                            .foregroundStyle(Sumi.seal)
                            .accessibilityIdentifier("today.plan.\(row.taskID).deferred-state")
                    } else if entry.isOptional {
                        Text("OPTIONAL - NOT INCLUDED IN CAPACITY OR CALENDAR")
                            .font(Sumi.body(10))
                            .foregroundStyle(Sumi.muted)
                            .accessibilityIdentifier("today.plan.\(row.taskID).optional-state")
                    }
                    if let conditionLabel = gamingUnlock.conditionLabel {
                        Text(conditionLabel)
                            .font(Sumi.body(10))
                            .foregroundStyle(Sumi.sealDeep)
                            .accessibilityIdentifier("today.plan.\(row.taskID).gaming-unlock-condition")
                    }
                    TodayEstimateStrip(
                        selectedMinutes: entry.estimateMinutes,
                        isUnknown: entry.estimateIsUncertain,
                        taskTitle: row.title,
                        taskID: row.taskID,
                        setEstimate: setEstimate,
                        setUnknown: setUnknown
                    )
                    if let suggestion = row.learnedEstimateSuggestion {
                        LearnedEstimateSuggestionView(
                            taskID: row.taskID,
                            taskTitle: row.title,
                            suggestion: suggestion,
                            currentEstimateMinutes: entry.estimateIsUncertain ? nil : entry.estimateMinutes,
                            useSuggestion: setEstimate
                        )
                    }
                    HStack(spacing: 14) {
                        Button("MOVE UP", action: moveUp)
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                            .disabled(entry.rank <= 1)
                            .accessibilityIdentifier("today.plan.\(row.taskID).move-up")
                        Button("MOVE DOWN", action: moveDown)
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                            .disabled(entry.rank >= planCount)
                            .accessibilityIdentifier("today.plan.\(row.taskID).move-down")
                        if !isMainObjective {
                            Button(gamingUnlock.makeMainTitle) {
                                if gamingUnlock.requiresConfirmation {
                                    isGamingUnlockConfirmationPresented = true
                                } else {
                                    makeMain()
                                }
                            }
                                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                                .accessibilityHint(gamingUnlock.accessibilityHint)
                                .accessibilityIdentifier("today.plan.\(row.taskID).make-main")
                        }
                        Button("REMOVE", action: remove)
                            .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                            .accessibilityLabel("Remove \(row.title) from today's plan")
                    }
                    HStack(spacing: 14) {
                        Button(entry.isOptional ? "MAKE COMMITTED" : "MARK OPTIONAL", action: toggleOptional)
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                            .disabled(entry.isMainObjective)
                            .accessibilityIdentifier("today.plan.\(row.taskID).optional")
                        Button(entry.deferredUntil == nil ? "DEFER TO TOMORROW" : "RETURN TO TODAY", action: toggleDeferral)
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                            .accessibilityIdentifier("today.plan.\(row.taskID).defer")
                        Button("MARK BLOCKED") {
                            blockReason = entry.blockedReason ?? ""
                            isBlockReasonPresented = true
                        }
                        .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                        .accessibilityIdentifier("today.plan.\(row.taskID).block")
                    }
                }
                .padding(.leading, 50)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(isRecommended ? Sumi.sealWash : Sumi.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.2), value: entry)
        .sheet(isPresented: $isBlockReasonPresented) {
            TaskBlockReasonSheet(taskTitle: row.title, reason: $blockReason) {
                markBlocked(blockReason)
                isBlockReasonPresented = false
            }
        }
        .alert("Move main objective and gaming unlock?", isPresented: $isGamingUnlockConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Move unlock condition", action: makeMain)
        } message: {
            Text(gamingUnlock.confirmationMessage(taskTitle: row.title))
        }
    }

    private var gamingUnlock: TodayPlanGamingUnlockControlState {
        TodayPlanGamingUnlockControlState(gaming: gaming, isMainObjective: isMainObjective)
    }

    private var estimateSummary: String {
        if let entry {
            if entry.estimateIsUncertain {
                return "Unknown · ~\(PlanningCapacityState.unknownEstimatePlaceholderMinutes)m placeholder"
            }
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
    @SumiReduceMotion private var reduceMotion
    let selectedMinutes: Int?
    let isUnknown: Bool
    let taskTitle: String
    let taskID: String
    let setEstimate: (Int) -> Void
    let setUnknown: () -> Void
    private let options = [15, 30, 45, 60, 90]
    @State private var isEnteringCustom = false
    @State private var customMinutes = ""
    @State private var customError: String?

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
            Button("UNKNOWN", action: setUnknown)
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(isUnknown ? Sumi.paper : Sumi.ink)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(isUnknown ? Sumi.seal : Sumi.paper)
                .overlay { Rectangle().stroke(isUnknown ? Sumi.seal : Sumi.rule, lineWidth: 1) }
                .buttonStyle(TodayCommandPressStyle())
                .accessibilityLabel("Set \(taskTitle) estimate to unknown and use a conservative \(PlanningCapacityState.unknownEstimatePlaceholderMinutes) minute placeholder")
                .accessibilityValue(isUnknown ? "Selected" : "Not selected")
            Button("CUSTOM") {
                customMinutes = selectedMinutes.map(String.init) ?? ""
                customError = nil
                isEnteringCustom = true
            }
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            .accessibilityLabel("Enter a custom estimate for \(taskTitle)")
            .accessibilityIdentifier("today-estimate-custom-\(taskID)")
            if isEnteringCustom {
                TextField("Minutes", text: $customMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 78)
                    .accessibilityLabel("Custom estimate for \(taskTitle) in minutes")
                    .accessibilityIdentifier("today-estimate-custom-input-\(taskID)")
                    .onSubmit(saveCustomEstimate)
                Button("SAVE", action: saveCustomEstimate)
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                    .accessibilityIdentifier("today-estimate-custom-save-\(taskID)")
                Button("CANCEL") {
                    isEnteringCustom = false
                    customError = nil
                }
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("today-estimate-custom-cancel-\(taskID)")
                if let customError {
                    Text(customError)
                        .font(Sumi.body(10))
                        .foregroundStyle(Sumi.sealDeep)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today-estimate-custom-error-\(taskID)")
                }
            }
            if let selectedMinutes {
                Text("\(selectedMinutes) MIN SELECTED")
                    .font(Sumi.label(7))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                    .contentTransition(.numericText())
                    .transition(SumiMotion.transition(
                        reduceMotion: reduceMotion,
                        normal: .opacity.combined(with: .scale(scale: 0.96))
                    ))
            } else if isUnknown {
                Text("~\(PlanningCapacityState.unknownEstimatePlaceholderMinutes) MIN PLACEHOLDER · UNCERTAIN")
                    .font(Sumi.label(7))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                    .accessibilityIdentifier("today-estimate-unknown-placeholder")
            }
        }
        .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.2), value: selectedMinutes)
        .animation(SumiMotion.animation(reduceMotion: reduceMotion, duration: 0.2), value: isEnteringCustom)
    }

    private func saveCustomEstimate() {
        switch TaskEstimateInput.parse(customMinutes) {
        case let .success(minutes):
            setEstimate(minutes)
            isEnteringCustom = false
            customError = nil
        case let .failure(error):
            customError = error.message
        }
    }
}

private typealias TodayCommandPressStyle = SumiPressButtonStyle
