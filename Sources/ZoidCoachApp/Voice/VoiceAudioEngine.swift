@preconcurrency import AVFoundation
import Foundation

final class VoiceAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var audioHandler: (@Sendable (Data) -> Void)?
    private var isCapturing = false

    init() {
        engine.attach(player)
        let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
    }

    @MainActor
    func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            // Opening the AVAudioEngine input is the reliable TCC trigger for
            // a native macOS audio app. Nothing is recorded and the engine is
            // stopped immediately after the permission decision.
            _ = engine.inputNode
            engine.prepare()
            do {
                try engine.start()
                engine.stop()
            } catch {
                return false
            }
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    func start(onAudio: @escaping @Sendable (Data) -> Void) throws {
        stopCapture()
        lock.withLock {
            audioHandler = onAudio
            isCapturing = true
        }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
              ),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw VoiceAudioEngineError.unsupportedInputFormat
        }
        input.installTap(onBus: 0, bufferSize: 1_600, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.lock.withLock({ self.isCapturing }) else { return }
            if self.player.isPlaying, Self.rootMeanSquare(buffer) > 0.08 {
                self.player.stop()
            }
            guard let converted = Self.convert(buffer, using: converter, targetFormat: targetFormat) else { return }
            self.lock.withLock { self.audioHandler }?(converted)
        }
        engine.prepare()
        try engine.start()
    }

    func play(pcm24: Data) {
        guard !pcm24.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1) else { return }
        let sampleCount = pcm24.count / MemoryLayout<Int16>.size
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ), let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        pcm24.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for index in 0..<sampleCount {
                channel[index] = Float(Int16(littleEndian: samples[index])) / 32_768
            }
        }
        player.scheduleBuffer(buffer)
        if !engine.isRunning { try? engine.start() }
        if !player.isPlaying { player.play() }
    }

    func stopPlayback() { player.stop() }

    func stop() {
        stopCapture()
        player.stop()
        engine.stop()
    }

    private func stopCapture() {
        let shouldRemove = lock.withLock { () -> Bool in
            let current = isCapturing
            isCapturing = false
            audioHandler = nil
            return current
        }
        if shouldRemove { engine.inputNode.removeTap(onBus: 0) }
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> Data? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard !supplied else {
                state.pointee = .endOfStream
                return nil
            }
            supplied = true
            state.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        let audioBuffer = output.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData else { return nil }
        return Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
    }

    private static func rootMeanSquare(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
        return sqrt(sum / Float(buffer.frameLength))
    }
}

enum VoiceAudioEngineError: LocalizedError {
    case unsupportedInputFormat

    var errorDescription: String? { "The current microphone format cannot be converted for Gemini Live." }
}
