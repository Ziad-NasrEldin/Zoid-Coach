import Foundation
import Testing
@testable import ZoidCoachApp

@MainActor
struct RemindersConnectionControllerTests {
    @Test func successfulRefreshPersistsCountAndLastSuccessAcrossReconstruction() async throws {
        let defaults = try isolatedDefaults()
        let completedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let service = StubRemindersService(
            health: Self.health(.healthy, detail: "Connected"),
            taskLoads: [.available([Self.task(id: "one"), Self.task(id: "two")])]
        )
        let controller = RemindersConnectionController(
            service: service,
            defaults: defaults,
            now: { completedAt }
        )

        await controller.refresh()

        #expect(controller.state == .connected(taskCount: 2))
        #expect(controller.lastSuccessfulSync == completedAt)
        let reconstructed = RemindersConnectionController(service: service, defaults: defaults)
        #expect(reconstructed.lastSuccessfulSync == completedAt)
        #expect(service.inspectCount == 1)
        #expect(service.requestCount == 0)
    }

    @Test func deniedRefreshDoesNotRepeatThePermissionRequest() async throws {
        let service = StubRemindersService(
            health: Self.health(.attention, detail: "Reminders access is unavailable"),
            taskLoads: []
        )
        let controller = RemindersConnectionController(service: service, defaults: try isolatedDefaults())

        await controller.refresh()
        await controller.refresh()

        #expect(controller.state == .permissionRequired(detail: "Reminders access is unavailable"))
        #expect(service.inspectCount == 2)
        #expect(service.requestCount == 0)
    }

    @Test func passiveCheckBeforeTheFirstDecisionDoesNotOpenThePermissionPrompt() async throws {
        let service = StubRemindersService(
            health: Self.health(.notConnected, detail: "Permission is ready to be requested"),
            taskLoads: []
        )
        let controller = RemindersConnectionController(service: service, defaults: try isolatedDefaults())

        await controller.refresh()

        #expect(controller.state == .permissionReady(detail: "Permission is ready to be requested"))
        #expect(service.inspectCount == 1)
        #expect(service.requestCount == 0)
    }

    @Test func explicitConnectRequestsOnceAndThenConfirmsTaskRefresh() async throws {
        let service = StubRemindersService(
            health: Self.health(.notConnected, detail: "Permission is ready"),
            requestedHealth: Self.health(.healthy, detail: "Connected"),
            taskLoads: [.available([Self.task(id: "connected")])]
        )
        let controller = RemindersConnectionController(service: service, defaults: try isolatedDefaults())

        await controller.connect()

        #expect(controller.state == .connected(taskCount: 1))
        #expect(service.requestCount == 1)
        #expect(service.inspectCount == 0)
    }

    @Test func failedRefreshPreservesPriorSuccessAndCanRetry() async throws {
        let defaults = try isolatedDefaults()
        let previousSuccess = Date(timeIntervalSince1970: 1_740_000_000)
        defaults.set(previousSuccess, forKey: "reminders.last-successful-sync")
        let service = StubRemindersService(
            health: Self.health(.healthy, detail: "Connected"),
            taskLoads: [.unavailable, .available([Self.task(id: "recovered")])]
        )
        let recoveredAt = Date(timeIntervalSince1970: 1_750_100_000)
        let controller = RemindersConnectionController(
            service: service,
            defaults: defaults,
            now: { recoveredAt }
        )

        await controller.refresh()
        #expect(controller.state == .refreshFailed(
            detail: "Apple Reminders did not return task data. Your last successful sync remains available while you retry."
        ))
        #expect(controller.lastSuccessfulSync == previousSuccess)

        await controller.refresh()
        #expect(controller.state == .connected(taskCount: 1))
        #expect(controller.lastSuccessfulSync == recoveredAt)
        #expect(service.inspectCount == 2)
    }

    @Test func permissionRepairOpensOnlyWhenTheUserChoosesIt() async throws {
        var openCount = 0
        let service = StubRemindersService(
            health: Self.health(.attention, detail: "Denied"),
            taskLoads: []
        )
        let controller = RemindersConnectionController(
            service: service,
            defaults: try isolatedDefaults(),
            openSystemSettings: {
                openCount += 1
                return true
            }
        )

        await controller.refresh()
        #expect(openCount == 0)
        #expect(controller.openPermissionSettings())
        #expect(openCount == 1)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "RemindersConnectionControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static func health(_ state: HealthState, detail: String) -> SourceHealth {
        SourceHealth(
            id: .reminders,
            title: "Apple Reminders",
            eyebrow: "Intent",
            state: state,
            detail: detail,
            evidence: "Test evidence",
            actionTitle: "Refresh"
        )
    }

    private static func task(id: String) -> ReminderTask {
        ReminderTask(
            id: id,
            title: "Task \(id)",
            listID: "list",
            listName: "Work",
            dueDate: nil,
            priority: 0,
            notes: nil,
            modificationDate: nil
        )
    }
}

@MainActor
private final class StubRemindersService: RemindersServicing {
    let isProductionAdapter = false
    var health: SourceHealth
    var requestedHealth: SourceHealth
    var taskLoads: [ReminderTaskLoad]
    private(set) var inspectCount = 0
    private(set) var requestCount = 0

    init(
        health: SourceHealth,
        requestedHealth: SourceHealth? = nil,
        taskLoads: [ReminderTaskLoad]
    ) {
        self.health = health
        self.requestedHealth = requestedHealth ?? health
        self.taskLoads = taskLoads
    }

    func inspect() async -> SourceHealth {
        inspectCount += 1
        return health
    }

    func requestAccessAndInspect() async -> SourceHealth {
        requestCount += 1
        return requestedHealth
    }

    func fetchIncompleteTasks() async -> ReminderTaskLoad {
        taskLoads.isEmpty ? .unavailable : taskLoads.removeFirst()
    }
}
