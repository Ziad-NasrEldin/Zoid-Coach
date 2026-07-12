import Foundation
import ServiceManagement
import ZoidCoachCore
import ZoidCoachInfrastructure

enum PolicyMutationXPCProbe {
    static let argument = "--qa-policy-mutation-xpc-probe"
    static let registerAgentArgument = "--qa-register-agent"
    static let unregisterAgentArgument = "--qa-unregister-agent"

    static func registerAgent() -> Int32 {
        let runtime = RuntimeEnvironment.current()
        guard case .qa = runtime.mode, runtime.packageMode == .qa else {
            fputs("FAIL: QA agent registration requires a packaged QA runtime\n", stderr)
            return 2
        }

        let service = SMAppServiceAgentRegistration(plistName: runtime.identity.launchAgentPlistName)
        do {
            try QAAgentRegistrationLifecycle.install(service: service)
            guard service.status != .requiresApproval else {
                fputs("FAIL: QA LaunchAgent registration requires user approval\n", stderr)
                return 3
            }
            guard service.status == .enabled else {
                fputs("FAIL: QA LaunchAgent did not become enabled\n", stderr)
                return 4
            }
            print("PASS: QA LaunchAgent registered and left enabled")
            return 0
        } catch {
            fputs("FAIL: QA LaunchAgent registration failed: \(error.localizedDescription)\n", stderr)
            return 5
        }
    }

    static func unregisterAgent() -> Int32 {
        let runtime = RuntimeEnvironment.current()
        guard case .qa = runtime.mode, runtime.packageMode == .qa else {
            fputs("FAIL: QA agent unregistration requires a packaged QA runtime\n", stderr)
            return 2
        }

        let service = SMAppServiceAgentRegistration(plistName: runtime.identity.launchAgentPlistName)
        do {
            try QAAgentRegistrationLifecycle.uninstall(service: service)
            print("PASS: QA LaunchAgent unregistered")
            return 0
        } catch {
            fputs("FAIL: QA LaunchAgent unregistration failed: \(error.localizedDescription)\n", stderr)
            return 5
        }
    }

    static func run() -> Int32 {
        let runtime = RuntimeEnvironment.current()
        guard case .qa = runtime.mode, runtime.packageMode == .qa else {
            fputs("FAIL: policy mutation XPC probe requires a packaged QA runtime\n", stderr)
            return 2
        }
        let service = SMAppService.agent(plistName: runtime.identity.launchAgentPlistName)
        do {
            if service.status != .notRegistered && service.status != .notFound {
                try service.unregister()
            }
            try service.register()
            guard service.status != .requiresApproval else {
                fputs("FAIL: QA LaunchAgent registration requires user approval\n", stderr)
                return 3
            }
        } catch {
            fputs("FAIL: QA LaunchAgent registration failed: \(error.localizedDescription)\n", stderr)
            return 4
        }

        let completion = ProbeCompletion()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            try? await Task.sleep(for: .seconds(1))
            completion.set(await execute(runtime: runtime))
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 30) == .success else {
            fputs("FAIL: policy mutation XPC probe timed out\n", stderr)
            return 124
        }
        try? service.unregister()
        return completion.value
    }

    private static func execute(runtime: RuntimeEnvironment) async -> Int32 {
        let client = TodayDashboardXPCClient(runtimeEnvironment: runtime)
        let policy = UserPolicy.defaults().replacingGamingPolicy(.flexible)
        let request = PolicyMutationRequest(
            requestID: "settings-policy-v1:qa-xpc-probe",
            expectedVersion: 1,
            policy: policy,
            origin: .settings
        )
        do {
            let first = try await saveAfterAgentStartup(client: client, request: request)
            guard first.accepted,
                  first.policyVersion == 2,
                  first.policyMutationReceipt?.requestID == request.requestID,
                  first.policyMutationReceipt?.resultingVersion == 2,
                  first.policyMutationReceipt?.replayed == false else {
                fputs("FAIL: first XPC mutation did not return the durable version-2 receipt\n", stderr)
                return 5
            }

            let replay = try await client.savePolicyMutation(request)
            guard replay.policyVersion == 2,
                  replay.policyMutationReceipt?.requestID == request.requestID,
                  replay.policyMutationReceipt?.resultingVersion == 2,
                  replay.policyMutationReceipt?.replayed == true else {
                fputs("FAIL: same-request XPC replay was not idempotent\n", stderr)
                return 6
            }

            let stale = PolicyMutationRequest(
                requestID: "settings-policy-v1:qa-xpc-probe-stale",
                expectedVersion: 1,
                policy: UserPolicy.defaults().replacingGamingPolicy(.firm),
                origin: .settings
            )
            do {
                _ = try await client.savePolicyMutation(stale)
                fputs("FAIL: stale XPC mutation unexpectedly succeeded\n", stderr)
                return 7
            } catch {
                let stored = try PolicyStore(databaseURL: runtime.databaseURL, readOnly: true).current()
                guard stored?.version == 2, stored?.policy.gaming == .flexible else {
                    fputs("FAIL: stale XPC rejection did not preserve the winning policy\n", stderr)
                    return 8
                }
            }
            print("PASS: QA XPC policy mutation receipt, replay, and stale rejection")
            return 0
        } catch {
            fputs("FAIL: policy mutation XPC probe failed: \(error.localizedDescription)\n", stderr)
            return 9
        }
    }

    private static func saveAfterAgentStartup(
        client: TodayDashboardXPCClient,
        request: PolicyMutationRequest
    ) async throws -> AgentMutationReceipt {
        var lastFailure = "The QA agent did not become reachable."
        for _ in 0 ..< 10 {
            do {
                return try await client.savePolicyMutation(request)
            } catch {
                lastFailure = error.localizedDescription
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw PolicyMutationXPCProbeError.agentUnavailable(lastFailure)
    }
}

protocol QAAgentServiceRegistration: AnyObject {
    var status: AgentRegistrationStatus { get }
    func register() throws
    func unregister() throws
}

private final class SMAppServiceAgentRegistration: QAAgentServiceRegistration {
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

enum QAAgentRegistrationLifecycle {
    private static let maximumAttempts = 3
    private static let statusPollCount = 30
    private static let statusPollInterval: TimeInterval = 0.1

    static func install(service: any QAAgentServiceRegistration) throws {
        var lastError: Error?
        for _ in 0..<maximumAttempts {
            do {
                try uninstall(service: service)
                try service.register()
                if service.status == .enabled || service.status == .requiresApproval {
                    return
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? QAAgentRegistrationLifecycleError.didNotEnable
    }

    static func uninstall(service: any QAAgentServiceRegistration) throws {
        guard service.status != .notRegistered, service.status != .notFound else {
            return
        }
        try service.unregister()
        for _ in 0..<statusPollCount {
            if service.status == .notRegistered || service.status == .notFound {
                return
            }
            Thread.sleep(forTimeInterval: statusPollInterval)
        }
        throw QAAgentRegistrationLifecycleError.didNotUnregister
    }
}

private enum QAAgentRegistrationLifecycleError: LocalizedError {
    case didNotEnable
    case didNotUnregister

    var errorDescription: String? {
        switch self {
        case .didNotEnable:
            "The QA background agent did not become enabled after registration."
        case .didNotUnregister:
            "The previous QA background agent registration did not clear."
        }
    }
}

private enum PolicyMutationXPCProbeError: LocalizedError {
    case agentUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .agentUnavailable(message):
            "The QA agent remained unavailable: \(message)"
        }
    }
}

private final class ProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Int32 = 1

    var value: Int32 {
        lock.withLock { storedValue }
    }

    func set(_ value: Int32) {
        lock.withLock { storedValue = value }
    }
}
