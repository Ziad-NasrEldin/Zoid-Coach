import Foundation
import ZoidCoachCore

public struct GeminiLiveConfiguration: Equatable, Sendable {
    public let model: String
    public let systemInstruction: String
    public let voiceName: String
    public let tools: [VoiceToolDefinition]
    public let sessionResumptionHandle: String?

    public init(
        model: String = "gemini-2.5-flash-native-audio-latest",
        systemInstruction: String,
        voiceName: String = "Kore",
        tools: [VoiceToolDefinition],
        sessionResumptionHandle: String? = nil
    ) {
        self.model = model
        self.systemInstruction = systemInstruction
        self.voiceName = voiceName
        self.tools = tools
        self.sessionResumptionHandle = sessionResumptionHandle
    }
}

public struct GeminiLiveToolCall: Equatable, Sendable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct GeminiLiveToolResponse: Equatable, Sendable {
    public let id: String
    public let name: String
    public let resultJSON: String

    public init(id: String, name: String, resultJSON: String) {
        self.id = id
        self.name = name
        self.resultJSON = resultJSON
    }
}

public enum GeminiLiveEvent: Equatable, Sendable {
    case setupComplete
    case audio(Data)
    case inputTranscript(String)
    case outputTranscript(String)
    case toolCall(GeminiLiveToolCall)
    case toolCallCancelled(String)
    case interrupted
    case generationComplete
    case turnComplete
    case usage(promptTokens: Int, responseTokens: Int)
    case sessionResumption(handle: String)
    case goAway(timeLeft: String)
}

public protocol GeminiLiveTransport: Sendable {
    func connect(configuration: GeminiLiveConfiguration, apiKey: String) async throws
    func sendAudio(_ pcm16: Data) async throws
    func sendImage(_ data: Data, mimeType: String) async throws
    func sendText(_ text: String) async throws
    func sendToolResponses(_ responses: [GeminiLiveToolResponse]) async throws
    func receiveEvents() async throws -> [GeminiLiveEvent]
    func disconnect() async
}

public enum GeminiLiveMessageCodec {
    public static func setupMessage(configuration: GeminiLiveConfiguration) throws -> Data {
        var setup: [String: Any] = [
            "model": configuration.model.hasPrefix("models/")
                ? configuration.model
                : "models/\(configuration.model)",
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": ["voiceName": configuration.voiceName]
                    ]
                ]
            ],
            "systemInstruction": [
                "parts": [["text": configuration.systemInstruction]]
            ],
            "contextWindowCompression": [
                "slidingWindow": [:]
            ],
            "sessionResumption": configuration.sessionResumptionHandle.map { ["handle": $0] } ?? [:],
            "inputAudioTranscription": [:],
            "outputAudioTranscription": [:]
        ]
        if !configuration.tools.isEmpty {
            setup["tools"] = [[
                "functionDeclarations": configuration.tools.map { definition -> [String: Any] in
                    var declaration: [String: Any] = [
                        "name": definition.name,
                        "description": definition.description
                    ]
                    if let schema = definition.parametersJSONSchema,
                       let object = try? JSONSerialization.jsonObject(with: Data(schema.utf8)) {
                        declaration["parameters"] = object
                    }
                    return declaration
                }
            ]]
        }
        return try serialize(["setup": setup])
    }

    public static func audioMessage(pcm16: Data) throws -> Data {
        try serialize([
            "realtimeInput": [
                "mediaChunks": [[
                    "mimeType": "audio/pcm;rate=16000",
                    "data": pcm16.base64EncodedString()
                ]]
            ]
        ])
    }

    public static func textMessage(_ text: String) throws -> Data {
        try serialize([
            "clientContent": [
                "turns": [[
                    "role": "user",
                    "parts": [["text": text]]
                ]],
                "turnComplete": true
            ]
        ])
    }

    public static func imageMessage(_ data: Data, mimeType: String) throws -> Data {
        guard mimeType == "image/jpeg" || mimeType == "image/webp" || mimeType == "image/png" else {
            throw GeminiLiveTransportError.invalidClientMessage
        }
        return try serialize([
            "realtimeInput": [
                "mediaChunks": [[
                    "mimeType": mimeType,
                    "data": data.base64EncodedString()
                ]]
            ]
        ])
    }

    public static func toolResponseMessage(_ responses: [GeminiLiveToolResponse]) throws -> Data {
        let values = responses.map { response -> [String: Any] in
            let data = Data(response.resultJSON.utf8)
            let result = (try? JSONSerialization.jsonObject(with: data)) ?? ["result": response.resultJSON]
            return [
                "id": response.id,
                "name": response.name,
                "response": result
            ]
        }
        return try serialize(["toolResponse": ["functionResponses": values]])
    }

    public static func events(from data: Data) throws -> [GeminiLiveEvent] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiLiveTransportError.invalidServerMessage
        }
        var events: [GeminiLiveEvent] = []
        if root["setupComplete"] != nil { events.append(.setupComplete) }
        if let content = root["serverContent"] as? [String: Any] {
            if let turn = content["modelTurn"] as? [String: Any],
               let parts = turn["parts"] as? [[String: Any]] {
                for part in parts {
                    guard let inlineData = part["inlineData"] as? [String: Any],
                          let encoded = inlineData["data"] as? String,
                          let audio = Data(base64Encoded: encoded) else { continue }
                    events.append(.audio(audio))
                }
            }
            if let transcript = (content["inputTranscription"] as? [String: Any])?["text"] as? String,
               !transcript.isEmpty {
                events.append(.inputTranscript(transcript))
            }
            if let transcript = (content["outputTranscription"] as? [String: Any])?["text"] as? String,
               !transcript.isEmpty {
                events.append(.outputTranscript(transcript))
            }
            if content["interrupted"] as? Bool == true { events.append(.interrupted) }
            if content["generationComplete"] as? Bool == true { events.append(.generationComplete) }
            if content["turnComplete"] as? Bool == true { events.append(.turnComplete) }
        }
        if let toolCall = root["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in calls {
                guard let id = call["id"] as? String, let name = call["name"] as? String else { continue }
                let arguments = call["args"] ?? [:]
                let argumentsData = try serialize(arguments)
                events.append(.toolCall(GeminiLiveToolCall(
                    id: id,
                    name: name,
                    argumentsJSON: String(decoding: argumentsData, as: UTF8.self)
                )))
            }
        }
        if let cancellation = root["toolCallCancellation"] as? [String: Any],
           let ids = cancellation["ids"] as? [String] {
            events.append(contentsOf: ids.map(GeminiLiveEvent.toolCallCancelled))
        }
        if let usage = root["usageMetadata"] as? [String: Any] {
            events.append(.usage(
                promptTokens: integer(usage["promptTokenCount"]),
                responseTokens: integer(usage["responseTokenCount"])
            ))
        }
        if let update = root["sessionResumptionUpdate"] as? [String: Any],
           update["resumable"] as? Bool == true,
           let handle = update["newHandle"] as? String {
            events.append(.sessionResumption(handle: handle))
        }
        if let goAway = root["goAway"] as? [String: Any], let timeLeft = goAway["timeLeft"] as? String {
            events.append(.goAway(timeLeft: timeLeft))
        }
        return events
    }

    private static func serialize(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw GeminiLiveTransportError.invalidClientMessage
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }
}

public actor GeminiLiveWebSocketTransport: GeminiLiveTransport {
    public static let endpoint = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!

    private let urlSession: URLSession
    private var task: URLSessionWebSocketTask?

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func connect(configuration: GeminiLiveConfiguration, apiKey: String) async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiLiveTransportError.missingAPIKey
        }
        await disconnect()
        var request = URLRequest(url: Self.endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let task = urlSession.webSocketTask(with: request)
        self.task = task
        task.resume()
        try await send(try GeminiLiveMessageCodec.setupMessage(configuration: configuration))
    }

    public func sendAudio(_ pcm16: Data) async throws {
        guard !pcm16.isEmpty else { return }
        try await send(try GeminiLiveMessageCodec.audioMessage(pcm16: pcm16))
    }

    public func sendImage(_ data: Data, mimeType: String) async throws {
        guard !data.isEmpty else { return }
        try await send(try GeminiLiveMessageCodec.imageMessage(data, mimeType: mimeType))
    }

    public func sendText(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await send(try GeminiLiveMessageCodec.textMessage(trimmed))
    }

    public func sendToolResponses(_ responses: [GeminiLiveToolResponse]) async throws {
        guard !responses.isEmpty else { return }
        try await send(try GeminiLiveMessageCodec.toolResponseMessage(responses))
    }

    public func receiveEvents() async throws -> [GeminiLiveEvent] {
        guard let task else { throw GeminiLiveTransportError.notConnected }
        let message = try await task.receive()
        switch message {
        case let .data(data): return try GeminiLiveMessageCodec.events(from: data)
        case let .string(text): return try GeminiLiveMessageCodec.events(from: Data(text.utf8))
        @unknown default: throw GeminiLiveTransportError.invalidServerMessage
        }
    }

    public func disconnect() async {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func send(_ data: Data) async throws {
        guard let task else { throw GeminiLiveTransportError.notConnected }
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }
}

public enum GeminiLiveTransportError: LocalizedError {
    case missingAPIKey
    case notConnected
    case invalidClientMessage
    case invalidServerMessage

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add a Gemini API key before starting a live conversation."
        case .notConnected: "The Gemini Live session is not connected."
        case .invalidClientMessage: "Zoid could not encode a Gemini Live message."
        case .invalidServerMessage: "Gemini Live returned an unsupported message."
        }
    }
}
