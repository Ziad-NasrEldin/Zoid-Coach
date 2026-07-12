import Foundation

public struct RuntimeEnvironment: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case production
        case qa(runRoot: URL)
    }

    public struct SystemDirectories: Equatable, Sendable {
        public let home: URL
        public let applicationSupport: URL

        public init(home: URL, applicationSupport: URL) {
            self.home = home
            self.applicationSupport = applicationSupport
        }

        public static func current(fileManager: FileManager = .default) -> Self {
            Self(
                home: fileManager.homeDirectoryForCurrentUser,
                applicationSupport: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            )
        }
    }

    public let mode: Mode
    public let databaseURL: URL
    public let screenwatchDirectory: URL
    public let applicationSupportRoot: URL
    public let exportRoot: URL
    public let userDefaultsSuiteName: String?
    public let keychainServiceSuffix: String

    public static func production(directories: SystemDirectories = .current()) -> Self {
        let applicationSupportRoot = directories.applicationSupport.standardizedFileURL
        let productSupport = applicationSupportRoot.appendingPathComponent("Zoid Coach", isDirectory: true)
        return Self(
            mode: .production,
            databaseURL: ZoidCoachStorage.databaseURL(applicationSupportRoot: applicationSupportRoot),
            screenwatchDirectory: directories.home
                .appendingPathComponent("screenwatch/days", isDirectory: true)
                .standardizedFileURL,
            applicationSupportRoot: applicationSupportRoot,
            exportRoot: productSupport.appendingPathComponent("Diagnostics", isDirectory: true),
            userDefaultsSuiteName: nil,
            keychainServiceSuffix: ""
        )
    }

    public static func resolve(
        arguments: [String],
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        directories: SystemDirectories = .current()
    ) throws -> RuntimeEnvironmentResolution {
        var values = RuntimeValues(processEnvironment: processEnvironment)
        var remainingArguments: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            guard let key = RuntimeArgument(rawValue: argument) else {
                remainingArguments.append(argument)
                index += 1
                continue
            }
            index += 1
            guard index < arguments.count else {
                throw RuntimeEnvironmentError.missingValue(argument)
            }
            values.set(arguments[index], for: key)
            index += 1
        }

        let mode: Mode
        let defaults: Self
        if let runRootValue = values.qaRunRoot {
            guard NSString(string: runRootValue).isAbsolutePath else {
                throw RuntimeEnvironmentError.qaRunRootMustBeAbsolute(runRootValue)
            }
            let runRoot = canonicalURL(runRootValue, isDirectory: true)
            mode = .qa(runRoot: runRoot)
            let identifier = stableIdentifier(for: runRoot.path)
            let applicationSupportRoot = runRoot.appendingPathComponent("Application Support", isDirectory: true)
            defaults = Self(
                mode: mode,
                databaseURL: ZoidCoachStorage.databaseURL(applicationSupportRoot: applicationSupportRoot),
                screenwatchDirectory: runRoot.appendingPathComponent("Screenwatch/days", isDirectory: true),
                applicationSupportRoot: applicationSupportRoot,
                exportRoot: runRoot.appendingPathComponent("Exports", isDirectory: true),
                userDefaultsSuiteName: "com.ziadnasreldin.ZoidCoach.qa.\(identifier)",
                keychainServiceSuffix: ".qa.\(identifier)"
            )
        } else {
            mode = .production
            defaults = .production(directories: directories)
        }

        let resolved = Self(
            mode: mode,
            databaseURL: values.databaseURL.map { canonicalURL($0, isDirectory: false) } ?? defaults.databaseURL,
            screenwatchDirectory: values.screenwatchDirectory.map { canonicalURL($0, isDirectory: true) } ?? defaults.screenwatchDirectory,
            applicationSupportRoot: values.applicationSupportRoot.map { canonicalURL($0, isDirectory: true) } ?? defaults.applicationSupportRoot,
            exportRoot: values.exportRoot.map { canonicalURL($0, isDirectory: true) } ?? defaults.exportRoot,
            userDefaultsSuiteName: try optionalNonempty(values.userDefaultsSuiteName) ?? defaults.userDefaultsSuiteName,
            keychainServiceSuffix: try optionalNonempty(values.keychainServiceSuffix) ?? defaults.keychainServiceSuffix
        )

        try resolved.validateIsolation()
        return RuntimeEnvironmentResolution(environment: resolved, remainingArguments: remainingArguments)
    }

    public static func current(
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        directories: SystemDirectories = .current()
    ) -> Self {
        do {
            return try resolve(
                arguments: arguments,
                processEnvironment: processEnvironment,
                directories: directories
            ).environment
        } catch {
            fatalError("Zoid Coach runtime environment is invalid: \(error.localizedDescription)")
        }
    }

    private func validateIsolation() throws {
        guard case let .qa(runRoot) = mode else { return }
        for (name, url) in [
            ("database", databaseURL),
            ("Screenwatch", screenwatchDirectory),
            ("Application Support", applicationSupportRoot),
            ("export", exportRoot)
        ] {
            guard Self.contains(url, in: runRoot) else {
                throw RuntimeEnvironmentError.pathOutsideQARunRoot(name: name, path: url.path, runRoot: runRoot.path)
            }
        }
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func canonicalURL(_ path: String, isDirectory: Bool) -> URL {
        URL(fileURLWithPath: path, isDirectory: isDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    private static func optionalNonempty(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RuntimeEnvironmentError.emptyIdentifier }
        return trimmed
    }

    private static func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public struct RuntimeEnvironmentResolution: Equatable, Sendable {
    public let environment: RuntimeEnvironment
    public let remainingArguments: [String]

    public init(environment: RuntimeEnvironment, remainingArguments: [String]) {
        self.environment = environment
        self.remainingArguments = remainingArguments
    }
}

public enum RuntimeEnvironmentError: LocalizedError, Equatable {
    case missingValue(String)
    case qaRunRootMustBeAbsolute(String)
    case pathOutsideQARunRoot(name: String, path: String, runRoot: String)
    case emptyIdentifier

    public var errorDescription: String? {
        switch self {
        case let .missingValue(argument):
            "Missing value for \(argument)"
        case let .qaRunRootMustBeAbsolute(path):
            "QA run root must be an absolute path: \(path)"
        case let .pathOutsideQARunRoot(name, path, runRoot):
            "QA \(name) path \(path) is outside run root \(runRoot)"
        case .emptyIdentifier:
            "Runtime identifiers cannot be empty"
        }
    }
}

private enum RuntimeArgument: String {
    case qaRunRoot = "--qa-run-root"
    case databaseURL = "--database"
    case screenwatchDirectory = "--screenwatch-directory"
    case applicationSupportRoot = "--app-support-root"
    case exportRoot = "--export-root"
    case userDefaultsSuiteName = "--user-defaults-suite"
    case keychainServiceSuffix = "--keychain-service-suffix"
}

private struct RuntimeValues {
    var qaRunRoot: String?
    var databaseURL: String?
    var screenwatchDirectory: String?
    var applicationSupportRoot: String?
    var exportRoot: String?
    var userDefaultsSuiteName: String?
    var keychainServiceSuffix: String?

    init(processEnvironment: [String: String]) {
        qaRunRoot = processEnvironment["ZOID_COACH_QA_RUN_ROOT"]
        databaseURL = processEnvironment["ZOID_COACH_DATABASE"]
        screenwatchDirectory = processEnvironment["ZOID_COACH_SCREENWATCH_DIRECTORY"]
        applicationSupportRoot = processEnvironment["ZOID_COACH_APP_SUPPORT_ROOT"]
        exportRoot = processEnvironment["ZOID_COACH_EXPORT_ROOT"]
        userDefaultsSuiteName = processEnvironment["ZOID_COACH_USER_DEFAULTS_SUITE"]
        keychainServiceSuffix = processEnvironment["ZOID_COACH_KEYCHAIN_SERVICE_SUFFIX"]
    }

    mutating func set(_ value: String, for argument: RuntimeArgument) {
        switch argument {
        case .qaRunRoot: qaRunRoot = value
        case .databaseURL: databaseURL = value
        case .screenwatchDirectory: screenwatchDirectory = value
        case .applicationSupportRoot: applicationSupportRoot = value
        case .exportRoot: exportRoot = value
        case .userDefaultsSuiteName: userDefaultsSuiteName = value
        case .keychainServiceSuffix: keychainServiceSuffix = value
        }
    }
}
