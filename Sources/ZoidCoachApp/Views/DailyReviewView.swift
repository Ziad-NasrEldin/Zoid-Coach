import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

protocol DailyReviewServicing: AnyObject {
    func load(sourceDay: String) throws -> DailyReviewSnapshot
    func mostRecentUnfinishedReview() throws -> UnfinishedDailyReview?
    func correct(
        _ session: DailyReviewSession,
        to classification: BehaviorClassification,
        taskID: String?,
        from splitDate: Date?,
        applyToFuture: Bool
    ) throws
    func setHypothesisState(_ state: DailyReviewHypothesisState, sourceDay: String) throws
    func savePersonalNote(_ note: String?, sourceDay: String) throws
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
    @Published private(set) var unfinishedReview: UnfinishedDailyReview?
    @Published private(set) var classificationRules: [AppClassificationCorrectionRule] = []
    @Published private(set) var isRulesOnlyMode: Bool
    @Published var personalNote = ""

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

    func localTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try refreshSnapshotAndResumeState()
            classificationRules = try service.classificationRules()
            errorMessage = nil
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }
    }

    func resumeUnfinishedReview() {
        guard let unfinishedReview,
              let date = Self.date(from: unfinishedReview.sourceDay, calendar: calendar)
        else { return }
        selectedDay = date
        load()
        successMessage = "Unfinished review restored. Your previous corrections are still applied."
    }

    private func refreshSnapshotAndResumeState() throws {
        let loaded = try service.load(sourceDay: sourceDay)
        snapshot = loaded
        personalNote = loaded.personalNote ?? ""
        unfinishedReview = try service.mostRecentUnfinishedReview()
    }

    private static func date(from sourceDay: String, calendar: Calendar) -> Date? {
        let parts = sourceDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
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
            try refreshSnapshotAndResumeState()
            classificationRules = try service.classificationRules()
            errorMessage = nil
            let action = session.classification == .unknown ? "classified" : "corrected"
            successMessage = applyToFuture
                ? "The session was \(action). Future \(session.application) activity will be classified as \(classification.rawValue)."
                : splitAtMidpoint
                ? "The second half of the session was \(action). Totals were recalculated."
                : "The session was \(action). Totals were recalculated."
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
            try refreshSnapshotAndResumeState()
            errorMessage = nil
            successMessage = state == .rejected
                ? "The explanation was rejected and will not be treated as fact."
                : "The explanation was accepted for this review."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePersonalNote() {
        do {
            try service.savePersonalNote(personalNote, sourceDay: sourceDay)
            try refreshSnapshotAndResumeState()
            errorMessage = nil
            successMessage = snapshot?.personalNote == nil
                ? "Personal review note cleared."
                : "Personal review note saved locally. Confirm the review when it is ready."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirm() {
        do {
            try service.confirm(sourceDay: sourceDay)
            try refreshSnapshotAndResumeState()
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
            try refreshSnapshotAndResumeState()
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
            try refreshSnapshotAndResumeState()
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
    func mostRecentUnfinishedReview() throws -> UnfinishedDailyReview? { throw error }
    func correct(_ session: DailyReviewSession, to classification: BehaviorClassification, taskID: String?, from splitDate: Date?, applyToFuture: Bool) throws { throw error }
    func setHypothesisState(_ state: DailyReviewHypothesisState, sourceDay: String) throws { throw error }
    func savePersonalNote(_ note: String?, sourceDay: String) throws { throw error }
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
            unfinishedReviewBanner
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

    @ViewBuilder
    private var unfinishedReviewBanner: some View {
        if let unfinished = controller.unfinishedReview {
            VStack(alignment: .leading, spacing: 8) {
                Text(unfinished.sourceDay == controller.sourceDay ? "REVIEW IN PROGRESS" : "UNFINISHED REVIEW")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text(unfinished.sourceDay == controller.sourceDay
                    ? "Your previous corrections are loaded and remain local until you confirm this review."
                    : "You changed the review for \(unfinished.sourceDay) but did not confirm it. Resume with every saved correction intact.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if unfinished.sourceDay != controller.sourceDay {
                    Button("RESUME \(unfinished.sourceDay)") { controller.resumeUnfinishedReview() }
                        .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                        .accessibilityIdentifier("reviews.unfinished.resume")
                        .accessibilityHint("Opens the most recently changed unconfirmed daily review with its saved corrections.")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Sumi.softPaper)
            .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reviews.unfinished")
        }
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
        behavioralHighlights(snapshot)
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
            let sessionReview = UnknownSessionReviewState(sessions: snapshot.sessions)
            totals(snapshot.totals)
            unknownSessionReview(sessionReview)
            classifiedSessionReview(sessionReview)
        }
        CompletedTaskHistorySection(entries: snapshot.completedTasks)
        OfflineWorkSection(
            entries: snapshot.offlineWork,
            taskTitles: Dictionary(uniqueKeysWithValues: snapshot.plannedTasks.map { ($0.taskID, $0.title) }),
            selectedDay: controller.selectedDay,
            onSave: controller.saveOfflineWork,
            onDelete: controller.deleteOfflineWork
        )
        hypothesis(snapshot)
        personalNoteSection(snapshot)
        confirmation(snapshot)
    }

    @ViewBuilder
    private func unknownSessionReview(_ state: UnknownSessionReviewState) -> some View {
        if state.hasPending {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("UNKNOWN SESSIONS NEED REVIEW")
                        .font(Sumi.label())
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Spacer()
                    Text("\(state.pending.count) SESSION\(state.pending.count == 1 ? "" : "S") · \(state.pendingMinutes) MIN")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                        .accessibilityIdentifier("reviews.unknown-sessions.count")
                }
                Text("Zoid 666 did not have enough evidence to classify this activity. Unknown time is not counted as distraction or treated as a plan violation. Correct only what you recognize; leaving a session Unknown is a valid choice.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(state.pending) { session in
                    sessionRow(session)
                }
            }
            .padding(16)
            .background(Sumi.sealWash)
            .overlay(Rectangle().stroke(Sumi.seal, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reviews.unknown-sessions")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("NO UNKNOWN SESSIONS")
                    .font(Sumi.label())
                    .sumiLabelTracking()
                Text("Every observed session for this day has a classification. No confirmation is waiting.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
            }
            .padding(14)
            .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reviews.unknown-sessions.empty")
        }
    }

    private func classifiedSessionReview(_ state: UnknownSessionReviewState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLASSIFIED ACTIVITY SESSIONS")
                .font(Sumi.label())
                .sumiLabelTracking()
            if state.classified.isEmpty {
                Text("No classified sessions are available yet. Unknown sessions stay in the review queue above.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("reviews.classified-sessions.empty")
            } else {
                ForEach(state.classified) { session in
                    sessionRow(session)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviews.classified-sessions")
    }

    private func sessionRow(_ session: DailyReviewSession) -> some View {
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

    private func behavioralHighlights(_ snapshot: DailyReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OBSERVED HIGHLIGHTS")
                .font(Sumi.label())
                .sumiLabelTracking()
            Text("These are corrected local observations, not judgments about why the activity happened.")
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                observedHighlight(
                    title: "STRONGEST WORK BLOCK",
                    session: snapshot.bestObservedWorkBlock,
                    empty: "No corrected observed work block was available for this day.",
                    identifier: "reviews.highlight.work"
                )
                observedHighlight(
                    title: "LARGEST DRIFT EPISODE",
                    session: snapshot.largestObservedDriftEpisode,
                    empty: "No corrected gaming or distracting episode was observed for this day.",
                    identifier: "reviews.highlight.drift"
                )
            }

            Divider()
            Text("BEHAVIOR COACHING")
                .font(Sumi.label(10))
                .sumiLabelTracking()
            if let quietDrift = snapshot.quietDrift {
                quietDriftSummary(quietDrift)
            }
            if snapshot.coachingInteractions.isEmpty {
                Text("No gaming-drift or wake-intervention prompt was created for this day.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("reviews.coaching.empty")
            } else {
                coachingOutcomeSummary(snapshot.coachingInteractions)
                VStack(spacing: 0) {
                    ForEach(snapshot.coachingInteractions) { interaction in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(interaction.promptType == "GAMING_DRIFT" ? "GAMING DRIFT" : "WAKE INTERVENTION")
                                    .font(Sumi.label(8))
                                    .sumiLabelTracking()
                                    .foregroundStyle(Sumi.seal)
                                Spacer()
                                Text(controller.localTime(interaction.createdAt))
                                    .font(Sumi.label(8))
                                    .foregroundStyle(Sumi.muted)
                            }
                            Text(interaction.title)
                                .font(Sumi.body(13))
                            Text(interaction.summary)
                                .font(Sumi.body(11))
                                .foregroundStyle(Sumi.muted)
                                .lineLimit(3)
                            if let evidence = coachingEvidenceSummary(interaction) {
                                Text(evidence)
                                    .font(Sumi.body(11))
                                    .foregroundStyle(Sumi.ink)
                                    .accessibilityIdentifier("reviews.coaching.evidence.\(interaction.promptID)")
                            }
                            Text(coachingOutcomeSummary(interaction))
                                .font(Sumi.label(8))
                                .sumiLabelTracking()
                                .foregroundStyle(interaction.effectWasApplied == false ? Sumi.seal : Sumi.okay)
                                .accessibilityIdentifier("reviews.coaching.outcome.\(interaction.promptID)")
                            if let response = coachingResponseMetadata(interaction) {
                                Text(response)
                                    .font(Sumi.label(8))
                                    .sumiLabelTracking()
                                    .foregroundStyle(Sumi.muted)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("reviews.coaching.\(interaction.promptID)")
                    }
                }
            }
        }
        .padding(18)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityIdentifier("reviews.behavioral-highlights")
    }

    private func quietDriftSummary(_ summary: DailyReviewQuietDriftSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("PROMPT CAP REACHED")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Spacer()
                Text("\(summary.episodeCount) LATER EPISODE\(summary.episodeCount == 1 ? "" : "S")")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
            Text("Later eligible drift was recorded without another interruption and is shown only in this review.")
                .font(Sumi.body(12))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(summary.totalObservedMinutes) observed minutes · largest \(summary.largestEpisodeMinutes) minutes")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.ink)
            if !summary.applications.isEmpty {
                Text(summary.applications.joined(separator: ", "))
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sumi.paper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reviews.coaching.quiet-drift")
    }

    private func observedHighlight(
        title: String,
        session: DailyReviewSession?,
        empty: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
            if let session {
                Text("\(session.durationMinutes) MIN")
                    .font(Sumi.display(22))
                Text("\(session.application) · \(controller.localTime(session.start))")
                    .font(Sumi.body(12))
                Text("\(session.classification.rawValue.capitalized) · corrected observed session")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
            } else {
                Text("NOT OBSERVED")
                    .font(Sumi.display(18))
                    .foregroundStyle(Sumi.muted)
                Text(empty)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func coachingOutcomeSummary(
        _ interactions: [DailyReviewCoachingInteraction]
    ) -> some View {
        let observedReturns = interactions.count {
            if case .returnedToWork = $0.outcome { return true }
            return false
        }
        let recoveryStarts = interactions.count {
            if case .returnedToWork = $0.outcome { return true }
            return $0.outcome == .recoveryStarted
        }
        let intentionalChoices = interactions.count { $0.outcome == .intentionalChoice }
        return HStack(spacing: 0) {
            coachingMetric("OBSERVED FOLLOW-THROUGH", observedReturns)
            coachingMetric("RECOVERY STARTS", recoveryStarts)
            coachingMetric("INTENTIONAL CHOICES", intentionalChoices)
        }
        .background(Sumi.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reviews.coaching.outcomes")
    }

    private func coachingMetric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(Sumi.display(18))
            Text(title)
                .font(Sumi.label(7))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
    }

    private func coachingEvidenceSummary(_ interaction: DailyReviewCoachingInteraction) -> String? {
        guard interaction.promptType == "GAMING_DRIFT" else { return nil }
        let observed = interaction.observedGamingMinutes.map { "OBSERVED \($0) MIN" } ?? "OBSERVED GAMING"
        let application = interaction.observedApplication.map { " IN \($0.uppercased())" } ?? ""
        let task = interaction.unfinishedTaskTitle.map { " · UNFINISHED \($0.uppercased())" } ?? ""
        return observed + application + task
    }

    private func coachingOutcomeSummary(_ interaction: DailyReviewCoachingInteraction) -> String {
        switch interaction.outcome {
        case .unanswered:
            return "NO RESPONSE RECORDED"
        case .effectPending:
            return "CHOICE RECORDED · EFFECT NOT YET CONFIRMED"
        case .recoveryStarted:
            return "RECOVERY STARTED · LATER WORK NOT OBSERVED"
        case let .returnedToWork(observedMinutes, selectedTaskMatched):
            let action = interaction.responseAction.flatMap(PromptActionKind.init(rawValue:))
            let describesReturn = action == .returnToActiveTask
            if selectedTaskMatched {
                return describesReturn
                    ? "RETURN TO SELECTED TASK OBSERVED · \(observedMinutes) MIN WITHIN 30 MIN"
                    : "SELECTED TASK START OBSERVED · \(observedMinutes) MIN WITHIN 30 MIN"
            }
            return describesReturn
                ? "RETURN TO WORK OBSERVED · \(observedMinutes) MIN WITHIN 30 MIN · TASK ALIGNMENT NOT PROVEN"
                : "WORK START OBSERVED · \(observedMinutes) MIN WITHIN 30 MIN · TASK ALIGNMENT NOT PROVEN"
        case .acceptedBreak:
            return "ACCEPTED BREAK STARTED · NOT COUNTED AS DRIFT"
        case .intentionalChoice:
            return "INTENTIONAL CHOICE RECORDED · NO JUDGMENT"
        case .extensionRecorded:
            return "FIVE-MINUTE EXTENSION RECORDED"
        case .responseRecorded:
            return "CHOICE APPLIED"
        }
    }

    private func coachingResponseMetadata(_ interaction: DailyReviewCoachingInteraction) -> String? {
        guard let action = interaction.responseAction else { return nil }
        let label = action.replacingOccurrences(of: "_", with: " ").uppercased()
        let surface = interaction.responseSurface?.uppercased() ?? "UNKNOWN SURFACE"
        return "\(label) · \(interaction.effectWasApplied == true ? "APPLIED" : "RECORDED") VIA \(surface)"
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

    private func personalNoteSection(_ snapshot: DailyReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PERSONAL NOTE")
                .font(Sumi.label())
                .sumiLabelTracking()
            Text("Keep private context for this day. This note stays local and is not treated as observed behavior, a hypothesis, or a learned fact.")
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $controller.personalNote)
                .font(Sumi.body(13))
                .frame(minHeight: 88)
                .padding(8)
                .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                .accessibilityLabel("Personal daily review note")
                .accessibilityIdentifier("reviews.personal-note.editor")
            HStack {
                Text("\(controller.personalNote.count) / 1000")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(controller.personalNote.count > 1_000 ? Sumi.sealDeep : Sumi.muted)
                Spacer()
                Button(snapshot.personalNote == nil ? "SAVE NOTE" : "UPDATE NOTE") {
                    controller.savePersonalNote()
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(controller.personalNote.count > 1_000 || controller.personalNote == (snapshot.personalNote ?? ""))
                .accessibilityIdentifier("reviews.personal-note.save")
            }
        }
        .padding(18)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviews.personal-note")
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
    let taskTitles: [String: String]
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
                                Text("Task: \(OfflineWorkTaskTitleResolver(titles: taskTitles).title(for: taskID))")
                                    .font(Sumi.body(12))
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

struct OfflineWorkTaskTitleResolver: Equatable, Sendable {
    let titles: [String: String]

    func title(for taskID: String) -> String {
        titles[taskID] ?? taskID
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
            if session.classification == .unknown {
                VStack(alignment: .leading, spacing: 5) {
                    Text("EVIDENCE INSUFFICIENT · CONFIRM IF YOU KNOW")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Text("This session remains Unknown until you classify it. Its app name and time range are shown without captured titles, URLs, screenshots, or a guessed explanation.")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reviews.session.\(session.id).unknown-explanation")
            }
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
            Button(session.classification == .unknown ? "APPLY CLASSIFICATION" : "APPLY CORRECTION") {
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
