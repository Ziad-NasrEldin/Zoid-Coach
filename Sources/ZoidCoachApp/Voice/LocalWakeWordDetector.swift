import AVFoundation
import Foundation
import Speech

@MainActor
final class LocalWakeWordDetector: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var availabilityMessage = "Wake word is off"

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onWake: (() -> Void)?
    private var shouldRun = false
    private var tapInstalled = false
    private let wakePhrases = ["hey zoid", "hey zoyd", "hey zoid 666", "hey zoid coach"]

    func start(onWake: @escaping () -> Void) async {
        self.onWake = onWake
        shouldRun = true
        guard await requestAuthorization() else {
            availabilityMessage = "Speech recognition permission is required"
            shouldRun = false
            return
        }
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            availabilityMessage = "On-device wake-word recognition is unavailable"
            shouldRun = false
            return
        }
        beginRecognition()
    }

    func stop() {
        shouldRun = false
        isListening = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        availabilityMessage = "Wake word is off"
    }

    private func requestAuthorization() async -> Bool {
        let speechAuthorized = await Self.requestSpeechAuthorization()
        guard speechAuthorized else { return false }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func beginRecognition() {
        guard shouldRun, let recognizer, !engine.isRunning else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: Self.makeAudioTapBlock(request: request)
        )
        tapInstalled = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let transcript = result?.bestTranscription.formattedString.lowercased(),
                   self.wakePhrases.contains(where: transcript.contains) {
                    let handler = self.onWake
                    self.stopRecognitionCycle()
                    handler?()
                    return
                }
                if error != nil || result?.isFinal == true {
                    self.stopRecognitionCycle()
                    guard self.shouldRun else { return }
                    try? await Task.sleep(for: .milliseconds(500))
                    self.beginRecognition()
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isListening = true
            availabilityMessage = "Listening locally for Hey Zoid"
        } catch {
            stopRecognitionCycle()
            availabilityMessage = error.localizedDescription
        }
    }

    private func stopRecognitionCycle() {
        isListening = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
    }

    nonisolated static func makeAudioTapBlock(
        request: SFSpeechAudioBufferRecognitionRequest
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
        }
    }
}
