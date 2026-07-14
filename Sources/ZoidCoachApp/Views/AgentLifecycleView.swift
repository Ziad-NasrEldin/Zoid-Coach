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
                blockingSafetyPanel
                actions
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Sumi.paper)
        .navigationTitle("Background Agent")
        .task {
            while !Task.isCancelled {
                controller.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .alert("Disable launch at login?", isPresented: $confirmsDisable) {
            Button("Cancel", role: .cancel) {}
            Button("Disable Launch at Login", role: .destructive) { controller.disable() }
        } message: {
            Text("The background agent will stop launching automatically. Overnight planning and automatic source refreshes will stop, while your local plans, reviews, and history stay on this Mac.")
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

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("LAUNCH AT LOGIN")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                Spacer()
                Text(controller.launchAtLoginDescription.uppercased())
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.ink)
                    .accessibilityIdentifier("agent-lifecycle.launch-at-login-status")
            }
            .padding(.top, 4)

            if let recoveryGuidance = controller.recoveryGuidance {
                Text(recoveryGuidance)
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
            behaviorRow("Enabled", "Launch at login is on. The signed local helper can run after login and recover after it exits.")
            behaviorRow("Disabled", "Launch at login is off. Only background work stops. Existing local data and the foreground app remain available.")
            behaviorRow("Repair", "Reconciles this installed build with macOS without deleting plans or history.")
            behaviorRow("Runtime proof", "A fresh local heartbeat confirms the helper is actually running; registration alone is never shown as healthy.")
            behaviorRow("Resource policy", "The helper uses bounded polling, backs off when the Mac is resource constrained, and stores no duplicate screenshot files.")
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

    private var blockingSafetyPanel: some View {
        let disclosure = BlockingSafetyDisclosure()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("ENFORCEMENT BOUNDARY")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                Spacer()
                Text(disclosure.statusTitle)
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.okay)
                    .accessibilityIdentifier("agent-lifecycle.blocking-safety.status")
            }
            Text(disclosure.explanation)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.ink)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(disclosure.requirements) { requirement in
                VStack(alignment: .leading, spacing: 4) {
                    Text(requirement.title.uppercased())
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.ink)
                    Text(requirement.detail)
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("agent-lifecycle.blocking-safety.\(requirement.id.rawValue)")
            }

            Text("Any future blocking must pass all four gates before it can activate.")
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.seal)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Sumi.softPaper)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-lifecycle.blocking-safety")
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
                    Button("ENABLE LAUNCH AT LOGIN") { controller.enable() }
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
                    Button("DISABLE LAUNCH AT LOGIN") { confirmsDisable = true }
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
