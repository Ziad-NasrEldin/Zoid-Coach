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

package struct ScreenwatchDirectoryEntry: Equatable, Sendable {
    public let name: String
    public let isDirectory: Bool
    public let isRegularFile: Bool
}

package struct ScreenwatchFileRead: Sendable {
    package let data: Data
    package let size: UInt64
    package let identity: String
    package let offset: UInt64
    package let isTruncated: Bool
}

public final class ScreenwatchDirectoryLease: @unchecked Sendable {
    public let source: ScreenwatchSourceKind
    public let rootURL: URL
    public let sourceFingerprint: String

    private let rootDescriptor: Int32
    private let stopAccess: (@Sendable () -> Void)?
    private let lock = NSLock()

    package convenience init(
        rootURL: URL,
        source: ScreenwatchSourceKind,
        stopAccess: (@Sendable () -> Void)? = nil
    ) throws {
        guard rootURL.isFileURL, rootURL.path.hasPrefix("/") else {
            throw ScreenwatchSourceResolutionError.unsafePath
        }
        let normalizedRootURL = Self.normalizedTemporaryAlias(rootURL)
        let descriptor = try Self.openAbsoluteDirectory(normalizedRootURL, createMissing: false)
        try self.init(
            rootURL: normalizedRootURL,
            source: source,
            openedDescriptor: descriptor,
            stopAccess: stopAccess
        )
    }

    private init(
        rootURL: URL,
        source: ScreenwatchSourceKind,
        openedDescriptor descriptor: Int32,
        stopAccess: (@Sendable () -> Void)?
    ) throws {
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR else {
            Darwin.close(descriptor)
            throw ScreenwatchSourceResolutionError.notDirectory
        }
        self.rootDescriptor = descriptor
        self.rootURL = Self.normalizedTemporaryAlias(rootURL)
        self.source = source
        self.stopAccess = stopAccess
        let fingerprintInput = "\(source.rawValue):\(information.st_dev):\(information.st_ino)"
        self.sourceFingerprint = SHA256.hash(data: Data(fingerprintInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    package static func descendant(
        rootURL: URL,
        candidateURL: URL,
        source: ScreenwatchSourceKind,
        stopAccess: (@Sendable () -> Void)? = nil
    ) throws -> ScreenwatchDirectoryLease {
        let normalizedRootURL = normalizedTemporaryAlias(rootURL)
        let normalizedCandidateURL = normalizedTemporaryAlias(candidateURL)
        let rootComponents = (normalizedRootURL.path as NSString).pathComponents
        let candidateComponents = (normalizedCandidateURL.path as NSString).pathComponents
        guard candidateComponents.count >= rootComponents.count,
              Array(candidateComponents.prefix(rootComponents.count)) == rootComponents else {
            throw ScreenwatchSourceResolutionError.outsideQARunRoot
        }
        let rootDescriptor = try openAbsoluteDirectory(normalizedRootURL, createMissing: false)
        var descriptor = rootDescriptor
        for component in candidateComponents.dropFirst(rootComponents.count) {
            let child = Darwin.openat(
                descriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            Darwin.close(descriptor)
            guard child >= 0 else {
                if errno == ENOENT { throw ScreenwatchSourceResolutionError.missingDirectory }
                if errno == ELOOP || errno == ENOTDIR {
                    throw ScreenwatchSourceResolutionError.unsafePath
                }
                if errno == EACCES || errno == EPERM {
                    throw ScreenwatchSourceResolutionError.securityScopeUnavailable
                }
                throw ScreenwatchSourceResolutionError.ioFailure
            }
            descriptor = child
        }
        return try ScreenwatchDirectoryLease(
            rootURL: normalizedCandidateURL,
            source: source,
            openedDescriptor: descriptor,
            stopAccess: stopAccess
        )
    }

    deinit {
        Darwin.close(rootDescriptor)
        stopAccess?()
    }

    package func entries(in components: [String] = []) throws -> [ScreenwatchDirectoryEntry] {
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

    package func fileExists(_ components: [String]) throws -> Bool {
        try lock.withLock {
            let descriptor: Int32
            do {
                descriptor = try openFile(components)
            } catch ScreenwatchSourceResolutionError.missingDirectory {
                return false
            }
            Darwin.close(descriptor)
            return true
        }
    }

    package func read(
        at components: [String],
        offset: UInt64 = 0,
        expectedIdentity: String? = nil,
        maximumBytes: Int
    ) throws -> ScreenwatchFileRead {
        guard maximumBytes >= 0, maximumBytes < Int.max else {
            throw ScreenwatchSourceResolutionError.ioFailure
        }
        return try lock.withLock {
            let descriptor = try openFile(components)
            var information = stat()
            guard fstat(descriptor, &information) == 0,
                  information.st_mode & S_IFMT == S_IFREG else {
                Darwin.close(descriptor)
                throw ScreenwatchSourceResolutionError.notRegularFile
            }
            let identity = "\(information.st_dev):\(information.st_ino)"
            let selectedOffset = expectedIdentity == nil || expectedIdentity == identity
                ? min(offset, UInt64(max(0, information.st_size)))
                : 0
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.seek(toOffset: selectedOffset)
            let buffered = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            let isTruncated = buffered.count > maximumBytes
            let data = isTruncated ? Data(buffered.prefix(maximumBytes)) : buffered
            return ScreenwatchFileRead(
                data: data,
                size: UInt64(max(0, information.st_size)),
                identity: identity,
                offset: selectedOffset,
                isTruncated: isTruncated
            )
        }
    }

    package func data(at components: [String], maximumBytes: Int = 8 * 1_024 * 1_024) throws -> Data {
        let result = try read(at: components, maximumBytes: maximumBytes)
        guard !result.isTruncated else {
            throw ScreenwatchSourceResolutionError.ioFailure
        }
        return result.data
    }

    package func withReadOnlyDescriptorURL<T: Sendable>(
        at components: [String],
        operation: @Sendable (URL) async throws -> T
    ) async throws -> T {
        let descriptor = try lock.withLock { try openFile(components) }
        defer { Darwin.close(descriptor) }
        let descriptorURL = URL(fileURLWithPath: "/dev/fd/\(descriptor)", isDirectory: false)
        return try await operation(descriptorURL)
    }

    package func removeFile(_ components: [String]) throws {
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

    private func openFile(_ components: [String]) throws -> Int32 {
        guard let fileName = components.last, isValidComponent(fileName) else {
            throw ScreenwatchSourceResolutionError.invalidRelativePath
        }
        let parent = try openDirectory(Array(components.dropLast()))
        defer { Darwin.close(parent) }
        let descriptor = Darwin.openat(parent, fileName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw ScreenwatchSourceResolutionError.missingDirectory }
            if errno == ELOOP || errno == ENOTDIR {
                throw ScreenwatchSourceResolutionError.unsafePath
            }
            if errno == EACCES || errno == EPERM {
                throw ScreenwatchSourceResolutionError.securityScopeUnavailable
            }
            throw ScreenwatchSourceResolutionError.ioFailure
        }
        return descriptor
    }

    private func openDirectory(_ components: [String]) throws -> Int32 {
        var descriptor = Darwin.openat(
            rootDescriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
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

    package static func openAbsoluteDirectory(
        _ url: URL,
        createMissing: Bool,
        mode: mode_t = S_IRWXU
    ) throws -> Int32 {
        let url = normalizedTemporaryAlias(url)
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw ScreenwatchSourceResolutionError.unsafePath
        }
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ScreenwatchSourceResolutionError.ioFailure }
        for component in (url.path as NSString).pathComponents where component != "/" {
            guard !component.isEmpty, component != ".", component != "..", !component.contains("/") else {
                Darwin.close(descriptor)
                throw ScreenwatchSourceResolutionError.unsafePath
            }
            var child = Darwin.openat(
                descriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            if child < 0, errno == ENOENT, createMissing {
                guard mkdirat(descriptor, component, mode) == 0 || errno == EEXIST else {
                    Darwin.close(descriptor)
                    throw ScreenwatchSourceResolutionError.ioFailure
                }
                child = Darwin.openat(
                    descriptor,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            Darwin.close(descriptor)
            guard child >= 0 else {
                if errno == ENOENT { throw ScreenwatchSourceResolutionError.missingDirectory }
                if errno == ELOOP || errno == ENOTDIR {
                    throw ScreenwatchSourceResolutionError.unsafePath
                }
                if errno == EACCES || errno == EPERM {
                    throw ScreenwatchSourceResolutionError.securityScopeUnavailable
                }
                throw ScreenwatchSourceResolutionError.ioFailure
            }
            descriptor = child
        }
        return descriptor
    }

    package static func normalizedTemporaryAlias(_ url: URL) -> URL {
        let path = (url.path as NSString).standardizingPath
        if path == "/var" || path.hasPrefix("/var/") {
            return URL(fileURLWithPath: "/private" + path, isDirectory: true)
        }
        if path == "/tmp" || path.hasPrefix("/tmp/") {
            return URL(fileURLWithPath: "/private" + path, isDirectory: true)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
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
    private static let storeFileName = "screenwatch-source-v1.bookmark"

    package let bookmarkFileURL: URL

    private let runtimeEnvironment: RuntimeEnvironment
    private let bookmarkAccess: ScreenwatchBookmarkAccess
    private let legacyDefaults: [UserDefaults]
    private let lock = NSLock()

    public init(
        runtimeEnvironment: RuntimeEnvironment,
        bookmarkAccess: ScreenwatchBookmarkAccess = .foundation,
        legacyDefaults: [UserDefaults]? = nil
    ) {
        self.runtimeEnvironment = runtimeEnvironment
        self.bookmarkFileURL = runtimeEnvironment.databaseURL.deletingLastPathComponent()
            .appendingPathComponent(Self.storeFileName, isDirectory: false)
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
            if (try? bookmarkExists()) == true { return true }
            return legacyDefaults.contains {
                $0.data(forKey: Self.legacyBookmarkDefaultsKey) != nil
            }
        }
    }

    public func saveAlternate(_ url: URL) throws {
        try validateRuntimeBoundary(url)
        _ = try makeLease(rootURL: url, source: .alternateBookmark)
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
            do {
                let directory = try storeDirectoryDescriptor(createMissing: false)
                defer { Darwin.close(directory) }
                if unlinkat(directory, Self.storeFileName, 0) != 0, errno != ENOENT {
                    throw ScreenwatchSourceResolutionError.ioFailure
                }
                guard fsync(directory) == 0 else {
                    throw ScreenwatchSourceResolutionError.ioFailure
                }
            } catch ScreenwatchSourceResolutionError.missingDirectory {
                // No canonical store exists yet, so only the legacy value needs removal.
            }
            for defaults in legacyDefaults {
                defaults.removeObject(forKey: Self.legacyBookmarkDefaultsKey)
            }
        }
    }

    public func resolveCanonicalSource() throws -> ScreenwatchDirectoryLease {
        let bookmark = try lock.withLock { try loadOrMigrateBookmark() }
        guard let bookmark else {
            try validateRuntimeBoundary(runtimeEnvironment.screenwatchDirectory)
            return try makeLease(
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
            return try makeLease(
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
        let candidate = (
            ScreenwatchDirectoryLease.normalizedTemporaryAlias(url).path as NSString
        ).pathComponents
        let root = (
            ScreenwatchDirectoryLease.normalizedTemporaryAlias(runRoot).path as NSString
        ).pathComponents
        guard candidate.count >= root.count,
              Array(candidate.prefix(root.count)) == root else {
            throw ScreenwatchSourceResolutionError.outsideQARunRoot
        }
    }

    private func makeLease(
        rootURL: URL,
        source: ScreenwatchSourceKind,
        stopAccess: (@Sendable () -> Void)? = nil
    ) throws -> ScreenwatchDirectoryLease {
        if case let .qa(runRoot) = runtimeEnvironment.mode {
            return try .descendant(
                rootURL: runRoot,
                candidateURL: rootURL,
                source: source,
                stopAccess: stopAccess
            )
        }
        return try ScreenwatchDirectoryLease(
            rootURL: rootURL,
            source: source,
            stopAccess: stopAccess
        )
    }

    private func loadOrMigrateBookmark() throws -> Data? {
        if let data = try readBookmarkFile() {
            for defaults in legacyDefaults {
                defaults.removeObject(forKey: Self.legacyBookmarkDefaultsKey)
            }
            return data
        }
        for defaults in legacyDefaults {
            guard let data = defaults.data(forKey: Self.legacyBookmarkDefaultsKey) else { continue }
            try writeAtomically(data)
            defaults.removeObject(forKey: Self.legacyBookmarkDefaultsKey)
            return data
        }
        return nil
    }

    private func readBookmarkFile() throws -> Data? {
        let directory: Int32
        do {
            directory = try storeDirectoryDescriptor(createMissing: false)
        } catch ScreenwatchSourceResolutionError.missingDirectory {
            return nil
        }
        defer { Darwin.close(directory) }
        let descriptor = Darwin.openat(
            directory,
            Self.storeFileName,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
        }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_uid == geteuid(),
              information.st_mode & 0o777 == 0o600,
              information.st_size > 0,
              information.st_size <= 1_048_576 else {
            Darwin.close(descriptor)
            throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            let data = try handle.read(upToCount: 1_048_577) ?? Data()
            guard !data.isEmpty, data.count <= 1_048_576 else {
                throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
            }
            return data
        } catch {
            throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
        }
    }

    private func writeAtomically(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 1_048_576 else {
            throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
        }
        let directory = try storeDirectoryDescriptor(createMissing: true)
        defer { Darwin.close(directory) }
        let temporary = ".screenwatch-bookmark-\(UUID().uuidString).tmp"
        let descriptor = Darwin.openat(
            directory,
            temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else { throw ScreenwatchSourceResolutionError.ioFailure }
        var shouldRemove = true
        defer {
            Darwin.close(descriptor)
            if shouldRemove { _ = unlinkat(directory, temporary, 0) }
        }
        guard fchmod(descriptor, 0o600) == 0 else {
            throw ScreenwatchSourceResolutionError.ioFailure
        }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_uid == geteuid(),
              information.st_mode & 0o777 == 0o600 else {
            throw ScreenwatchSourceResolutionError.ioFailure
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
        guard writeSucceeded,
              fsync(descriptor) == 0,
              renameat(directory, temporary, directory, Self.storeFileName) == 0,
              fsync(directory) == 0 else {
            throw ScreenwatchSourceResolutionError.ioFailure
        }
        shouldRemove = false
    }

    private func bookmarkExists() throws -> Bool {
        let directory: Int32
        do {
            directory = try storeDirectoryDescriptor(createMissing: false)
        } catch ScreenwatchSourceResolutionError.missingDirectory {
            return false
        }
        defer { Darwin.close(directory) }
        var information = stat()
        if fstatat(directory, Self.storeFileName, &information, AT_SYMLINK_NOFOLLOW) == 0 {
            return information.st_mode & S_IFMT == S_IFREG
        }
        if errno == ENOENT { return false }
        throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
    }

    private func storeDirectoryDescriptor(createMissing: Bool) throws -> Int32 {
        let support = try ScreenwatchDirectoryLease.openAbsoluteDirectory(
            runtimeEnvironment.applicationSupportRoot,
            createMissing: createMissing,
            mode: 0o700
        )
        var directory = Darwin.openat(
            support,
            bookmarkFileURL.deletingLastPathComponent().lastPathComponent,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        if directory < 0, errno == ENOENT, createMissing {
            let directoryName = bookmarkFileURL.deletingLastPathComponent().lastPathComponent
            guard mkdirat(support, directoryName, 0o700) == 0 || errno == EEXIST else {
                Darwin.close(support)
                throw ScreenwatchSourceResolutionError.ioFailure
            }
            directory = Darwin.openat(
                support,
                directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        Darwin.close(support)
        guard directory >= 0 else {
            if errno == ENOENT { throw ScreenwatchSourceResolutionError.missingDirectory }
            if errno == ELOOP || errno == ENOTDIR {
                throw ScreenwatchSourceResolutionError.bookmarkStoreCorrupt
            }
            throw ScreenwatchSourceResolutionError.ioFailure
        }
        return directory
    }
}
