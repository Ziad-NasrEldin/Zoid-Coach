import Foundation
import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachInfrastructure

@Test
func appInventoryMergesInstalledAndObservedAppsWithoutDescendingIntoBundles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-app-inventory-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try makeApplication(named: "Xcode", in: root)
    let suite = root.appendingPathComponent("Utilities", isDirectory: true)
    try makeApplication(named: "Terminal", in: suite)
    let nestedInsideBundle = root
        .appendingPathComponent("Xcode.app/Contents/Applications", isDirectory: true)
    try makeApplication(named: "Hidden Helper", in: nestedInsideBundle)
    let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let laterObservation = observedAt.addingTimeInterval(60)
    let service = AppInventoryService(
        applicationRoots: [root],
        observedApplications: {
            [
                ObservedApplication(application: "xcode", lastObservedAt: observedAt, observationCount: 10),
                ObservedApplication(application: " XCODE ", lastObservedAt: laterObservation, observationCount: 2),
                ObservedApplication(application: "Steam", lastObservedAt: observedAt, observationCount: 5)
            ]
        }
    )

    let result = service.load()

    #expect(result.warning == nil)
    #expect(result.items.map(\.name) == ["Steam", "Terminal", "Xcode"])
    #expect(result.items.first(where: { $0.normalizedName == "xcode" })?.isInstalled == true)
    #expect(result.items.first(where: { $0.normalizedName == "xcode" })?.lastObservedAt == laterObservation)
    #expect(result.items.first(where: { $0.normalizedName == "xcode" })?.observationCount == 12)
    #expect(result.items.contains(where: { $0.name == "Hidden Helper" }) == false)
}

private func makeApplication(named name: String, in directory: URL) throws {
    let contents = directory.appendingPathComponent("\(name).app/Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleDisplayName": name,
        "CFBundleIdentifier": "test.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
}
