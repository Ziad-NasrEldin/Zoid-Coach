import Foundation
import ServiceManagement
import ZoidCoachCore

enum AgentRegistrationStatus: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown
}

@MainActor
protocol AgentServiceRegistration: AnyObject {
    var status: AgentRegistrationStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
private final class SystemAgentServiceRegistration: AgentServiceRegistration {
    private let service: SMAppService

    init(plistName: String) {
        service = SMAppService.agent(plistName: plistName)
    }

    var status: AgentRegistrationStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
}

@MainActor
struct AgentServiceRegistrationFactory {
    let production: (String) -> any AgentServiceRegistration
    let qa: (String) -> any AgentServiceRegistration

    static let live = Self(
        production: { SystemAgentServiceRegistration(plistName: $0) },
        qa: { SystemAgentServiceRegistration(plistName: $0) }
    )
}

@MainActor
final class AgentLaunchService {
    private let plistName: String
    private let registrationFingerprintKey = "ZoidCoachAgentRegistrationFingerprint"
    private let userDefaults: UserDefaults
    private let service: (any AgentServiceRegistration)?
    private let isControlDisabled: Bool
    private let bundleURL: URL
    private let buildVersion: String

    init(
        runtimeEnvironment: RuntimeEnvironment = .current(),
        service: (any AgentServiceRegistration)? = nil,
        registrationFactory: AgentServiceRegistrationFactory = .live,
        bundleURL: URL = Bundle.main.bundleURL,
        buildVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
    ) {
        plistName = runtimeEnvironment.identity.launchAgentPlistName
        userDefaults = runtimeEnvironment.makeUserDefaults()
        self.bundleURL = bundleURL
        self.buildVersion = buildVersion
        if case .qa = runtimeEnvironment.mode, runtimeEnvironment.packageMode != .qa {
            isControlDisabled = true
            self.service = service
        } else {
            isControlDisabled = false
            if let service {
                self.service = service
            } else if runtimeEnvironment.packageMode == .qa {
                self.service = registrationFactory.qa(plistName)
            } else {
                self.service = registrationFactory.production(plistName)
            }
        }
    }

    func inspect() -> SourceHealth {
        guard !isControlDisabled else { return isolatedQAHealth }
        guard isBundled else {
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .unavailable,
                detail: "The background agent is available in the packaged app",
                evidence: "Build the signed Zoid 666.app to enable overnight planning",
                actionTitle: "Package"
            )
        }
        guard let service else { return unavailableProductionServiceHealth }

        switch service.status {
        case .enabled:
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .healthy,
                detail: "Background planning agent is enabled",
                evidence: "It continues while the main app is closed and the Mac is awake",
                actionTitle: "Inspect"
            )
        case .requiresApproval:
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .attention,
                detail: "Background agent needs approval in Login Items",
                evidence: "Enable Zoid 666 in System Settings, then retry",
                actionTitle: "Retry"
            )
        case .notRegistered:
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .notConnected,
                detail: "Background planning is not enabled",
                evidence: "Register the bundled agent to prepare plans overnight",
                actionTitle: "Enable"
            )
        case .notFound:
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .unavailable,
                detail: "The bundled agent could not be found",
                evidence: "Repackage Zoid 666 before enabling autonomy",
                actionTitle: "Package"
            )
        case .unknown:
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .attention,
                detail: "Background-agent status is not recognized",
                evidence: "No overnight job was started",
                actionTitle: "Inspect"
            )
        }
    }

    func enableAndInspect() -> SourceHealth {
        guard !isControlDisabled else { return isolatedQAHealth }
        guard isBundled else { return inspect() }
        guard let service else { return unavailableProductionServiceHealth }
        // A package assembled under .build is a staging artifact. Registering it
        // would let a disposable build take ownership away from the installed app.
        if Self.isDevelopmentBundle(bundleURL) {
            return inspect()
        }
        do {
            let fingerprint = Self.registrationFingerprint(
                build: buildVersion,
                bundleURL: bundleURL
            )
            if service.status == .enabled,
               userDefaults.string(forKey: registrationFingerprintKey) == fingerprint {
                return inspect()
            }
            if service.status == .enabled {
                try service.unregister()
            }
            try service.register()
            userDefaults.set(fingerprint, forKey: registrationFingerprintKey)
        } catch {
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .attention,
                detail: "Background planning could not be enabled",
                evidence: error.localizedDescription,
                actionTitle: "Retry"
            )
        }
        return inspect()
    }

    func disableAndInspect() -> SourceHealth {
        guard !isControlDisabled else { return isolatedQAHealth }
        guard isBundled else { return inspect() }
        guard let service else { return unavailableProductionServiceHealth }
        do {
            if service.status != .notRegistered && service.status != .notFound {
                try service.unregister()
            }
            userDefaults.removeObject(forKey: registrationFingerprintKey)
        } catch {
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .attention,
                detail: "Background planning could not be disabled",
                evidence: error.localizedDescription,
                actionTitle: "Retry"
            )
        }
        return inspect()
    }

    private var isolatedQAHealth: SourceHealth {
        SourceHealth(
            id: .agent,
                title: "Zoid 666 Agent",
            eyebrow: "Autonomy",
            state: .unavailable,
            detail: "QA background agent is disabled",
            evidence: "The dedicated QA LaunchAgent is not registered automatically",
            actionTitle: "Unavailable"
        )
    }

    private var unavailableProductionServiceHealth: SourceHealth {
        SourceHealth(
            id: .agent,
                title: "Zoid 666 Agent",
            eyebrow: "Autonomy",
            state: .unavailable,
            detail: "The background agent service is unavailable",
            evidence: "Repackage Zoid 666 before enabling autonomy",
            actionTitle: "Package"
        )
    }

    private var isBundled: Bool {
        bundleURL.pathExtension == "app"
    }

    nonisolated static func registrationFingerprint(build: String, bundleURL: URL) -> String {
        "\(build)|\(bundleURL.standardizedFileURL.path)"
    }

    nonisolated static func isDevelopmentBundle(_ bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.path.contains("/.build/")
    }
}
