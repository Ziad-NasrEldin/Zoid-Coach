import AppKit
import SwiftUI

@main
struct ZoidCoachApplication: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
                .background(Sumi.paper)
                .onAppear {
                    positionInitialWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }

    private func positionInitialWindow() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: {
                $0.canBecomeKey && $0.level == .normal
            }) else { return }

            let targetSize = NSSize(width: 1180, height: 760)
            window.setContentSize(targetSize)
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }
}
