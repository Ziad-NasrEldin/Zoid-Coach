import AppKit
import SQLite3
import SwiftUI
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@Suite("Menu bar active time comparison")
struct MenuBarActiveTimeComparisonTests {
    @Test("elapsed and observed aligned time stay separate while the active timer advances")
    func activeComparisonKeepsLiveElapsedSeparateFromObservedEvidence() throws {
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let comparison = ActiveTaskTimeComparison(
            elapsedMinutes: 12,
            activeSince: confirmedAt.addingTimeInterval(-720),
            observations: [
                .init(observedAt: confirmedAt.addingTimeInterval(-120), application: "Xcode", classification: .work),
                .init(observedAt: confirmedAt.addingTimeInterval(-60), application: "Steam", classification: .gaming),
            ],
            now: confirmedAt
        )
        let row = activeTimingTask(elapsedMinutes: 12, comparison: comparison)
        let state = MenuBarCoachState(
            snapshot: activeTimingSnapshot(
                row: row,
                startedAt: confirmedAt.addingTimeInterval(-720)
            ),
            snapshotConfirmedAt: confirmedAt
        )

        let presentation = try #require(state.activeTimeComparison(at: confirmedAt.addingTimeInterval(125)))
        #expect(presentation.elapsedMinutes == 14)
        #expect(presentation.observedAlignedMinutes == 1)
        #expect(presentation.elapsedText == "14 MIN ELAPSED")
        #expect(presentation.alignedText == "1 MIN OBSERVED ALIGNED")
        #expect(presentation.accessibilitySummary.contains("Task elapsed 14 minutes"))
        #expect(presentation.accessibilitySummary.contains("Observed aligned 1 minute"))
        #expect(presentation.evidenceExplanation.contains("signal, not proof"))
    }

    @Test("missing producer data stays absent while zero observed evidence is explicit")
    func unavailableComparisonStaysAbsentAndZeroEvidenceRemainsHonest() throws {
        let row = activeTimingTask(elapsedMinutes: 9, comparison: nil)
        let activeState = MenuBarCoachState(snapshot: activeTimingSnapshot(row: row))
        #expect(activeState.activeTimeComparison(at: Date()) == nil)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let zeroEvidence = ActiveTaskTimeComparison(
            elapsedMinutes: 9,
            activeSince: now.addingTimeInterval(-540),
            observations: [],
            now: now
        )
        let zeroEvidenceState = MenuBarCoachState(snapshot: activeTimingSnapshot(
            row: activeTimingTask(elapsedMinutes: 9, comparison: zeroEvidence)
        ))
        let zeroPresentation = try #require(zeroEvidenceState.activeTimeComparison(at: now))
        #expect(zeroPresentation.observedAlignedMinutes == 0)
        #expect(zeroPresentation.evidenceExplanation.contains("No Screenwatch time"))

        let pausedRow = TodayTaskRow(
            taskID: row.taskID,
            title: row.title,
            estimateMinutes: row.estimateMinutes,
            dueDate: nil,
            urgency: .medium,
            state: .paused,
            elapsedMinutes: 9,
            activeTimeComparison: ActiveTaskTimeComparison(
                elapsedMinutes: 9,
                activeSince: Date().addingTimeInterval(-540),
                observations: [],
                now: Date()
            )
        )
        #expect(MenuBarCoachState(snapshot: activeTimingSnapshot(row: pausedRow, isActive: false))
            .activeTimeComparison(at: Date()) == nil)
    }

    @Test("compact comparison exposes separate stable accessibility elements")
    @MainActor
    func compactComparisonAccessibilityIsIndependentlyNavigable() async throws {
        let presentation = MenuBarActiveTimeComparison(
            elapsedMinutes: 14,
            observedAlignedMinutes: 5,
            evidenceExplanation: "Aligned time is observed work evidence, not proof of task match."
        )
        let host = NSHostingView(rootView: MenuBarActiveTimeComparisonView(comparison: presentation))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 110)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        let records = activeTimingAccessibilityDescendants(of: host).compactMap { element -> ActiveTimingAccessibilityRecord? in
            guard let identifier = activeTimingAccessibilityIdentifier(element),
                  identifier.hasPrefix("menu-bar.task.")
            else { return nil }
            return .init(
                identifier: identifier,
                label: activeTimingAccessibilityLabel(element) ?? ""
            )
        }
        #expect(records.contains(.init(
            identifier: "menu-bar.task.elapsed-time",
            label: "Task elapsed, 14 minutes"
        )))
        #expect(records.contains(.init(
            identifier: "menu-bar.task.aligned-time",
            label: "Observed aligned, 5 minutes"
        )))
        #expect(records.contains(where: {
            $0.identifier == "menu-bar.task.alignment-evidence"
                && $0.label.contains("not proof")
        }))

        withExtendedLifetime(host) {}
    }

    @Test("relaunch restores persisted elapsed and observed aligned evidence")
    func relaunchedAgentRestoresComparisonForCompactPresentation() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoid-666-menu-active-time-\(UUID().uuidString).sqlite")
        defer { removeActiveTimingDatabase(at: databaseURL) }
        let activeSince = Date(timeIntervalSince1970: 1_750_000_000)
        let now = activeSince.addingTimeInterval(180)

        let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
        try reminders.replace([
            .init(id: "focus", title: "Write proposal", dueDate: now, priority: 9),
        ])
        let plans = try AutonomousPlanStore(databaseURL: databaseURL)
        try plans.replaceDailyPlan(
            .init(
                items: [
                    .init(taskID: "focus", title: "Write proposal", rank: 1, estimateMinutes: 30, reason: "Main", score: 100),
                ],
                mainObjectiveTaskID: "focus",
                plannedFocusMinutes: 30,
                availableFocusMinutes: 60
            ),
            for: activeSince
        )
        do {
            let firstAgent = try TodayDashboardAgent(databaseURL: databaseURL)
            _ = try firstAgent.apply(.start, taskID: "focus", now: activeSince)
        }
        try insertActiveTimingObservations(databaseURL: databaseURL, activeSince: activeSince)

        let relaunchedAgent = try TodayDashboardAgent(databaseURL: databaseURL)
        let restoredSnapshot = try relaunchedAgent.snapshot(now: now)
        let state = MenuBarCoachState(snapshot: restoredSnapshot, snapshotConfirmedAt: now)
        let presentation = try #require(state.activeTimeComparison(at: now))

        #expect(restoredSnapshot.activeTask?.taskID == "focus")
        #expect(presentation.elapsedMinutes == 3)
        #expect(presentation.observedAlignedMinutes == 2)
        #expect(presentation.evidenceExplanation.contains("signal, not proof"))
    }
}

private func activeTimingTask(
    elapsedMinutes: Int,
    comparison: ActiveTaskTimeComparison?
) -> TodayTaskRow {
    .init(
        taskID: "focus",
        title: "Write proposal",
        estimateMinutes: 30,
        dueDate: nil,
        urgency: .medium,
        state: .active,
        elapsedMinutes: elapsedMinutes,
        activeTimeComparison: comparison
    )
}

private func activeTimingSnapshot(
    row: TodayTaskRow,
    startedAt: Date? = nil,
    isActive: Bool = true
) -> TodaySnapshot {
    .init(
        localDate: Date(timeIntervalSince1970: 1_800_000_000),
        timeZoneIdentifier: "UTC",
        mainObjective: row.title,
        taskRows: [row],
        activeTask: isActive
            ? .init(taskID: row.taskID, startedAt: startedAt, elapsedMinutes: row.elapsedMinutes)
            : nil,
        recommendation: .init(taskID: row.taskID, sentence: "Continue focused work", reasons: []),
        behavior: .init(workMinutes: 0, gamingMinutes: 0, distractingMinutes: 0, idleMinutes: 0),
        coverage: .init(isLimited: true, explanation: "No evidence", lastObservationAt: nil),
        gaming: .init(
            budgetMinutes: 0,
            earnedMinutes: 0,
            usedMinutes: 0,
            unlockedRemainingMinutes: 0,
            nextUnlockReason: "Observation only",
            confidenceIsLimited: true,
            budgetEnabled: false
        ),
        sourceFreshnessExplanation: "Local snapshot"
    )
}

private func insertActiveTimingObservations(databaseURL: URL, activeSince: Date) throws {
    var database: OpaquePointer?
    try #require(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let records = [
        (activeSince, "Steam", "gaming"),
        (activeSince.addingTimeInterval(60), "Xcode", "work"),
        (activeSince.addingTimeInterval(120), "Terminal", "work"),
    ]
    for (observedAt, application, classification) in records {
        let sql = """
        INSERT INTO behavior_records(
            source_day, epoch, time_label, app_name, window_title, url,
            has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version
        ) VALUES (
            '2025-06-15', \(Int(observedAt.timeIntervalSince1970)), '00-00-00',
            '\(application)', '', '', 0, NULL, '2025-06-15T00:00:00Z', '\(classification)', 1
        );
        """
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }
}

private func removeActiveTimingDatabase(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}

private struct ActiveTimingAccessibilityRecord: Equatable {
    let identifier: String
    let label: String
}

@MainActor
private func activeTimingAccessibilityIdentifier(_ element: Any) -> String? {
    if let element = element as? NSAccessibilityElement { return element.accessibilityIdentifier() }
    if let element = element as? NSView { return element.accessibilityIdentifier() }
    return nil
}

@MainActor
private func activeTimingAccessibilityLabel(_ element: Any) -> String? {
    if let element = element as? NSAccessibilityElement { return element.accessibilityLabel() }
    if let element = element as? NSView { return element.accessibilityLabel() }
    return nil
}

@MainActor
private func activeTimingAccessibilityDescendants(of root: NSView) -> [Any] {
    var visited = Set<ObjectIdentifier>()
    var result: [Any] = []

    func visit(_ value: Any) {
        guard let object = value as AnyObject? else { return }
        let identity = ObjectIdentifier(object)
        guard visited.insert(identity).inserted else { return }
        result.append(value)
        if let view = value as? NSView {
            view.subviews.forEach(visit)
            view.accessibilityChildren()?.forEach(visit)
        } else if let element = value as? NSAccessibilityElement {
            element.accessibilityChildren()?.forEach(visit)
        }
    }

    visit(root)
    return result
}
