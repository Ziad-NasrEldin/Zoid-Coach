import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func calendarPlanOperationPersistsFrozenIntentAndExactReceiptAcrossRelaunch() throws {
    let databaseURL = temporaryCalendarOperationDatabase("relaunch")
    defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
    let operationID = UUID()
    let day = Date(timeIntervalSince1970: 1_752_489_600)
    let prepared = preparedCalendarSchedule(fingerprint: "fingerprint-a")
    let receipt = AgentMutationReceipt(
        accepted: true,
        commandIDs: ["cmd-calendar", "cmd-reminder"],
        message: "Reconciled 2 exact Calendar and Reminder updates."
    )

    do {
        let store = try CalendarPlanOperationStore(databaseURL: databaseURL)
        let pending = try store.begin(
            id: operationID,
            requestFingerprint: prepared.requestFingerprint,
            normalizedDay: day,
            preparedSchedule: prepared,
            requestedAt: day
        )
        #expect(pending.state == .pending)
        #expect(pending.preparedSchedule == prepared)
        #expect(pending.receipt == nil)
        let sameFingerprintReplay = try store.begin(
            id: operationID,
            requestFingerprint: prepared.requestFingerprint,
            normalizedDay: day,
            preparedSchedule: PreparedAgentPlanSchedule(
                requestFingerprint: prepared.requestFingerprint,
                unscheduledTaskIDs: [],
                commands: []
            ),
            requestedAt: day.addingTimeInterval(1)
        )
        #expect(sameFingerprintReplay.preparedSchedule == prepared)
        try store.finish(
            id: operationID,
            requestFingerprint: prepared.requestFingerprint,
            receipt: receipt,
            at: day.addingTimeInterval(1)
        )
    }

    let relaunched = try CalendarPlanOperationStore(databaseURL: databaseURL)
    let loaded = try relaunched.load(id: operationID)
    let completed = try #require(loaded)
    #expect(completed.state == .completed)
    #expect(completed.preparedSchedule == prepared)
    #expect(completed.receipt == receipt)
    try relaunched.finish(
        id: operationID,
        requestFingerprint: prepared.requestFingerprint,
        receipt: receipt,
        at: day.addingTimeInterval(2)
    )
}

@Test
func calendarPlanOperationRejectsSameIDForChangedFingerprint() throws {
    let databaseURL = temporaryCalendarOperationDatabase("conflict")
    defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
    let store = try CalendarPlanOperationStore(databaseURL: databaseURL)
    let operationID = UUID()
    let day = Date(timeIntervalSince1970: 1_752_489_600)
    let first = preparedCalendarSchedule(fingerprint: "fingerprint-a")
    let changed = preparedCalendarSchedule(fingerprint: "fingerprint-b")

    _ = try store.begin(
        id: operationID,
        requestFingerprint: first.requestFingerprint,
        normalizedDay: day,
        preparedSchedule: first,
        requestedAt: day
    )

    #expect(throws: CalendarPlanOperationStoreError.operationKeyConflict) {
        _ = try store.begin(
            id: operationID,
            requestFingerprint: changed.requestFingerprint,
            normalizedDay: day,
            preparedSchedule: changed,
            requestedAt: day
        )
    }
    #expect(try store.load(id: operationID)?.preparedSchedule == first)
}

@Test
func calendarPlanOperationPersistsAuthoritativeRefusal() throws {
    let databaseURL = temporaryCalendarOperationDatabase("refusal")
    defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
    let store = try CalendarPlanOperationStore(databaseURL: databaseURL)
    let operationID = UUID()
    let day = Date(timeIntervalSince1970: 1_752_489_600)
    let prepared = PreparedAgentPlanSchedule(
        requestFingerprint: "fingerprint-refused",
        unscheduledTaskIDs: ["task-1"]
    )
    let refusal = AgentMutationReceipt(
        accepted: false,
        message: "The reviewed plan no longer fits. Nothing was written."
    )

    _ = try store.begin(
        id: operationID,
        requestFingerprint: prepared.requestFingerprint,
        normalizedDay: day,
        preparedSchedule: prepared,
        requestedAt: day
    )
    try store.finish(
        id: operationID,
        requestFingerprint: prepared.requestFingerprint,
        receipt: refusal,
        at: day
    )

    let loaded = try store.load(id: operationID)
    let stored = try #require(loaded)
    #expect(stored.state == .refused)
    #expect(stored.receipt == refusal)
}

private func preparedCalendarSchedule(fingerprint: String) -> PreparedAgentPlanSchedule {
    PreparedAgentPlanSchedule(
        requestFingerprint: fingerprint,
        unscheduledTaskIDs: [],
        commands: [
            AgentPlanPreparedCommand(
                type: .reconcileCalendarBlock,
                entityID: "task-1",
                desiredState: .calendarBlock(
                    CalendarBlockDesiredState(
                        title: "Write proposal",
                        start: Date(timeIntervalSince1970: 1_752_525_600),
                        end: Date(timeIntervalSince1970: 1_752_527_400),
                        ownershipToken: "zoid-plan:2025-07-14:task-1",
                        planItemID: "task-1"
                    )
                ),
                planVersion: 1,
                origin: .explicitUser
            ),
            AgentPlanPreparedCommand(
                type: .setReminderPriority,
                entityID: "task-1",
                desiredState: .reminder(ReminderDesiredState(priority: 1)),
                planVersion: 1,
                origin: .explicitUser
            )
        ]
    )
}

private func temporaryCalendarOperationDatabase(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-calendar-operation-\(label)-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("agent.sqlite")
}
