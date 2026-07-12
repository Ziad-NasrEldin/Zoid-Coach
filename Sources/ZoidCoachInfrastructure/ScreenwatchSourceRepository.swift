import CryptoKit
import Darwin
import Foundation
import ZoidCoachCore

public enum ScreenwatchSourceKind: String, Equatable, Sendable {
    case defaultLocation
    case alternateBookmark
    case nativeCapture
}

public enum ScreenwatchSourceResolutionError: LocalizedError, Equatable, Sendable {
    case invalidBookmark
    case staleBookmark
    case missingDirectory
    case unsafePath
    case outsideQARunRoot
    case securityScopeUnavailable
    case bookmarkStoreCorrupt
    case invalidRelativePath
    case notDirectory
    case notRegularFile
    case ioFailure

    public var errorDescription: String? {
        switch self {
        case .invalidBookmark: "The saved Screenwatch folder authorization is invalid. Choose the folder again."
        case .staleBookmark: "The saved Screenwatch folder authorization is stale. Choose the folder again."
        case .missingDirectory: "The selected Screenwatch folder no longer exists."
        case .unsafePath: "The selected Screenwatch path contains an unsafe symbolic link."
        case .outsideQARunRoot: "The selected Screenwatch folder is outside this isolated QA run."
        case .securityScopeUnavailable: "macOS did not grant access to the selected Screenwatch folder."
        case .bookmarkStoreCorrupt: "The saved Screenwatch folder authorization could not be read safely."
        case .invalidRelativePath: "A Screenwatch child path was rejected."
        case .notDirectory: "The selected Screenwatch item is not a directory."
        case .notRegularFile: "The Screenwatch log is not a regular file."
        case .ioFailure: "The Screenwatch source could not be read safely."
        }
    }
}

public struct ScreenwatchBookmarkResolution: Sendable {
    public let url: URL
    public let isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

public struct ScreenwatchBookmarkAccess: Sendable {
    public let create: @Sendable (URL) throws -> Data
    public let resolve: @Sendable (Data) throws -> ScreenwatchBookmarkResolution
    public let startAccess: @Sendable (URL) -> Bool
    public let stopAccess: @Sendable (URL) -> Void

    public init(
        create: @escaping @Sendable (URL) throws -> Data,
        resolve: @escaping @Sendable (Data) throws -> ScreenwatchBookmarkResolution,
        startAccess: @escaping @Sendable (URL) -> Bool,
        stopAccess: @escaping @Sendable (URL) -> Void
    ) {
        self.create = create
        self.resolve = resolve
        self.startAccess = startAccess
        self.stopAccess = stopAccess
    }

    public static let foundation = Self(
        create: { url in
            try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                relativeTo: nil
            )
        },
        resolve: { data in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return .init(url: url, isStale: isStale)
        },
        startAccess: { $0.startAccessingSecurityScopedResource() },
        stopAccess: { $0.stopAccessingSecurityScopedResource() }
    )
}

public struct ScreenwatchDirectoryEntry: Equatable, Sendable {
    public let name: String
    public let isDirectory: Bool
    public let isRegularFile: Bool
}

public struct ScreenwatchOpenedFile: @unchecked Sendable {
    public let handle: FileHandle
    public let size: UInt64
    public let identity: String
}

public final class ScreenwatchDirectoryLease: @unchecked Sendable {
    public let source: ScreenwatchSourceKind
    public let rootURL: URL
    public let sourceFingerprint: String

    private let rootDescriptor: Int32
    private let stopAccess: (@Sendable () -> Void)?
    private let lock = NSLock()

    public init(
        rootURL: URL,
        source: ScreenwatchSourceKind,
        stopAccess: (@Sendable () -> Void)? = nil
    ) throws {
        guard rootURL.isFileURL, rootURL.path.hasPrefix("/") else {
            throw ScreenwatchSourceResolutionError.unsafePath
        }
        var linkInformation = stat()
        guard lstat(rootURL.path, &linkInformation) == 0 else {
            throw ScreenwatchSourceResolutionError.missingDirectory
        }
        guard linkInformation.st_mode & S_IFMT != S_IFLNK else {
            throw ScreenwatchSourceResolutionError.unsafePath
        }
        let descriptor = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw ScreenwatchSourceResolutionError.missingDirectory }
            if errno == ELOOP { throw ScreenwatchSourceResolutionError.unsafePath }
            throw ScreenwatchSourceResolutionError.notDirectory
        }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR else {
            Darwin.close(descriptor)
            throw ScreenwatchSourceResolutionError.notDirectory
        }
        self.rootDescriptor = descriptor
        self.rootURL = rootURL.standardizedFileURL
        self.source = source
        self.stopAccess = stopAccess
        let fingerprintInput = "\(source.rawValue):\(self.rootURL.resolvingSymlinksInPath().path)"
        self.sourceFingerprint = SHA256.hash(data: Data(fingerprintInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    deinit {
        Darwin.close(rootDescriptor)
        stopAccess?()
    }

    public func entries(in components: [String] = []) throws -> [ScreenwatchDirectoryEntry] {
        try lock.withLock {
            let directory = try openDirectory(components)
            defer { Darwin.close(directory) }
            guard let stream = fdopendir(dup(directory)) else {
                throw ScreenwatchSourceResolutionError.ioFailure
            }
            defer { closedir(stream) }
            var result: [ScreenwatchDirectoryEntry] = []
            while let pointer = readdir(stream) {
                let name = withUnsafePointer(to: &pointer.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                        String(cString: $0)
                    }
                }
                guard name != ".", name != "..", isValidComponent(name) else { continue }
                var information = stat()
                guard fstatat(directory, name, &information, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
                let kind = information.st_mode & S_IFMT
                result.append(.init(
                    name: name,
                    isDirectory: kind == S_IFDIR,
                    isRegularFile: kind == S_IFREG
                ))
            }
            return result
        }
    }

    public func fileExists(_ components: [String]) -> Bool {
        (try? withOpenedFile(components) { _ in true }) ?? false
    }

    public func withOpenedFile<T>(
        _ components: [String],
        _ body: (ScreenwatchOpenedFile) throws -> T
    ) throws -> T {
        try lock.withLock {
            guard let fileName = components.last else {
                throw ScreenwatchSourceResolutionError.invalidRelativePath
            }
            let parent = try openDirectory(Array(components.dropLast()))
            defer { Darwin.close(parent) }
            guard isValidComponent(fileName) else {
                throw ScreenwatchSourceResolutionError.invalidRelativePath
            }
            let descriptor = Darwin.openat(parent, fileName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else {
                if errno == ENOENT { throw ScreenwatchSourceResolutionError.missingDirectory }
                if errno == ELOOP { throw ScreenwatchSourceResolutionError.unsafePath }
                throw ScreenwatchSourceResolutionError.ioFailure
            }
            var information = stat()
            guard fstat(descriptor, &information) == 0,
                  information.st_mode & S_IFMT == S_IFREG else {
                Darwin.close(descriptor)
                throw ScreenwatchSourceResolutionError.notRegularFile
            }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            let opened = ScreenwatchOpenedFile(
                handle: handle,
                size: UInt64(max(0, information.st_size)),
                identity: "\(information.st_dev):\(information.st_ino)"
            )
            return try body(opened)
        }
    }

    public func data(at components: [String], maximumBytes: Int = 8 * 1_024 * 1_024) throws -> Data {
        try withOpenedFile(components) { opened in
            guard opened.size <= UInt64(maximumBytes) else {
                throw ScreenwatchSourceResolutionError.ioFailure
            }
            return try opened.handle.readToEnd() ?? Data()
        }
    }

    public func removeFile(_ components: [String]) throws {
        try lock.withLock {
            guard let fileName = components.last, isValidComponent(fileName) else {
                throw ScreenwatchSourceResolutionError.invalidRelativePath
            }
            let parent = try openDirectory(Array(components.dropLast()))
            defer { Darwin.close(parent) }
            var information = stat()
            guard fstatat(parent, fileName, &information, AT_SYMLINK_NOFOLLOW) == 0,
                  information.st_mode & S_IFMT == S_IFREG else {
                throw ScreenwatchSourceResolutionError.notRegularFile
            }
            guard unlinkat(parent, fileName, 0) == 0 else {
                throw ScreenwatchSourceResolutionError.ioFailure
            }
        }
    }

    private func openDirectory(_ components: [String]) throws -> Int32 {
        var descriptor = dup(rootDescriptor)
        guard descriptor >= 0 else { throw ScreenwatchSourceResolutionError.ioFailure }
        for component in components {
            guard isValidComponent(component) else {
                Darwin.close(descriptor)
                throw ScreenwatchSourceResolutionError.invalidRelativePath
            }
            let child = Darwin.openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            Darwin.close(descriptor)
            guard child >= 0 else {
                if errno == ENOENT { throw ScreenwatchSourceResolutionError.missingDirectory }
                if errno == ELOOP { throw ScreenwatchSourceResolutionError.unsafePath }
                throw ScreenwatchSourceResolutionError.notDirectory
            }
            descriptor = child
        }
        return descriptor
    }

    private func isValidComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("/")
            && !component.contains("\0")
    }
}

public final class ScreenwatchSourceRepository: @unchecked Sendable {
    public static let legacyBookmarkDefaultsKey = "screenwatch.setup.alternate-days-bookmark.v1"

    public let bookmarkFileURL: URL

    private let runtimeEnvironment: RuntimeEnvironment
    private let bookmarkAccess: ScreenwatchBookmarkAccess
    private let legacyDefaults: [UserDefaults]
    private let lock = NSLock()

    public init(
        runtimeEnvironment: RuntimeEnvironment,
        bookmarkFileURL: URL? = nil,
        bookmarkAccess: ScreenwatchBookmarkAccess = .foundation,
        legacyDefaults: [UserDefaults]? = nil
    ) {
        self.runtimeEnvironment = runtimeEnvironment
        self.bookmarkFileURL = bookmarkFileURL
            ?? runtimeEnvironment.applicationSupportRoot
                .appendingPathComponent("Zoid Coach", isDirectory: true)
                .appendingPathComponent("screenwatch-source-v1.bookmark", isDirectory: false)
        self.bookmarkAccess = bookmarkAccess
        if let legacyDefaults {
            self.legacyDefaults = legacyDefaults
        } else {
            var values = [runtimeEnvironment.makeUserDefaults()]
            if case .production = runtimeEnvironment.mode,
               let appDefaults = UserDefaults(suiteName: RuntimeEnvironment.productionUserDefaultsDomain) {
                values.append(appDefaults)
            }
            self.legacyDefaults = values
        }
    }

    public var hasAlternateSelection: Bool {
        lock.withLock {
            if FileManager.default.fileExists(atPath: bookmarkFileURL.path) { return true }
            return legacyDefaults.contains {
                $0.data(forKey: Self.legacyBookmarkDefaultsKey) != nil
            }
        }
    }

    public func saveAlternate(_ url: URL) throws {
        try validateRuntimeBoundary(url)
        _ = try ScreenwatchDirectoryLease(rootURL: url, source: .alternateBookmark)
        let data: Data
        do {
            data = try bookmarkAccess.create(url)
        } catch {
            throw ScreenwatchSourceResolutionError.invalidBookmark
        }
        try lock.withLock { try writeAtomically(data) }
    }

    public func clearAlternate() throws {
        try lock.withLock {
            if unlink(bookmarkFileURL.path) != 0, errno != ENOENT {
                throw ScreenwatchSourceResolutionError.ioFailure
            }
            try syncParentDirectory()
            for defaults in legacyDefaults {
                defaults.removeObject(forKey: Self.legacyBookmarkDefaultsKey)
            }
        }
    }

    public func resolveCanonicalSource() throws -> ScreenwatchDirectoryLease {
        let bookmark = try lock.withLock { try loadOrMigrateBookmark() }
        guard let bookmark else {
            try validateRuntimeBoundary(runtimeEnvironment.screenwatchDirectory)
            return try ScreenwatchDirectoryLease(
                rootURL: runtimeEnvironment.screenwatchDirectory,
                source: .defaultLocation
            )
        }
        let resolution: ScreenwatchBookmarkResolution
        do {
            resolution = try bookmarkAccess.resolve(bookmark)
        } catch {
            throw ScreenwatchSourceResolutionError.invalidBookmark
        }
        guard !resolution.isStale else {
            throw ScreenwatchSourceResolutionError.staleBookmark
        }
        try validateRuntimeBoundary(resolution.url)
        guard bookmarkAccess.startAccess(resolution.url) else {
            throw ScreenwatchSourceResolutionError.securityScopeUnavailable
        }
        do {
            return try ScreenwatchDirectoryLease(
                rootURL: resolution.url,
                source: .alternateBookmark,
                stopAccess: { [bookmarkAccess] in bookmarkAccess.stopAccess(resolution.url) }
            )
        } catch {
            bookmarkAccess.stopAccess(resolution.url)
            throw error
        }
    }

    private func validateRuntimeBoundary(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw ScreenwatchSourceResolutionError.unsafePath
        }
        guard case let .qa(runRoot) = runtimeEnvironment.mode else { return }
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        let root = runRoot.resolvingSymlinksInPath().standardizedFileURL.path
        guard candidate == root || candidate.hasPrefix(root + "/") else {
            throw ScreenwatchSourceResolutionError.outsideQARunRoot
        }
    }

    private func loadOrMigrateBookmark() throws -> Data? {
        if let data = try readBookmarkFile() { return data }
        for defaults in legacyDefaults {
            guard let data = defaults.data(forKey: Self.legacyBookmarkDefaultsKey) else { continue }
            try writeAtomically(data)
            defaults.removeObject(forKey: Self.legacyBookmarkDefaultsKey)
            return data
        }
        return nil
    }

    private func readBookmarkFile() throws -> Data? {
        let descriptor = Darwin.open(bookmarkFileURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt }
            throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
        }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_size > 0,
              information.st_size <= 1_048_576 else {
            Darwin.close(descriptor)
            throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            return try handle.readToEnd()
        } catch {
            throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
        }
    }

    private func writeAtomically(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 1_048_576 else {
            throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
        }
        let parent = bookmarkFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = parent.appendingPathComponent(".screenwatch-bookmark-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw ScreenwatchSourceResolutionError.ioFailure }
        var shouldRemove = true
        defer {
            Darwin.close(descriptor)
            if shouldRemove { unlink(temporary.path) }
        }
        let writeSucceeded = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += count
            }
            return true
        }
        guard writeSucceeded, fsync(descriptor) == 0,
              rename(temporary.path, bookmarkFileURL.path) == 0 else {
            throw ScreenwatchSourceResolutionError.ioFailure
        }
        shouldRemove = false
        _ = chmod(bookmarkFileURL.path, S_IRUSR | S_IWUSR)
        try syncParentDirectory()
    }

    private func syncParentDirectory() throws {
        let descriptor = Darwin.open(
            bookmarkFileURL.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ENOENT { return }
            throw ScreenwatchSourceResolutionError.ioFailure
        }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw ScreenwatchSourceResolutionError.ioFailure
        }
    }
}
