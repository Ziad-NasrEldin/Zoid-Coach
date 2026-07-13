import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

protocol DailyReviewServicing: AnyObject {
    func load(sourceDay: String) throws -> DailyReviewSnapshot
    func correct(
        _ session: DailyReviewSession,
        to classification: BehaviorClassification,
        taskID: String?,
        from splitDate: Date?,
        applyToFuture: Bool
    ) throws
    func setHypothesisState(_ state: DailyReviewHypothesisState, sourceDay: String) throws
    func confirm(sourceDay: String) throws
    @discardableResult
    func saveOfflineWork(
        id: String?,
        sourceDay: String,
        taskID: String?,
        startedAt: Date,
        durationMinutes: Int,
        note: String?
    ) throws -> String
    func deleteOfflineWork(id: String, sourceDay: String) throws
    func classificationRules() throws -> [AppClassificationCorrectionRule]
    func upsertClassificationRule(
        for session: DailyReviewSession,
        classification: BehaviorClassification
    ) throws -> AppClassificationCorrectionRule
    func removeClassificationRule(normalizedApplication: String) throws
    func resetClassificationRules() throws -> Int
}

extension DailyReviewStore: DailyReviewServicing {}

@MainActor
final class DailyReviewController: ObservableObject {
    @Published var selectedDay: Date
    @Published private(set) var snapshot: DailyReviewSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?
    @Published private(set) var classificationRules: [AppClassificationCorrectionRule] = []
    @Published private(set) var isRulesOnlyMode: Bool

    private let service: any DailyReviewServicing
    private let calendar: Calendar

    init(
        service: any DailyReviewServicing,
        selectedDay: Date = Date(),
        calendar: Calendar = .current,
        isRulesOnlyMode: Bool = false
    ) {
        self.service = service
        self.selectedDay = selectedDay
        self.calendar = calendar
        self.isRulesOnlyMode = isRulesOnlyMode
    }

    convenience init(runtimeEnvironment: RuntimeEnvironment = .current()) {
        do {
            let policy = try PolicyStore(databaseURL: runtimeEnvironment.databaseURL).current()?.policy
                ?? UserPolicy.defaults()
            let timeZone = TimeZone(identifier: policy.schedule.timeZoneIdentifier) ?? .current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            try self.init(
                service: DailyReviewStore(databaseURL: runtimeEnvironment.databaseURL, timeZone: timeZone),
                calendar: calendar,
                isRulesOnlyMode: policy.privacy.aiProvider == .disabled
            )
        } catch {
            self.init(service: UnavailableDailyReviewService(error: error))
            errorMessage = error.localizedDescription
        }
    }

    var sourceDay: String {
        var localCalendar = calendar
        localCalendar.timeZone = calendar.timeZone
        let components = localCalendar.dateComponents([.year, .month, .day], from: selectedDay)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try service.load(sourceDay: sourceDay)
            classificationRules = try service.classificationRules()
            errorMessage = nil
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }
    }

    func correct(
        session: DailyReviewSession,
        classification: BehaviorClassification,
        taskID: String?,
        splitAtMidpoint: Bool,
        applyToFuture: Bool
    ) {
        do {
            let splitDate = splitAtMidpoint
                ? session.start.addingTimeInterval(session.end.timeIntervalSince(session.start) / 2)
                : nil
            try service.correct(
                session,
                to: classification,
                taskID: taskID,
                from: splitDate,
                applyToFuture: applyToFuture
            )
            snapshot = try service.load(sourceDay: sourceDay)
            classificationRules = try service.classificationRules()
            errorMessage = nil
            successMessage = applyToFuture
                ? "The session was corrected. Future \(session.application) activity will be classified as \(classification.rawValue)."
                : splitAtMidpoint
                ? "The second half of the session was corrected. Totals were recalculated."
                : "The session was corrected. Totals were recalculated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func classificationRule(for application: String) -> AppClassificationCorrectionRule? {
        let normalized = BehaviorPolicy.normalize(application)
        return classificationRules.first { $0.normalizedApplication == normalized }
    }

    func removeClassificationRule(_ rule: AppClassificationCorrectionRule) {
        do {
            try service.removeClassificationRule(normalizedApplication: rule.normalizedApplication)
            classificationRules = try service.classificationRules()
            errorMessage = nil
            successMessage = "The future rule for \(rule.application) was removed. Historical corrections are unchanged."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetClassificationRules() {
        do {
            let removed = try service.resetClassificationRules()
            classificationRules = try service.classificationRules()
            errorMessage = nil
            successMessage = removed == 1
                ? "1 learned future rule was reset. Historical corrections are unchanged."
                : "\(removed) learned future rules were reset. Historical corrections are unchanged."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setHypothesis(_ state: DailyReviewHypothesisState) {
        do {
            try service.setHypothesisState(state, sourceDay: sourceDay)
            snapshot = try service.load(sourceDay: sourceDay)
            errorMessage = nil
            successMessage = state == .rejected
                ? "The explanation was rejected and will not be treated as fact."
                : "The explanation was accepted for this review."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirm() {
        do {
            try service.confirm(sourceDay: sourceDay)
            snapshot = try service.load(sourceDay: sourceDay)
            errorMessage = nil
            successMessage = "Daily review confirmed. Corrections remain editable."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveOfflineWork(
        id: String?,
        startedAt: Date,
        durationMinutes: Int,
        taskID: String,
        note: String
    ) -> Bool {
        do {
            _ = try service.saveOfflineWork(
                id: id,
                sourceDay: sourceDay,
                taskID: taskID,
                startedAt: startedAt,
                durationMinutes: durationMinutes,
                note: note
            )
            snapshot = try service.load(sourceDay: sourceDay)
            errorMessage = nil
            successMessage = id == nil
                ? "Away-from-Mac work added. It is included in actual time and kept separate from Screenwatch coverage."
                : "Away-from-Mac work updated. Actual time was recalculated."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteOfflineWork(_ entry: OfflineWorkEntry) {
        do {
            try service.deleteOfflineWork(id: entry.id, sourceDay: entry.sourceDay)
            snapshot = try service.load(sourceDay: sourceDay)
            errorMessage = nil
            successMessage = "Away-from-Mac work removed. Actual time was recalculated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private final class UnavailableDailyReviewService: DailyReviewServicing {
    private let error: Error
    init(error: Error) { self.error = error }
    func load(sourceDay: String) throws -> DailyReviewSnapshot { throw error }
    func correct(_ session: DailyReviewSession, to classification: BehaviorClassification, taskID: String?, from splitDate: Date?, applyToFuture: Bool) throws { throw error }
    func setHypothesisState(_ state: DailyReviewHypothesisState, sourceDay: String) throws { throw error }
    func confirm(sourceDay: String) throws { throw error }
    func saveOfflineWork(id: String?, sourceDay: String, taskID: String?, startedAt: Date, durationMinutes: Int, note: String?) throws -> String { throw error }
    func deleteOfflineWork(id: String, sourceDay: String) throws { throw error }
    func classificationRules() throws -> [AppClassificationCorrectionRule] { throw error }
    func upsertClassificationRule(for session: DailyReviewSession, classification: BehaviorClassification) throws -> AppClassificationCorrectionRule { throw error }
    func removeClassificationRule(normalizedApplication: String) throws { throw error }
    func resetClassificationRules() throws -> Int { throw error }
}

struct DailyReviewView: View {
    @StateObject private var controller: DailyReviewController
    @State private var confirmsRuleReset = false

    init(controller: DailyReviewController? = nil) {
        _controller = StateObject(wrappedValue: controller ?? DailyReviewController())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if let errorMessage = controller.errorMessage {
                errorCard(errorMessage)
            }
            if let successMessage = controller.successMessage {
                Text(successMessage)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.okay)
                    .accessibilityIdentifier("reviews.success")
            }
            if let snapshot = controller.snapshot {
                let state = RulesOnlyReviewState(
                    isRulesOnly: controller.isRulesOnlyMode,
                    sessionCount: snapshot.sessions.count,
                    hasLimitedCoverage: snapshot.sessions.isEmpty
                )
                if state.isRulesOnly {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.title)
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.seal)
                        Text(state.detail)
                            .font(Sumi.body(12))
                            .foregroundStyle(Sumi.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.softPaper)
                    .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reviews.rules-only-boundary")
                }
            }
            if controller.isLoading {
                ProgressView("Loading local activity...")
                    .accessibilityIdentifier("reviews.loading")
            } else if let snapshot = controller.snapshot {
                snapshotContent(snapshot)
            }

            Divider()
                .padding(.vertical, 8)
            WeeklyReviewView()
        }
        .padding(34)
        .frame(maxWidth: 980, alignment: .leading)
        .task { controller.load() }
        .onChange(of: controller.selectedDay) { controller.load() }
        .accessibilityIdentifier("reviews.daily")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DAILY REVIEW")
                .font(Sumi.label(10))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text("Correct the record before it teaches the coach.")
                .font(Sumi.display(34))
                .tracking(-1)
            Text("Only local activity summaries are shown. Window titles, URLs, and screenshots are never displayed here.")
                .font(Sumi.body(14))
                .foregroundStyle(Sumi.muted)
            DatePicker("Review day", selection: $controller.selectedDay, displayedComponents: .date)
                .datePickerStyle(.compact)
                .accessibilityIdentifier("reviews.day")
            if !controller.classificationRules.isEmpty {
                HStack(spacing: 12) {
                    Text("\(controller.classificationRules.count) ACTIVE LEARNED RULE\(controller.classificationRules.count == 1 ? "" : "S")")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.muted)
                    Button("RESET LEARNED RULES") { confirmsRuleReset = true }
                        .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                        .accessibilityIdentifier("reviews.learned-rules.reset")
                }
            }
        }
        .confirmationDialog(
            "Reset all learned app rules?",
            isPresented: $confirmsRuleReset,
            titleVisibility: .visible
        ) {
            Button("Reset all learned rules", role: .destructive) {
                controller.resetClassificationRules()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Future observations will return to the normal Settings policy. Historical corrections and review totals will remain unchanged.")
        }
    }

    @ViewBuilder
    private func snapshotContent(_ snapshot: DailyReviewSnapshot) -> some View {
        reviewCoverage(snapshot)
        planOutcomes(snapshot)
        DailySourceCoverageView(selectedDay: controller.selectedDay)
        if snapshot.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("NO COVERED ACTIVITY")
                    .font(Sumi.label())
                    .sumiLabelTracking()
                Text("There are no local behavior observations for this day. Nothing was inferred or confirmed.")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
                Button("RELOAD") { controller.load() }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .accessibilityIdentifier("reviews.empty.reload")
            }
            .padding(18)
            .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
            .accessibilityIdentifier("reviews.empty")
        } else {
            totals(snapshot.totals)
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVITY SESSIONS")
                    .font(Sumi.label())
                    .sumiLabelTracking()
                ForEach(snapshot.sessions) { session in
                    DailyReviewSessionRow(
                        session: session,
                        activeRule: controller.classificationRule(for: session.application),
                        removeRule: controller.removeClassificationRule
                    ) { classification, taskID, split, applyToFuture in
                        controller.correct(
                            session: session,
                            classification: classification,
                            taskID: taskID,
                            splitAtMidpoint: split,
                            applyToFuture: applyToFuture
                        )
                    }
                }
            }
        }
        CompletedTaskHistorySection(entries: snapshot.completedTasks)
        OfflineWorkSection(
            entries: snapshot.offlineWork,
            selectedDay: controller.selectedDay,
            onSave: controller.saveOfflineWork,
            onDelete: controller.deleteOfflineWork
        )
        hypothesis(snapshot)
        confirmation(snapshot)
    }

    private func planOutcomes(_ snapshot: DailyReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PLAN OUTCOMES")
                .font(Sumi.label())
                .sumiLabelTracking()
            if snapshot.plannedTasks.isEmpty {
                Text("No priority plan was recorded for this day. Zoid 666 will not invent a main objective or completion count.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reviews.plan.empty")
            } else {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(mainObjectiveStatus(snapshot))
                            .font(Sumi.display(20))
                            .foregroundStyle(mainObjectiveStatusColor(snapshot))
                        Text("MAIN OBJECTIVE")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.muted)
                        Text(snapshot.mainObjective?.title ?? "No main objective was designated")
                            .font(Sumi.body(11))
                            .lineLimit(2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reviews.plan.main-objective")

                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(snapshot.completedPriorityTaskCount) OF \(snapshot.plannedTasks.count)")
                            .font(Sumi.display(20))
                        Text("PRIORITY TASKS COMPLETED")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.muted)
                        Text("Only same-day durable completion history is counted.")
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.muted)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reviews.plan.priority-count")
                }

                VStack(spacing: 0) {
                    ForEach(snapshot.plannedTasks) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(task.isCompleted ? "DONE" : "OPEN")
                                .font(Sumi.label(8))
                                .sumiLabelTracking()
                                .foregroundStyle(task.isCompleted ? Sumi.okay : Sumi.seal)
                                .frame(width: 42, alignment: .leading)
                            Text(task.title)
                                .font(Sumi.body(12))
                                .lineLimit(2)
                            Spacer()
                            if task.isMainObjective {
                                Text("MAIN")
                                    .font(Sumi.label(8))
                                    .sumiLabelTracking()
                                    .foregroundStyle(Sumi.seal)
                            }
                            if let estimate = task.estimatedMinutes {
                                Text("\(estimate) MIN EST")
                                    .font(Sumi.label(8))
                                    .sumiLabelTracking()
                                    .foregroundStyle(Sumi.muted)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 38)
                        .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("reviews.plan.task.\(task.taskID)")
                    }
                }
            }
        }
        .padding(18)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityIdentifier("reviews.plan-outcomes")
    }

    private func mainObjectiveStatus(_ snapshot: DailyReviewSnapshot) -> String {
        guard let mainObjective = snapshot.mainObjective else { return "NOT DESIGNATED" }
        return mainObjective.isCompleted ? "COMPLETED" : "UNFINISHED"
    }

    private func mainObjectiveStatusColor(_ snapshot: DailyReviewSnapshot) -> Color {
        guard let mainObjective = snapshot.mainObjective else { return Sumi.muted }
        return mainObjective.isCompleted ? Sumi.okay : Sumi.seal
    }

    private func reviewCoverage(_ snapshot: DailyReviewSnapshot) -> some View {
        HStack(spacing: 0) {
            reviewMetric("ACTUAL TIME", minutes: snapshot.actualMinutes, identifier: "reviews.actual-minutes")
            reviewMetric("SCREENWATCH-OBSERVED", minutes: snapshot.observedMinutes, identifier: "reviews.observed-minutes")
            reviewMetric("AWAY FROM MAC", minutes: snapshot.offlineMinutes, identifier: "reviews.offline-minutes")
        }
        .accessibilityIdentifier("reviews.coverage-summary")
    }

    private func reviewMetric(_ title: String, minutes: Int, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(minutes) MIN")
                .font(Sumi.display(22))
            Text(title)
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func totals(_ totals: [DailyReviewTotal]) -> some View {
        HStack(spacing: 0) {
            ForEach(totals) { total in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(total.minutes) MIN")
                        .font(Sumi.display(22))
                    Text(total.classification.rawValue.uppercased())
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reviews.total.\(total.classification.rawValue)")
            }
        }
        .accessibilityIdentifier("reviews.totals")
    }

    private func hypothesis(_ snapshot: DailyReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("POSSIBLE EXPLANATION")
                .font(Sumi.label())
                .sumiLabelTracking()
            Text(snapshot.hypothesis ?? "There is not enough covered activity for an explanation.")
                .font(Sumi.body(14))
            Text("This is a hypothesis, not a fact. Rejecting it is useful feedback.")
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
            HStack {
                Button(snapshot.hypothesisState == .accepted ? "ACCEPTED" : "ACCEPT") {
                    controller.setHypothesis(.accepted)
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(snapshot.hypothesis == nil || snapshot.hypothesisState == .accepted)
                .accessibilityIdentifier("reviews.hypothesis.accept")
                Button(snapshot.hypothesisState == .rejected ? "REJECTED" : "REJECT") {
                    controller.setHypothesis(.rejected)
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(snapshot.hypothesis == nil || snapshot.hypothesisState == .rejected)
                .accessibilityIdentifier("reviews.hypothesis.reject")
            }
        }
        .padding(18)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityIdentifier("reviews.hypothesis")
    }

    private func confirmation(_ snapshot: DailyReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let confirmedAt = snapshot.confirmedAt {
                Text("CONFIRMED \(confirmedAt.formatted(date: .abbreviated, time: .shortened).uppercased())")
                    .font(Sumi.label())
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.okay)
                    .accessibilityIdentifier("reviews.confirmed")
                Text("You can still correct a session. Any later edit reopens the review before it influences learning.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
            } else {
                Button("CONFIRM CORRECTED REVIEW") { controller.confirm() }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .large))
                    .accessibilityIdentifier("reviews.confirm")
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(message)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.sealDeep)
            Spacer()
            Button("RETRY") { controller.load() }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                .accessibilityIdentifier("reviews.retry")
        }
        .padding(14)
        .background(Sumi.sealWash)
        .overlay(Rectangle().stroke(Sumi.seal, lineWidth: 1))
        .accessibilityIdentifier("reviews.error")
    }
}

private struct OfflineWorkSection: View {
    let entries: [OfflineWorkEntry]
    let selectedDay: Date
    let onSave: (String?, Date, Int, String, String) -> Bool
    let onDelete: (OfflineWorkEntry) -> Void

    @State private var editingID: String?
    @State private var startedAt = Date()
    @State private var durationMinutes = 30
    @State private var taskID = ""
    @State private var note = ""
    @State private var entryToDelete: OfflineWorkEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AWAY-FROM-MAC WORK")
                .font(Sumi.label())
                .sumiLabelTracking()
            Text("Record intentional work that Screenwatch could not observe. It counts toward actual task time but remains visibly separate from computer-observed time, so missing telemetry is never invented as work.")
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
            if entries.isEmpty {
                Text("No intentional offline work has been recorded for this day.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("reviews.offline.empty")
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.durationMinutes) MIN · \(entry.startedAt.formatted(date: .omitted, time: .shortened))")
                                .font(Sumi.label(10))
                                .sumiLabelTracking()
                            if let taskID = entry.taskID {
                                Text("Task: \(taskID)").font(Sumi.body(12))
                            }
                            if let note = entry.note {
                                Text(note).font(Sumi.body(12)).foregroundStyle(Sumi.muted)
                            }
                        }
                        Spacer()
                        Button("EDIT") { edit(entry) }
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                            .accessibilityIdentifier("reviews.offline.edit.\(entry.id)")
                        Button("REMOVE") { entryToDelete = entry }
                            .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                            .accessibilityIdentifier("reviews.offline.remove.\(entry.id)")
                    }
                    .padding(12)
                    .background(Sumi.paper)
                    .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
                    .accessibilityIdentifier("reviews.offline.entry.\(entry.id)")
                }
            }
            Divider()
            Text(editingID == nil ? "ADD INTENTIONAL OFFLINE WORK" : "CORRECT OFFLINE WORK")
                .font(Sumi.label(10))
                .sumiLabelTracking()
            HStack(alignment: .bottom, spacing: 12) {
                DatePicker("Started", selection: $startedAt, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("reviews.offline.started-at")
                Stepper("\(durationMinutes) minutes", value: $durationMinutes, in: 1...1_440, step: 5)
                    .accessibilityIdentifier("reviews.offline.duration")
            }
            TextField("Task identifier or title (optional)", text: $taskID)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("reviews.offline.task")
            TextField("What did you work on? (optional)", text: $note)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("reviews.offline.note")
            Text("Add a task or note so intentional work remains distinct from missing telemetry.")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .accessibilityIdentifier("reviews.offline.validation")
            HStack {
                Button(editingID == nil ? "ADD WORK" : "SAVE CORRECTION") {
                    if onSave(editingID, startedAt, durationMinutes, taskID, note) {
                        reset()
                    }
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                .disabled(!canSave)
                .accessibilityIdentifier("reviews.offline.save")
                if editingID != nil {
                    Button("CANCEL") { reset() }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                        .accessibilityIdentifier("reviews.offline.cancel")
                }
            }
        }
        .padding(18)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityIdentifier("reviews.offline")
        .onAppear { alignStartToSelectedDay() }
        .onChange(of: selectedDay) { reset() }
        .confirmationDialog(
            "Remove this away-from-Mac work entry?",
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove entry", role: .destructive) {
                if let entryToDelete { onDelete(entryToDelete) }
                entryToDelete = nil
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("Only this intentional offline-work record will be removed. Screenwatch observations are unchanged.")
        }
    }

    private func edit(_ entry: OfflineWorkEntry) {
        editingID = entry.id
        startedAt = entry.startedAt
        durationMinutes = entry.durationMinutes
        taskID = entry.taskID ?? ""
        note = entry.note ?? ""
    }

    private func reset() {
        editingID = nil
        durationMinutes = 30
        taskID = ""
        note = ""
        alignStartToSelectedDay()
    }

    private func alignStartToSelectedDay() {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: Date())
        startedAt = calendar.date(
            bySettingHour: time.hour ?? 9,
            minute: time.minute ?? 0,
            second: 0,
            of: selectedDay
        ) ?? selectedDay
    }

    private var canSave: Bool {
        let trimmedTask = taskID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmedTask.isEmpty || !trimmedNote.isEmpty)
            && trimmedTask.count <= 200
            && trimmedNote.count <= 1_000
    }
}

private struct CompletedTaskHistorySection: View {
    let entries: [CompletedTaskHistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMPLETED TASKS")
                .font(Sumi.label())
                .sumiLabelTracking()
            Text("Finished work leaves the active list, but stays here as a local record of what you completed.")
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)

            if entries.isEmpty {
                Text("No tasks were completed on this day.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("reviews.completed.empty")
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(Sumi.body(15))
                            HStack(spacing: 6) {
                                Text(entry.completedAt.formatted(date: .omitted, time: .shortened))
                                Text("·")
                                Text(sourceLabel(entry.sourceKind))
                                if let reason = entry.lastPauseReason {
                                    Text("·")
                                    Text(reason.userFacingLabel)
                                }
                            }
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.muted)
                        }
                        Spacer(minLength: 12)
                        Text("COMPLETED")
                            .font(Sumi.label(10))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.seal)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sumi.paper)
                    .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(entry))
                    .accessibilityIdentifier("reviews.completed.\(entry.id)")
                }
            }
        }
        .padding(16)
        .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
        .accessibilityIdentifier("reviews.completed")
    }

    private func sourceLabel(_ source: CompletedTaskSourceKind) -> String {
        switch source {
        case .reminders: "Apple Reminders"
        case .local: "Local task"
        case .unknown: "Local history"
        }
    }

    private func accessibilityLabel(_ entry: CompletedTaskHistoryEntry) -> String {
        var parts = [
            entry.title,
            "Completed at \(entry.completedAt.formatted(date: .omitted, time: .shortened))",
            sourceLabel(entry.sourceKind)
        ]
        if let reason = entry.lastPauseReason {
            parts.append(reason.userFacingLabel)
        }
        return parts.joined(separator: ", ")
    }
}

private struct DailyReviewSessionRow: View {
    let session: DailyReviewSession
    let activeRule: AppClassificationCorrectionRule?
    let removeRule: (AppClassificationCorrectionRule) -> Void
    let apply: (BehaviorClassification, String?, Bool, Bool) -> Void

    @State private var classification: BehaviorClassification
    @State private var taskID: String
    @State private var splitAtMidpoint = false
    @State private var applyToFuture = false
    @State private var ruleToRemove: AppClassificationCorrectionRule?

    init(
        session: DailyReviewSession,
        activeRule: AppClassificationCorrectionRule?,
        removeRule: @escaping (AppClassificationCorrectionRule) -> Void,
        apply: @escaping (BehaviorClassification, String?, Bool, Bool) -> Void
    ) {
        self.session = session
        self.activeRule = activeRule
        self.removeRule = removeRule
        self.apply = apply
        _classification = State(initialValue: session.classification)
        _taskID = State(initialValue: session.taskID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.application).font(Sumi.body(15))
                    Text("\(session.start.formatted(date: .omitted, time: .shortened)) - \(session.end.formatted(date: .omitted, time: .shortened)) · \(session.durationMinutes) min · \(session.observationCount) observations")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                }
                Spacer()
                Picker("Classification", selection: $classification) {
                    ForEach(BehaviorClassification.allCases, id: \.self) { value in
                        Text(value.rawValue.uppercased()).tag(value)
                    }
                }
                .frame(width: 150)
                .accessibilityIdentifier("reviews.session.\(session.id).classification")
            }
            HStack {
                TextField("Optional task ID or title", text: $taskID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Attach session to a task")
                    .accessibilityIdentifier("reviews.session.\(session.id).task")
                Toggle("Correct second half only", isOn: $splitAtMidpoint)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("reviews.session.\(session.id).split")
            }
            if let activeRule {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("FUTURE RULE")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                    Text("\(activeRule.application) → \(activeRule.classification.rawValue.uppercased())")
                        .font(Sumi.body(12))
                    Text("Historical records are unchanged.")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                    Spacer()
                    Button("REMOVE FUTURE RULE") { ruleToRemove = activeRule }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        .accessibilityIdentifier("reviews.session.\(session.id).future-rule.remove")
                }
                .padding(10)
                .background(Sumi.softPaper)
                .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
                .accessibilityIdentifier("reviews.session.\(session.id).future-rule.active")
            }
            Toggle("Use this app classification for future activity", isOn: $applyToFuture)
                .toggleStyle(.checkbox)
                .disabled(!supportsFutureRule)
                .accessibilityIdentifier("reviews.session.\(session.id).future-rule")
            if applyToFuture {
                Text(futureRulePreview)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("reviews.session.\(session.id).future-rule.preview")
            } else if !supportsFutureRule {
                Text("Idle and Unknown are observation states, so they cannot become a lasting app rule.")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
            }
            Button("APPLY CORRECTION") {
                apply(classification, taskID.isEmpty ? nil : taskID, splitAtMidpoint, applyToFuture)
            }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(
                    classification == session.classification
                        && taskID == (session.taskID ?? "")
                        && !splitAtMidpoint
                        && !applyToFuture
                )
                .accessibilityIdentifier("reviews.session.\(session.id).apply")
        }
        .padding(16)
        .background(Sumi.paper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviews.session.\(session.id)")
        .onChange(of: classification) {
            if !supportsFutureRule { applyToFuture = false }
        }
        .confirmationDialog(
            "Remove the future rule for \(session.application)?",
            isPresented: Binding(
                get: { ruleToRemove != nil },
                set: { if !$0 { ruleToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove future rule", role: .destructive) {
                if let ruleToRemove { removeRule(ruleToRemove) }
                ruleToRemove = nil
            }
            Button("Cancel", role: .cancel) { ruleToRemove = nil }
        } message: {
            Text("Future observations will return to the normal Settings policy. This review's historical correction will remain.")
        }
    }

    private var supportsFutureRule: Bool {
        [.work, .gaming, .distracting].contains(classification)
    }

    private var futureRulePreview: String {
        if let activeRule, activeRule.classification != classification {
            return "This replaces the current \(activeRule.classification.rawValue) rule. New \(session.application) observations will be \(classification.rawValue). Historical observations stay unchanged."
        }
        return "New \(session.application) observations will be \(classification.rawValue). Historical observations stay unchanged."
    }
}
