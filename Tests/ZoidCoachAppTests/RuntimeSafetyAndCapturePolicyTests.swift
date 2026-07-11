import Foundation
import Testing
@testable import ZoidCoachInfrastructure

struct RuntimeSafetyAndCapturePolicyTests {
    @Test
    func writeFailureTripsReadOnlyCircuitUntilExplicitReset() throws {
        let breaker = DatabaseWriteCircuitBreaker()
        let trippedAt = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(breaker.allowsExternalMutations)
        breaker.trip(reason: "disk full\nprivate detail", at: trippedAt)

        #expect(!breaker.allowsExternalMutations)
        #expect(breaker.snapshot.isReadOnly)
        #expect(breaker.snapshot.trippedAt == trippedAt)
        #expect(breaker.snapshot.reason == "disk full private detail")
        #expect(throws: DatabaseWriteCircuitBreakerError.self) {
            try breaker.throwIfTripped()
        }

        breaker.reset()
        #expect(breaker.allowsExternalMutations)
        try breaker.throwIfTripped()
    }

    @Test
    func firstWriteFailureRemainsTheCircuitBreakerReason() {
        let breaker = DatabaseWriteCircuitBreaker()
        breaker.trip(reason: "first failure", at: Date(timeIntervalSince1970: 10))
        breaker.trip(reason: "later failure", at: Date(timeIntervalSince1970: 20))

        #expect(breaker.snapshot.reason == "first failure")
        #expect(breaker.snapshot.trippedAt == Date(timeIntervalSince1970: 10))
    }

    @Test
    func capturePolicyUsesFiveSecondCadenceAndSkipsImagesAtNinetySecondsIdle() {
        #expect(NativeCapturePolicy.metadataCadenceSeconds == 5)
        #expect(NativeCapturePolicy.idleSkipSeconds == 90)
        #expect(NativeCapturePolicy.shouldCaptureImage(idleSeconds: 89.9))
        #expect(!NativeCapturePolicy.shouldCaptureImage(idleSeconds: 90))
    }

    @Test
    func capturePolicyHonorsConfiguredDisplaysAndDefaultsToAll() {
        #expect(NativeCapturePolicy.selectedDisplayIDs(available: [1, 2, 3], configured: []) == [1, 2, 3])
        #expect(NativeCapturePolicy.selectedDisplayIDs(available: [1, 2, 3], configured: [2, 3]) == [2, 3])
    }

    @Test
    func nativeCaptureDirectoryIsAppOwnedAndCannotCollideWithLegacyScreenwatch() {
        let applicationSupport = URL(fileURLWithPath: "/Users/test/Library/Application Support", isDirectory: true)
        let native = NativeCapturePolicy.appOwnedDaysDirectory(applicationSupportDirectory: applicationSupport)
        let legacy = URL(fileURLWithPath: "/Users/test/screenwatch/days", isDirectory: true)

        #expect(native.path == "/Users/test/Library/Application Support/Zoid Coach/native-capture/days")
        #expect(NativeCapturePolicy.pathsDoNotCollide(native: native, legacy: legacy))
        #expect(!NativeCapturePolicy.pathsDoNotCollide(native: legacy, legacy: legacy))
    }

    @Test
    func captureConfigurationPersistsAtomicallyAndEnforcesParityGate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-config-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeCaptureConfigurationStore(fileURL: root.appendingPathComponent("native-capture-config.json"))

        #expect(try store.load() == .legacy)
        try store.save(NativeCaptureConfiguration(mode: .native, configuredDisplayIDs: [9, 2, 9], parityPassed: false))
        let gated = try store.load()
        #expect(gated.mode == .parity)
        #expect(gated.configuredDisplayIDs == [2, 9])

        try store.save(NativeCaptureConfiguration(mode: .native, configuredDisplayIDs: [2], parityPassed: true))
        #expect(try store.load().mode == .native)
    }
}
