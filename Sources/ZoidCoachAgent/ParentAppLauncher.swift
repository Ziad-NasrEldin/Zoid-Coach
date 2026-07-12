import AppKit
import Foundation
import ZoidCoachCore

enum ParentAppLauncher {
    static func launchForBackgroundScheduling(runtimeEnvironment: RuntimeEnvironment) {
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == runtimeEnvironment.identity.appBundleIdentifier
        }) == false else { return }
        let executableURL = Bundle.main.executableURL
        let appURL = executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let appURL, appURL.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--background-schedule"]
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
    }
}
