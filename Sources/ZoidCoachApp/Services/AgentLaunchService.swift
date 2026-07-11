import Foundation
import ServiceManagement

@MainActor
final class AgentLaunchService {
    private let plistName = "com.ziadnasreldin.ZoidCoach.agent.plist"
    private let registrationFingerprintKey = "ZoidCoachAgentRegistrationFingerprint"

    func inspect() -> SourceHealth {
        guard isBundled else {
            return SourceHealth(
                id: .agent,
                title: "Zoid Coach Agent",
                eyebrow: "Autonomy",
                state: .unavailable,
                detail: "The background agent is available in the packaged app",
                evidence: "Build the signed Zoid Coach.app to enable overnight planning",
                actionTitle: "Package"
            )
        }

        switch service.status {
        case .enabled:
            return SourceHealth(
                id: .agent,
                title: "Zoid Coach Agent",
                eyebrow: "Autonomy",
                state: .healthy,
                detail: "Background planning agent is enabled",
                evidence: "It continues while the main app is closed and the Mac is awake",
                actionTitle: "Inspect"
            )
        case .requiresApproval:
            return SourceHealth(
                id: .agent,
                title: "Zoid Coach Agent",
                eyebrow: "Autonomy",
                state: .attention,
                detail: "Background agent needs approval in Login Items",
                evidence: "Enable Zoid Coach in System Settings, then retry",
                actionTitle: "Retry"
            )
        case .notRegistered:
            return SourceHealth(
                id: .agent,
                title: "Zoid Coach Agent",
                eyebrow: "Autonomy",
                state: .notConnected,
                detail: "Background planning is not enabled",
                evidence: "Register the bundled agent to prepare plans overnight",
                actionTitle: "Enable"
            )
        case .notFound:
            return SourceHealth(
                id: .agent,
                title: "Zoid Coach Agent",
                eyebrow: "Autonomy",
                state: .unavailable,
                detail: "The bundled agent could not be found",
                evidence: "Repackage Zoid Coach before enabling autonomy",
                actionTitle: "Package"
            )
        @unknown default:
            return SourceHealth(
                id: .agent,
                title: "Zoid Coach Agent",
                eyebrow: "Autonomy",
                state: .attention,
                detail: "Background-agent status is not recognized",
                evidence: "No overnight job was started",
                actionTitle: "Inspect"
            )
        }
    }

    func enableAndInspect() -> SourceHealth {
        guard isBundled else { return inspect() }
        // A package assembled under .build is a staging artifact. Registering it
        // would let a disposable build take ownership away from the installed app.
        if Self.isDevelopmentBundle(Bundle.main.bundleURL) {
            return inspect()
        }
        do {
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let fingerprint = Self.registrationFingerprint(build: build, bundleURL: Bundle.main.bundleURL)
            if service.status == .enabled,
               UserDefaults.standard.string(forKey: registrationFingerprintKey) == fingerprint {
                return inspect()
            }
            if service.status == .enabled {
                try service.unregister()
            }
            try service.register()
            UserDefaults.standard.set(fingerprint, forKey: registrationFingerprintKey)
        } catch {
            return SourceHealth(
                id: .agent,
                title: "Zoid Coach Agent",
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
        guard isBundled else { return inspect() }
        do {
            if service.status != .notRegistered && service.status != .notFound {
                try service.unregister()
            }
            UserDefaults.standard.removeObject(forKey: registrationFingerprintKey)
        } catch {
            return SourceHealth(
                id: .agent,
                title: "Zoid Coach Agent",
                eyebrow: "Autonomy",
                state: .attention,
                detail: "Background planning could not be disabled",
                evidence: error.localizedDescription,
                actionTitle: "Retry"
            )
        }
        return inspect()
    }

    private var service: SMAppService {
        SMAppService.agent(plistName: plistName)
    }

    private var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    nonisolated static func registrationFingerprint(build: String, bundleURL: URL) -> String {
        "\(build)|\(bundleURL.standardizedFileURL.path)"
    }

    nonisolated static func isDevelopmentBundle(_ bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.path.contains("/.build/")
    }
}
