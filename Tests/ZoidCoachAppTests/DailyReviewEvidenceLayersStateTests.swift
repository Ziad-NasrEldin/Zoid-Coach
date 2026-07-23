import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Daily review evidence layers")
struct DailyReviewEvidenceLayersStateTests {
    @Test("facts, context, and hypotheses remain visibly distinct")
    func distinctLayers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = DailyReviewSnapshot(
            sourceDay: "2026-07-14",
            sessions: [
                session(application: "Xcode", classification: .work, start: now, minutes: 10),
                session(application: "Safari", classification: .unknown, start: now.addingTimeInterval(900), minutes: 5),
            ],
            totals: [
                DailyReviewTotal(classification: .work, minutes: 10),
                DailyReviewTotal(classification: .unknown, minutes: 5),
            ],
            hypothesis: "Observed work was the largest covered category.",
            hypothesisState: .pending,
            confirmedAt: nil,
            personalNote: "Client feedback changed the afternoon.",
            offlineWork: [OfflineWorkEntry(
                id: "offline",
                sourceDay: "2026-07-14",
                startedAt: now,
                durationMinutes: 15,
                note: nil,
                createdAt: now,
                updatedAt: now
            )]
        )

        let state = DailyReviewEvidenceLayersState(snapshot: snapshot)

        #expect(state.layers.map(\.kind) == [.facts, .context, .hypothesis])
        #expect(state.layers[0].body.contains("15 corrected observed minutes across 2 sessions"))
        #expect(state.layers[0].body.contains("15 minutes recorded away from the Mac"))
        #expect(state.layers[1].body.contains("5 observed minutes remain Unknown"))
        #expect(state.layers[1].body.contains("personal note supplies user context"))
        #expect(state.layers[2].body == "Observed work was the largest covered category.")
        #expect(state.layers[2].detail.contains("never presented as fact"))
    }

    @Test("empty evidence never invents a fact, context, or hypothesis")
    func honestEmptyState() {
        let snapshot = DailyReviewSnapshot(
            sourceDay: "2026-07-14",
            sessions: [],
            totals: [],
            hypothesis: nil,
            hypothesisState: .pending,
            confirmedAt: nil
        )

        let state = DailyReviewEvidenceLayersState(snapshot: snapshot)

        #expect(state.layers[0].body == "No covered activity or completed task was recorded for this day.")
        #expect(state.layers[1].body.contains("Screenwatch contributed no corrected minutes"))
        #expect(state.layers[2].body == "No possible explanation was generated because the covered evidence is insufficient.")
    }

    @Test("all three layers expose stable accessibility contracts")
    func accessibilityContracts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZoidCoachApp/Views/DailyReviewView.swift"),
            encoding: .utf8
        )
        let state = DailyReviewEvidenceLayersState(snapshot: DailyReviewSnapshot(
            sourceDay: "2026-07-14",
            sessions: [],
            totals: [],
            hypothesis: nil,
            hypothesisState: .pending,
            confirmedAt: nil
        ))

        #expect(source.contains("reviews.evidence-layers"))
        #expect(state.layers.map(\.accessibilityIdentifier) == [
            "reviews.evidence-layers.facts",
            "reviews.evidence-layers.context",
            "reviews.evidence-layers.hypothesis",
        ])
        #expect(state.layers.allSatisfy { !$0.accessibilityLabel.isEmpty })
    }

    private func session(
        application: String,
        classification: BehaviorClassification,
        start: Date,
        minutes: Int
    ) -> DailyReviewSession {
        DailyReviewSession(
            sourceDay: "2026-07-14",
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            application: application,
            classification: classification,
            observationCount: 1
        )
    }
}
