import Darwin
import Foundation

enum DescriptorRelativeStateDirectoryCheckpoint: Equatable, Sendable {
    case createdRootComponent(String)
    case syncedRootComponentParent(String)
    case createdStateDirectory(String)
    case syncedStateDirectoryParent(String)
}

struct DescriptorRelativeStateDirectoryOperations: Sendable {
    let createDirectory: @Sendable (Int32, String, mode_t) -> Int32
    let syncDirectory: @Sendable (Int32) -> Int32

    static let live = Self(
        createDirectory: { descriptor, name, mode in
            mkdirat(descriptor, name, mode) == 0 ? 0 : errno
        },
        syncDirectory: { descriptor in
            fsync(descriptor) == 0 ? 0 : errno
        }
    )
}

final class DescriptorRelativeStateDirectory<Failure: Error & Sendable>: @unchecked Sendable {
    typealias UnsafeEntryError = @Sendable (String) -> Failure
    typealias FilesystemError = @Sendable (String, Int32) -> Failure

    private let descriptor: Int32
    private let unsafeEntryError: UnsafeEntryError
    private let filesystemError: FilesystemError
    private let operations: DescriptorRelativeStateDirectoryOperations

    init(
        rootURL: URL,
        directoryName: String,
        createRootIfMissing: Bool = false,
        operations: DescriptorRelativeStateDirectoryOperations = .live,
        checkpoint: @escaping @Sendable (
            DescriptorRelativeStateDirectoryCheckpoint
        ) -> Void = { _ in },
        unsafeEntryError: @escaping UnsafeEntryError,
        filesystemError: @escaping FilesystemError
    ) throws {
        self.unsafeEntryError = unsafeEntryError
        self.filesystemError = filesystemError
        self.operations = operations
        guard Self.isSafeName(directoryName) else {
            throw unsafeEntryError(directoryName)
        }
        let rootDescriptor = try Self.openAbsoluteDirectoryWithoutFollowing(
            rootURL,
            createIfMissing: createRootIfMissing,
            operations: operations,
            checkpoint: checkpoint,
            unsafeEntryError: unsafeEntryError,
            filesystemError: filesystemError
        )
        defer { Darwin.close(rootDescriptor) }
        let createStateDirectoryError = operations.createDirectory(
            rootDescriptor,
            directoryName,
            0o700
        )
        if createStateDirectoryError != 0, createStateDirectoryError != EEXIST {
            throw filesystemError("create state directory", createStateDirectoryError)
        }
        if createStateDirectoryError == 0 {
            checkpoint(.createdStateDirectory(directoryName))
            let syncError = operations.syncDirectory(rootDescriptor)
            guard syncError == 0 else {
                throw filesystemError("sync state directory parent", syncError)
            }
            checkpoint(.syncedStateDirectoryParent(directoryName))
        }
        descriptor = openat(
            rootDescriptor,
            directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw unsafeEntryError(directoryName) }
    }

    deinit { Darwin.close(descriptor) }

    func acquire(exclusive: Bool) throws {
        guard flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) == 0 else {
            throw filesystemError("lock state directory", errno)
        }
    }

    func release() {
        _ = flock(descriptor, LOCK_UN)
    }

    func withLock<T>(exclusive: Bool, _ body: () throws -> T) throws -> T {
        try acquire(exclusive: exclusive)
        defer { release() }
        return try body()
    }

    func exists(_ name: String) throws -> Bool {
        try validateName(name)
        var status = stat()
        if fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 {
            guard status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1 else {
                throw unsafeEntryError(name)
            }
            return true
        }
        guard errno == ENOENT else {
            throw filesystemError("inspect \(name)", errno)
        }
        return false
    }

    func read(_ name: String) throws -> Data {
        try validateName(name)
        let fileDescriptor = openat(descriptor, name, O_RDONLY | O_NOFOLLOW)
        guard fileDescriptor >= 0 else {
            if errno == ELOOP { throw unsafeEntryError(name) }
            throw filesystemError("open \(name)", errno)
        }
        let handle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(fileDescriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_nlink == 1 else {
            throw unsafeEntryError(name)
        }
        do {
            return try handle.readToEnd() ?? Data()
        } catch {
            throw filesystemError("read \(name)", EIO)
        }
    }

    func writeAtomic(
        _ data: Data,
        name: String,
        beforeCommit: () throws -> Void = {}
    ) throws {
        try validateName(name)
        let temporaryName = ".\(name).tmp"
        _ = unlinkat(descriptor, temporaryName, 0)
        let fileDescriptor = openat(
            descriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard fileDescriptor >= 0 else {
            throw filesystemError("create temporary \(name)", errno)
        }
        var committed = false
        defer {
            Darwin.close(fileDescriptor)
            if !committed { _ = unlinkat(descriptor, temporaryName, 0) }
        }
        try data.withUnsafeBytes { rawBuffer in
            guard var cursor = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let count = Darwin.write(fileDescriptor, cursor, remaining)
                guard count > 0 else {
                    throw filesystemError("write temporary \(name)", errno)
                }
                remaining -= count
                cursor = cursor.advanced(by: count)
            }
        }
        guard fsync(fileDescriptor) == 0 else {
            throw filesystemError("sync temporary \(name)", errno)
        }
        try beforeCommit()
        guard renameat(descriptor, temporaryName, descriptor, name) == 0 else {
            throw filesystemError("commit \(name)", errno)
        }
        committed = true
        let syncError = operations.syncDirectory(descriptor)
        guard syncError == 0 else {
            throw filesystemError("sync state directory", syncError)
        }
    }

    func rename(_ source: String, to destination: String) throws {
        try validateName(source)
        try validateName(destination)
        guard try exists(source) else { return }
        if try exists(destination) { try removeIfPresent(destination) }
        guard renameat(descriptor, source, descriptor, destination) == 0 else {
            throw filesystemError("rename \(source)", errno)
        }
        let syncError = operations.syncDirectory(descriptor)
        guard syncError == 0 else {
            throw filesystemError("sync renamed \(source)", syncError)
        }
    }

    func removeIfPresent(_ name: String) throws {
        try validateName(name)
        guard try exists(name) else { return }
        guard unlinkat(descriptor, name, 0) == 0 else {
            throw filesystemError("remove \(name)", errno)
        }
        let syncError = operations.syncDirectory(descriptor)
        guard syncError == 0 else {
            throw filesystemError("sync removed \(name)", syncError)
        }
    }

    private func validateName(_ name: String) throws {
        guard Self.isSafeName(name) else { throw unsafeEntryError(name) }
    }

    private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    private static func openAbsoluteDirectoryWithoutFollowing(
        _ url: URL,
        createIfMissing: Bool,
        operations: DescriptorRelativeStateDirectoryOperations,
        checkpoint: @escaping @Sendable (
            DescriptorRelativeStateDirectoryCheckpoint
        ) -> Void,
        unsafeEntryError: UnsafeEntryError,
        filesystemError: FilesystemError
    ) throws -> Int32 {
        guard url.path.hasPrefix("/") else { throw unsafeEntryError(url.path) }
        let traversalPath = macOSTemporaryDirectoryAliasResolvedPath(url)
        let root = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard root >= 0 else { throw filesystemError("open filesystem root", errno) }
        var descriptorChain = [root]
        do {
            for component in traversalPath
                .split(separator: "/").map(String.init) {
                var next = openat(
                    descriptorChain.last!, component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                if next < 0, errno == ENOENT, createIfMissing {
                    let createError = operations.createDirectory(
                        descriptorChain.last!,
                        component,
                        0o700
                    )
                    if createError != 0, createError != EEXIST {
                        throw filesystemError("create root component \(component)", createError)
                    }
                    if createError == 0 {
                        checkpoint(.createdRootComponent(component))
                        let syncError = operations.syncDirectory(descriptorChain.last!)
                        guard syncError == 0 else {
                            throw filesystemError("sync root component \(component)", syncError)
                        }
                        checkpoint(.syncedRootComponentParent(component))
                    }
                    next = openat(
                        descriptorChain.last!, component,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                    )
                }
                guard next >= 0 else { throw unsafeEntryError(component) }
                descriptorChain.append(next)
            }
            let result = descriptorChain.removeLast()
            descriptorChain.forEach { Darwin.close($0) }
            return result
        } catch {
            descriptorChain.forEach { Darwin.close($0) }
            throw error
        }
    }

    private static func macOSTemporaryDirectoryAliasResolvedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        guard path == "/var" || path.hasPrefix("/var/") else { return path }
        return "/private" + path
    }
}
