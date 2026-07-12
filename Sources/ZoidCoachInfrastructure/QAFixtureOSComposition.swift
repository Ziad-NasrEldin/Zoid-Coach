import Foundation
import ZoidCoachCore

public enum QAFixtureOSCompositionError: Error, Equatable, Sendable {
    case signedQAPackageRequired
    case malformedControl
}

public struct QAFixtureOSControlRequest: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case seed
        case reset
        case snapshot
        case notificationAction
    }

    public let operation: Operation
    public let seed: QAFixtureOSSeed?
    public let notificationID: String?
    public let actionIdentifier: String?

    public init(
        operation: Operation,
        seed: QAFixtureOSSeed? = nil,
        notificationID: String? = nil,
        actionIdentifier: String? = nil
    ) {
        self.operation = operation
        self.seed = seed
        self.notificationID = notificationID
        self.actionIdentifier = actionIdentifier
    }
}

public enum QAFixtureOSComposition {
    public static let controlRelativePath = "QA Control/os-fixture-request.json"
    public static let snapshotRelativePath = "QA Control/os-fixture-snapshot.json"

    public static func makeAuthorizedAdapter(
        runtimeEnvironment: RuntimeEnvironment,
        clock: ZoidClock = .system
    ) throws -> DeterministicOSFixtureAdapters {
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
            adapter: adapter
        )
        return adapter
    }

    @discardableResult
    public static func apply(
        _ request: QAFixtureOSControlRequest,
        to adapter: DeterministicOSFixtureAdapters
    ) throws -> QAFixtureOSSnapshot {
        switch request.operation {
        case .seed:
            guard let seed = request.seed else {
                throw QAFixtureOSCompositionError.malformedControl
            }
            try adapter.reset(to: seed)
        case .reset:
            try adapter.reset(to: request.seed ?? .init())
        case .snapshot:
            break
        case .notificationAction:
            guard let notificationID = request.notificationID,
                  let actionIdentifier = request.actionIdentifier,
                  !notificationID.isEmpty,
                  !actionIdentifier.isEmpty else {
                throw QAFixtureOSCompositionError.malformedControl
            }
            _ = try adapter.deliverDueNotifications()
            _ = try adapter.respondToNotification(
                identifier: notificationID,
                actionIdentifier: actionIdentifier
            )
        }
        return try adapter.snapshot()
    }

    private static func processPendingControl(
        runtimeEnvironment: RuntimeEnvironment,
        adapter: DeterministicOSFixtureAdapters
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
            let snapshot = try apply(request, to: adapter)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try control.writeAtomic(
                try encoder.encode(snapshot),
                name: "os-fixture-snapshot.json"
            )
            try control.removeIfPresent(processingName)
        }
    }
}
