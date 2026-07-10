import AppKit
import Foundation

public struct MacChiefOfStaffActions: Sendable {
    public init() {}

    @MainActor
    public func openApplication(name: String, bundleIdentifier: String?) async throws -> Bool {
        let workspace = NSWorkspace.shared
        let applicationURL: URL?
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
        } else {
            applicationURL = Self.applicationURL(named: name)
        }
        guard let applicationURL else { throw MacChiefOfStaffActionError.applicationNotFound }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(at: applicationURL, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: true) }
            }
        }
    }

    @MainActor
    public func searchWeb(query: String) throws -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MacChiefOfStaffActionError.invalidInput }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = components?.url else { throw MacChiefOfStaffActionError.invalidInput }
        return NSWorkspace.shared.open(url)
    }

    public func findFiles(query: String, limit: Int) async throws -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MacChiefOfStaffActionError.invalidInput }
        return try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-interpret", trimmed]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw MacChiefOfStaffActionError.searchFailed }
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .prefix(min(max(limit, 1), 20))
                .map(String.init)
        }.value
    }

    @MainActor
    public func openFile(path: String) throws -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MacChiefOfStaffActionError.fileNotFound
        }
        return NSWorkspace.shared.open(url)
    }

    private static func applicationURL(named name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }), let url = running.bundleURL {
            return url
        }
        let applicationName = trimmed.lowercased().hasSuffix(".app") ? trimmed : "\(trimmed).app"
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in roots {
            let direct = root.appendingPathComponent(applicationName, isDirectory: true)
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            if let match = children.first(where: {
                $0.pathExtension == "app" && $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
            }) {
                return match
            }
        }
        return nil
    }
}

public enum MacChiefOfStaffActionError: LocalizedError {
    case invalidInput
    case applicationNotFound
    case fileNotFound
    case searchFailed

    public var errorDescription: String? {
        switch self {
        case .invalidInput: "The Mac action needs a non-empty value."
        case .applicationNotFound: "Zoid could not find that installed application."
        case .fileNotFound: "Zoid could not find that local file."
        case .searchFailed: "Spotlight could not complete the file search."
        }
    }
}
