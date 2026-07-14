import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore

@Test
func zc052005ProbeRefusesProductionAndUnpackagedQA() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zc052005-probe-guard-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let unpackaged = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", root.path],
        processEnvironment: [:]
    ).environment
    let packaged = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment

    #expect(!ZC052005AcceptanceProbe.isAvailable(in: .production()))
    #expect(!ZC052005AcceptanceProbe.isAvailable(in: unpackaged))
    #expect(ZC052005AcceptanceProbe.isAvailable(in: packaged))
}

@Test
func zc052005ProbeOnlyParsesNamedSafeModes() {
    #expect(ZC052005AcceptanceProbe.Mode(argument: "prepare-external-reminder") == .prepareExternalReminder)
    #expect(ZC052005AcceptanceProbe.Mode(argument: "temporary-lock") == .temporaryLock)
    #expect(ZC052005AcceptanceProbe.Mode(argument: "lost-task-reply") == .lostTaskReply)
    #expect(ZC052005AcceptanceProbe.Mode(argument: "calendar-lost-reply") == .calendarLostReply)
    #expect(ZC052005AcceptanceProbe.Mode(argument: "hold-lock") == .holdLock)
    #expect(ZC052005AcceptanceProbe.Mode(argument: "production-database") == nil)
}
