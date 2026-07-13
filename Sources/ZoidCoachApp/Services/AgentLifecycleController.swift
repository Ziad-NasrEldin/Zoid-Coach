import AppKit
import Foundation

@MainActor
protocol AgentLifecycleServicing: AnyObject {
    func inspect() -> SourceHealth
    func enableAndInspect() -> SourceHealth
    func repairAndInspect() -> SourceHealth
    func disableAndInspect() -> SourceHealth
}

extension AgentLaunchService: AgentLifecycleServicing {}

@MainActor
final class AgentLifecycleController: ObservableObject {
    enum Operation: Equatable {
        case idle
        case checking
        case enabling
        case repairing
        case disabling

        var description: String {
            switch self {
            case .idle: "Ready"
            case .checking: "Checking the background agent"
            case .enabling: "Enabling the background agent"
            case .repairing: "Repairing the background agent"
            case .disabling: "Disabling the background agent"
            }
        }
    }

    @Published private(set) var health: SourceHealth
    @Published private(set) var operation: Operation = .idle
    @Published private(set) var lastCheckedAt: Date
    @Published private(set) var loginItemsOpenFailure: String?

    private let service: any AgentLifecycleServicing
    private let now: () -> Date
    private let openURL: (URL) -> Bool

    init(
        service: (any AgentLifecycleServicing)? = nil,
        now: @escaping () -> Date = Date.init,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        let resolvedService = service ?? AgentLaunchService()
        self.service = resolvedService
        self.now = now
        self.openURL = openURL
        health = resolvedService.inspect()
        lastCheckedAt = now()
    }

    var canEnable: Bool {
        operation == .idle && health.state == .notConnected
    }

    var canRepair: Bool {
        operation == .idle && (health.state == .attention || health.state == .healthy)
    }

    var canDisable: Bool {
        operation == .idle && health.state == .healthy
    }

    func refresh() {
        perform(.checking) { $0.inspect() }
    }

    func enable() {
        perform(.enabling) { $0.enableAndInspect() }
    }

    func repair() {
        perform(.repairing) { $0.repairAndInspect() }
    }

    func disable() {
        perform(.disabling) { $0.disableAndInspect() }
    }

    func openLoginItems() {
        loginItemsOpenFailure = nil
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            loginItemsOpenFailure = "Login Items could not be opened. Open System Settings, then General, then Login Items."
            return
        }
        if !openURL(url) {
            loginItemsOpenFailure = "Login Items could not be opened. Open System Settings, then General, then Login Items."
        }
    }

    func clearLoginItemsOpenFailure() {
        loginItemsOpenFailure = nil
    }

    private func perform(
        _ nextOperation: Operation,
        action: (any AgentLifecycleServicing) -> SourceHealth
    ) {
        guard operation == .idle else { return }
        operation = nextOperation
        health = action(service)
        lastCheckedAt = now()
        operation = .idle
    }
}
