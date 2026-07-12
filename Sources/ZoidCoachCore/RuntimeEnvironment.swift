import Foundation

public struct RuntimeNotificationIdentity: Equatable, Sendable {
    public let promptRequestPrefix: String
    public let promptActionPrefix: String
    public let promptCategoryPrefix: String
    public let wakeRequestPrefix: String
    public let wakeCategoryIdentifier: String
    public let proactiveRequestPrefix: String
    public let actionRequestPrefix: String

    public func promptCategoryIdentifier(_ baseIdentifier: String) -> String {
        guard !promptCategoryPrefix.isEmpty,
              !baseIdentifier.hasPrefix(promptCategoryPrefix) else { return baseIdentifier }
        promptCategoryPrefix + baseIdentifier
    }
}

public struct RuntimeIdentity: Equatable, Sendable {
    public let appBundleIdentifier: String
    public let appSigningIdentifier: String
    public let appExecutableName: String
    public let appDisplayName: String
    public let agentBundleIdentifier: String
    public let agentSigningIdentifier: String
    public let agentExecutableName: String
    public let launchAgentLabel: String
    public let launchAgentPlistName: String
    public let machServiceName: String
    public let notification: RuntimeNotificationIdentity

    public var allowedXPCSigningIdentifiers: Set<String> {
        [appSigningIdentifier, agentSigningIdentifier]
    }

    public static let production = Self(
        appBundleIdentifier: "com.ziadnasreldin.ZoidCoach",
        appSigningIdentifier: "com.ziadnasreldin.ZoidCoach",
        appExecutableName: "ZoidCoach",
        appDisplayName: "Zoid Coach",
        agentBundleIdentifier: "com.ziadnasreldin.ZoidCoach.agent",
        agentSigningIdentifier: "com.ziadnasreldin.ZoidCoach.agent",
        agentExecutableName: "ZoidCoachAgent",
        launchAgentLabel: "com.ziadnasreldin.ZoidCoach.agent",
        launchAgentPlistName: "com.ziadnasreldin.ZoidCoach.agent.plist",
        machServiceName: "com.ziadnasreldin.ZoidCoach.agent",
        notification: RuntimeNotificationIdentity(
            promptRequestPrefix: "zoid.prompt.",
            promptActionPrefix: "ZOID_PROMPT_",
            promptCategoryPrefix: "",
            wakeRequestPrefix: "zoid-coach.wake.",
            wakeCategoryIdentifier: "ZOID_WAKE",
            proactiveRequestPrefix: "zoid-proactive-",
            actionRequestPrefix: ""
        )
    )

    public static let qa = Self(
        appBundleIdentifier: "qa.ziadnasreldin.ZoidCoach",
        appSigningIdentifier: "qa.ziadnasreldin.ZoidCoach",
        appExecutableName: "ZoidCoachQA",
        appDisplayName: "Zoid Coach QA",
        agentBundleIdentifier: "qa.ziadnasreldin.ZoidCoach.agent",
        agentSigningIdentifier: "qa.ziadnasreldin.ZoidCoach.agent",
        agentExecutableName: "ZoidCoachAgentQA",
        launchAgentLabel: "qa.ziadnasreldin.ZoidCoach.agent",
        launchAgentPlistName: "qa.ziadnasreldin.ZoidCoach.agent.plist",
        machServiceName: "qa.ziadnasreldin.ZoidCoach.agent",
        notification: RuntimeNotificationIdentity(
            promptRequestPrefix: "zcqa.prompt.",
            promptActionPrefix: "ZCQA_PROMPT_",
            promptCategoryPrefix: "ZCQA_",
            wakeRequestPrefix: "zcqa.wake.",
            wakeCategoryIdentifier: "ZCQA_WAKE",
            proactiveRequestPrefix: "zcqa-proactive-",
            actionRequestPrefix: "zcqa.action."
        )
    )
}

public struct RuntimeEnvironment: Equatable, Sendable {
    public static let productionUserDefaultsDomain = "com.ziadnasreldin.ZoidCoach"

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
    public let identity: RuntimeIdentity

    public var nativeCaptureConfigurationURL: URL {
        applicationSupportRoot
            .appendingPathComponent("Zoid Coach/native-capture-config.json", isDirectory: false)
    }

    public var nativeCaptureDaysDirectory: URL {
        applicationSupportRoot
            .appendingPathComponent("Zoid Coach/native-capture/days", isDirectory: true)
    }

    public func makeUserDefaults() -> UserDefaults {
        guard let userDefaultsSuiteName else { return .standard }
        guard let defaults = UserDefaults(suiteName: userDefaultsSuiteName) else {
            fatalError("Could not open isolated UserDefaults suite \(userDefaultsSuiteName)")
        }
        return defaults
    }

    public func keychainService(base: String) -> String {
        base + keychainServiceSuffix
    }

    public func validatedWritableURL(_ url: URL, name: String) throws -> URL {
        guard case let .qa(runRoot) = mode else { return url }
        let canonical = Self.canonicalURL(url)
        guard Self.contains(canonical, in: runRoot) else {
            throw RuntimeEnvironmentError.pathOutsideQARunRoot(
                name: name,
                path: canonical.path,
                runRoot: runRoot.path
            )
        }
        return canonical
    }

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
            keychainServiceSuffix: "",
            identity: .production
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
            try validateQARunRoot(runRoot, directories: directories)
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
                keychainServiceSuffix: ".qa.\(identifier)",
                identity: .qa
            )
        } else {
            mode = .production
            defaults = .production(directories: directories)
        }

        let userDefaultsSuiteName: String?
        let keychainServiceSuffix: String
        if case .qa = mode {
            if values.userDefaultsSuiteName == Self.productionUserDefaultsDomain {
                throw RuntimeEnvironmentError.productionIdentityInQA(
                    name: "UserDefaults suite",
                    value: Self.productionUserDefaultsDomain
                )
            }
            if let requested = values.userDefaultsSuiteName,
               requested != defaults.userDefaultsSuiteName {
                throw RuntimeEnvironmentError.qaIdentityOverrideNotAllowed(
                    name: "UserDefaults suite"
                )
            }
            if let requested = values.keychainServiceSuffix,
               requested != defaults.keychainServiceSuffix {
                throw RuntimeEnvironmentError.qaIdentityOverrideNotAllowed(
                    name: "Keychain service suffix"
                )
            }
            userDefaultsSuiteName = defaults.userDefaultsSuiteName
            keychainServiceSuffix = defaults.keychainServiceSuffix
        } else {
            userDefaultsSuiteName = try optionalNonempty(values.userDefaultsSuiteName)
                ?? defaults.userDefaultsSuiteName
            keychainServiceSuffix = try optionalNonempty(values.keychainServiceSuffix)
                ?? defaults.keychainServiceSuffix
        }

        let resolved = Self(
            mode: mode,
            databaseURL: values.databaseURL.map { canonicalURL($0, isDirectory: false) } ?? defaults.databaseURL,
            screenwatchDirectory: values.screenwatchDirectory.map { canonicalURL($0, isDirectory: true) } ?? defaults.screenwatchDirectory,
            applicationSupportRoot: values.applicationSupportRoot.map { canonicalURL($0, isDirectory: true) } ?? defaults.applicationSupportRoot,
            exportRoot: values.exportRoot.map { canonicalURL($0, isDirectory: true) } ?? defaults.exportRoot,
            userDefaultsSuiteName: userDefaultsSuiteName,
            keychainServiceSuffix: keychainServiceSuffix,
            identity: defaults.identity
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
            var resolvedProcessEnvironment = processEnvironment
            if resolvedProcessEnvironment["ZOID_COACH_QA_RUN_ROOT"] == nil,
               Bundle.main.object(forInfoDictionaryKey: "ZoidCoachPackageMode") as? String == "qa",
               let packagedRunRoot = Bundle.main.object(
                   forInfoDictionaryKey: "ZoidCoachQARunRoot"
               ) as? String {
                resolvedProcessEnvironment["ZOID_COACH_QA_RUN_ROOT"] = packagedRunRoot
            }
            return try resolve(
                arguments: arguments,
                processEnvironment: resolvedProcessEnvironment,
                directories: directories
            ).environment
        } catch {
            fatalError("Zoid Coach runtime environment is invalid: \(error.localizedDescription)")
        }
    }

    private func validateIsolation() throws {
        guard case let .qa(runRoot) = mode else { return }
        if userDefaultsSuiteName == Self.productionUserDefaultsDomain {
            throw RuntimeEnvironmentError.productionIdentityInQA(
                name: "UserDefaults suite",
                value: Self.productionUserDefaultsDomain
            )
        }
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
        let rootPath = canonicalURL(root).path
        let candidatePath = canonicalURL(candidate).path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func validateQARunRoot(
        _ runRoot: URL,
        directories: SystemDirectories
    ) throws {
        let actualDirectories = SystemDirectories.current()
        let protectedPaths = protectedProductionRoots(actualDirectories)
            + (directories == actualDirectories ? [] : protectedProductionRoots(directories))
        for protectedPath in protectedPaths {
            if contains(runRoot, in: protectedPath) || contains(protectedPath, in: runRoot) {
                throw RuntimeEnvironmentError.qaRunRootOverlapsProductionPath(
                    runRoot: runRoot.path,
                    productionPath: protectedPath.path
                )
            }
        }
    }

    private static func protectedProductionRoots(
        _ directories: SystemDirectories
    ) -> [URL] {
        [
            directories.home.appendingPathComponent("screenwatch", isDirectory: true),
            directories.home.appendingPathComponent("Library", isDirectory: true),
            directories.applicationSupport,
        ].map(canonicalURL)
    }

    private static func canonicalURL(_ path: String, isDirectory: Bool) -> URL {
        canonicalURL(URL(fileURLWithPath: path, isDirectory: isDirectory))
    }

    private static func canonicalURL(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        var existingAncestor = standardized
        var missingComponents: [String] = []
        while !FileManager.default.fileExists(atPath: existingAncestor.path),
              existingAncestor.path != "/" {
            missingComponents.insert(existingAncestor.lastPathComponent, at: 0)
            existingAncestor.deleteLastPathComponent()
        }
        var resolved = existingAncestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents {
            resolved.appendPathComponent(component)
        }
        return URL(
            fileURLWithPath: resolved.standardizedFileURL.path,
            isDirectory: url.hasDirectoryPath
        )
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
    case qaRunRootOverlapsProductionPath(runRoot: String, productionPath: String)
    case pathOutsideQARunRoot(name: String, path: String, runRoot: String)
    case productionIdentityInQA(name: String, value: String)
    case qaIdentityOverrideNotAllowed(name: String)
    case emptyIdentifier

    public var errorDescription: String? {
        switch self {
        case let .missingValue(argument):
            "Missing value for \(argument)"
        case let .qaRunRootMustBeAbsolute(path):
            "QA run root must be an absolute path: \(path)"
        case let .qaRunRootOverlapsProductionPath(runRoot, productionPath):
            "QA run root \(runRoot) overlaps production path \(productionPath)"
        case let .pathOutsideQARunRoot(name, path, runRoot):
            "QA \(name) path \(path) is outside run root \(runRoot)"
        case let .productionIdentityInQA(name, value):
            "QA \(name) cannot use production identity \(value)"
        case let .qaIdentityOverrideNotAllowed(name):
            "QA \(name) is derived from the run root and cannot be overridden"
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
