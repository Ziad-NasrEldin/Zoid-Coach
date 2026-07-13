import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func qaReadyStateFixtureProducesFinishedOnboardingAndProcessableState() async throws {
    let paths = try QAReadyStateTestPaths(label: "granted")
    defer { paths.remove() }

    let result = try runReadyStateScript(
        manifest: paths.exampleManifest,
        root: paths.runRoot
    )
    #expect(result.status == 0)
    #expect(result.stdout.contains("READY: isolated QA root prepared"))

    let runtime = try packagedQARuntime(root: paths.runRoot)
    let progress = try OnboardingProgressStore(runtimeEnvironment: runtime).load()
    #expect(progress.isFinished)
    #expect(progress.currentStep == .firstDailyPlan)
    #expect(progress.completedSteps == OnboardingProgress.stepSequence)
    #expect(progress.remindersAccess == .granted)
    #expect(progress.screenwatchAccess == .granted)
    #expect(progress.notificationAccess == .granted)
    #expect(progress.reminderListDecisions == [ReminderListDecision(listID: "work", isIncluded: true)])

    let adapter = try QAFixtureOSComposition.makeAuthorizedAdapter(runtimeEnvironment: runtime)
    let snapshot = try adapter.snapshot()
    #expect(snapshot.permissions[.reminders] == .granted)
    #expect(snapshot.permissions[.calendar] == .granted)
    #expect(snapshot.permissions[.notifications] == .granted)
    #expect(snapshot.reminders.map(\.id) == ["qa-ready-task"])
    #expect(snapshot.calendarCommitments.map(\.id) == ["qa-ready-calendar"])
    #expect(snapshot.notifications.map(\.id) == ["qa-ready-notification"])
    #expect(FileManager.default.fileExists(
        atPath: runtime.screenwatchDirectory
            .appendingPathComponent("2026-07-13/log.jsonl")
            .path
    ))
    let screenwatch = await ScreenwatchReader(baseDirectory: runtime.screenwatchDirectory)
        .inspect(now: Date(timeIntervalSince1970: 1_783_944_020))
    #expect(screenwatch.state == .healthy)
    #expect(!FileManager.default.fileExists(
        atPath: paths.runRoot
            .appendingPathComponent(QAFixtureOSComposition.controlRelativePath)
            .path
    ))
    #expect(FileManager.default.fileExists(
        atPath: paths.runRoot
            .appendingPathComponent(QAFixtureOSComposition.snapshotRelativePath)
            .path
    ))
}

@Test
func qaReadyStateFixtureSupportsExplicitDeferredSources() throws {
    let paths = try QAReadyStateTestPaths(label: "deferred")
    defer { paths.remove() }

    var manifest = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: paths.exampleManifest)) as? [String: Any]
    )
    var onboarding = try #require(manifest["onboarding"] as? [String: Any])
    onboarding["remindersAccess"] = "deferred"
    onboarding["screenwatchAccess"] = "deferred"
    onboarding["notificationAccess"] = "deferred"
    manifest["onboarding"] = onboarding
    var fixture = try #require(manifest["osFixture"] as? [String: Any])
    fixture["permissions"] = [
        "reminders": "notDetermined",
        "calendar": "granted",
        "notifications": "notDetermined",
    ]
    manifest["osFixture"] = fixture
    manifest["screenwatch"] = ["state": "deferred", "days": []]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: paths.customManifest, options: .atomic)

    let result = try runReadyStateScript(manifest: paths.customManifest, root: paths.runRoot)
    #expect(result.status == 0)

    let runtime = try packagedQARuntime(root: paths.runRoot)
    let progress = try OnboardingProgressStore(runtimeEnvironment: runtime).load()
    #expect(progress.isFinished)
    #expect(progress.remindersAccess == .deferred)
    #expect(progress.screenwatchAccess == .deferred)
    #expect(progress.notificationAccess == .deferred)
    #expect(!FileManager.default.fileExists(atPath: runtime.screenwatchDirectory.path))
    let fixtureSnapshot = try QAFixtureOSComposition
        .makeAuthorizedAdapter(runtimeEnvironment: runtime)
        .snapshot()
    #expect(fixtureSnapshot.permissions[.reminders] == .notDetermined)
    #expect(fixtureSnapshot.permissions[.notifications] == .notDetermined)
}

@Test
func qaReadyStateFixtureFailsClosedWithoutReplacingExistingRoot() throws {
    let paths = try QAReadyStateTestPaths(label: "malformed")
    defer { paths.remove() }
    try FileManager.default.createDirectory(at: paths.runRoot, withIntermediateDirectories: true)
    let sentinel = paths.runRoot.appendingPathComponent("sentinel.txt")
    try Data("preserve-me".utf8).write(to: sentinel)

    var manifest = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: paths.exampleManifest)) as? [String: Any]
    )
    manifest["unsupported"] = true
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: paths.customManifest, options: .atomic)

    let result = try runReadyStateScript(
        manifest: paths.customManifest,
        root: paths.runRoot,
        replace: true
    )
    #expect(result.status == 2)
    #expect(result.stderr.contains("SETUP_FAIL"))
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "preserve-me")
    let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: paths.runRoot.path)
    #expect(remainingFiles == ["sentinel.txt"])
}

private struct QAReadyStateTestPaths {
    let repositoryRoot: URL
    let parent: URL
    let runRoot: URL
    let exampleManifest: URL
    let customManifest: URL

    init(label: String) throws {
        repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        parent = repositoryRoot
            .appendingPathComponent(".build/qa-ready-state-tests", isDirectory: true)
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        runRoot = parent.appendingPathComponent("run", isDirectory: true)
        exampleManifest = repositoryRoot
            .appendingPathComponent("Scripts/fixtures/qa-ready-state.example.json")
        customManifest = parent.appendingPathComponent("manifest.json")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: parent)
    }
}

private func runReadyStateScript(
    manifest: URL,
    root: URL,
    replace: Bool = false
) throws -> (status: Int32, stdout: String, stderr: String) {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "python3",
        repositoryRoot.appendingPathComponent("Scripts/prepare-qa-ready-state.py").path,
        manifest.path,
        root.path,
    ] + (replace ? ["--replace"] : [])
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    return (
        process.terminationStatus,
        String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    )
}

private func packagedQARuntime(root: URL) throws -> RuntimeEnvironment {
    try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
}
