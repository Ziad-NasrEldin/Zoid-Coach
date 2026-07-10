import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func geminiSetupEnablesAudioToolsCompressionAndSessionResumptionWithoutEmbeddingTheAPIKey() throws {
    let configuration = GeminiLiveConfiguration(
        model: "gemini-3.1-flash-live-preview",
        systemInstruction: "You are Zoid.",
        voiceName: "Kore",
        tools: [VoiceToolDefinition(
            name: "open_application",
            description: "Open an installed application.",
            riskLevel: .reversibleLocal,
            requiresExplicitUserIntent: true
        )],
        sessionResumptionHandle: "resume-token"
    )

    let data = try GeminiLiveMessageCodec.setupMessage(configuration: configuration)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let setup = try #require(json["setup"] as? [String: Any])
    let generation = try #require(setup["generationConfig"] as? [String: Any])
    let compression = try #require(setup["contextWindowCompression"] as? [String: Any])
    let resumption = try #require(setup["sessionResumption"] as? [String: Any])
    let tools = try #require(setup["tools"] as? [[String: Any]])
    let declarations = try #require(tools.first?["functionDeclarations"] as? [[String: Any]])

    #expect(setup["model"] as? String == "models/gemini-3.1-flash-live-preview")
    #expect(generation["responseModalities"] as? [String] == ["AUDIO"])
    #expect(compression["slidingWindow"] != nil)
    #expect(resumption["handle"] as? String == "resume-token")
    #expect(declarations.first?["name"] as? String == "open_application")
    #expect(String(decoding: data, as: UTF8.self).contains("api-key") == false)
}

@Test
func geminiServerMessageDecodesAudioToolCallsUsageAndLifecycleSignals() throws {
    let audio = Data([1, 2, 3, 4])
    let message = Data("""
    {
      "serverContent": {
        "modelTurn": {"parts": [{"inlineData": {"mimeType": "audio/pcm;rate=24000", "data": "\(audio.base64EncodedString())"}}]},
        "outputTranscription": {"text": "Opening Xcode"},
        "interrupted": true,
        "turnComplete": true
      },
      "toolCall": {"functionCalls": [{"id": "call-1", "name": "open_application", "args": {"name": "Xcode"}}]},
      "usageMetadata": {"promptTokenCount": 100, "responseTokenCount": 25},
      "sessionResumptionUpdate": {"resumable": true, "newHandle": "next-token"},
      "goAway": {"timeLeft": "5s"}
    }
    """.utf8)

    let events = try GeminiLiveMessageCodec.events(from: message)

    #expect(events.contains(.audio(audio)))
    #expect(events.contains(.outputTranscript("Opening Xcode")))
    #expect(events.contains(.interrupted))
    #expect(events.contains(.turnComplete))
    #expect(events.contains(.usage(promptTokens: 100, responseTokens: 25)))
    #expect(events.contains(.sessionResumption(handle: "next-token")))
    #expect(events.contains(.goAway(timeLeft: "5s")))
    #expect(events.contains(.toolCall(GeminiLiveToolCall(
        id: "call-1",
        name: "open_application",
        argumentsJSON: #"{"name":"Xcode"}"#
    ))))
}

@Test
func realtimeAudioMessageUsesSixteenKilohertzPCM() throws {
    let pcm = Data([0, 1, 2, 3])

    let data = try GeminiLiveMessageCodec.audioMessage(pcm16: pcm)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let input = try #require(json["realtimeInput"] as? [String: Any])
    let chunks = try #require(input["mediaChunks"] as? [[String: Any]])

    #expect(chunks.first?["mimeType"] as? String == "audio/pcm;rate=16000")
    #expect(chunks.first?["data"] as? String == pcm.base64EncodedString())
}
