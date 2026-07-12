import SwiftUI

struct AgentLifecycleView: View {
    @ObservedObject var controller: AgentLifecycleController
    @State private var confirmsDisable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statusPanel
                behaviorPanel
                actions
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Sumi.paper)
        .navigationTitle("Background Agent")
        .alert("Disable the background agent?", isPresented: $confirmsDisable) {
            Button("Cancel", role: .cancel) {}
            Button("Disable", role: .destructive) { controller.disable() }
        } message: {
            Text("Overnight planning and automatic source refreshes will stop. Your local plans, reviews, and history stay on this Mac.")
        }
        .alert(
            "Login Items could not be opened",
            isPresented: Binding(
                get: { controller.loginItemsOpenFailure != nil },
                set: { if !$0 { controller.clearLoginItemsOpenFailure() } }
            )
        ) {
            Button("OK") { controller.clearLoginItemsOpenFailure() }
        } message: {
            Text(controller.loginItemsOpenFailure ?? "Open System Settings, then General, then Login Items.")
        }
        .accessibilityIdentifier("agent-lifecycle.window")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUTONOMY / LOCAL SERVICE")
                .font(Sumi.label(10))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text("Background Agent")
                .font(Sumi.display(34))
                .foregroundStyle(Sumi.ink)
            Text("Keep overnight planning, source refreshes, and approved automatic actions running when the main window is closed.")
                .font(Sumi.body(14))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(controller.health.state.rawValue.uppercased())
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.ink)
                Spacer()
                Text(controller.lastCheckedAt.formatted(date: .omitted, time: .shortened))
                    .font(Sumi.label(9))
                    .foregroundStyle(Sumi.muted)
            }

            Text(controller.health.detail)
                .font(Sumi.body(18))
                .foregroundStyle(Sumi.ink)
                .accessibilityIdentifier("agent-lifecycle.detail")
            Text(controller.health.evidence)
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)

            if controller.health.state == .attention || controller.health.state == .notConnected {
                Text("If macOS requires approval, open Login Items, allow Zoid 666, then return here and choose CHECK AGAIN.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.seal)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agent-lifecycle.approval-guidance")
            }
        }
        .padding(20)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-lifecycle.status")
    }

    private var behaviorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT CHANGES")
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
            behaviorRow("Enabled", "The signed local helper can run after login and recover after it exits.")
            behaviorRow("Disabled", "Only background work stops. Existing local data and the foreground app remain available.")
            behaviorRow("Repair", "Reconciles this installed build with macOS without deleting plans or history.")
        }
        .padding(20)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
    }

    private func behaviorRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(title.uppercased())
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.ink)
                .frame(width: 76, alignment: .leading)
            Text(detail)
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button("CHECK AGAIN") { controller.refresh() }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .disabled(controller.operation != .idle)
                    .accessibilityIdentifier("agent-lifecycle.refresh")
                Button("OPEN LOGIN ITEMS") { controller.openLoginItems() }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .disabled(controller.operation != .idle)
                    .accessibilityIdentifier("agent-lifecycle.open-login-items")
                if controller.canEnable {
                    Button("ENABLE") { controller.enable() }
                        .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                        .accessibilityIdentifier("agent-lifecycle.enable")
                }
                if controller.canRepair {
                    Button("REPAIR REGISTRATION") { controller.repair() }
                        .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                        .accessibilityIdentifier("agent-lifecycle.repair")
                }
                Spacer()
                if controller.canDisable {
                    Button("DISABLE") { confirmsDisable = true }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        .accessibilityIdentifier("agent-lifecycle.disable")
                }
            }
            Text(controller.operation.description)
                .font(Sumi.label(9))
                .foregroundStyle(Sumi.muted)
                .accessibilityIdentifier("agent-lifecycle.operation")
        }
    }

    private var statusColor: Color {
        switch controller.health.state {
        case .healthy: Sumi.okay
        case .checking: Sumi.ink
        case .attention, .notConnected: Sumi.seal
        case .unavailable: Sumi.muted
        }
    }
}

struct AgentLifecycleCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Background Agent…") {
                openWindow(id: "agent-lifecycle")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
