import Foundation
import ServiceManagement
import ZoidCoachCore
import ZoidCoachInfrastructure

enum PolicyMutationXPCProbe {
    static let argument = "--qa-policy-mutation-xpc-probe"

    static func run() -> Int32 {
        let runtime = RuntimeEnvironment.current()
        guard case .qa = runtime.mode, runtime.packageMode == .qa else {
            fputs("FAIL: policy mutation XPC probe requires a packaged QA runtime\n", stderr)
            return 2
        }
        let service = SMAppService.agent(plistName: runtime.identity.launchAgentPlistName)
        do {
            if service.status == .notRegistered || service.status == .notFound {
                try service.register()
            }
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
            let first = try await client.savePolicyMutation(request)
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
