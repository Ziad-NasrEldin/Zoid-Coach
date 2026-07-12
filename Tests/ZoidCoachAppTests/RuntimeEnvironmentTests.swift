import Foundation
import Testing
import ZoidCoachCore

@Test
func productionRuntimeEnvironmentPreservesExistingDefaults() {
    let directories = RuntimeEnvironment.SystemDirectories(
        home: URL(fileURLWithPath: "/Users/tester", isDirectory: true),
        applicationSupport: URL(fileURLWithPath: "/Users/tester/Library/Application Support", isDirectory: true)
    )

    let environment = RuntimeEnvironment.production(directories: directories)

    #expect(environment.mode == .production)
    #expect(environment.databaseURL.path == "/Users/tester/Library/Application Support/Zoid 666/zoid-coach.sqlite")
    #expect(environment.screenwatchDirectory.path == "/Users/tester/screenwatch/days")
    #expect(environment.applicationSupportRoot.path == "/Users/tester/Library/Application Support")
    #expect(environment.exportRoot.path == "/Users/tester/Library/Application Support/Zoid 666/Diagnostics")
    #expect(environment.userDefaultsSuiteName == nil)
    #expect(environment.keychainServiceSuffix.isEmpty)
    #expect(environment.identity == .production)
    #expect(environment.identity.appBundleIdentifier == "com.ziadnasreldin.ZoidCoach")
    #expect(environment.identity.appExecutableName == "ZoidCoach")
    #expect(environment.identity.agentSigningIdentifier == "com.ziadnasreldin.ZoidCoach.agent")
    #expect(environment.identity.launchAgentPlistName == "com.ziadnasreldin.ZoidCoach.agent.plist")
    #expect(environment.identity.machServiceName == "com.ziadnasreldin.ZoidCoach.agent")
    #expect(environment.packageMode == nil)
}

@Test
func productionRuntimeMigratesLegacyProductDirectoryWithoutLosingData() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-storage-migration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let support = root.appendingPathComponent("Application Support", isDirectory: true)
    let legacy = support.appendingPathComponent("Zoid Coach", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    let legacyDatabase = legacy.appendingPathComponent("zoid-coach.sqlite")
    try Data("existing-user-data".utf8).write(to: legacyDatabase)

    let environment = RuntimeEnvironment.production(directories: .init(
        home: root,
        applicationSupport: support
    ))

    #expect(environment.databaseURL.path == support.appendingPathComponent("Zoid 666/zoid-coach.sqlite").path)
    #expect(try Data(contentsOf: environment.databaseURL) == Data("existing-user-data".utf8))
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
}

@Test
func qaRuntimeEnvironmentDerivesEveryWritableLocationFromRunRoot() throws {
    let resolution = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", "/tmp/zoid-qa/run-42", "--once"],
        processEnvironment: [:]
    )

    #expect(resolution.environment.mode == .qa(runRoot: URL(fileURLWithPath: "/private/tmp/zoid-qa/run-42", isDirectory: true)))
    #expect(resolution.environment.databaseURL.path == "/private/tmp/zoid-qa/run-42/Application Support/Zoid 666/zoid-coach.sqlite")
    #expect(resolution.environment.screenwatchDirectory.path == "/private/tmp/zoid-qa/run-42/Screenwatch/days")
    #expect(resolution.environment.applicationSupportRoot.path == "/private/tmp/zoid-qa/run-42/Application Support")
    #expect(resolution.environment.exportRoot.path == "/private/tmp/zoid-qa/run-42/Exports")
    #expect(resolution.environment.userDefaultsSuiteName?.hasPrefix("com.ziadnasreldin.ZoidCoach.qa.") == true)
    #expect(resolution.environment.keychainServiceSuffix.hasPrefix(".qa."))
    #expect(resolution.environment.identity == .qa)
    #expect(resolution.environment.packageMode == nil)
    #expect(resolution.remainingArguments == ["--once"])
}

@Test
func packagedQATemporaryAliasCanonicalizesToPrivateTmp() throws {
    let token = "zoid-qa-tmp-alias-\(UUID().uuidString)"
    let aliasRoot = URL(fileURLWithPath: "/tmp/\(token)", isDirectory: true)
    let canonicalRoot = URL(fileURLWithPath: "/private/tmp/\(token)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: canonicalRoot) }
    try FileManager.default.createDirectory(
        at: canonicalRoot,
        withIntermediateDirectories: true
    )
    let resolution = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", canonicalRoot.path],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: aliasRoot,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    )

    #expect(resolution.environment.mode == .qa(runRoot: canonicalRoot))
    #expect(resolution.environment.applicationSupportRoot.path
        == canonicalRoot.appendingPathComponent("Application Support").path)
    #expect(resolution.environment.databaseURL.path.hasPrefix(canonicalRoot.path + "/"))
    #expect(resolution.environment.screenwatchDirectory.path.hasPrefix(canonicalRoot.path + "/"))
    #expect(resolution.environment.exportRoot.path.hasPrefix(canonicalRoot.path + "/"))
}

@Test
func packagedQADirectExecutableUsesEmbeddedRootWhenEnvironmentIsStripped() throws {
    let fixture = try packagedRuntimeFixture(mode: .qa)
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let marker = try #require(try PackagedRuntimeMarker.current(
        executableURL: fixture.executableURL
    ))

    let resolution = try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: marker,
        executableSigningIdentifier: RuntimeIdentity.qa.agentSigningIdentifier
    )

    #expect(resolution.environment.mode == .qa(runRoot: fixture.qaRunRoot))
    #expect(resolution.environment.identity == .qa)
    #expect(resolution.environment.packageMode == .qa)
}

@Test
func packagedRuntimeRejectsModeRootAndBundleIdentityMismatches() throws {
    let fixture = try packagedRuntimeFixture(mode: .qa)
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let marker = try #require(try PackagedRuntimeMarker.current(
        executableURL: fixture.executableURL
    ))

    #expect(throws: RuntimeEnvironmentError.packageModeMismatch(
        expected: "qa",
        actual: "production"
    )) {
        try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: ["ZOID_COACH_PACKAGE_MODE": "production"],
            packagedRuntime: marker,
            executableSigningIdentifier: RuntimeIdentity.qa.agentSigningIdentifier
        )
    }
    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", fixture.container.appendingPathComponent("other").path],
            processEnvironment: [:],
            packagedRuntime: marker,
            executableSigningIdentifier: RuntimeIdentity.qa.agentSigningIdentifier
        )
    }
    #expect(throws: RuntimeEnvironmentError.packageIdentityMismatch(
        expected: RuntimeIdentity.qa.appBundleIdentifier,
        actual: RuntimeIdentity.production.appBundleIdentifier
    )) {
        try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: [:],
            packagedRuntime: .init(
                mode: .qa,
                qaRunRoot: fixture.qaRunRoot,
                appBundleIdentifier: RuntimeIdentity.production.appBundleIdentifier
            ),
            executableSigningIdentifier: RuntimeIdentity.qa.agentSigningIdentifier
        )
    }
    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: [:],
            packagedRuntime: marker,
            executableSigningIdentifier: RuntimeIdentity.production.appSigningIdentifier
        )
    }
}

@Test
func packagedRuntimeMarkerRejectsInfoAndLaunchEnvironmentMismatch() throws {
    let fixture = try packagedRuntimeFixture(mode: .qa)
    defer { try? FileManager.default.removeItem(at: fixture.container) }
    let infoURL = fixture.executableURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Info.plist")
    let object = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: infoURL),
        format: nil
    )
    var info = try #require(object as? [String: Any])
    info["LSEnvironment"] = [
        "ZOID_COACH_PACKAGE_MODE": "qa",
        "ZOID_COACH_QA_RUN_ROOT": fixture.container.appendingPathComponent("other").path,
    ]
    try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    ).write(to: infoURL, options: .atomic)

    #expect(throws: RuntimeEnvironmentError.invalidPackageMarker(path: infoURL.path)) {
        try PackagedRuntimeMarker.current(executableURL: fixture.executableURL)
    }
}

@Test
func productionPackageRejectsEveryQARuntimeInjection() {
    let marker = PackagedRuntimeMarker(
        mode: .production,
        qaRunRoot: nil,
        appBundleIdentifier: RuntimeIdentity.production.appBundleIdentifier
    )

    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", "/tmp/forbidden-qa"],
            processEnvironment: [:],
            packagedRuntime: marker,
            executableSigningIdentifier: RuntimeIdentity.production.appSigningIdentifier
        )
    }
    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: [
                "ZOID_COACH_PACKAGE_MODE": "qa",
                "ZOID_COACH_QA_RUN_ROOT": "/tmp/forbidden-qa",
            ],
            packagedRuntime: marker,
            executableSigningIdentifier: RuntimeIdentity.production.appSigningIdentifier
        )
    }
}

@Test
func unbundledQAInjectionRemainsExplicitAndPackageModeCannotBeSpoofed() throws {
    let qa = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", "/tmp/zoid-unbundled-explicit"],
        processEnvironment: [:],
        packagedRuntime: nil
    ).environment

    #expect(qa.packageMode == nil)
    #expect(qa.identity == .qa)
    #expect(throws: RuntimeEnvironmentError.packageMarkerRequired("qa")) {
        try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: ["ZOID_COACH_PACKAGE_MODE": "qa"],
            packagedRuntime: nil
        )
    }
    #expect(throws: RuntimeEnvironmentError.signedExecutableRequiresPackageMarker(
        RuntimeIdentity.qa.agentSigningIdentifier
    )) {
        try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: [:],
            packagedRuntime: nil,
            executableSigningIdentifier: RuntimeIdentity.qa.agentSigningIdentifier
        )
    }
}

@Test
func runtimeIdentityExactlyMatchesPackageIdentityManifest() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("App/PackageIdentities.plist"))
    let manifest = try #require(
        try PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: [String: String]]
    )

    try assertIdentity(RuntimeIdentity.production, equals: #require(manifest["production"]))
    try assertIdentity(RuntimeIdentity.qa, equals: #require(manifest["qa"]))
}

@Test
func qaRuntimeIdentityDoesNotCollideWithAnyProductionIdentity() throws {
    let environment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", "/tmp/zoid-qa/identity-noncollision"],
        processEnvironment: [:]
    ).environment
    let production = RuntimeIdentity.production
    let qa = environment.identity
    let productionValues = Set([
        production.appBundleIdentifier,
        production.appSigningIdentifier,
        production.appExecutableName,
        production.appDisplayName,
        production.agentBundleIdentifier,
        production.agentSigningIdentifier,
        production.agentExecutableName,
        production.launchAgentLabel,
        production.launchAgentPlistName,
        production.machServiceName,
        production.notification.promptRequestPrefix,
        production.notification.promptActionPrefix,
        production.notification.wakeRequestPrefix,
        production.notification.wakeCategoryIdentifier,
        production.notification.proactiveRequestPrefix,
        production.notification.promptCategoryPrefix,
        production.notification.actionRequestPrefix,
    ])
    let qaValues = Set([
        qa.appBundleIdentifier,
        qa.appSigningIdentifier,
        qa.appExecutableName,
        qa.appDisplayName,
        qa.agentBundleIdentifier,
        qa.agentSigningIdentifier,
        qa.agentExecutableName,
        qa.launchAgentLabel,
        qa.launchAgentPlistName,
        qa.machServiceName,
        qa.notification.promptRequestPrefix,
        qa.notification.promptActionPrefix,
        qa.notification.wakeRequestPrefix,
        qa.notification.wakeCategoryIdentifier,
        qa.notification.proactiveRequestPrefix,
        qa.notification.promptCategoryPrefix,
        qa.notification.actionRequestPrefix,
    ])

    #expect(productionValues.isDisjoint(with: qaValues))
    #expect(qa.allowedXPCSigningIdentifiers == [
        "qa.ziadnasreldin.ZoidCoach",
        "qa.ziadnasreldin.ZoidCoach.agent",
    ])
    #expect(qaValues.allSatisfy { !$0.contains("com.ziadnasreldin.ZoidCoach") })
}

@Test
func qaRuntimeEnvironmentRejectsAnyPathOutsideRunRoot() {
    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: [
                "--qa-run-root", "/tmp/zoid-qa/run-42",
                "--database", "/tmp/zoid-coach.sqlite"
            ],
            processEnvironment: [:]
        )
    }

    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: [
                "--qa-run-root", "/tmp/zoid-qa/run-42",
                "--screenwatch-directory", "/tmp/zoid-qa/run-42/../shared-screenwatch"
            ],
            processEnvironment: [:]
        )
    }
}

@Test
func runtimeArgumentsOverrideEnvironmentAndLeaveAgentArgumentsUntouched() throws {
    let resolution = try RuntimeEnvironment.resolve(
        arguments: [
            "--database", "/tmp/from-argument.sqlite",
            "--screenwatch-directory", "/tmp/from-argument-screenwatch",
            "--draft-plan"
        ],
        processEnvironment: [
            "ZOID_COACH_DATABASE": "/tmp/from-environment.sqlite",
            "ZOID_COACH_SCREENWATCH_DIRECTORY": "/tmp/from-environment-screenwatch",
            "ZOID_COACH_APP_SUPPORT_ROOT": "/tmp/support",
            "ZOID_COACH_EXPORT_ROOT": "/tmp/exports",
            "ZOID_COACH_USER_DEFAULTS_SUITE": "com.example.zoid-tests",
            "ZOID_COACH_KEYCHAIN_SERVICE_SUFFIX": ".tests"
        ]
    )

    #expect(resolution.environment.databaseURL.path == "/tmp/from-argument.sqlite")
    #expect(resolution.environment.screenwatchDirectory.path == "/tmp/from-argument-screenwatch")
    #expect(resolution.environment.applicationSupportRoot.path == "/tmp/support")
    #expect(resolution.environment.exportRoot.path == "/tmp/exports")
    #expect(resolution.environment.userDefaultsSuiteName == "com.example.zoid-tests")
    #expect(resolution.environment.keychainServiceSuffix == ".tests")
    #expect(resolution.remainingArguments == ["--draft-plan"])
}

@Test
func runtimeParsingReportsMissingValues() {
    #expect(throws: RuntimeEnvironmentError.missingValue("--qa-run-root")) {
        try RuntimeEnvironment.resolve(arguments: ["--qa-run-root"], processEnvironment: [:])
    }

    #expect(throws: RuntimeEnvironmentError.qaRunRootMustBeAbsolute("relative/run")) {
        try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", "relative/run"],
            processEnvironment: [:]
        )
    }
}

private struct PackagedRuntimeFixture {
    let container: URL
    let executableURL: URL
    let qaRunRoot: URL
}

private func packagedRuntimeFixture(mode: RuntimePackageMode) throws -> PackagedRuntimeFixture {
    let container = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-packaged-runtime-\(UUID().uuidString)", isDirectory: true)
        .resolvingSymlinksInPath()
    let appURL = container.appendingPathComponent("Zoid 666 QA.app", isDirectory: true)
    let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
    let executableURL = contents.appendingPathComponent("MacOS/ZoidCoachAgentQA")
    let qaRunRoot = container.appendingPathComponent("qa-runtime", isDirectory: true)
    try FileManager.default.createDirectory(
        at: executableURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data().write(to: executableURL)
    var info: [String: Any] = [
        "CFBundleIdentifier": mode == .qa
            ? RuntimeIdentity.qa.appBundleIdentifier
            : RuntimeIdentity.production.appBundleIdentifier,
        "ZoidCoachPackageMode": mode.rawValue,
        "LSEnvironment": ["ZOID_COACH_PACKAGE_MODE": mode.rawValue],
    ]
    if mode == .qa {
        info["ZoidCoachQARunRoot"] = qaRunRoot.path
        info["LSEnvironment"] = [
            "ZOID_COACH_PACKAGE_MODE": mode.rawValue,
            "ZOID_COACH_QA_RUN_ROOT": qaRunRoot.path,
        ]
    }
    let plist = try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    )
    try plist.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    return PackagedRuntimeFixture(
        container: container,
        executableURL: executableURL,
        qaRunRoot: qaRunRoot
    )
}

private func assertIdentity(
    _ identity: RuntimeIdentity,
    equals manifest: [String: String]
) {
    #expect(manifest["appBundleIdentifier"] == identity.appBundleIdentifier)
    #expect(manifest["appSigningIdentifier"] == identity.appSigningIdentifier)
    #expect(manifest["appExecutableName"] == identity.appExecutableName)
    #expect(manifest["appDisplayName"] == identity.appDisplayName)
    #expect(manifest["agentBundleIdentifier"] == identity.agentBundleIdentifier)
    #expect(manifest["agentSigningIdentifier"] == identity.agentSigningIdentifier)
    #expect(manifest["agentExecutableName"] == identity.agentExecutableName)
    #expect(manifest["launchAgentLabel"] == identity.launchAgentLabel)
    #expect(manifest["launchAgentPlistName"] == identity.launchAgentPlistName)
    #expect(manifest["machServiceName"] == identity.machServiceName)
    #expect(manifest["promptRequestPrefix"] == identity.notification.promptRequestPrefix)
    #expect(manifest["promptActionPrefix"] == identity.notification.promptActionPrefix)
    #expect(manifest["promptCategoryPrefix"] == identity.notification.promptCategoryPrefix)
    #expect(manifest["wakeRequestPrefix"] == identity.notification.wakeRequestPrefix)
    #expect(manifest["wakeCategoryIdentifier"] == identity.notification.wakeCategoryIdentifier)
    #expect(manifest["proactiveRequestPrefix"] == identity.notification.proactiveRequestPrefix)
    #expect(manifest["actionRequestPrefix"] == identity.notification.actionRequestPrefix)
}
