import Foundation
import Testing
@testable import ZoidCoachInfrastructure

@Test
func taskHistoryStoreCountsPostponementsForFuturePlanning() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-history-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try TaskHistoryStore(databaseURL: databaseURL)
    try store.record(taskID: "proposal", state: .selected)
    try store.record(taskID: "proposal", state: .postponed)
    try store.record(taskID: "proposal", state: .postponed)

    let evidence = try store.evidence(for: ["proposal"])

    #expect(evidence["proposal"]?.deferralCount == 2)
    #expect(evidence["proposal"]?.selectionCount == 1)
}

@Test
func taskHistoryStoreSummarizesTheCompletedAndPostponedDay() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-day-history-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try TaskHistoryStore(databaseURL: databaseURL)
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    try store.record(taskID: "proposal", state: .selected, at: day)
    try store.record(taskID: "proposal", state: .completed, at: day)
    try store.record(taskID: "admin", state: .postponed, at: day)

    let summary = try store.summary(for: day)

    #expect(summary.selectedCount == 1)
    #expect(summary.completedCount == 1)
    #expect(summary.postponedCount == 1)
}
