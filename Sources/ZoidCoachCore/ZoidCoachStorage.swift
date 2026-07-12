import Foundation

public enum ZoidCoachStorage {
    public static let productDirectoryName = "Zoid 666"
    public static let legacyProductDirectoryName = "Zoid Coach"

    public static func databaseURL(fileManager: FileManager = .default) -> URL {
        databaseURL(
            applicationSupportRoot: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            fileManager: fileManager
        )
    }

    public static func databaseURL(
        applicationSupportRoot: URL,
        fileManager: FileManager = .default
    ) -> URL {
        productSupportURL(
            applicationSupportRoot: applicationSupportRoot,
            fileManager: fileManager
        )
            .appendingPathComponent("zoid-coach.sqlite", isDirectory: false)
    }

    /// Moves the former product directory on first launch and falls back to it
    /// if macOS refuses the move, so a cosmetic rename can never hide user data.
    public static func productSupportURL(
        applicationSupportRoot: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let current = applicationSupportRoot
            .appendingPathComponent(productDirectoryName, isDirectory: true)
        let legacy = applicationSupportRoot
            .appendingPathComponent(legacyProductDirectoryName, isDirectory: true)
        guard !fileManager.fileExists(atPath: current.path),
              fileManager.fileExists(atPath: legacy.path)
        else { return current }
        do {
            try fileManager.createDirectory(
                at: applicationSupportRoot,
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacy, to: current)
            return current
        } catch {
            // The main app and login agent may race on first launch. If the
            // peer completed the move, converge on the new directory.
            return fileManager.fileExists(atPath: current.path) ? current : legacy
        }
    }
}
