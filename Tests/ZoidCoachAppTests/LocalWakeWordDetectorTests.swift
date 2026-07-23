import AVFoundation
import Speech
import Testing
@testable import ZoidCoachApp

@Test
func audioTapBlockCanRunOutsideMainActor() async throws {
    let request = SFSpeechAudioBufferRecognitionRequest()
    let callback = LocalWakeWordDetector.makeAudioTapBlock(request: request)
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    ))
    let buffer = try #require(AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: 1_024
    ))

    await withCheckedContinuation { continuation in
        DispatchQueue(label: "LocalWakeWordDetectorTests.audio-tap").async {
            callback(buffer, AVAudioTime())
            continuation.resume()
        }
    }
}
