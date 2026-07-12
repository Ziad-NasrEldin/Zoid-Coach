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
