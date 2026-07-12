import Foundation
import Testing
import ZoidCoachCore

@Test
func fixedClockAlwaysReturnsTheConfiguredInstant() {
    let instant = Date(timeIntervalSince1970: 1_735_732_800)
    let clock = ZoidClock.fixed(instant)

    #expect(clock.now() == instant)
    #expect(clock.now() == instant)
}

@Test
func fixtureWorkspacePreparationIsRepeatableAndRemovesStaleState() throws {
    let testRoot = temporaryTestRoot("repeatability")
    defer { try? FileManager.default.removeItem(at: testRoot) }
    let environment = try qaEnvironment(runRoot: testRoot)
    let builder = try QAFixtureWorkspaceBuilder(environment: environment)

    let first = try builder.prepare(fixtureID: "planning-morning")
    let staleFile = first.root.appendingPathComponent("stale.txt")
    try Data("stale".utf8).write(to: staleFile)
    let second = try builder.prepare(fixtureID: "planning-morning")

    #expect(first == second)
    #expect(
        first.root.path == testRoot
            .appendingPathComponent("Fixtures/planning-morning")
            .path
    )
    #expect(first.launchArguments == ["--qa-run-root", first.root.path])
    #expect(
        first.databaseURL.path == first.root
            .appendingPathComponent("Application Support/Zoid Coach/zoid-coach.sqlite")
            .path
    )
    #expect(!FileManager.default.fileExists(atPath: staleFile.path))
    #expect(FileManager.default.fileExists(atPath: second.applicationSupportRoot.path))
    #expect(FileManager.default.fileExists(atPath: second.screenwatchDirectory.path))
    #expect(FileManager.default.fileExists(atPath: second.exportRoot.path))
}

@Test
func fixtureWorkspacesAreIsolatedAndCleanupDoesNotRemoveSiblings() throws {
    let testRoot = temporaryTestRoot("isolation")
    defer { try? FileManager.default.removeItem(at: testRoot) }
    let environment = try qaEnvironment(runRoot: testRoot)
    let builder = try QAFixtureWorkspaceBuilder(environment: environment)
    let first = try builder.prepare(fixtureID: "scenario-one")
    let second = try builder.prepare(fixtureID: "scenario-two")

    try Data("one".utf8).write(to: first.root.appendingPathComponent("marker.txt"))
    #expect(
        !FileManager.default.fileExists(
            atPath: second.root.appendingPathComponent("marker.txt").path
        )
    )

    try builder.cleanup(first)

    #expect(!FileManager.default.fileExists(atPath: first.root.path))
    #expect(FileManager.default.fileExists(atPath: second.root.path))
}

@Test
func fixtureBuilderRefusesProductionEnvironmentBeforeWriting() throws {
    let testRoot = temporaryTestRoot("production-guard")
    defer { try? FileManager.default.removeItem(at: testRoot) }
    let environment = RuntimeEnvironment.production(
        directories: .init(
            home: testRoot.appendingPathComponent("home", isDirectory: true),
            applicationSupport: testRoot.appendingPathComponent("Application Support", isDirectory: true)
        )
    )

    #expect(throws: QAFixtureWorkspaceError.productionEnvironmentRefused) {
        try QAFixtureWorkspaceBuilder(environment: environment)
    }
    #expect(!FileManager.default.fileExists(atPath: testRoot.path))
}

@Test
func fixtureBuilderRefusesQARootInsideProductionProductStorage() throws {
    let testRoot = temporaryTestRoot("production-root-guard")
    defer { try? FileManager.default.removeItem(at: testRoot) }
    let directories = RuntimeEnvironment.SystemDirectories(
        home: testRoot.appendingPathComponent("home", isDirectory: true),
        applicationSupport: testRoot.appendingPathComponent("Application Support", isDirectory: true)
    )
    let environment = try qaEnvironment(runRoot: directories.applicationSupport)

    #expect(
        throws: QAFixtureWorkspaceError.productionRootRefused(
            path: directories.applicationSupport.path
        )
    ) {
        try QAFixtureWorkspaceBuilder(
            environment: environment,
            productionDirectories: directories
        )
    }
    #expect(!FileManager.default.fileExists(atPath: testRoot.path))
}

@Test
func fixtureBuilderRejectsPathTraversal() throws {
    let testRoot = temporaryTestRoot("invalid-id")
    defer { try? FileManager.default.removeItem(at: testRoot) }
    let environment = try qaEnvironment(runRoot: testRoot)
    let builder = try QAFixtureWorkspaceBuilder(environment: environment)

    #expect(throws: QAFixtureWorkspaceError.invalidFixtureID("../production")) {
        try builder.prepare(fixtureID: "../production")
    }
}

@Test
func fixtureBuilderRefusesPreexistingSymlinkEscape() throws {
    let container = temporaryTestRoot("symlink-escape")
    defer { try? FileManager.default.removeItem(at: container) }
    let qaRoot = container.appendingPathComponent("qa", isDirectory: true)
    let outsideRoot = container.appendingPathComponent("outside", isDirectory: true)
    let fixturesRoot = qaRoot.appendingPathComponent("Fixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: fixturesRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
    let marker = outsideRoot.appendingPathComponent("preserve.txt")
    try Data("preserve".utf8).write(to: marker)
    try FileManager.default.createSymbolicLink(
        at: fixturesRoot.appendingPathComponent("escaped"),
        withDestinationURL: outsideRoot
    )
    let environment = try qaEnvironment(runRoot: qaRoot)
    let builder = try QAFixtureWorkspaceBuilder(environment: environment)

    #expect(
        throws: QAFixtureWorkspaceError.workspaceOutsideQARunRoot(
            path: outsideRoot.path,
            runRoot: qaRoot.path
        )
    ) {
        try builder.prepare(fixtureID: "escaped")
    }
    #expect(FileManager.default.fileExists(atPath: marker.path))
}

private func qaEnvironment(runRoot: URL) throws -> RuntimeEnvironment {
    try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", runRoot.path],
        processEnvironment: [:]
    ).environment
}

private func temporaryTestRoot(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-fixture-tests", isDirectory: true)
        .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
}
