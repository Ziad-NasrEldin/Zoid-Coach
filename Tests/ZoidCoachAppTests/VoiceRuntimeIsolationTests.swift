import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@MainActor
@Test
func qaVoiceUsesDedicatedDashboardIdentityWhileOSControlsFailClosed() async throws {
    let runtimeEnvironment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", "/tmp/zoid-voice-qa-\(UUID().uuidString)"],
        processEnvironment: [:]
    ).environment
    let hotKey = RecordingVoiceHotKeyController()
    let wakeWord = RecordingVoiceWakeWordController()
    let audio = RecordingVoiceAudioController()
    let model = VoiceConversationModel(
        runtimeEnvironment: runtimeEnvironment,
        hotKey: hotKey,
        wakeWord: wakeWord,
        audio: audio
    )

    #expect(model.isDashboardConnectionEnabled)
    model.startAlwaysAvailable()
    model.toggleSession(source: .menuBar)
    model.toggleSession(source: .globalHotkey)
    model.toggleSession(source: .wakeWord)
    model.toggleSession(source: .text)
    await Task.yield()

    #expect(model.state == .idle)
    #expect(model.statusMessage == "QA voice controls are disabled until isolated audio adapters are configured")
    #expect(hotKey.registerCount == 0)
    #expect(wakeWord.startCount == 0)
    #expect(audio.microphoneRequestCount == 0)
    #expect(audio.startCount == 0)
}

@MainActor
private final class RecordingVoiceHotKeyController: VoiceHotKeyControlling {
    private(set) var registerCount = 0
    func register(preset: VoiceHotKeyPreset, action: @escaping () -> Void) throws {
        registerCount += 1
    }
    func unregister() {}
}

@MainActor
private final class RecordingVoiceWakeWordController: VoiceWakeWordControlling {
    let availabilityMessage = "Recording"
    private(set) var startCount = 0
    func start(onWake: @escaping () -> Void) async { startCount += 1 }
    func stop() {}
}

@MainActor
private final class RecordingVoiceAudioController: VoiceAudioControlling {
    private(set) var microphoneRequestCount = 0
    private(set) var startCount = 0
    func requestMicrophoneAccess() async -> Bool {
        microphoneRequestCount += 1
        return true
    }
    func start(onAudio: @escaping @Sendable (Data) -> Void) throws { startCount += 1 }
    func play(pcm24: Data) {}
    func stopPlayback() {}
    func stop() {}
}
