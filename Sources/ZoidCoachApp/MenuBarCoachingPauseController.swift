import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

protocol MenuBarCoachingPauseClient: Sendable {
    func loadCurrentPolicy() async throws -> VersionedUserPolicy
    func savePolicyMutation(_ request: PolicyMutationRequest) async throws -> AgentMutationReceipt
}

struct LiveMenuBarCoachingPauseClient: MenuBarCoachingPauseClient {
    let runtimeEnvironment: RuntimeEnvironment

    func loadCurrentPolicy() async throws -> VersionedUserPolicy {
        let store = try PolicyStore(
            databaseURL: runtimeEnvironment.databaseURL,
            readOnly: true
        )
        guard let current = try store.current() else {
            throw MenuBarCoachingPauseError.policyUnavailable
        }
        return current
    }

    func savePolicyMutation(_ request: PolicyMutationRequest) async throws -> AgentMutationReceipt {
        try await TodayDashboardXPCClient(runtimeEnvironment: runtimeEnvironment)
            .savePolicyMutation(request)
    }
}

enum MenuBarCoachingPauseError: LocalizedError {
    case policyUnavailable
    case invalidReceipt

    var errorDescription: String? {
        switch self {
        case .policyUnavailable:
            "Coaching status is unavailable. Open Source Health and check the background agent."
        case .invalidReceipt:
            "The background agent did not confirm the coaching change. The last confirmed state is still shown."
        }
    }
}

@MainActor
final class MenuBarCoachingPauseController: ObservableObject {
    @Published private(set) var pause: AutomationPause = .running
    @Published private(set) var defaultPauseDuration: CoachingPauseDuration = .indefinitely
    @Published private(set) var policyVersion: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let client: any MenuBarCoachingPauseClient
    private let makeRequestID: @Sendable () -> String
    private let now: @Sendable () -> Date

    init(
        client: any MenuBarCoachingPauseClient,
        makeRequestID: @escaping @Sendable () -> String = {
            "system-policy-v1:menu-bar-coaching-pause:\(UUID().uuidString.lowercased())"
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.makeRequestID = makeRequestID
        self.now = now
    }

    convenience init(runtimeEnvironment: RuntimeEnvironment) {
        self.init(
            client: LiveMenuBarCoachingPauseClient(runtimeEnvironment: runtimeEnvironment)
        )
    }

    var isPaused: Bool { pause.isPaused }
    var pauseActionAccessibilityLabel: String {
        "Pause coaching \(pausePhrase(for: defaultPauseDuration))"
    }

    var runningDetail: String {
        "Zoid 666 may offer evidence-based coaching while your workday is active. Quick Pause is set to \(defaultPauseDuration.selectionDescription)."
    }

    func refresh() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let current = try await client.loadCurrentPolicy()
            install(current)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPaused(_ paused: Bool) async {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = nil
        errorMessage = nil
        defer { isSaving = false }

        do {
            let current = try await client.loadCurrentPolicy()
            install(current)
            let duration = current.policy.schedule.effectiveDefaultCoachingPauseDuration
            let timeZone = TimeZone(identifier: current.policy.schedule.timeZoneIdentifier) ?? .current
            let nextPause = paused
                ? duration.automationPause(from: now(), timeZone: timeZone)
                : .running
            let policy = current.policy.replacingAutomationPause(nextPause)
            let origin = PolicyMutationOrigin.system(component: "menu-bar-coaching-pause")
            let request = PolicyMutationRequest(
                requestID: makeRequestID(),
                expectedVersion: current.version,
                policy: policy,
                origin: origin
            )
            let result = try await client.savePolicyMutation(request)
            let digest = try PolicyMutationRequest.canonicalPayloadDigest(for: policy)
            guard result.accepted,
                  let receipt = result.policyMutationReceipt,
                  receipt.requestID == request.requestID,
                  receipt.expectedVersion == request.expectedVersion,
                  receipt.payloadDigest == digest,
                  receipt.origin == origin,
                  receipt.resultingVersion == result.policyVersion
            else {
                throw MenuBarCoachingPauseError.invalidReceipt
            }

            pause = nextPause
            policyVersion = receipt.resultingVersion
            statusMessage = paused
                ? "Coaching paused \(pausePhrase(for: duration)). Task tracking and Today remain available."
                : "Coaching resumed. New interventions may appear when evidence supports them."
        } catch {
            errorMessage = error.localizedDescription
            if let current = try? await client.loadCurrentPolicy() {
                install(current)
            }
        }
    }

    private func install(_ current: VersionedUserPolicy) {
        pause = current.policy.automationPause
        defaultPauseDuration = current.policy.schedule.effectiveDefaultCoachingPauseDuration
        policyVersion = current.version
    }

    private func pausePhrase(for duration: CoachingPauseDuration) -> String {
        switch duration {
        case .oneHour: "for one hour"
        case .untilTomorrow: "until tomorrow"
        case .indefinitely: "indefinitely"
        }
    }
}
