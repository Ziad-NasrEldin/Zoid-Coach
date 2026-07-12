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
}

public struct QAFixtureWorkspaceBuilder {
    private let qaRunRoot: URL
    private let fixturesRoot: URL
    private let fileManager: FileManager

    public init(
        environment: RuntimeEnvironment,
        productionDirectories: RuntimeEnvironment.SystemDirectories = .current(),
        fileManager: FileManager = .default
    ) throws {
        guard case let .qa(runRoot) = environment.mode else {
            throw QAFixtureWorkspaceError.productionEnvironmentRefused
        }
        let canonicalRunRoot = runRoot.resolvingSymlinksInPath().standardizedFileURL
        let production = RuntimeEnvironment.production(directories: productionDirectories)
        let productionRoots = [
            production.applicationSupportRoot,
            production.databaseURL.deletingLastPathComponent(),
            production.screenwatchDirectory.deletingLastPathComponent()
        ]
        guard !productionRoots.contains(where: { Self.contains(canonicalRunRoot, in: $0) }) else {
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
        guard workspace.root.deletingLastPathComponent().standardizedFileURL == fixturesRoot else {
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
        let candidatePath = workspaceRoot
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard candidatePath.hasPrefix(rootPath + "/") else {
            throw QAFixtureWorkspaceError.workspaceOutsideQARunRoot(
                path: candidatePath,
                runRoot: rootPath
            )
        }
    }

    private static func isValidFixtureID(_ fixtureID: String) -> Bool {
        guard !fixtureID.isEmpty, fixtureID.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return fixtureID.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
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
