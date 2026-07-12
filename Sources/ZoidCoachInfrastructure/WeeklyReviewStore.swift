import Foundation
import SQLite3
import ZoidCoachCore

public final class WeeklyReviewStore: @unchecked Sendable {
    private let databaseURL: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        databaseURL: URL,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.databaseURL = databaseURL
        self.calendar = calendar
        self.now = now
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw WeeklyReviewStoreError.missingDatabase
        }
    }

    public func load(referenceDate: Date? = nil) throws -> WeeklyReviewSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let window = reviewWindow(referenceDate ?? now())
        let database = try open(readOnly: true)
        defer { sqlite3_close(database) }

        let coveredDays = try coveredReviewDays(database, window: window)
        let hasSufficientEvidence = coveredDays.count >= WeeklyReviewSnapshot.minimumCoveredDays
        let outcomes = try outcomeSummary(database, window: window)
        let range = WeeklyReviewDateRange(startDay: window.startDay, endDay: window.endDay)
        let patterns = try patternSummaries(
            database,
            window: window,
            range: range,
            coveredDays: coveredDays,
            evidenceIsSufficient: hasSufficientEvidence
        )
        let experiment = try loadOrProposeExperiment(
            database,
            window: window,
            patterns: patterns,
            evidenceIsSufficient: hasSufficientEvidence
        )

        let qualityExplanation: String
        if hasSufficientEvidence {
            qualityExplanation = "\(coveredDays.count) reviewed days have at least 30 minutes of observed activity. Patterns are still suggestions, not facts."
        } else {
            let remaining = WeeklyReviewSnapshot.minimumCoveredDays - coveredDays.count
            qualityExplanation = "Only \(coveredDays.count) adequately covered day\(coveredDays.count == 1 ? "" : "s") is confirmed. Review \(remaining) more day\(remaining == 1 ? "" : "s") before Zoid 666 offers a weekly conclusion or experiment."
        }

        return WeeklyReviewSnapshot(
            dateRange: range,
            coveredDays: coveredDays.count,
            quality: hasSufficientEvidence ? .sufficient : .limited,
            qualityExplanation: qualityExplanation,
            outcomes: outcomes,
            patterns: patterns,
            experiment: experiment
        )
    }

    @discardableResult
    public func acceptExperiment(id: String) throws -> WeeklyExperiment {
        try updateExperiment(id: id, state: .accepted, title: nil, instruction: nil, measurement: nil)
    }

    @discardableResult
    public func rejectExperiment(id: String) throws -> WeeklyExperiment {
        try updateExperiment(id: id, state: .rejected, title: nil, instruction: nil, measurement: nil)
    }

    @discardableResult
    public func editExperiment(
        id: String,
        title: String,
        instruction: String,
        measurement: String
    ) throws -> WeeklyExperiment {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMeasurement = measurement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanInstruction.isEmpty, !cleanMeasurement.isEmpty else {
            throw WeeklyReviewStoreError.incompleteExperiment
        }
        guard cleanTitle.count <= 120, cleanInstruction.count <= 500, cleanMeasurement.count <= 300 else {
            throw WeeklyReviewStoreError.experimentTooLong
        }
        return try updateExperiment(
            id: id,
            state: .proposed,
            title: cleanTitle,
            instruction: cleanInstruction,
            measurement: cleanMeasurement
        )
    }

    private func updateExperiment(
        id: String,
        state: WeeklyExperimentState,
        title: String?,
        instruction: String?,
        measurement: String?
    ) throws -> WeeklyExperiment {
        lock.lock()
        defer { lock.unlock() }
        let database = try open(readOnly: false)
        defer { sqlite3_close(database) }

        guard let current = try readExperiment(database, id: id) else {
            throw WeeklyReviewStoreError.missingExperiment
        }
        let timestamp = Self.timestamp(now())
        let trackingStart: String?
        if state == .accepted {
            trackingStart = dayString(calendar.date(byAdding: .day, value: 7, to: date(for: current.reviewWeekStart)) ?? now())
        } else {
            trackingStart = nil
        }
        let sql = """
        UPDATE weekly_review_experiments
        SET title = ?, instruction = ?, measurement = ?, state = ?, tracking_week_start = ?, updated_at_utc = ?
        WHERE id = ?;
        """
        try execute(
            database,
            sql,
            bindings: [
                .text(title ?? current.title),
                .text(instruction ?? current.instruction),
                .text(measurement ?? current.measurement),
                .text(state.rawValue),
                trackingStart.map(Binding.text) ?? .null,
                .text(timestamp),
                .text(id)
            ]
        )
        guard let updated = try readExperiment(database, id: id) else {
            throw WeeklyReviewStoreError.missingExperiment
        }
        return updated
    }

    private func loadOrProposeExperiment(
        _ database: OpaquePointer,
        window: ReviewWindow,
        patterns: [WeeklyReviewPattern],
        evidenceIsSufficient: Bool
    ) throws -> WeeklyExperiment? {
        if let existing = try readExperiment(database, reviewWeekStart: window.startDay) {
            return withTrackingProgress(existing, referenceDate: window.referenceDate)
        }
        guard evidenceIsSufficient, let pattern = patterns.max(by: { $0.confidencePercent < $1.confidencePercent }) else {
            return nil
        }

        let proposal = proposal(for: pattern, weekStart: window.startDay)
        let writable = try open(readOnly: false)
        defer { sqlite3_close(writable) }
        try execute(
            writable,
            """
            INSERT OR IGNORE INTO weekly_review_experiments(
                id, review_week_start, title, instruction, measurement, state,
                tracking_week_start, updated_at_utc
            ) VALUES (?, ?, ?, ?, ?, 'proposed', NULL, ?);
            """,
            bindings: [
                .text(proposal.id), .text(proposal.reviewWeekStart), .text(proposal.title),
                .text(proposal.instruction), .text(proposal.measurement),
                .text(Self.timestamp(proposal.updatedAt))
            ]
        )
        return try readExperiment(writable, reviewWeekStart: window.startDay)
    }

    private func patternSummaries(
        _ database: OpaquePointer,
        window: ReviewWindow,
        range: WeeklyReviewDateRange,
        coveredDays: [String],
        evidenceIsSufficient: Bool
    ) throws -> [WeeklyReviewPattern] {
        guard evidenceIsSufficient else { return [] }
        var patterns: [WeeklyReviewPattern] = []

        if let estimate = try aggregate(database, type: "estimate", window: window) {
            let direction = estimate.medianValue > 1.1
                ? "Recent focused work usually took longer than its estimate."
                : estimate.medianValue < 0.9
                    ? "Recent focused work usually finished inside its estimate."
                    : "Recent focused work generally matched its estimate."
            patterns.append(pattern(
                .estimateAccuracy,
                title: "Estimate accuracy",
                conclusion: direction,
                sampleCount: estimate.sampleCount,
                range: range,
                examples: ["Median actual-to-estimate ratio: \(String(format: "%.2f", estimate.medianValue))"],
                confidence: estimate.confidence,
                alternative: "Task difficulty or incomplete tracking may explain part of the difference."
            ))
        }

        if let workWindow = try aggregate(database, type: "preferred_work_window", window: window) {
            patterns.append(pattern(
                .bestWorkWindow,
                title: "Best work window",
                conclusion: "The strongest repeated work-window signal is \(workWindow.key.replacingOccurrences(of: "|", with: " · ")).",
                sampleCount: workWindow.sampleCount,
                range: range,
                examples: ["Local aggregate: \(workWindow.key)"],
                confidence: workWindow.confidence,
                alternative: "Meeting load and the kind of work attempted can shift the apparent window."
            ))
        }

        let driftRows = try correctedSessionMinutes(
            window: window,
            classifications: [.distracting, .gaming]
        )
        if let strongest = driftRows.first {
            patterns.append(pattern(
                .driftTrigger,
                title: "Frequent drift trigger",
                conclusion: "\(strongest.label) appeared most often during covered distracting or gaming intervals.",
                sampleCount: driftRows.reduce(0) { $0 + $1.count },
                range: range,
                examples: driftRows.map { "\($0.label): \($0.count) corrected minutes" },
                confidence: min(90, 45 + coveredDays.count * 8),
                alternative: "App presence does not prove intent; a review correction can change this pattern."
            ))
        }

        let gamingCounts = try dailyClassificationSummaries(window: window, classification: .gaming)
        let gamingBudget = (try? PolicyStore(databaseURL: databaseURL, readOnly: true).currentGamingPolicy().dailyBudgetMinutes) ?? 60
        if !gamingCounts.isEmpty {
            let overBudgetDays = gamingCounts.filter { $0.minutes > gamingBudget }.count
            patterns.append(pattern(
                .gamingBudget,
                title: "Gaming timing and budget",
                conclusion: overBudgetDays == 0
                    ? "Observed gaming stayed within the \(gamingBudget)-minute daily budget on covered days."
                    : "Observed gaming exceeded the \(gamingBudget)-minute daily budget on \(overBudgetDays) covered day\(overBudgetDays == 1 ? "" : "s").",
                sampleCount: gamingCounts.count,
                range: range,
                examples: gamingCounts.prefix(3).map {
                    "\($0.day): about \($0.minutes) minutes, first observed \(timeString($0.firstStart))"
                },
                confidence: min(85, 40 + gamingCounts.count * 8),
                alternative: "Observation gaps and classification corrections can change gaming totals."
            ))
        }

        let prompt = try promptSummary(database, window: window)
        if prompt.responded > 0 {
            patterns.append(pattern(
                .promptUsefulness,
                title: "Prompt follow-through",
                conclusion: "\(prompt.applied) of \(prompt.responded) answered prompts completed their requested local action.",
                sampleCount: prompt.responded,
                range: range,
                examples: ["Applied: \(prompt.applied)", "Failed or pending: \(max(0, prompt.responded - prompt.applied))"],
                confidence: min(85, 35 + prompt.responded * 10),
                alternative: "Completing an action does not prove that the prompt improved later behavior."
            ))
            patterns.append(pattern(
                .promptRecovery,
                title: "Recovery after prompts",
                conclusion: "\(prompt.recovered) of \(prompt.responded) answered prompts were followed by corrected observed work within 30 minutes.",
                sampleCount: prompt.responded,
                range: range,
                examples: prompt.recoveryExamples.isEmpty
                    ? ["No corrected work interval was observed within 30 minutes of an answered prompt."]
                    : prompt.recoveryExamples,
                confidence: min(80, 30 + prompt.responded * 8),
                alternative: "A later work interval may follow task completion, a break, or ordinary context change rather than the prompt."
            ))
        }

        let blocked = try groupedRows(
            database,
            sql: """
            SELECT COALESCE(NULLIF(TRIM(s.title), ''), 'Unnamed task'), COUNT(*)
            FROM task_history h
            LEFT JOIN source_tasks s ON s.source_id = h.task_id
            WHERE h.occurred_at >= ? AND h.occurred_at < ? AND h.state = 'blocked'
            GROUP BY h.task_id, s.title
            HAVING COUNT(*) >= 2
            ORDER BY COUNT(*) DESC, COALESCE(NULLIF(TRIM(s.title), ''), 'Unnamed task') ASC
            LIMIT 3;
            """,
            bindings: [.text(Self.timestamp(window.startDate)), .text(Self.timestamp(window.endExclusive))]
        )
        if let repeated = blocked.first {
            patterns.append(pattern(
                .blockedTasks,
                title: "Repeated blocked work",
                conclusion: "A task was marked blocked \(repeated.count) times during the review window.",
                sampleCount: blocked.reduce(0) { $0 + $1.count },
                range: range,
                examples: blocked.map { "\($0.label): \($0.count) blocked events" },
                confidence: 90,
                alternative: "Repeated status changes may describe one long external dependency rather than an unclear task."
            ))
        }

        return patterns.sorted {
            if $0.confidencePercent != $1.confidencePercent { return $0.confidencePercent > $1.confidencePercent }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }

    private func coveredReviewDays(_ database: OpaquePointer, window: ReviewWindow) throws -> [String] {
        var statement: OpaquePointer?
        let sql = """
        SELECT r.source_day
        FROM daily_reviews r
        WHERE r.source_day >= ? AND r.source_day <= ? AND r.confirmed_at_utc IS NOT NULL
          AND (SELECT COALESCE(MAX(b.epoch) - MIN(b.epoch), 0)
               FROM behavior_records b WHERE b.source_day = r.source_day) >= 1800
        ORDER BY r.source_day;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError(database, operation: "read covered days")
        }
        defer { sqlite3_finalize(statement) }
        bind(.text(window.startDay), to: statement, at: 1)
        bind(.text(window.endDay), to: statement, at: 2)
        var days: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) { days.append(String(cString: value)) }
        }
        return days
    }

    private func outcomeSummary(_ database: OpaquePointer, window: ReviewWindow) throws -> WeeklyReviewOutcomeSummary {
        var statement: OpaquePointer?
        let sql = """
        SELECT COUNT(*),
               SUM(CASE WHEN i.state = 'completed' THEN 1 ELSE 0 END),
               COALESCE(SUM(i.estimate_minutes), 0)
        FROM daily_plan_items i
        JOIN daily_plans p ON p.id = i.plan_id
        WHERE p.local_day >= ? AND p.local_day <= ?;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError(database, operation: "read planned outcomes")
        }
        defer { sqlite3_finalize(statement) }
        bind(.text(window.startDay), to: statement, at: 1)
        bind(.text(window.endDay), to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return WeeklyReviewOutcomeSummary(plannedTasks: 0, completedTasks: 0, plannedMinutes: 0)
        }
        return WeeklyReviewOutcomeSummary(
            plannedTasks: Int(sqlite3_column_int(statement, 0)),
            completedTasks: Int(sqlite3_column_int(statement, 1)),
            plannedMinutes: Int(sqlite3_column_int(statement, 2))
        )
    }

    private func aggregate(
        _ database: OpaquePointer,
        type: String,
        window: ReviewWindow
    ) throws -> AggregateRow? {
        var statement: OpaquePointer?
        let sql = """
        SELECT aggregate_key, sample_count, median_value, confidence
        FROM learning_aggregates
        WHERE aggregate_type = ? AND updated_at_utc >= ? AND updated_at_utc < ?
        ORDER BY confidence DESC, sample_count DESC, aggregate_key ASC LIMIT 1;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError(database, operation: "read learning aggregate")
        }
        defer { sqlite3_finalize(statement) }
        bind(.text(type), to: statement, at: 1)
        bind(.text(Self.timestamp(window.startDate)), to: statement, at: 2)
        bind(.text(Self.timestamp(window.endExclusive)), to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_ROW, let key = text(statement, 0) else { return nil }
        return AggregateRow(
            key: key,
            sampleCount: Int(sqlite3_column_int(statement, 1)),
            medianValue: sqlite3_column_double(statement, 2),
            confidence: Int((sqlite3_column_double(statement, 3) * 100).rounded())
        )
    }

    private func promptSummary(_ database: OpaquePointer, window: ReviewWindow) throws -> PromptSummary {
        var statement: OpaquePointer?
        let sql = """
        SELECT r.responded_at_utc, COALESCE(e.state, 'pending')
        FROM prompt_responses r
        LEFT JOIN prompt_response_effects e ON e.response_id = r.id
        WHERE r.responded_at_utc >= ? AND r.responded_at_utc < ?
        ORDER BY r.responded_at_utc ASC, r.id ASC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError(database, operation: "read prompt effectiveness")
        }
        defer { sqlite3_finalize(statement) }
        bind(.text(Self.timestamp(window.startDate)), to: statement, at: 1)
        bind(.text(Self.timestamp(window.endExclusive)), to: statement, at: 2)
        var responded = 0
        var applied = 0
        var recovered = 0
        var recoveryExamples: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let respondedRaw = text(statement, 0), let respondedAt = Self.date(respondedRaw) else { continue }
            responded += 1
            if text(statement, 1) == "applied" { applied += 1 }
            if try hasCorrectedWorkSoonAfter(respondedAt) {
                recovered += 1
                recoveryExamples.append("\(dayString(respondedAt)): corrected work observed within 30 minutes")
            }
        }
        return PromptSummary(
            responded: responded,
            applied: applied,
            recovered: recovered,
            recoveryExamples: Array(recoveryExamples.prefix(3))
        )
    }

    private func hasCorrectedWorkSoonAfter(_ responseDate: Date) throws -> Bool {
        let snapshot = try DailyReviewStore(databaseURL: databaseURL).load(sourceDay: dayString(responseDate))
        let deadline = responseDate.addingTimeInterval(30 * 60)
        return snapshot.sessions.contains {
            $0.classification == .work && $0.start >= responseDate && $0.start <= deadline
        }
    }

    private func groupedRows(
        _ database: OpaquePointer,
        sql: String,
        bindings: [Binding]
    ) throws -> [(label: String, count: Int)] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError(database, operation: "read weekly evidence")
        }
        defer { sqlite3_finalize(statement) }
        for (offset, binding) in bindings.enumerated() { bind(binding, to: statement, at: Int32(offset + 1)) }
        var rows: [(String, Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let label = text(statement, 0) { rows.append((label, Int(sqlite3_column_int(statement, 1)))) }
        }
        return rows
    }

    private func dailyClassificationSummaries(
        window: ReviewWindow,
        classification: BehaviorClassification
    ) throws -> [DailyClassificationSummary] {
        let reviewStore = try DailyReviewStore(databaseURL: databaseURL)
        var result: [DailyClassificationSummary] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: window.startDate) else { continue }
            let day = dayString(date)
            let snapshot = try reviewStore.load(sourceDay: day)
            let sessions = snapshot.sessions.filter { $0.classification == classification }
            guard let firstStart = sessions.map(\.start).min() else { continue }
            result.append(DailyClassificationSummary(
                day: day,
                minutes: sessions.reduce(0) { $0 + $1.durationMinutes },
                firstStart: firstStart
            ))
        }
        return result
    }

    private func correctedSessionMinutes(
        window: ReviewWindow,
        classifications: [BehaviorClassification]
    ) throws -> [(label: String, count: Int)] {
        let reviewStore = try DailyReviewStore(databaseURL: databaseURL)
        var minutesByApp: [String: Int] = [:]
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: window.startDate) else { continue }
            let snapshot = try reviewStore.load(sourceDay: dayString(date))
            for session in snapshot.sessions where classifications.contains(session.classification) {
                minutesByApp[session.application, default: 0] += session.durationMinutes
            }
        }
        return minutesByApp
            .map { (label: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.label < $1.label
            }
            .prefix(3)
            .map { $0 }
    }

    private func readExperiment(_ database: OpaquePointer, id: String) throws -> WeeklyExperiment? {
        try readExperiment(database, predicate: "id = ?", binding: .text(id))
    }

    private func readExperiment(_ database: OpaquePointer, reviewWeekStart: String) throws -> WeeklyExperiment? {
        try readExperiment(database, predicate: "review_week_start = ?", binding: .text(reviewWeekStart))
    }

    private func readExperiment(
        _ database: OpaquePointer,
        predicate: String,
        binding: Binding
    ) throws -> WeeklyExperiment? {
        var statement: OpaquePointer?
        let sql = """
        SELECT id, review_week_start, title, instruction, measurement, state,
               tracking_week_start, updated_at_utc
        FROM weekly_review_experiments WHERE \(predicate) LIMIT 1;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError(database, operation: "read weekly experiment")
        }
        defer { sqlite3_finalize(statement) }
        bind(binding, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let id = text(statement, 0), let week = text(statement, 1),
              let title = text(statement, 2), let instruction = text(statement, 3),
              let measurement = text(statement, 4), let rawState = text(statement, 5),
              let state = WeeklyExperimentState(rawValue: rawState),
              let updatedRaw = text(statement, 7), let updated = Self.date(updatedRaw) else { return nil }
        return WeeklyExperiment(
            id: id,
            reviewWeekStart: week,
            title: title,
            instruction: instruction,
            measurement: measurement,
            state: state,
            trackingWeekStart: text(statement, 6),
            updatedAt: updated
        )
    }

    private func withTrackingProgress(_ experiment: WeeklyExperiment, referenceDate: Date) -> WeeklyExperiment {
        guard experiment.state == .accepted,
              let rawStart = experiment.trackingWeekStart else { return experiment }
        let start = date(for: rawStart)
        let elapsed = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: referenceDate)).day ?? 0
        return WeeklyExperiment(
            id: experiment.id,
            reviewWeekStart: experiment.reviewWeekStart,
            title: experiment.title,
            instruction: experiment.instruction,
            measurement: experiment.measurement,
            state: experiment.state,
            trackingWeekStart: rawStart,
            trackingDaysCompleted: min(7, max(0, elapsed + 1)),
            updatedAt: experiment.updatedAt
        )
    }

    private func proposal(for pattern: WeeklyReviewPattern, weekStart: String) -> WeeklyExperiment {
        let title: String
        let instruction: String
        let measurement: String
        switch pattern.kind {
        case .estimateAccuracy:
            title = "Add a small estimate buffer"
            instruction = "For the next week, add 10 minutes to the first focused task estimate before approving the plan."
            measurement = "Compare planned and actual aligned minutes for the first focused task on each covered day."
        case .bestWorkWindow:
            title = "Protect the strongest work window"
            instruction = "Place the main objective inside the strongest observed work window on three days next week."
            measurement = "Compare completion and aligned-work coverage inside and outside that window."
        case .driftTrigger:
            title = "Add one intentional transition"
            instruction = "Before opening the most frequent drift app, pause for one minute and choose whether it serves the active task."
            measurement = "Count intentional choices and distracting intervals involving that app."
        case .gamingBudget:
            title = "Make the gaming boundary explicit"
            instruction = "Choose the intended gaming start before work begins and keep it visible in Today."
            measurement = "Compare daily gaming minutes with the configured budget on covered days."
        case .promptRecovery, .promptUsefulness:
            title = "Try one smaller recovery action"
            instruction = "When the next recovery prompt appears, choose the smallest offered action and return to the active task."
            measurement = "Track prompt completion and the next observed work interval without treating correlation as proof."
        case .blockedTasks:
            title = "Rewrite one repeatedly blocked task"
            instruction = "Turn one repeatedly blocked task into a next physical action before adding it to tomorrow's plan."
            measurement = "Count repeated blocked events for that task during the next covered week."
        }
        return WeeklyExperiment(
            id: "weekly-experiment-\(weekStart)",
            reviewWeekStart: weekStart,
            title: title,
            instruction: instruction,
            measurement: measurement,
            state: .proposed,
            updatedAt: now()
        )
    }

    private func pattern(
        _ kind: WeeklyReviewPatternKind,
        title: String,
        conclusion: String,
        sampleCount: Int,
        range: WeeklyReviewDateRange,
        examples: [String],
        confidence: Int,
        alternative: String
    ) -> WeeklyReviewPattern {
        WeeklyReviewPattern(
            id: "\(range.startDay)-\(kind.rawValue)",
            kind: kind,
            title: title,
            conclusion: conclusion,
            sampleCount: sampleCount,
            dateRange: range,
            examples: examples,
            confidencePercent: confidence,
            alternativeExplanation: alternative
        )
    }

    private func reviewWindow(_ referenceDate: Date) -> ReviewWindow {
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
            ?? calendar.startOfDay(for: referenceDate)
        let startDate = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
        let endExclusive = currentWeekStart
        let endDate = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? startDate
        return ReviewWindow(
            referenceDate: referenceDate,
            startDate: startDate,
            endExclusive: endExclusive,
            startDay: dayString(startDate),
            endDay: dayString(endDate)
        )
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func date(for day: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day) ?? now()
    }

    private func open(readOnly: Bool) throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX)
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            throw WeeklyReviewStoreError.openDatabase
        }
        sqlite3_busy_timeout(database, 2_000)
        return database
    }

    private func execute(_ database: OpaquePointer, _ sql: String, bindings: [Binding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError(database, operation: "prepare weekly update")
        }
        defer { sqlite3_finalize(statement) }
        for (offset, binding) in bindings.enumerated() { bind(binding, to: statement, at: Int32(offset + 1)) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(database, operation: "save weekly update")
        }
    }

    private func bind(_ value: Binding, to statement: OpaquePointer, at index: Int32) {
        switch value {
        case let .text(value):
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        case .null:
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private func databaseError(_ database: OpaquePointer, operation: String) -> WeeklyReviewStoreError {
        WeeklyReviewStoreError.database(operation: operation, detail: String(cString: sqlite3_errmsg(database)))
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

public enum WeeklyReviewStoreError: LocalizedError {
    case missingDatabase
    case openDatabase
    case missingExperiment
    case incompleteExperiment
    case experimentTooLong
    case database(operation: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .missingDatabase:
            "Weekly review is not ready because local storage has not been created yet."
        case .openDatabase:
            "Weekly review could not open local storage. Your existing data was not changed."
        case .missingExperiment:
            "That weekly experiment is no longer available. Refresh the review before trying again."
        case .incompleteExperiment:
            "Add a title, one concrete action, and a way to measure the experiment."
        case .experimentTooLong:
            "Keep the experiment title under 120 characters and its instructions concise."
        case let .database(operation, detail):
            "Weekly review could not \(operation). \(detail)"
        }
    }
}

private struct ReviewWindow {
    let referenceDate: Date
    let startDate: Date
    let endExclusive: Date
    let startDay: String
    let endDay: String
}

private struct AggregateRow {
    let key: String
    let sampleCount: Int
    let medianValue: Double
    let confidence: Int
}

private struct PromptSummary {
    let responded: Int
    let applied: Int
    let recovered: Int
    let recoveryExamples: [String]
}

private struct DailyClassificationSummary {
    let day: String
    let minutes: Int
    let firstStart: Date
}

private enum Binding {
    case text(String)
    case null
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
