import Foundation

@MainActor
final class AtollService {
    private let activityID = "zoid-coach.release-0.health"
    private let bundleIdentifier = "com.ziadnasreldin.ZoidCoach"
    private let endpoint = URL(string: "ws://127.0.0.1:9020")!

    func inspect() async -> SourceHealth {
        guard let version = installedVersion else {
            return SourceHealth(
                id: .atoll,
                title: "Atoll",
                eyebrow: "Intervention",
                state: .unavailable,
                detail: "Atoll is not installed",
                evidence: "Install Atoll to enable notch interactions",
                actionTitle: "Retry"
            )
        }

        do {
            let result = try await request(method: "atoll.getVersion")
            let connectedVersion = result["version"] as? String ?? version
            let authorized = (try? await request(method: "atoll.checkAuthorization")["authorized"] as? Bool) ?? false
            return health(version: connectedVersion, authorized: authorized, testPresented: false)
        } catch {
            return SourceHealth(
                id: .atoll,
                title: "Atoll",
                eyebrow: "Intervention",
                state: .attention,
                detail: "Atoll \(version) is installed but not reachable",
                evidence: "Open Atoll, then retry the local extension check",
                actionTitle: "Retry"
            )
        }
    }

    func authorizeAndPresentTest() async -> SourceHealth {
        guard let version = installedVersion else { return await inspect() }

        do {
            let authorization = try await request(method: "atoll.requestAuthorization")
            let authorized = authorization["authorized"] as? Bool ?? false
            guard authorized else {
                return health(version: version, authorized: false, testPresented: false)
            }

            _ = try await request(
                method: "atoll.presentLiveActivity",
                additionalParameters: [
                    "activity": [
                        "id": activityID,
                        "priority": "normal",
                        "title": "Zoid Coach",
                        "subtitle": "Release 0 source check passed",
                        "leadingIcon": ["symbol": ["name": "checkmark.seal"]],
                        "accentColor": ["red": 194.0 / 255.0, "green": 58.0 / 255.0, "blue": 46.0 / 255.0],
                        "allowsMusicCoexistence": true,
                        "estimatedDuration": 12
                    ]
                ]
            )
            return health(version: version, authorized: true, testPresented: true)
        } catch {
            return SourceHealth(
                id: .atoll,
                title: "Atoll",
                eyebrow: "Intervention",
                state: .attention,
                detail: "Atoll test activity was not accepted",
                evidence: "Open Atoll and review its extension authorization prompt",
                actionTitle: "Retry"
            )
        }
    }

    private var installedVersion: String? {
        let applicationURL = URL(fileURLWithPath: "/Applications/Atoll.app")
        guard let bundle = Bundle(url: applicationURL), bundle.bundleIdentifier != nil else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "installed"
    }

    private func request(
        method: String,
        additionalParameters: [String: Any] = [:]
    ) async throws -> [String: Any] {
        var parameters: [String: Any] = ["bundleIdentifier": bundleIdentifier]
        additionalParameters.forEach { parameters[$0.key] = $0.value }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": parameters,
            "id": UUID().uuidString
        ]

        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: endpoint)
        socket.resume()
        defer {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }

        let message = try JSONSerialization.data(withJSONObject: payload)
        try await socket.send(.data(message))
        let response = try await withTimeout(seconds: 2) {
            try await socket.receive()
        }
        let responseData: Data
        switch response {
        case let .data(data): responseData = data
        case let .string(string): responseData = Data(string.utf8)
        @unknown default: throw AtollError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw AtollError.invalidResponse
        }
        if let error = json["error"] as? [String: Any] {
            throw AtollError.remote(error["message"] as? String ?? "Atoll rejected the request")
        }
        guard let result = json["result"] as? [String: Any] else {
            throw AtollError.invalidResponse
        }
        return result
    }

    private func withTimeout<Value: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AtollError.timedOut
            }
            guard let result = try await group.next() else { throw AtollError.timedOut }
            group.cancelAll()
            return result
        }
    }

    private func health(version: String, authorized: Bool, testPresented: Bool) -> SourceHealth {
        if authorized {
            return SourceHealth(
                id: .atoll,
                title: "Atoll",
                eyebrow: "Intervention",
                state: .healthy,
                detail: testPresented ? "Test activity sent to Atoll \(version)" : "Atoll \(version) is authorized",
                evidence: "Local extension channel is ready",
                actionTitle: "Send test"
            )
        }

        return SourceHealth(
            id: .atoll,
            title: "Atoll",
            eyebrow: "Intervention",
            state: .notConnected,
            detail: "Atoll \(version) is installed",
            evidence: "Extension authorization is required",
            actionTitle: "Authorize"
        )
    }
}

private enum AtollError: Error {
    case invalidResponse
    case remote(String)
    case timedOut
}
