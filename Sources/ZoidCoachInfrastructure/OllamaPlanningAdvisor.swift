import Foundation

public struct PlanningAdviceInput: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let dueDate: Date?
    public let reminderPriority: Int
    public let carryoverDays: Int
    public let deferralCount: Int
    public let recentAlignedMinutes: Int

    public init(
        id: String,
        title: String,
        dueDate: Date?,
        reminderPriority: Int,
        carryoverDays: Int,
        deferralCount: Int,
        recentAlignedMinutes: Int
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.reminderPriority = reminderPriority
        self.carryoverDays = carryoverDays
        self.deferralCount = deferralCount
        self.recentAlignedMinutes = recentAlignedMinutes
    }
}

public struct PlanningAdvice: Codable, Equatable, Sendable {
    public let id: String
    public let adjustment: Int
    public let reason: String

    public init(id: String, adjustment: Int, reason: String) {
        self.id = id
        self.adjustment = min(max(adjustment, -200), 200)
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct PlanningBehaviorEvidence: Codable, Equatable, Sendable {
    public let application: String
    public let observationCount: Int

    public init(application: String, observationCount: Int) {
        self.application = application
        self.observationCount = observationCount
    }
}

public protocol PlanningAdvising: Sendable {
    func advise(on tasks: [PlanningAdviceInput], recentBehavior: [PlanningBehaviorEvidence]) async throws -> [PlanningAdvice]
}

public struct OllamaPlanningAdvisor: PlanningAdvising, Sendable {
    private let model: String
    private let endpoint: URL
    private let session: URLSession

    public init(
        model: String = "qwen3.6:27b",
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!,
        session: URLSession = .shared
    ) {
        self.model = model
        self.endpoint = endpoint
        self.session = session
    }

    public func advise(on tasks: [PlanningAdviceInput], recentBehavior: [PlanningBehaviorEvidence]) async throws -> [PlanningAdvice] {
        guard !tasks.isEmpty else { return [] }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(
            model: model,
            stream: false,
            format: "json",
            messages: [
                Message(
                    role: "system",
                    content: "You are a private productivity planner. Return only valid JSON with one key, advice. advice is an array of objects with id, adjustment, and reason. adjustment is an integer from -200 to 200. Use only the supplied task evidence. Do not invent deadlines, commitments, or personal facts. Keep every reason under 120 characters."
                ),
                Message(
                    role: "user",
                    content: try JSONEncoder().encode(PlanningContext(tasks: tasks, recentBehavior: recentBehavior)).utf8String
                )
            ]
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw OllamaPlanningAdvisorError.unavailable
        }
        let envelope = try JSONDecoder().decode(Response.self, from: data)
        let decoded = try JSONDecoder().decode(AdviceDocument.self, from: Data(envelope.message.content.utf8))
        let knownIDs = Set(tasks.map(\.id))
        return decoded.advice
            .filter { knownIDs.contains($0.id) && !$0.reason.isEmpty }
            .map { PlanningAdvice(id: $0.id, adjustment: $0.adjustment, reason: $0.reason) }
    }

    private struct Request: Encodable {
        let model: String
        let stream: Bool
        let format: String
        let messages: [Message]
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct Response: Decodable {
        let message: Message
    }

    private struct AdviceDocument: Decodable {
        let advice: [PlanningAdvice]
    }

    private struct PlanningContext: Encodable {
        let tasks: [PlanningAdviceInput]
        let recentBehavior: [PlanningBehaviorEvidence]
    }
}

public enum OllamaPlanningAdvisorError: LocalizedError {
    case unavailable

    public var errorDescription: String? { "The configured local Ollama model is unavailable or returned invalid planning advice." }
}

private extension Data {
    var utf8String: String { String(decoding: self, as: UTF8.self) }
}
