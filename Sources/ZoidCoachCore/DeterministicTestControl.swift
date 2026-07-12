import Foundation

public struct ZoidClock: Sendable {
    private let nowProvider: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date) {
        nowProvider = now
    }

    public func now() -> Date {
        nowProvider()
    }

    public static var system: Self {
        Self(now: Date.init)
    }

    public static func fixed(_ instant: Date) -> Self {
        Self(now: { instant })
    }
}

public struct QAFixtureWorkspace: Equatable, Sendable {
    public let root: URL
    public let environment: RuntimeEnvironment

    public var databaseURL: URL { environment.databaseURL }
    public var applicationSupportRoot: URL { environment.applicationSupportRoot }
    public var screenwatchDirectory: URL { environment.screenwatchDirectory }
    public var exportRoot: URL { environment.exportRoot }
    public var launchArguments: [String] { ["--qa-run-root", root.path] }

    public init(runtimeEnvironment: RuntimeEnvironment) throws {
        guard case let .qa(runRoot) = runtimeEnvironment.mode else {
            throw QAFixtureWorkspaceError.productionEnvironmentRefused
        }
        root = runRoot
        environment = runtimeEnvironment
    }

    init(root: URL, environment: RuntimeEnvironment) {
        self.root = root
        self.environment = environment
    }
}

public struct QAFixtureWorkspaceBuilder {
    private let qaRunRoot: URL
    private let fixturesRoot: URL
    private let fileManager: FileManager

    public init(
        environment: RuntimeEnvironment,
        additionalProtectedRoots: [URL] = [],
        fileManager: FileManager = .default
    ) throws {
        guard case let .qa(runRoot) = environment.mode else {
            throw QAFixtureWorkspaceError.productionEnvironmentRefused
        }
        let canonicalRunRoot = Self.canonicalizingExistingAncestor(
            of: runRoot,
            fileManager: fileManager
        )
        let production = RuntimeEnvironment.production()
        let productionRoots = [
            production.applicationSupportRoot,
            production.databaseURL.deletingLastPathComponent(),
            production.screenwatchDirectory.deletingLastPathComponent()
        ] + additionalProtectedRoots
        guard !productionRoots.contains(where: {
            Self.pathsOverlap(canonicalRunRoot, $0, fileManager: fileManager)
        }) else {
            throw QAFixtureWorkspaceError.productionRootRefused(path: canonicalRunRoot.path)
        }
        qaRunRoot = canonicalRunRoot
        fixturesRoot = qaRunRoot.appendingPathComponent("Fixtures", isDirectory: true)
        self.fileManager = fileManager
    }

    public func prepare(fixtureID: String) throws -> QAFixtureWorkspace {
        guard Self.isValidFixtureID(fixtureID) else {
            throw QAFixtureWorkspaceError.invalidFixtureID(fixtureID)
        }
        let root = fixturesRoot
            .appendingPathComponent(fixtureID, isDirectory: true)
            .standardizedFileURL
        try validate(root)

        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }

        let environment = try RuntimeEnvironment.resolve(
            arguments: ["--qa-run-root", root.path],
            processEnvironment: [:]
        ).environment
        for directory in [
            environment.applicationSupportRoot,
            environment.screenwatchDirectory,
            environment.exportRoot
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return QAFixtureWorkspace(root: root, environment: environment)
    }

    public func cleanup(_ workspace: QAFixtureWorkspace) throws {
        try validate(workspace.root)
        let workspaceParent = Self.canonicalizingExistingAncestor(
            of: workspace.root.deletingLastPathComponent(),
            fileManager: fileManager
        )
        let canonicalFixturesRoot = Self.canonicalizingExistingAncestor(
            of: fixturesRoot,
            fileManager: fileManager
        )
        guard workspaceParent == canonicalFixturesRoot else {
            throw QAFixtureWorkspaceError.workspaceOutsideQARunRoot(
                path: workspace.root.path,
                runRoot: qaRunRoot.path
            )
        }
        if fileManager.fileExists(atPath: workspace.root.path) {
            try fileManager.removeItem(at: workspace.root)
        }
    }

    private func validate(_ workspaceRoot: URL) throws {
        let rootPath = qaRunRoot.path
        let candidatePath = Self.canonicalizingExistingAncestor(
            of: workspaceRoot,
            fileManager: fileManager
        ).path
        guard candidatePath.hasPrefix(rootPath + "/") else {
            throw QAFixtureWorkspaceError.workspaceOutsideQARunRoot(
                path: candidatePath,
                runRoot: rootPath
            )
        }
    }

    private static func isValidFixtureID(_ fixtureID: String) -> Bool {
        guard !fixtureID.isEmpty, fixtureID.count <= 128 else { return false }
        return fixtureID.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (97 ... 122).contains(value)
                || (48 ... 57).contains(value)
                || value == 45
                || value == 95
        }
    }

    private static func pathsOverlap(
        _ first: URL,
        _ second: URL,
        fileManager: FileManager
    ) -> Bool {
        let first = canonicalizingExistingAncestor(of: first, fileManager: fileManager)
        let second = canonicalizingExistingAncestor(of: second, fileManager: fileManager)
        return contains(first, in: second) || contains(second, in: first)
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = candidate.path
        let rootPath = root.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func canonicalizingExistingAncestor(
        of url: URL,
        fileManager: FileManager
    ) -> URL {
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []

        while !fileManager.fileExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            missingComponents.append(existingAncestor.lastPathComponent)
            existingAncestor = parent
        }

        var canonical = existingAncestor
            .resolvingSymlinksInPath()
            .standardizedFileURL
        for component in missingComponents.reversed() {
            canonical.appendPathComponent(component)
        }
        return canonical.standardizedFileURL
    }
}

public enum QAFixtureWorkspaceError: LocalizedError, Equatable {
    case productionEnvironmentRefused
    case productionRootRefused(path: String)
    case invalidFixtureID(String)
    case workspaceOutsideQARunRoot(path: String, runRoot: String)

    public var errorDescription: String? {
        switch self {
        case .productionEnvironmentRefused:
            "Fixture workspaces require an explicitly isolated QA runtime environment"
        case let .productionRootRefused(path):
            "Fixture workspaces refuse production storage roots: \(path)"
        case let .invalidFixtureID(fixtureID):
            "Fixture ID contains unsupported characters: \(fixtureID)"
        case let .workspaceOutsideQARunRoot(path, runRoot):
            "Fixture workspace \(path) is outside QA run root \(runRoot)"
        }
    }
}
