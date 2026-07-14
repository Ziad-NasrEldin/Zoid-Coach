import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test
func timeZonePickerControlIsAvailableOnlyToSignedIsolatedQAPackages() throws {
    let production = SignedQATimeZonePickerControl(
        runtimeEnvironment: .production()
    )
    let unpackagedQAEnvironment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", "/private/tmp/zoid-666-time-zone-unpackaged-qa"],
        processEnvironment: [:]
    ).environment
    let unpackagedQA = SignedQATimeZonePickerControl(
        runtimeEnvironment: unpackagedQAEnvironment
    )
    let signedQA = SignedQATimeZonePickerControl(
        runtimeEnvironment: try signedQARuntimeEnvironment()
    )

    #expect(!production.isAvailable)
    #expect(!unpackagedQA.isAvailable)
    #expect(signedQA.isAvailable)
    #expect(production.crossDayDestination(from: "Africa/Cairo", at: Date()) == nil)
    #expect(unpackagedQA.crossDayDestination(from: "Africa/Cairo", at: Date()) == nil)
}

@Test(arguments: [
    TimeZoneSelectionCase(sourceIdentifier: "Africa/Cairo", timestamp: "2026-07-14T10:00:00Z"),
    TimeZoneSelectionCase(sourceIdentifier: "America/Los_Angeles", timestamp: "2026-03-08T09:30:00Z"),
    TimeZoneSelectionCase(sourceIdentifier: "America/Los_Angeles", timestamp: "2026-11-01T08:30:00Z")
])
func signedQATimeZonePickerChoosesAStableCrossDayDestination(testCase: TimeZoneSelectionCase) throws {
    let control = SignedQATimeZonePickerControl(
        runtimeEnvironment: try signedQARuntimeEnvironment()
    )
    let referenceDate = try #require(ISO8601DateFormatter().date(from: testCase.timestamp))
    let destination = try #require(
        control.crossDayDestination(from: testCase.sourceIdentifier, at: referenceDate)
    )

    #expect(destination != testCase.sourceIdentifier)
    for offset in [-300.0, 0, 300.0] {
        let date = referenceDate.addingTimeInterval(offset)
        #expect(localDayKey(date, in: testCase.sourceIdentifier) != localDayKey(date, in: destination))
    }
}

@Test(arguments: [
    TimeZoneSelectionCase(sourceIdentifier: "Africa/Cairo", timestamp: "2026-07-14T10:00:00Z"),
    TimeZoneSelectionCase(sourceIdentifier: "America/Los_Angeles", timestamp: "2026-03-08T09:30:00Z"),
    TimeZoneSelectionCase(sourceIdentifier: "America/Los_Angeles", timestamp: "2026-11-01T08:30:00Z"),
    TimeZoneSelectionCase(sourceIdentifier: "Pacific/Kiritimati", timestamp: "2026-07-14T10:00:00Z"),
    TimeZoneSelectionCase(sourceIdentifier: "Pacific/Pago_Pago", timestamp: "2026-07-14T10:00:00Z")
])
func signedQATimeZonePickerChoosesAStableSameDayDestination(testCase: TimeZoneSelectionCase) throws {
    let control = SignedQATimeZonePickerControl(
        runtimeEnvironment: try signedQARuntimeEnvironment()
    )
    let referenceDate = try #require(ISO8601DateFormatter().date(from: testCase.timestamp))
    let destination = try #require(
        control.sameDayDestination(from: testCase.sourceIdentifier, at: referenceDate)
    )

    #expect(destination != testCase.sourceIdentifier)
    for offset in [-300.0, 0, 300.0] {
        let date = referenceDate.addingTimeInterval(offset)
        #expect(localDayKey(date, in: testCase.sourceIdentifier) == localDayKey(date, in: destination))
    }
}

struct TimeZoneSelectionCase: Sendable {
    let sourceIdentifier: String
    let timestamp: String
}

private func signedQARuntimeEnvironment() throws -> RuntimeEnvironment {
    let runRoot = URL(
        fileURLWithPath: "/private/tmp/zoid-666-time-zone-signed-qa",
        isDirectory: true
    )
    return try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: PackagedRuntimeMarker(
            mode: .qa,
            qaRunRoot: runRoot,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
}

private func localDayKey(_ date: Date, in timeZoneIdentifier: String) -> String? {
    guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year,
          let month = components.month,
          let day = components.day else { return nil }
    return String(format: "%04d-%02d-%02d", year, month, day)
}
