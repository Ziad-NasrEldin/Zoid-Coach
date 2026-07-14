import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachInfrastructure

@Test
func durablePromotionSurvivesStoreAndLearningServiceRestart() throws {
    let databaseURL = promotionDatabaseURL("restart")
    defer { removePromotionDatabase(databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let promotedAt = ISO8601DateFormatter().date(from: "2026-07-14T12:00:00Z")!
    let candidate = persistedCandidate()

    let firstStore = try ReviewHypothesisPromotionStore(databaseURL: databaseURL, now: { promotedAt })
    let firstService = ReviewHypothesisLearningService(sink: firstStore)
    let first = try firstService.reconcile(candidate: candidate, decision: .accepted)

    let reopenedStore = try ReviewHypothesisPromotionStore(databaseURL: databaseURL)
    let reopenedService = ReviewHypothesisLearningService(sink: reopenedStore)
    let restoredBoundary = try reopenedService.boundary(for: candidate)
    let repeated = try reopenedService.reconcile(candidate: candidate, decision: .accepted)
    let stored = try #require(try reopenedStore.promotion(candidateID: candidate.id))

    #expect(first.kind == .promoted)
    #expect(restoredBoundary.status == .learned)
    #expect(repeated.kind == .alreadyPromoted)
    #expect(stored.hypothesis == candidate.hypothesis)
    #expect(stored.sourceDay == candidate.sourceDay)
    #expect(stored.evidence == candidate.evidence)
    #expect(stored.promotedAt == promotedAt)
}

@Test
func pendingAndRejectedHypothesesNeverReachDurableStore() throws {
    let databaseURL = promotionDatabaseURL("negative-boundary")
    defer { removePromotionDatabase(databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let store = try ReviewHypothesisPromotionStore(databaseURL: databaseURL)
    let service = ReviewHypothesisLearningService(sink: store)
    let candidate = persistedCandidate()

    #expect(try service.reconcile(candidate: candidate, decision: .pending).kind == .notLearned)
    #expect(try service.reconcile(candidate: candidate, decision: .rejected).kind == .notLearned)
    #expect(try store.promotion(candidateID: candidate.id) == nil)
    #expect(try service.boundary(for: candidate).status == .notLearned)
}

@Test
func durablePromotionIdentityRejectsChangedEvidence() throws {
    let databaseURL = promotionDatabaseURL("conflict")
    defer { removePromotionDatabase(databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let store = try ReviewHypothesisPromotionStore(databaseURL: databaseURL)
    let service = ReviewHypothesisLearningService(sink: store)
    let candidate = persistedCandidate()
    _ = try service.reconcile(candidate: candidate, decision: .accepted)
    let conflicting = ReviewHypothesisLearningCandidate(
        id: candidate.id,
        hypothesis: candidate.hypothesis,
        sourceDay: candidate.sourceDay,
        evidence: ["Different evidence"]
    )

    #expect(throws: ReviewHypothesisLearningError.candidateConflict(candidate.id)) {
        try service.reconcile(candidate: conflicting, decision: .accepted)
    }
}

private func persistedCandidate() -> ReviewHypothesisLearningCandidate {
    ReviewHypothesisLearningCandidate(
        id: "weekly-review:2026-07-06:2026-07-12:best-work-window",
        hypothesis: "Focused work may be easier before noon.",
        sourceDay: "2026-07-06 TO 2026-07-12",
        evidence: ["Monday: 42 corrected work minutes", "Wednesday: 38 corrected work minutes"]
    )
}

private func promotionDatabaseURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-review-promotion-\(name)-\(UUID().uuidString).sqlite")
}

private func removePromotionDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
