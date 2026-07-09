import Foundation
import Testing
@testable import ZoidCoachApp

@Test
func eventStoreReplaysImmutableSourceCheckSequence() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-event-store-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = EventStore(databaseURL: databaseURL)
    let firstCheck = SourceHealth(id: .screenwatch, title: "Screenwatch", eyebrow: "Behavior", state: .healthy, detail: "9 records parsed", evidence: "Schema valid", actionTitle: "Refresh")
    let secondCheck = SourceHealth(id: .screenwatch, title: "Screenwatch", eyebrow: "Behavior", state: .attention, detail: "Stream stale", evidence: "Last event was 4 minutes ago", actionTitle: "Retry")
    let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
    let secondDate = Date(timeIntervalSince1970: 1_700_000_120)
    await store.recordSourceCheck(firstCheck, checkedAt: firstDate)
    await store.recordSourceCheck(secondCheck, checkedAt: secondDate)
    let replay = await store.replaySourceChecks()
    #expect(replay.count == 2)
    #expect(replay.map(\.state) == [.healthy, .attention])
    #expect(replay.map(\.detail) == ["9 records parsed", "Stream stale"])
    #expect(replay.map(\.checkedAt) == [firstDate, secondDate])
}
