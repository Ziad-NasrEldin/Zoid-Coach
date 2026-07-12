import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class DailySourceCoverageController: ObservableObject {
    typealias Loader = @Sendable (Date, Calendar) async throws -> DailySourceCoverage

    @Published private(set) var coverage: DailySourceCoverage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let loader: Loader?
    private let unavailableError: Error?
    private let calendar: Calendar
    private var loadGeneration = 0

    convenience init() {
        do {
            try self.init(store: DailySourceCoverageStore(
                databaseURL: RuntimeEnvironment.current().databaseURL
            ))
        } catch {
            self.init(unavailableError: error)
        }
    }

    init(store: DailySourceCoverageStore, calendar: Calendar = .current) {
        loader = { day, calendar in
            try await Task.detached(priority: .utility) {
                try store.load(day: day, calendar: calendar)
            }.value
        }
        unavailableError = nil
        self.calendar = calendar
    }

    init(loader: @escaping Loader, calendar: Calendar = .current) {
        self.loader = loader
        unavailableError = nil
        self.calendar = calendar
    }

    private init(unavailableError: Error) {
        loader = nil
        self.unavailableError = unavailableError
        calendar = .current
    }

    @discardableResult
    func load(day: Date) -> Task<Void, Never>? {
        loadGeneration += 1
        let generation = loadGeneration
        guard let loader else {
            errorMessage = (unavailableError ?? DailySourceCoverageStoreError.openDatabase).localizedDescription
            isLoading = false
            return nil
        }
        isLoading = true
        let loadCalendar = calendar
        return Task { [weak self] in
            do {
                let result = try await loader(day, loadCalendar)
                guard let self, generation == self.loadGeneration else { return }
                self.coverage = result
                self.errorMessage = nil
            } catch {
                guard let self, generation == self.loadGeneration else { return }
                self.errorMessage = error.localizedDescription
            }
            guard let self, generation == self.loadGeneration else { return }
            self.isLoading = false
        }
    }
}

struct DailySourceCoverageView: View {
    let selectedDay: Date
    @StateObject private var controller: DailySourceCoverageController

    init(
        selectedDay: Date,
        controller: DailySourceCoverageController = DailySourceCoverageController()
    ) {
        self.selectedDay = selectedDay
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SOURCE COVERAGE")
                        .font(Sumi.label())
                        .sumiLabelTracking()
                    Text("What was observed, and what remains unknown")
                        .font(Sumi.display(20))
                }
                Spacer()
                Button("REFRESH") { controller.load(day: selectedDay) }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .accessibilityIdentifier("reviews.coverage.refresh")
            }
            if controller.isLoading {
                ProgressView("Rebuilding coverage from local evidence")
                    .accessibilityIdentifier("reviews.coverage.loading")
            } else if let error = controller.errorMessage {
                errorState(error)
            } else if let coverage = controller.coverage {
                summary(coverage)
                categoryBreakdown(coverage)
                sourceExplanation(coverage)
            }
        }
        .padding(18)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviews.source-coverage")
        .task(id: selectedDay) { controller.load(day: selectedDay) }
    }

    private func summary(_ coverage: DailySourceCoverage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if coverage.isLowCoverage {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LIMITED COVERAGE")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.sealDeep)
                    Text(lowCoverageExplanation(coverage))
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.sealDeep)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Sumi.sealWash)
                .accessibilityIdentifier("reviews.coverage.warning")
            }
            HStack(spacing: 0) {
                metric("ACTIVE TASK", coverage.displayMinutes(coverage.activeTaskMinutes), "reviews.coverage.active")
                metric("OBSERVED IN TASK", coverage.displayMinutes(coverage.observedTaskMinutes), "reviews.coverage.observed")
                metric("ALIGNED WORK", coverage.displayMinutes(coverage.alignedTaskMinutes), "reviews.coverage.aligned")
                metric("MISSING", missingValue(coverage), "reviews.coverage.missing")
            }
            Text(coverage.missingExplanation)
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
                .accessibilityIdentifier("reviews.coverage.missing-explanation")
        }
    }

    private func categoryBreakdown(_ coverage: DailySourceCoverage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OBSERVED CATEGORY EVIDENCE")
                .font(Sumi.label(9))
                .sumiLabelTracking()
            HStack(spacing: 0) {
                metric("WORK", coverage.displayMinutes(coverage.workMinutes), "reviews.coverage.work")
                metric("GAMING", coverage.displayMinutes(coverage.gamingMinutes), "reviews.coverage.gaming")
                metric("DISTRACTION", coverage.displayMinutes(coverage.distractingMinutes), "reviews.coverage.distracting")
                metric("UNKNOWN", coverage.displayMinutes(coverage.unknownMinutes), "reviews.coverage.unknown")
                metric(
                    "IDLE",
                    coverage.idleIsReliable ? coverage.displayMinutes(coverage.idleMinutes) : "not reliable",
                    "reviews.coverage.idle"
                )
            }
            Text("Unknown is kept separate from distraction. Idle is shown only when source coverage is healthy enough to support it.")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
        }
    }

    private func sourceExplanation(_ coverage: DailySourceCoverage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WHY TOTALS MAY BE INCOMPLETE")
                .font(Sumi.label(9))
                .sumiLabelTracking()
            if let source = coverage.source {
                Text("Screenwatch: \(source.state.uppercased())")
                    .font(Sumi.body(13))
                Text(source.detail)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                if !source.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(source.evidence)
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                }
                if let checkedAt = source.checkedAt {
                    Text("Last checked \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(Sumi.body(10))
                        .foregroundStyle(Sumi.muted)
                }
            } else {
                Text("No Screenwatch health checkpoint is available. Totals remain observed evidence, not a complete account of the day.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
            }
        }
        .accessibilityIdentifier("reviews.coverage.source-cause")
    }

    private func metric(_ title: String, _ value: String, _ identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value.uppercased())
                .font(Sumi.display(17))
            Text(title)
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Sumi.paleRule, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func lowCoverageExplanation(_ coverage: DailySourceCoverage) -> String {
        var parts: [String] = []
        if let percent = coverage.coveragePercent, percent < 70 {
            parts.append("Screenwatch covered about \(percent)% of active-task time")
        }
        if coverage.unknownSharePercent >= 30 {
            parts.append("\(coverage.unknownSharePercent)% of observed time remains unknown")
        }
        if coverage.source?.isHealthy == false {
            parts.append("the latest Screenwatch health check is \(coverage.source?.state ?? "unhealthy")")
        }
        if parts.isEmpty {
            parts.append("there is not enough observed activity for precise totals")
        }
        return parts.joined(separator: "; ") + ". Category minutes are rounded and must not be read as a complete account of the day."
    }

    private func missingValue(_ coverage: DailySourceCoverage) -> String {
        guard coverage.activeTaskMinutes > 0 else { return "not measurable" }
        return coverage.precision == .exactWithinTrackedWindow
            ? "\(coverage.missingTaskMinutes) min"
            : "about \(coverage.missingTaskMinutes) min"
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COVERAGE REVIEW UNAVAILABLE")
                .font(Sumi.label())
                .sumiLabelTracking()
                .foregroundStyle(Sumi.sealDeep)
            Text(message).font(Sumi.body(12))
            Text("No missing time is inferred while local evidence is unreadable.")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
            Button("TRY AGAIN") { controller.load(day: selectedDay) }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                .accessibilityIdentifier("reviews.coverage.retry")
        }
        .accessibilityIdentifier("reviews.coverage.error")
    }
}
