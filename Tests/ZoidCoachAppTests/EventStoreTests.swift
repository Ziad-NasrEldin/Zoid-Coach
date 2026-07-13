import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

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

@Test
func eventStorePersistsDailyPlanEntries() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-daily-plan-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = EventStore(databaseURL: databaseURL)
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let entries = [
        DailyPlanEntry(
            reminderID: "first",
            rank: 1,
            isMainObjective: true,
            estimateMinutes: 45,
            selectionReason: "Due within 24 hours",
            selectionScore: 880
        ),
        DailyPlanEntry(reminderID: "second", rank: 2, isMainObjective: false, estimateMinutes: nil)
    ]

    await store.replaceDailyPlan(entries, for: day)

    #expect(await store.loadDailyPlan(for: day) == entries)
}

@Test
func agentPlanPersistenceRetainsExplicitUnknownEstimateAcrossRestart() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-unknown-estimate-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let day = Date(timeIntervalSince1970: 1_700_000_000)

    try AgentOwnedStateStore(databaseURL: databaseURL).replaceDailyPlan([
        AgentPlanItem(
            reminderID: "uncertain",
            rank: 1,
            isMainObjective: true,
            estimateMinutes: nil,
            estimateIsUncertain: true,
            selectionReason: "User explicitly chose Unknown.",
            selectionScore: nil
        )
    ], day: day, now: day)

    let restored = await EventStore(databaseURL: databaseURL).loadDailyPlan(for: day)
    #expect(restored.count == 1)
    #expect(restored[0].estimateMinutes == nil)
    #expect(restored[0].estimateIsUncertain)
}

@Test
func legacyPlanMutationDecodesAsConfidentWhenUncertaintyFieldIsAbsent() throws {
    let data = Data(#"{"reminderID":"legacy","rank":1,"isMainObjective":true,"estimateMinutes":30,"selectionReason":null,"selectionScore":null,"isOptional":false,"blockedReason":null,"deferredUntil":null}"#.utf8)

    let item = try JSONDecoder().decode(AgentPlanItem.self, from: data)

    #expect(item.estimateMinutes == 30)
    #expect(item.estimateIsUncertain == nil)
}

@Test
func eventStoreLoadsOnlyIncompleteLocalTaskIdentifiersForPlanReconciliation() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-local-plan-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    _ = try reminders.upsertLocal(ReminderSourceSnapshot(
        id: "local-ready",
        title: "Keep the local plan",
        dueDate: nil,
        priority: 0,
        sourceKind: .local
    ))
    _ = try reminders.upsertLocal(ReminderSourceSnapshot(
        id: "local-complete",
        title: "Do not retain completed work",
        dueDate: nil,
        priority: 0,
        isCompleted: true,
        sourceKind: .local
    ))

    let store = EventStore(databaseURL: databaseURL)

    #expect(await store.loadIncompleteLocalTaskIDs() == ["local-ready"])
}

@Test
func eventStorePersistsReminderListOrder() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-list-order-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = EventStore(databaseURL: databaseURL)

    await store.replaceReminderListOrder(["work", "tinker", "later"])

    #expect(await store.loadReminderListOrder() == ["work", "tinker", "later"])
}

@Test
func eventStorePersistsZoidOwnedScheduledBlocksForTheCurrentDay() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-blocks-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = EventStore(databaseURL: databaseURL)
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let blocks = [
        ScheduledBlockRecord(
            planItemID: "client-review",
            calendarEventID: "event-1",
            start: Date(timeIntervalSince1970: 1_700_000_600),
            end: Date(timeIntervalSince1970: 1_700_003_300)
        )
    ]

    await store.replaceScheduledBlocks(blocks, for: day)

    #expect(await store.loadScheduledBlocks(for: day) == blocks)
}
