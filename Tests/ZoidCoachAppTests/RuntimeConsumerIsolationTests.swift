import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore
import ZoidCoachInfrastructure

@Test
func productionRuntimeConsumersKeepExistingPathsAndIdentities() throws {
    let runtimeEnvironment = RuntimeEnvironment.production(
        directories: .init(
            home: URL(fileURLWithPath: "/Users/tester", isDirectory: true),
            applicationSupport: URL(
                fileURLWithPath: "/Users/tester/Library/Application Support",
                isDirectory: true
            )
        )
    )

    #expect(runtimeEnvironment.makeUserDefaults() === UserDefaults.standard)
    #expect(GeminiAPIKeyStore.serviceName(runtimeEnvironment: runtimeEnvironment) == GeminiAPIKeyStore.service)
    #expect(LocalEvidenceCipher.serviceName(runtimeEnvironment: runtimeEnvironment) == LocalEvidenceCipher.service)
    #expect(
        runtimeEnvironment.nativeCaptureConfigurationURL.path
            == "/Users/tester/Library/Application Support/Zoid Coach/native-capture-config.json"
    )
    #expect(
        runtimeEnvironment.nativeCaptureDaysDirectory.path
            == "/Users/tester/Library/Application Support/Zoid Coach/native-capture/days"
    )
    #expect(
        NativeCaptureConfigurationStore.defaultURL(runtimeEnvironment: runtimeEnvironment)
            == runtimeEnvironment.nativeCaptureConfigurationURL
    )
    let explicitNativePath = URL(
        fileURLWithPath: "/tmp/zoid-production-native/../capture",
        isDirectory: true
    )
    #expect(
        try runtimeEnvironment.validatedWritableURL(
            explicitNativePath,
            name: "native capture"
        ) == explicitNativePath
    )
}

@Test
func qaRuntimeConsumersUseOnlyRunSpecificSuitesServicesAndPaths() throws {
    let runRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-runtime-consumers-\(UUID().uuidString)", isDirectory: true)
    let runtimeEnvironment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", runRoot.path],
        processEnvironment: [:]
    ).environment
    let defaultsKey = "RuntimeIsolation-\(UUID().uuidString)"
    let qaDefaults = runtimeEnvironment.makeUserDefaults()
    defer {
        qaDefaults.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        try? FileManager.default.removeItem(at: runRoot)
    }

    qaDefaults.set("qa-only", forKey: defaultsKey)

    #expect(qaDefaults.string(forKey: defaultsKey) == "qa-only")
    #expect(UserDefaults.standard.object(forKey: defaultsKey) == nil)
    #expect(GeminiAPIKeyStore.serviceName(runtimeEnvironment: runtimeEnvironment) != GeminiAPIKeyStore.service)
    #expect(LocalEvidenceCipher.serviceName(runtimeEnvironment: runtimeEnvironment) != LocalEvidenceCipher.service)
    #expect(GeminiAPIKeyStore.serviceName(runtimeEnvironment: runtimeEnvironment).hasSuffix(runtimeEnvironment.keychainServiceSuffix))
    #expect(LocalEvidenceCipher.serviceName(runtimeEnvironment: runtimeEnvironment).hasSuffix(runtimeEnvironment.keychainServiceSuffix))
    #expect(runtimeEnvironment.nativeCaptureConfigurationURL.path.hasPrefix(runRoot.path + "/"))
    #expect(runtimeEnvironment.nativeCaptureDaysDirectory.path.hasPrefix(runRoot.path + "/"))
    #expect(runtimeEnvironment.exportRoot.path.hasPrefix(runRoot.path + "/"))
    #expect(
        try runtimeEnvironment.validatedWritableURL(
            runtimeEnvironment.nativeCaptureDaysDirectory,
            name: "native capture"
        ) == runtimeEnvironment.nativeCaptureDaysDirectory
    )
    #expect(throws: RuntimeEnvironmentError.self) {
        try runtimeEnvironment.validatedWritableURL(
            URL(fileURLWithPath: "/tmp/production-native-capture", isDirectory: true),
            name: "native capture"
        )
    }
}

@Test
func separateQARunsUseDifferentPreferencesAndKeychainIdentities() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-two-run-isolation-\(UUID().uuidString)", isDirectory: true)
    let first = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", base.appendingPathComponent("first").path],
        processEnvironment: [:]
    ).environment
    let second = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", base.appendingPathComponent("second").path],
        processEnvironment: [:]
    ).environment
    let key = "shared-test-key"
    let firstDefaults = first.makeUserDefaults()
    let secondDefaults = second.makeUserDefaults()
    defer {
        firstDefaults.removeObject(forKey: key)
        secondDefaults.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: base)
    }

    firstDefaults.set("first", forKey: key)

    #expect(first.userDefaultsSuiteName != second.userDefaultsSuiteName)
    #expect(first.keychainServiceSuffix != second.keychainServiceSuffix)
    #expect(secondDefaults.object(forKey: key) == nil)
    #expect(
        GeminiAPIKeyStore.serviceName(runtimeEnvironment: first)
            != GeminiAPIKeyStore.serviceName(runtimeEnvironment: second)
    )
    #expect(
        LocalEvidenceCipher.serviceName(runtimeEnvironment: first)
            != LocalEvidenceCipher.serviceName(runtimeEnvironment: second)
    )
}

@Test
func qaRuntimeRejectsPreferenceAndKeychainIdentityOverrides() {
    #expect(throws: RuntimeEnvironmentError.qaIdentityOverrideNotAllowed(
        name: "UserDefaults suite"
    )) {
        try RuntimeEnvironment.resolve(
            arguments: [
                "--qa-run-root", "/tmp/zoid-qa/preference-override",
                "--user-defaults-suite", "com.example.shared"
            ],
            processEnvironment: [:]
        )
    }
    #expect(throws: RuntimeEnvironmentError.qaIdentityOverrideNotAllowed(
        name: "Keychain service suffix"
    )) {
        try RuntimeEnvironment.resolve(
            arguments: [
                "--qa-run-root", "/tmp/zoid-qa/keychain-override",
                "--keychain-service-suffix", ".shared"
            ],
            processEnvironment: [:]
        )
    }
    #expect(throws: RuntimeEnvironmentError.qaIdentityOverrideNotAllowed(
        name: "UserDefaults suite"
    )) {
        try RuntimeEnvironment.resolve(
            arguments: [],
            processEnvironment: [
                "ZOID_COACH_QA_RUN_ROOT": "/tmp/zoid-qa/environment-override",
                "ZOID_COACH_USER_DEFAULTS_SUITE": "com.example.environment-shared"
            ]
        )
    }
}

@Test
func injectedDirectoriesCannotReplaceRealProductionScreenwatchProtection() {
    let actual = RuntimeEnvironment.SystemDirectories.current()
    let actualScreenwatch = actual.home.appendingPathComponent("screenwatch", isDirectory: true)
    let fakeRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-fake-system-directories-\(UUID().uuidString)", isDirectory: true)
    let injected = RuntimeEnvironment.SystemDirectories(
        home: fakeRoot,
        applicationSupport: fakeRoot.appendingPathComponent("Application Support", isDirectory: true)
    )

    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: [
                "--qa-run-root",
                actualScreenwatch.appendingPathComponent("qa-run", isDirectory: true).path
            ],
            processEnvironment: [:],
            directories: injected
        )
    }
    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", actual.home.path],
            processEnvironment: [:],
            directories: injected
        )
    }
}

@Test
func qaRuntimeRejectsTheProductionUserDefaultsIdentity() {
    #expect(throws: RuntimeEnvironmentError.productionIdentityInQA(
        name: "UserDefaults suite",
        value: RuntimeEnvironment.productionUserDefaultsDomain
    )) {
        try RuntimeEnvironment.resolve(
            arguments: [
                "--qa-run-root", "/tmp/zoid-qa/identity-test",
                "--user-defaults-suite", RuntimeEnvironment.productionUserDefaultsDomain
            ],
            processEnvironment: [:]
        )
    }
}

@Test
func qaRuntimeRejectsAnExistingParentSymlinkEscape() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-symlink-isolation-\(UUID().uuidString)", isDirectory: true)
    let runRoot = root.appendingPathComponent("run", isDirectory: true)
    let outside = root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let escape = runRoot.appendingPathComponent("escape", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)

    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: [
                "--qa-run-root", runRoot.path,
                "--export-root", escape.appendingPathComponent("exports", isDirectory: true).path
            ],
            processEnvironment: [:]
        )
    }
}

@Test
func qaRuntimeRejectsRootsInsideOrAliasedToTheProductionLibrary() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-production-alias-\(UUID().uuidString)", isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let library = home.appendingPathComponent("Library", isDirectory: true)
    let applicationSupport = library.appendingPathComponent("Application Support", isDirectory: true)
    let alias = root.appendingPathComponent("qa-alias", isDirectory: true)
    try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: library)
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = RuntimeEnvironment.SystemDirectories(
        home: home,
        applicationSupport: applicationSupport
    )

    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", library.appendingPathComponent("qa").path],
            processEnvironment: [:],
            directories: directories
        )
    }
    #expect(throws: RuntimeEnvironmentError.self) {
        try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", alias.path],
            processEnvironment: [:],
            directories: directories
        )
    }
}

@Test
func privacyExportHonorsTheIsolatedRuntimeExportRoot() throws {
    let runRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-runtime-export-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: runRoot) }
    let runtimeEnvironment = try RuntimeEnvironment.resolve(
        arguments: ["--qa-run-root", runRoot.path],
        processEnvironment: [:]
    ).environment
    let service = try PrivacyDataService(
        databaseURL: runtimeEnvironment.databaseURL,
        exportRoot: runtimeEnvironment.exportRoot
    )

    let exportURL = try service.exportRedactedDiagnostics(
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(exportURL.deletingLastPathComponent() == runtimeEnvironment.exportRoot)
    #expect(FileManager.default.fileExists(atPath: exportURL.path))
}
