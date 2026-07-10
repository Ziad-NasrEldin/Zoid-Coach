import Foundation

public enum ZoidCoachStorage {
    public static func databaseURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Zoid Coach", isDirectory: true)
            .appendingPathComponent("zoid-coach.sqlite", isDirectory: false)
    }
}
