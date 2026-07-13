import Foundation
import Testing
import ZoidCoachCore
import ZoidCoachInfrastructure

@Suite("Accepted break reminder service")
struct AcceptedBreakReminderServiceTests {
    @Test("A persisted break schedules once at the exact end and resume cancels it")
    func restartSafeScheduleAndCancellation() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let startedAt = now.addingTimeInterval(-120)
        let scheduler = RecordingAcceptedBreakScheduler()
        let service = AcceptedBreakReminderService(scheduler: scheduler)
        let onBreak = row(
            acceptedBreak: AcceptedBreakSnapshot(startedAt: startedAt),
            latestPauseReason: .break
        )

        let first = await service.reconcile(taskRows: [onBreak], now: now)
        let replay = await service.reconcile(taskRows: [onBreak], now: now.addingTimeInterval(5))

        #expect(first.scheduledTaskIDs == ["priority"])
        #expect(replay.scheduledTaskIDs.isEmpty)
        let scheduled = await scheduler.scheduled
        #expect(scheduled.count == 1)
        #expect(scheduled[0].taskTitle == "Ship proposal")
        #expect(scheduled[0].startedAt == startedAt)
        #expect(scheduled[0].deliveryDate == startedAt.addingTimeInterval(15 * 60))

        let resumed = row(acceptedBreak: nil, latestPauseReason: .break, state: .active)
        let cancellation = await service.reconcile(taskRows: [resumed], now: now.addingTimeInterval(10))

        #expect(cancellation.cancelledTaskIDs == ["priority"])
        #expect(await scheduler.cancelledTaskIDs == ["priority"])
    }

    @Test("A helper restart after the boundary schedules one immediate recovery reminder")
    func missedBoundarySchedulesImmediateReminder() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scheduler = RecordingAcceptedBreakScheduler()
        let service = AcceptedBreakReminderService(scheduler: scheduler)
        let expired = row(
            acceptedBreak: AcceptedBreakSnapshot(startedAt: now.addingTimeInterval(-20 * 60)),
            latestPauseReason: .break
        )

        let result = await service.reconcile(taskRows: [expired], now: now)

        #expect(result.scheduledTaskIDs == ["priority"])
        #expect(await scheduler.scheduled.first?.deliveryDate == now.addingTimeInterval(1))
    }

    @Test("The QA notification seam replaces per-break requests and cancels on resume")
    func fixtureNotificationReplacementAndCancellation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("accepted-break-reminder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runtime = try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: [:],
            packagedRuntime: .init(
                mode: .qa,
                qaRunRoot: root,
                appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
            ),
            executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
        ).environment
        let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(runtimeEnvironment: runtime)
        try adapter.reset(to: .init(permissions: [.notifications: .granted]))
        let coordinator = PromptNotificationCoordinator(
            promptStore: try PromptInboxStore(databaseURL: runtime.databaseURL),
            fixtureAdapter: adapter,
            runtimeEnvironment: runtime
        )
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let deliveryDate = startedAt.addingTimeInterval(15 * 60)

        #expect(try await coordinator.scheduleAcceptedBreakEnd(
            taskID: "priority",
            taskTitle: "Ship proposal",
            startedAt: startedAt,
            deliveryDate: deliveryDate
        ))
        #expect(try await coordinator.scheduleAcceptedBreakEnd(
            taskID: "priority",
            taskTitle: "Ship proposal",
            startedAt: startedAt,
            deliveryDate: deliveryDate
        ) == false)

        let scheduled = try adapter.snapshot().notifications
        #expect(scheduled.count == 1)
        #expect(scheduled[0].desired.category == "BREAK_END")
        #expect(scheduled[0].desired.title == "Break complete")
        #expect(scheduled[0].desired.body == "Ship proposal is ready when you are. Resume when it feels right.")
        #expect(scheduled[0].desired.deliveryDate == deliveryDate)
        #expect(scheduled[0].id.hasPrefix("zcqa.action.accepted-break.priority."))

        try adapter.cancelNotifications(withPrefix: "zcqa.action.accepted-break.priority.")
        #expect(try adapter.snapshot().notifications.isEmpty)
        #expect(try await coordinator.scheduleAcceptedBreakEnd(
            taskID: "priority",
            taskTitle: "Ship proposal",
            startedAt: startedAt,
            deliveryDate: deliveryDate
        ) == false)
        #expect(try adapter.snapshot().notifications.isEmpty)

        await coordinator.cancelAcceptedBreakEnds(taskID: "priority")
        #expect(try adapter.snapshot().notifications.isEmpty)

        #expect(try await coordinator.scheduleAcceptedBreakEnd(
            taskID: "priority",
            taskTitle: "Ship proposal",
            startedAt: startedAt.addingTimeInterval(1_800),
            deliveryDate: deliveryDate.addingTimeInterval(1_800)
        ))
        #expect(try adapter.snapshot().notifications.count == 1)
    }

    private func row(
        acceptedBreak: AcceptedBreakSnapshot?,
        latestPauseReason: TaskPauseReason?,
        state: TaskExecutionState = .paused
    ) -> TodayTaskRow {
        TodayTaskRow(
            taskID: "priority",
            title: "Ship proposal",
            estimateMinutes: 60,
            dueDate: nil,
            urgency: .low,
            state: state,
            latestPauseReason: latestPauseReason,
            acceptedBreak: acceptedBreak
        )
    }
}

private actor RecordingAcceptedBreakScheduler: AcceptedBreakReminderScheduling {
    struct Scheduled: Equatable {
        let taskID: String
        let taskTitle: String
        let startedAt: Date
        let deliveryDate: Date
    }

    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelledTaskIDs: [String] = []

    func scheduleAcceptedBreakEnd(
        taskID: String,
        taskTitle: String,
        startedAt: Date,
        deliveryDate: Date
    ) async throws -> Bool {
        let value = Scheduled(
            taskID: taskID,
            taskTitle: taskTitle,
            startedAt: startedAt,
            deliveryDate: deliveryDate
        )
        guard !scheduled.contains(value) else { return false }
        scheduled.append(value)
        return true
    }

    func cancelAcceptedBreakEnds(taskID: String) async {
        cancelledTaskIDs.append(taskID)
    }
}
