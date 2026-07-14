import Foundation
import ServiceManagement
import SQLite3
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
    private nonisolated static let registrationFingerprintKey = "ZoidCoachAgentRegistrationFingerprint"
    private nonisolated static let launchAtLoginChoiceKey = "ZoidCoachAgentLaunchAtLoginChoice"
    private let userDefaults: UserDefaults
    private let service: (any AgentServiceRegistration)?
    private let isControlDisabled: Bool
    private let bundleURL: URL
    private let buildVersion: String
    private let now: () -> Date
    private let heartbeat: () -> Date?
    private let heartbeatFreshness: TimeInterval

    init(
        runtimeEnvironment: RuntimeEnvironment = .current(),
        service: (any AgentServiceRegistration)? = nil,
        registrationFactory: AgentServiceRegistrationFactory = .live,
        userDefaults: UserDefaults? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        buildVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown",
        now: @escaping () -> Date = Date.init,
        heartbeat: (() -> Date?)? = nil,
        heartbeatFreshness: TimeInterval = 120
    ) {
        plistName = runtimeEnvironment.identity.launchAgentPlistName
        self.userDefaults = userDefaults ?? runtimeEnvironment.makeUserDefaults()
        self.bundleURL = bundleURL
        self.buildVersion = buildVersion
        self.now = now
        self.heartbeat = heartbeat ?? {
            Self.readAgentHeartbeat(databaseURL: runtimeEnvironment.databaseURL)
        }
        self.heartbeatFreshness = max(5, heartbeatFreshness)
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
            return enabledHealth()
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

    func launchAtLoginStatus() -> AgentRegistrationStatus {
        guard !isControlDisabled, isBundled, let service else { return .notFound }
        return service.status
    }

    func enableAndInspect() -> SourceHealth {
        enableAndInspect(forceRepair: false)
    }

    func reconcileAtLaunchAndInspect() -> SourceHealth {
        if userDefaults.object(forKey: Self.launchAtLoginChoiceKey) as? Bool == false {
            return inspect()
        }
        return enableAndInspect()
    }

    func repairAndInspect() -> SourceHealth {
        enableAndInspect(forceRepair: true)
    }

    private func enableAndInspect(forceRepair: Bool) -> SourceHealth {
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
            if !forceRepair,
               service.status == .enabled,
               userDefaults.string(forKey: Self.registrationFingerprintKey) == fingerprint {
                userDefaults.set(true, forKey: Self.launchAtLoginChoiceKey)
                return inspect()
            }
            if service.status == .enabled {
                try service.unregister()
            }
            try service.register()
            Self.recordSuccessfulExternalRegistration(
                userDefaults: userDefaults,
                bundleURL: bundleURL,
                buildVersion: buildVersion
            )
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
            userDefaults.removeObject(forKey: Self.registrationFingerprintKey)
            userDefaults.set(false, forKey: Self.launchAtLoginChoiceKey)
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

    private func enabledHealth() -> SourceHealth {
        guard let heartbeatAt = heartbeat() else {
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .attention,
                detail: "Background agent is enabled but has not checked in yet",
                evidence: "The registration exists, but no runtime heartbeat is available. Check again shortly or repair the registration.",
                actionTitle: "Repair"
            )
        }
        let age = max(0, now().timeIntervalSince(heartbeatAt))
        guard age <= heartbeatFreshness else {
            let minutes = max(1, Int(age / 60))
            return SourceHealth(
                id: .agent,
                title: "Zoid 666 Agent",
                eyebrow: "Autonomy",
                state: .attention,
                detail: "Background agent is enabled but is not currently checking in",
                evidence: "The last local heartbeat was \(minutes) minute\(minutes == 1 ? "" : "s") ago. Repair restarts the installed registration without deleting local data.",
                actionTitle: "Repair"
            )
        }
        return SourceHealth(
            id: .agent,
            title: "Zoid 666 Agent",
            eyebrow: "Autonomy",
            state: .healthy,
            detail: "Background agent is running",
            evidence: "A current local runtime heartbeat confirms the helper, not only its Login Items registration.",
            actionTitle: "Inspect"
        )
    }

    nonisolated static func readAgentHeartbeat(databaseURL: URL) -> Date? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else { return nil }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT last_success_at_utc FROM processing_checkpoints WHERE source_id = 'agent-runtime' LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let pointer = sqlite3_column_text(statement, 0) else { return nil }
        return ISO8601DateFormatter().date(from: String(cString: pointer))
    }

    nonisolated static func registrationFingerprint(build: String, bundleURL: URL) -> String {
        "\(build)|\(bundleURL.standardizedFileURL.path)"
    }

    nonisolated static func recordSuccessfulExternalRegistration(
        userDefaults: UserDefaults,
        bundleURL: URL,
        buildVersion: String
    ) {
        userDefaults.set(
            registrationFingerprint(build: buildVersion, bundleURL: bundleURL),
            forKey: registrationFingerprintKey
        )
        userDefaults.set(true, forKey: launchAtLoginChoiceKey)
    }

    nonisolated static func isDevelopmentBundle(_ bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.path.contains("/.build/")
    }
}
