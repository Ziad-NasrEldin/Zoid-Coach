import AppKit
import Foundation

@MainActor
protocol AgentLifecycleServicing: AnyObject {
    func inspect() -> SourceHealth
    func launchAtLoginStatus() -> AgentRegistrationStatus
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
    @Published private(set) var launchAtLoginStatus: AgentRegistrationStatus
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
        launchAtLoginStatus = resolvedService.launchAtLoginStatus()
        lastCheckedAt = now()
    }

    var canEnable: Bool {
        operation == .idle && launchAtLoginStatus == .notRegistered
    }

    var canRepair: Bool {
        operation == .idle && (health.state == .attention || health.state == .healthy)
    }

    var canDisable: Bool {
        operation == .idle
            && (launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval)
    }

    var launchAtLoginDescription: String {
        switch launchAtLoginStatus {
        case .enabled: "Enabled"
        case .requiresApproval: "Waiting for approval"
        case .notRegistered: "Disabled"
        case .notFound: "Unavailable"
        case .unknown: "Unknown"
        }
    }

    var recoveryGuidance: String? {
        switch launchAtLoginStatus {
        case .requiresApproval:
            "macOS is waiting for approval. Open Login Items, allow Zoid 666, then return here and choose CHECK AGAIN."
        case .enabled where health.state == .attention || health.state == .notConnected:
            "Launch at Login is enabled, but the helper is not checking in. Choose REPAIR REGISTRATION, then CHECK AGAIN."
        default:
            nil
        }
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
        launchAtLoginStatus = service.launchAtLoginStatus()
        lastCheckedAt = now()
        operation = .idle
    }
}
