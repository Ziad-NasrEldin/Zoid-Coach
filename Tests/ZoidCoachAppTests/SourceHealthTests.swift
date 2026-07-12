import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test
func initialSourcesRepresentAllRequiredIntegrations() {
    let sourceIDs = Set(SourceHealth.initial.map(\.id))

    #expect(sourceIDs == Set([.reminders, .calendar, .screenwatch, .agent, .notifications]))
}

@Test
func healthStatesAlwaysExposeWrittenLabels() {
    for state in [HealthState.healthy, .checking, .attention, .notConnected, .unavailable] {
        #expect(!state.rawValue.isEmpty)
    }
}

@MainActor
@Test
func sourceCheckCompletesWithStableSourceStates() async {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let model = AppModel(screenwatchReader: ScreenwatchReader(baseDirectory: root))

    model.runSourceCheck()
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(15))
    while model.isCheckingSources, clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(50))
    }

    #expect(model.sources.allSatisfy { $0.state != .checking })
    #expect(model.isCheckingSources == false)
}

@MainActor
@Test
func appModelPropagatesQARuntimeToBackgroundAgentControl() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-app-model-qa-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtimeEnvironment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:]
    ).environment
    var remindersConstructionCount = 0
    var calendarConstructionCount = 0
    var notificationConstructionCount = 0
    let liveServiceFactory = AppOSServiceFactory(
        reminders: {
            remindersConstructionCount += 1
            return RemindersService()
        },
        calendar: {
            calendarConstructionCount += 1
            return CalendarService()
        },
        notifications: {
            notificationConstructionCount += 1
            return NotificationService()
        }
    )
    let productionReminders = RecordingProductionRemindersService()
    let productionCalendar = RecordingProductionCalendarService()
    let productionNotifications = RecordingProductionNotificationService()
    let model = AppModel(
        runtimeEnvironment: runtimeEnvironment,
        screenwatchReader: ScreenwatchReader(baseDirectory: runtimeEnvironment.screenwatchDirectory),
        remindersService: productionReminders,
        calendarService: productionCalendar,
        notificationService: productionNotifications,
        liveServiceFactory: liveServiceFactory
    )
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))

    while model.sources.first(where: { $0.id == .agent })?.detail
        != "QA background agent is disabled",
        clock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(
        model.sources.first(where: { $0.id == .agent })?.detail
            == "QA background agent is disabled"
    )
    #expect(
        model.sources.first(where: { $0.id == .reminders })?.detail
            == "QA fixture startup failed: QA OS fixtures require a signed QA app or agent with the embedded QA run root."
    )
    #expect(
        model.sources.first(where: { $0.id == .calendar })?.detail
            == "QA fixture startup failed: QA OS fixtures require a signed QA app or agent with the embedded QA run root."
    )
    #expect(
        model.sources.first(where: { $0.id == .notifications })?.detail
            == "QA fixture startup failed: QA OS fixtures require a signed QA app or agent with the embedded QA run root."
    )
    #expect(remindersConstructionCount == 0)
    #expect(calendarConstructionCount == 0)
    #expect(notificationConstructionCount == 0)
    #expect(productionReminders.callCount == 0)
    #expect(productionCalendar.callCount == 0)
    #expect(productionNotifications.callCount == 0)
}

@MainActor
private final class RecordingProductionRemindersService: RemindersServicing {
    let isProductionAdapter = true
    private(set) var callCount = 0
    func inspect() async -> SourceHealth {
        callCount += 1
        return .initial[0]
    }
    func requestAccessAndInspect() async -> SourceHealth {
        callCount += 1
        return .initial[0]
    }
    func fetchIncompleteTasks() async -> ReminderTaskLoad {
        callCount += 1
        return .available([])
    }
}

@MainActor
private final class RecordingProductionCalendarService: CalendarServicing {
    let isProductionAdapter = true
    private(set) var callCount = 0
    var selectionAvailability: CalendarSelectionAvailability {
        callCount += 1
        return .available
    }
    func availableCalendars() throws -> [CalendarChoice] {
        callCount += 1
        return []
    }
    func inspect() async -> SourceHealth {
        callCount += 1
        return .initial[1]
    }
    func requestAccessAndInspect() async -> SourceHealth {
        callCount += 1
        return .initial[1]
    }
}

@MainActor
private final class RecordingProductionNotificationService: NotificationServicing {
    let isProductionAdapter = true
    private(set) var callCount = 0
    func inspect() async -> SourceHealth {
        callCount += 1
        return .initial[4]
    }
    func requestAccessAndInspect() async -> SourceHealth {
        callCount += 1
        return .initial[4]
    }
}
