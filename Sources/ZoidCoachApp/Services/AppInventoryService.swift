import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

struct AppInventoryItem: Identifiable, Equatable, Sendable {
    let name: String
    let normalizedName: String
    let bundleIdentifier: String?
    let isInstalled: Bool
    let lastObservedAt: Date?
    let observationCount: Int

    var id: String { normalizedName }
    var isObserved: Bool { lastObservedAt != nil }
}

struct AppInventoryLoadResult: Equatable, Sendable {
    let items: [AppInventoryItem]
    let warning: String?
}

struct AppInventoryService: @unchecked Sendable {
    private let applicationRoots: [URL]
    private let fileManager: FileManager
    private let observedApplications: @Sendable () throws -> [ObservedApplication]

    init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        applicationRoots: [URL] = Self.defaultApplicationRoots,
        fileManager: FileManager = .default
    ) {
        self.applicationRoots = applicationRoots
        self.fileManager = fileManager
        observedApplications = {
            try ScreenwatchArchive(databaseURL: databaseURL, readOnly: true).observedApplications()
        }
    }

    init(
        applicationRoots: [URL],
        fileManager: FileManager = .default,
        observedApplications: @escaping @Sendable () throws -> [ObservedApplication]
    ) {
        self.applicationRoots = applicationRoots
        self.fileManager = fileManager
        self.observedApplications = observedApplications
    }

    func load() -> AppInventoryLoadResult {
        var warnings: [String] = []
        let installed = installedApplications(warnings: &warnings)
        let observed: [ObservedApplication]
        do {
            observed = try observedApplications()
        } catch {
            observed = []
            warnings.append("Observed apps are unavailable until the local behavior archive recovers.")
        }
        return AppInventoryLoadResult(
            items: Self.merge(installed: installed, observed: observed),
            warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
        )
    }

    private func installedApplications(warnings: inout [String]) -> [InstalledApplication] {
        var applications: [InstalledApplication] = []
        for root in applicationRoots where fileManager.fileExists(atPath: root.path) {
            var rootHadError = false
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in
                    rootHadError = true
                    return true
                }
            ) else {
                warnings.append("Apps in \(root.path) could not be read.")
                continue
            }
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { continue }
                enumerator.skipDescendants()
                let bundle = Bundle(url: url)
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                applications.append(
                    InstalledApplication(
                        name: displayName,
                        bundleIdentifier: bundle?.bundleIdentifier
                    )
                )
            }
            if rootHadError {
                warnings.append("Some apps in \(root.path) could not be read.")
            }
        }
        return applications
    }

    private static func merge(installed: [InstalledApplication], observed: [ObservedApplication]) -> [AppInventoryItem] {
        var items: [String: AppInventoryItem] = [:]
        for application in installed {
            let normalized = BehaviorPolicy.normalize(application.name)
            guard !normalized.isEmpty else { continue }
            items[normalized] = AppInventoryItem(
                name: application.name,
                normalizedName: normalized,
                bundleIdentifier: application.bundleIdentifier,
                isInstalled: true,
                lastObservedAt: nil,
                observationCount: 0
            )
        }
        for application in observed {
            let normalized = BehaviorPolicy.normalize(application.application)
            guard !normalized.isEmpty else { continue }
            let existing = items[normalized]
            let latestObservation = max(existing?.lastObservedAt ?? .distantPast, application.lastObservedAt)
            items[normalized] = AppInventoryItem(
                name: existing?.name ?? application.application.trimmingCharacters(in: .whitespacesAndNewlines),
                normalizedName: normalized,
                bundleIdentifier: existing?.bundleIdentifier,
                isInstalled: existing?.isInstalled ?? false,
                lastObservedAt: latestObservation,
                observationCount: (existing?.observationCount ?? 0) + application.observationCount
            )
        }
        return items.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static var defaultApplicationRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }
}

private struct InstalledApplication: Equatable, Sendable {
    let name: String
    let bundleIdentifier: String?
}
