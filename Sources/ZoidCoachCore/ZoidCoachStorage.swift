import Foundation

public enum ZoidCoachStorage {
    public static func databaseURL(fileManager: FileManager = .default) -> URL {
        databaseURL(
            applicationSupportRoot: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        )
    }

    public static func databaseURL(applicationSupportRoot: URL) -> URL {
        applicationSupportRoot
            .appendingPathComponent("Zoid Coach", isDirectory: true)
            .appendingPathComponent("zoid-coach.sqlite", isDirectory: false)
    }
}
