import Foundation
import ZoidCoachCore

public enum QAFixtureOSCompositionError: LocalizedError, Equatable, Sendable {
    case signedQAPackageRequired
    case malformedControl
    case invalidRequestIdentifier
    case invalidNotificationAction(String)

    public var errorDescription: String? {
        switch self {
        case .signedQAPackageRequired:
            "QA OS fixtures require a signed QA app or agent with the embedded QA run root."
        case .malformedControl:
            "The QA OS fixture control request is missing fields required by its operation."
        case .invalidRequestIdentifier:
            "The QA OS fixture control request requires a non-empty requestID for exactly-once recovery."
        case let .invalidNotificationAction(identifier):
            "The QA notification action '\(identifier)' is not valid for the active QA notification namespace."
        }
    }
}

public struct QAFixtureOSControlRequest: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case seed
        case reset
        case snapshot
        case notificationAction
    }

    public let requestID: String
    public let operation: Operation
    public let seed: QAFixtureOSSeed?
    public let notificationID: String?
    public let actionIdentifier: String?

    private enum CodingKeys: String, CodingKey {
        case requestID, operation, seed, notificationID, actionIdentifier
    }

    public init(
        requestID: String,
        operation: Operation,
        seed: QAFixtureOSSeed? = nil,
        notificationID: String? = nil,
        actionIdentifier: String? = nil
    ) {
        self.requestID = requestID
        self.operation = operation
        self.seed = seed
        self.notificationID = notificationID
        self.actionIdentifier = actionIdentifier
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try values.decodeIfPresent(String.self, forKey: .requestID) ?? ""
        operation = try values.decode(Operation.self, forKey: .operation)
        seed = try values.decodeIfPresent(QAFixtureOSSeed.self, forKey: .seed)
        notificationID = try values.decodeIfPresent(String.self, forKey: .notificationID)
        actionIdentifier = try values.decodeIfPresent(String.self, forKey: .actionIdentifier)
    }
}

public enum QAFixtureOSControlCheckpoint: Equatable, Sendable {
    case mutationCommitted
    case snapshotPersisted
}

public struct AuthorizedQAFixtureOSComposition: Sendable {
    public let adapter: DeterministicOSFixtureAdapters
    public let authorization: AgentOSFixtureAuthorization
}

public enum QAFixtureOSComposition {
    public static let controlRelativePath = "QA Control/os-fixture-request.json"
    public static let snapshotRelativePath = "QA Control/os-fixture-snapshot.json"

    public static func makeAuthorizedAdapter(
        runtimeEnvironment: RuntimeEnvironment,
        clock: ZoidClock = .system
    ) throws -> DeterministicOSFixtureAdapters {
        try makeAuthorizedComposition(
            runtimeEnvironment: runtimeEnvironment,
            clock: clock
        ).adapter
    }

    public static func makeAuthorizedComposition(
        runtimeEnvironment: RuntimeEnvironment,
        clock: ZoidClock = .system,
        controlCheckpoint: @escaping @Sendable (QAFixtureOSControlCheckpoint) throws -> Void = { _ in }
    ) throws -> AuthorizedQAFixtureOSComposition {
        guard case .qa = runtimeEnvironment.mode,
              runtimeEnvironment.packageMode == .qa,
              runtimeEnvironment.identity == .qa else {
            throw QAFixtureOSCompositionError.signedQAPackageRequired
        }
        let workspace = try QAFixtureWorkspace(runtimeEnvironment: runtimeEnvironment)
        let adapter = try DeterministicOSFixtureAdapters(
            workspace: workspace,
            clock: clock,
            stableID: { kind, index in "qa-\(kind.rawValue)-\(index)" }
        )
        try processPendingControl(
            runtimeEnvironment: runtimeEnvironment,
            adapter: adapter,
            checkpoint: controlCheckpoint
        )
        let authorization = AgentOSFixtureAuthorization { [weak adapter] environment in
            guard adapter != nil,
                  case let .qa(candidateRoot) = environment.mode,
                  case let .qa(expectedRoot) = runtimeEnvironment.mode else { return false }
            return environment.packageMode == .qa
                && environment.identity == .qa
                && candidateRoot.standardizedFileURL == expectedRoot.standardizedFileURL
        }
        return AuthorizedQAFixtureOSComposition(
            adapter: adapter,
            authorization: authorization
        )
    }

    package static func apply(
        _ request: QAFixtureOSControlRequest,
        runtimeEnvironment: RuntimeEnvironment,
        to adapter: DeterministicOSFixtureAdapters
    ) throws -> QAFixtureOSSnapshot {
        guard !request.requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QAFixtureOSCompositionError.invalidRequestIdentifier
        }
        switch request.operation {
        case .seed:
            guard request.seed != nil else {
                throw QAFixtureOSCompositionError.malformedControl
            }
        case .reset:
            break
        case .snapshot:
            break
        case .notificationAction:
            guard let notificationID = request.notificationID,
                  let actionIdentifier = request.actionIdentifier,
                  !notificationID.isEmpty,
                  !actionIdentifier.isEmpty else {
                throw QAFixtureOSCompositionError.malformedControl
            }
            guard PromptNotificationCoordinator.fixtureActionKind(
                identifier: actionIdentifier,
                notificationIdentity: runtimeEnvironment.identity.notification
            ) != nil else {
                throw QAFixtureOSCompositionError.invalidNotificationAction(actionIdentifier)
            }
        }
        return try adapter.applyControl(
            request,
            notificationIdentity: runtimeEnvironment.identity.notification
        )
    }

    private static func processPendingControl(
        runtimeEnvironment: RuntimeEnvironment,
        adapter: DeterministicOSFixtureAdapters,
        checkpoint: @Sendable (QAFixtureOSControlCheckpoint) throws -> Void
    ) throws {
        guard case let .qa(runRoot) = runtimeEnvironment.mode else {
            throw QAFixtureOSCompositionError.signedQAPackageRequired
        }
        let control = try DescriptorRelativeStateDirectory(
            workspaceRoot: runRoot,
            directoryName: "QA Control"
        )
        try control.withLock(exclusive: true) {
            let requestName = "os-fixture-request.json"
            let processingName = "os-fixture-request.processing.json"
            if !(try control.exists(processingName)) {
                guard try control.exists(requestName) else { return }
                try control.rename(requestName, to: processingName)
            }
            let request = try JSONDecoder().decode(
                QAFixtureOSControlRequest.self,
                from: control.read(processingName)
            )
            let snapshot = try apply(
                request,
                runtimeEnvironment: runtimeEnvironment,
                to: adapter
            )
            try checkpoint(.mutationCommitted)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try control.writeAtomic(
                try encoder.encode(snapshot),
                name: "os-fixture-snapshot.json"
            )
            try checkpoint(.snapshotPersisted)
            try control.removeIfPresent(processingName)
        }
    }
}
