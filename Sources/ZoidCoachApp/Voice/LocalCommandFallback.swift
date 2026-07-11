import AVFoundation
import Foundation
import Speech
import ZoidCoachCore

enum LocalCommandParser {
    static func invocation(from transcript: String, sessionID: String, now: Date) -> VoiceToolInvocation? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        let tool: String
        let arguments: [String: Any]
        if let value = suffix(afterAny: ["open file "], in: trimmed, normalized: normalized) {
            tool = "open_file"
            arguments = ["path": value]
        } else if let value = suffix(afterAny: ["open ", "launch "], in: trimmed, normalized: normalized) {
            tool = "open_application"
            arguments = ["name": value]
        } else if let value = suffix(afterAny: ["search for ", "search "], in: trimmed, normalized: normalized) {
            tool = "search_web"
            arguments = ["query": value]
        } else if let value = suffix(afterAny: ["find file ", "find files ", "find "], in: trimmed, normalized: normalized) {
            tool = "find_files"
            arguments = ["query": value, "limit": 8]
        } else if normalized.contains("pause automation") {
            tool = "pause_automation"
            arguments = [:]
        } else if normalized.contains("resume automation") {
            tool = "resume_automation"
            arguments = [:]
        } else if normalized.contains("what should i do")
                    || normalized.contains("daily brief")
                    || normalized.contains("اعمل ايه")
                    || normalized.contains("أعمل ايه") {
            tool = "get_daily_brief"
            arguments = [:]
        } else {
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) else { return nil }
        return VoiceToolInvocation(
            id: UUID().uuidString,
            sessionID: sessionID,
            toolName: tool,
            argumentsJSON: String(decoding: data, as: UTF8.self),
            originTurnID: nil,
            originUserText: trimmed,
            hasExplicitUserIntent: true,
            requestedAt: now
        )
    }

    private static func suffix(afterAny prefixes: [String], in original: String, normalized: String) -> String? {
        for prefix in prefixes where normalized.hasPrefix(prefix) {
            let index = original.index(original.startIndex, offsetBy: prefix.count)
            let value = original[index...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }
}

@MainActor
final class LocalCommandFallback {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var latestTranscript = ""
    private var tapInstalled = false

    func listenOnce() async throws -> String {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            throw LocalCommandFallbackError.onDeviceRecognitionUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            latestTranscript = ""
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let value = result?.bestTranscription.formattedString,
                       !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.latestTranscript = value
                        self.silenceTask?.cancel()
                        self.silenceTask = Task { [weak self] in
                            try? await Task.sleep(for: .milliseconds(900))
                            guard !Task.isCancelled else { return }
                            self?.finish(.success(value))
                        }
                    }
                    if let error { self.finish(.failure(error)) }
                    else if result?.isFinal == true { self.finish(.success(self.latestTranscript)) }
                }
            }
            do {
                engine.prepare()
                try engine.start()
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(LocalCommandFallbackError.noSpeech))
                }
            } catch {
                finish(.failure(error))
            }
        }
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        silenceTask?.cancel()
        recognitionTask?.cancel()
        recognitionTask = nil
        request?.endAudio()
        request = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        continuation.resume(with: result)
    }
}

enum LocalCommandFallbackError: LocalizedError {
    case onDeviceRecognitionUnavailable
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .onDeviceRecognitionUnavailable: "On-device speech recognition is unavailable for local command mode."
        case .noSpeech: "Zoid did not hear a local command."
        }
    }
}
