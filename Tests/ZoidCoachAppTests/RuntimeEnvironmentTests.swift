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
    #expect(environment.databaseURL.path == "/Users/tester/Library/Application Support/Zoid Coach/zoid-coach.sqlite")
    #expect(environment.screenwatchDirectory.path == "/Users/tester/screenwatch/days")
    #expect(environment.applicationSupportRoot.path == "/Users/tester/Library/Application Support")
    #expect(environment.exportRoot.path == "/Users/tester/Library/Application Support/Zoid Coach/Diagnostics")
    #expect(environment.userDefaultsSuiteName == nil)
    #expect(environment.keychainServiceSuffix.isEmpty)
}

@Test
func qaRuntimeEnvironmentDerivesEveryWritableLocationFromRunRoot() throws {
    let resolution = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", "/tmp/zoid-qa/run-42", "--once"],
        processEnvironment: [:]
    )

    #expect(resolution.environment.mode == .qa(runRoot: URL(fileURLWithPath: "/tmp/zoid-qa/run-42", isDirectory: true)))
    #expect(resolution.environment.databaseURL.path == "/tmp/zoid-qa/run-42/Application Support/Zoid Coach/zoid-coach.sqlite")
    #expect(resolution.environment.screenwatchDirectory.path == "/tmp/zoid-qa/run-42/Screenwatch/days")
    #expect(resolution.environment.applicationSupportRoot.path == "/tmp/zoid-qa/run-42/Application Support")
    #expect(resolution.environment.exportRoot.path == "/tmp/zoid-qa/run-42/Exports")
    #expect(resolution.environment.userDefaultsSuiteName?.hasPrefix("com.ziadnasreldin.ZoidCoach.qa.") == true)
    #expect(resolution.environment.keychainServiceSuffix.hasPrefix(".qa."))
    #expect(resolution.remainingArguments == ["--once"])
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
