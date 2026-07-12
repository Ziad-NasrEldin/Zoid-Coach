import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class BaselineObservationController: ObservableObject {
    @Published private(set) var status: BaselineObservationStatus?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let store: BaselineObservationStore?
    private let unavailableError: Error?
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    convenience init() {
        let runtime = RuntimeEnvironment.current()
        do {
            try self.init(store: BaselineObservationStore(databaseURL: runtime.databaseURL))
        } catch {
            self.init(unavailableError: error)
        }
    }

    init(
        store: BaselineObservationStore,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.store = store
        unavailableError = nil
        self.now = now
        self.calendar = calendar
    }

    private init(unavailableError: Error) {
        store = nil
        self.unavailableError = unavailableError
        now = Date.init
        calendar = .current
    }

    func refresh() {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let store else { throw unavailableError ?? BaselineObservationStoreError.openDatabase }
            status = try store.reconcileCompletedDays(before: now(), calendar: calendar)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BaselineObservationView: View {
    @StateObject private var controller: BaselineObservationController

    init(controller: BaselineObservationController = BaselineObservationController()) {
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if controller.isLoading {
                ProgressView("Reviewing completed local days")
                    .accessibilityIdentifier("baseline.loading")
            } else if let error = controller.errorMessage {
                errorState(error)
            } else if let status = controller.status {
                progress(status)
                dayLedger(status)
                if status.isComplete { report(status.report) }
            } else {
                Text("No baseline record is available yet.")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
            }
        }
        .padding(20)
        .background(Sumi.paper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("baseline.observation")
        .task { controller.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FIRST-WEEK OBSERVATION")
                    .font(Sumi.label())
                    .sumiLabelTracking()
                Text("Learn quietly before coaching gets louder")
                    .font(Sumi.display(22))
                Text("Zoid 666 records eligible drift and coverage during seven complete local days. Behavior-triggered prompts stay off until the baseline is complete. Planning and manual task controls remain available.")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
            }
            Spacer(minLength: 12)
            Button("REFRESH") { controller.refresh() }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                .accessibilityIdentifier("baseline.refresh")
        }
    }

    private func progress(_ status: BaselineObservationStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(status.completeDayCount) / \(status.requiredCompleteDays) COMPLETE DAYS")
                    .font(Sumi.display(18))
                Spacer()
                Text(status.isComplete ? "BASELINE COMPLETE" : "OBSERVATION MODE")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(status.isComplete ? Sumi.okay : Sumi.seal)
            }
            ProgressView(value: status.progress)
                .progressViewStyle(.linear)
                .accessibilityLabel("Baseline progress")
                .accessibilityValue("\(status.completeDayCount) of \(status.requiredCompleteDays) complete days")
            Text(status.isComplete
                 ? "The baseline is complete. The configured coaching level may now begin, while pause and override controls remain available."
                 : "Accountability prompts are paused for \(status.remainingCompleteDays) more complete day\(status.remainingCompleteDays == 1 ? "" : "s"). Eligible drift is still counted so the later review reflects what actually happened.")
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
                .accessibilityIdentifier("baseline.prompt-policy")
            Text("\(status.observedEligibleDriftCount) eligible drift episode\(status.observedEligibleDriftCount == 1 ? "" : "s") observed without interruption")
                .font(Sumi.body(12))
                .accessibilityIdentifier("baseline.eligible-drift")
        }
        .padding(16)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
        .accessibilityIdentifier("baseline.progress")
    }

    private func dayLedger(_ status: BaselineObservationStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAY-BY-DAY COVERAGE")
                .font(Sumi.label())
                .sumiLabelTracking()
            if status.days.isEmpty {
                Text("The baseline starts after the first completed day with local behavior coverage. Today never counts before it is finished.")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
            } else {
                ForEach(status.days) { day in
                    HStack(spacing: 12) {
                        Text(day.localDay)
                            .font(.system(size: 11, design: .monospaced))
                        Text(day.coverage == .complete ? "COUNTS" : day.coverage.rawValue.uppercased())
                            .font(Sumi.label(8))
                            .sumiLabelTracking()
                            .foregroundStyle(day.coverage == .complete ? Sumi.okay : Sumi.seal)
                        Spacer()
                        Text("\(day.observedMinutes)m observed · \(day.eligibleDriftCount) eligible drift")
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.muted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("baseline.day.\(day.localDay)")
                }
            }
        }
    }

    private func report(_ report: BaselineObservationReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BASELINE REVIEW")
                .font(Sumi.label())
                .sumiLabelTracking()
            Text("Capacity, gaming, and alert sensitivity")
                .font(Sumi.display(18))
            HStack(spacing: 12) {
                reportMetric("WORK CAPACITY", "\(report.averageObservedWorkMinutes)m", "average observed work per complete day")
                reportMetric("GAMING", "\(report.totalGamingMinutes)m", "across \(report.gamingDayCount) complete day\(report.gamingDayCount == 1 ? "" : "s")")
                reportMetric("DRIFT", "\(report.eligibleDriftCount)", "eligible episodes observed quietly")
            }
            Text(report.alertSensitivityGuidance)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.muted)
                .accessibilityIdentifier("baseline.alert-guidance")
            Text("Unknown or idle coverage: \(report.unknownSharePercent)%. This review describes local observations; it does not grade effort or infer intent.")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
        }
        .padding(16)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
        .accessibilityIdentifier("baseline.report")
    }

    private func reportMetric(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Sumi.label(8)).sumiLabelTracking()
            Text(value).font(Sumi.display(20))
            Text(detail).font(Sumi.body(10)).foregroundStyle(Sumi.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BASELINE UNAVAILABLE")
                .font(Sumi.label())
                .sumiLabelTracking()
                .foregroundStyle(Sumi.sealDeep)
            Text(message).font(Sumi.body(13))
            Text("Planning and manual task tracking remain available. No behavior prompt is enabled from an unreadable baseline.")
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
            Button("TRY AGAIN") { controller.refresh() }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                .accessibilityIdentifier("baseline.retry")
        }
        .accessibilityIdentifier("baseline.error")
    }
}
