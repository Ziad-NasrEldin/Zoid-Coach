import AppKit
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class RemindersConnectionController: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case connected(taskCount: Int)
        case permissionReady(detail: String)
        case permissionRequired(detail: String)
        case refreshFailed(detail: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var repairDetail: String?

    private let service: any RemindersServicing
    private let defaults: UserDefaults
    private let now: () -> Date
    private let openSystemSettings: () -> Bool
    private let lastSuccessfulSyncKey = "reminders.last-successful-sync"

    init(
        service: (any RemindersServicing)? = nil,
        runtimeEnvironment: RuntimeEnvironment = .current(),
        defaults: UserDefaults? = nil,
        now: @escaping () -> Date = Date.init,
        openSystemSettings: (() -> Bool)? = nil
    ) {
        self.service = service ?? Self.makeService(runtimeEnvironment: runtimeEnvironment)
        self.defaults = defaults ?? runtimeEnvironment.makeUserDefaults()
        self.now = now
        self.openSystemSettings = openSystemSettings ?? {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
            ) else { return false }
            return NSWorkspace.shared.open(url)
        }
        lastSuccessfulSync = self.defaults.object(forKey: lastSuccessfulSyncKey) as? Date
    }

    private static func makeService(
        runtimeEnvironment: RuntimeEnvironment
    ) -> any RemindersServicing {
        guard runtimeEnvironment.packageMode == .qa else {
            return RemindersService()
        }

        do {
            let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(
                runtimeEnvironment: runtimeEnvironment
            )
            return QAFixtureRemindersService(
                adapter: adapter,
                shouldFailTaskFetch: {
                    qaFetchFailureIsEnabled(runtimeEnvironment: runtimeEnvironment)
                }
            )
        } catch {
            return DisabledQARemindersService(
                detail: "QA fixture startup failed: \(error.localizedDescription)"
            )
        }
    }

    private static func qaFetchFailureIsEnabled(
        runtimeEnvironment: RuntimeEnvironment
    ) -> Bool {
        guard case let .qa(runRoot) = runtimeEnvironment.mode else { return false }
        let marker = runRoot
            .appendingPathComponent("QA Control", isDirectory: true)
            .appendingPathComponent("reminders-fetch-failure", isDirectory: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: marker.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            return false
        }
        return true
    }

    var isBusy: Bool { state == .checking }

    var needsPermissionRepair: Bool {
        if case .permissionRequired = state { return true }
        return false
    }

    func refresh() async {
        guard !isBusy else { return }
        repairDetail = nil
        state = .checking
        await reconcile(health: await service.inspect())
    }

    func connect() async {
        guard !isBusy else { return }
        repairDetail = nil
        state = .checking
        await reconcile(health: await service.requestAccessAndInspect())
    }

    func applicationDidBecomeActive() async {
        guard !isBusy else { return }
        switch state {
        case .permissionReady, .permissionRequired, .refreshFailed, .connected:
            await refresh()
        case .idle, .checking:
            break
        }
    }

    @discardableResult
    func openPermissionSettings() -> Bool {
        let opened = openSystemSettings()
        repairDetail = opened
            ? "System Settings opened. Return to Zoid 666 and access will be checked automatically."
            : "System Settings could not be opened. Open Privacy & Security, choose Reminders, then allow full access for Zoid 666."
        return opened
    }

    private func reconcile(health: SourceHealth) async {
        guard health.state == .healthy else {
            switch health.state {
            case .notConnected:
                state = .permissionReady(detail: health.detail)
            case .attention:
                state = .permissionRequired(detail: health.detail)
            case .checking, .unavailable:
                state = .refreshFailed(detail: health.detail)
            case .healthy:
                break
            }
            return
        }

        switch await service.fetchIncompleteTasks() {
        case let .available(tasks):
            let completedAt = now()
            lastSuccessfulSync = completedAt
            defaults.set(completedAt, forKey: lastSuccessfulSyncKey)
            state = .connected(taskCount: tasks.count)
        case .unavailable:
            let recoveryDetail = lastSuccessfulSync == nil
                ? "Apple Reminders did not return task data. No confirmed task refresh is available yet. Retry when the source is available."
                : "Apple Reminders did not return task data. Your last successful sync remains available while you retry."
            state = .refreshFailed(
                detail: recoveryDetail
            )
        }
    }
}
