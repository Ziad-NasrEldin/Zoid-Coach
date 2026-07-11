import AtollExtensionKit
import Foundation

public protocol AtollNotchExperiencePresenting: Sendable {
    func presentNotchExperience(_ descriptor: AtollNotchExperienceDescriptor) async throws
}

public struct AtollRPCClient: Sendable, AtollNotchExperiencePresenting {
    private let endpoint: URL
    private let timeout: Duration

    public init(
        endpoint: URL = URL(string: "ws://127.0.0.1:9020")!,
        timeout: Duration = .seconds(3)
    ) {
        self.endpoint = endpoint
        self.timeout = timeout
    }

    public func presentNotchExperience(_ descriptor: AtollNotchExperienceDescriptor) async throws {
        let descriptorData = try JSONEncoder().encode(descriptor)
        guard let descriptorObject = try JSONSerialization.jsonObject(with: descriptorData) as? [String: Any] else {
            throw AtollRPCError.invalidDescriptor
        }
        _ = try await request(
            method: "atoll.presentNotchExperience",
            bundleIdentifier: descriptor.bundleIdentifier,
            parameters: ["descriptor": descriptorObject]
        )
    }

    private func request(
        method: String,
        bundleIdentifier: String,
        parameters: [String: Any]
    ) async throws -> [String: Any] {
        var requestParameters = parameters
        requestParameters["bundleIdentifier"] = bundleIdentifier
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": requestParameters,
            "id": UUID().uuidString,
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: endpoint)
        socket.resume()
        defer {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }
        try await socket.send(.data(payloadData))
        let message = try await withTimeout { try await socket.receive() }
        let responseData: Data
        switch message {
        case let .data(data): responseData = data
        case let .string(string): responseData = Data(string.utf8)
        @unknown default: throw AtollRPCError.invalidResponse
        }
        guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw AtollRPCError.invalidResponse
        }
        if let error = response["error"] as? [String: Any] {
            throw AtollRPCError.remote(error["message"] as? String ?? "A-Toll rejected the request")
        }
        guard let result = response["result"] as? [String: Any] else {
            throw AtollRPCError.invalidResponse
        }
        return result
    }

    private func withTimeout<Value: Sendable>(
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AtollRPCError.timedOut
            }
            guard let result = try await group.next() else { throw AtollRPCError.timedOut }
            group.cancelAll()
            return result
        }
    }
}

public enum AtollRPCError: LocalizedError, Sendable {
    case invalidDescriptor
    case invalidResponse
    case remote(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .invalidDescriptor: "The A-Toll descriptor could not be encoded"
        case .invalidResponse: "A-Toll returned an invalid response"
        case let .remote(message): message
        case .timedOut: "A-Toll did not respond before the local timeout"
        }
    }
}
