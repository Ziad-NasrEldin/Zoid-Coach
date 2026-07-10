import AppKit
import SwiftUI
import ZoidCoachCore
import ZoidCoachInfrastructure

@MainActor
final class SettingsPolicyController: ObservableObject {
    @Published var draft: SettingsPolicyDraft
    @Published private(set) var activeVersion: Int?
    @Published private(set) var policyHistory: [VersionedUserPolicy] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var isSaving = false

    private let store: PolicyStore?
    private let savePolicyThroughAgent: @Sendable (UserPolicy) async throws -> AgentMutationReceipt
    private var persistedPolicy: UserPolicy

    init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        savePolicyThroughAgent: (@Sendable (UserPolicy) async throws -> AgentMutationReceipt)? = nil
    ) {
        if let savePolicyThroughAgent {
            self.savePolicyThroughAgent = savePolicyThroughAgent
        } else {
            let client = TodayDashboardXPCClient()
            self.savePolicyThroughAgent = { try await client.apply(.savePolicy($0)) }
        }
        store = try? PolicyStore(databaseURL: databaseURL, readOnly: true)
        let current: VersionedUserPolicy?
        if let store {
            current = try? store.current()
        } else {
            current = nil
        }
        let policy = current?.policy ?? UserPolicy.defaults()
        persistedPolicy = policy
        draft = SettingsPolicyDraft(policy: policy)
        activeVersion = current?.version
        policyHistory = (try? store?.history()) ?? []
        if store == nil {
            statusMessage = "Policy storage is unavailable. Settings are read-only until local storage recovers."
        }
    }

    var isReadOnly: Bool { store == nil }

    var previousPolicyVersion: Int? {
        policyHistory.first(where: { $0.version != activeVersion })?.version
    }

    @discardableResult
    func save() -> Task<Void, Never>? {
        guard store != nil else { return nil }
        isSaving = true
        let policy = draft.policy(preserving: persistedPolicy)
        return Task {
            do {
                try await persist(policy)
            } catch {
                statusMessage = "Settings were not saved: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    @discardableResult
    func setPaused(_ paused: Bool) -> Task<Void, Never>? {
        guard store != nil else { return nil }
        var pauseOnlyDraft = SettingsPolicyDraft(policy: persistedPolicy)
        pauseOnlyDraft.isPaused = paused
        isSaving = true
        let policy = pauseOnlyDraft.policy(preserving: persistedPolicy)
        return Task {
            do {
                try await persist(policy)
            } catch {
                statusMessage = "Automation was not \(paused ? "paused" : "resumed"): \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    func requestWakeChange(_ enabled: Bool) {
        draft.wakeEligible = enabled
        if !enabled { save() }
    }

    @discardableResult
    func rollbackToPreviousPolicy() -> Task<Void, Never>? {
        guard let target = policyHistory.first(where: { $0.version != activeVersion }) else { return nil }
        isSaving = true
        return Task {
            do {
                try await persist(target.policy)
                statusMessage = "Restored the settings from policy v\(target.version) as a new audited version."
            } catch {
                statusMessage = "Policy rollback failed: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    func openDataFolder() {
        NSWorkspace.shared.open(ZoidCoachStorage.databaseURL().deletingLastPathComponent())
    }

    private func persist(_ policy: UserPolicy) async throws {
        let receipt = try await savePolicyThroughAgent(policy)
        persistedPolicy = policy
        draft = SettingsPolicyDraft(policy: policy)
        activeVersion = receipt.policyVersion
        policyHistory = (try? store?.history()) ?? policyHistory
        statusMessage = receipt.message
    }
}

struct SettingsView: View {
    @StateObject private var controller = SettingsPolicyController()
    @State private var confirmingWakeEnable = false
    @State private var actionAudit: [ActionAuditEntry] = []
    @State private var actionAuditError: String?
    @State private var deleteRangeStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var deleteRangeEnd = Date()
    @State private var confirmingRangeDeletion = false
    @State private var confirmingTextDeletion = false
    @State private var confirmingPolicyRollback = false
    @State private var dataStatusMessage: String?
    private let xpcClient = TodayDashboardXPCClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader

            VStack(alignment: .leading, spacing: 22) {
                automationSection
                scheduleSection
                calendarSection
                privacySection
                wakeSection
                dataSection
                actionAuditSection
            }
            .padding(28)
        }
        .alert("Enable wake interventions?", isPresented: $confirmingWakeEnable) {
            Button("Keep disabled", role: .cancel) { controller.draft.wakeEligible = false }
            Button("I understand, enable") {
                controller.draft.wakeEligible = true
                controller.save()
            }
        } message: {
            Text("This is a high-trust capability. Zoid Coach may notify you during the configured wake window, up to the daily limit. You can disable it here at any time.")
        }
        .task { await refreshActionAudit() }
        .confirmationDialog("Delete local evidence in this date range?", isPresented: $confirmingRangeDeletion, titleVisibility: .visible) {
            Button("Delete selected range", role: .destructive) {
                Task { await performDataCommand(.deleteDataRange(start: deleteRangeStart, end: deleteRangeEnd)) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete all extracted conversation text?", isPresented: $confirmingTextDeletion, titleVisibility: .visible) {
            Button("Delete extracted text", role: .destructive) {
                Task { await performDataCommand(.deleteExtractedConversationText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Restore the previous policy?", isPresented: $confirmingPolicyRollback, titleVisibility: .visible) {
            Button("Restore previous policy") { controller.rollbackToPreviousPolicy() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current settings will remain in history, and the restored settings will be saved as a new audited policy version.")
        }
    }

    private var actionAuditSection: some View {
        SettingsCard(title: "ACTION AUDIT", detail: "Recent agent-owned external actions. Safe Calendar changes and pending commands can be undone.") {
            if let actionAuditError {
                Text(actionAuditError).font(Sumi.body(12)).foregroundStyle(Sumi.seal)
            } else if actionAudit.isEmpty {
                Text("No external actions have been recorded yet.").font(Sumi.body(12)).foregroundStyle(Sumi.muted)
            } else {
                ForEach(actionAudit.prefix(8)) { entry in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.actionType.replacingOccurrences(of: "_", with: " ").uppercased())
                                .font(Sumi.label(9))
                                .sumiLabelTracking()
                            Text("\(entry.state) · \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(Sumi.body(11))
                                .foregroundStyle(Sumi.muted)
                        }
                        Spacer()
                        if entry.canUndo {
                            Button("UNDO") {
                                Task {
                                    _ = try? await xpcClient.apply(.undoAction(commandID: entry.id))
                                    await refreshActionAudit()
                                }
                            }
                            .buttonStyle(SettingsButtonStyle())
                        }
                    }
                }
            }
            Button("REFRESH AUDIT") { Task { await refreshActionAudit() } }
                .buttonStyle(SettingsButtonStyle())
        }
    }

    private func refreshActionAudit() async {
        do {
            actionAudit = try await xpcClient.fetchActionAudit()
            actionAuditError = nil
        } catch {
            actionAuditError = "The action audit is available when the background agent is running."
        }
    }

    private var settingsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AUTONOMY / PRIVACY")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("Boundaries the agent must obey")
                    .font(Sumi.display(28))
                    .foregroundStyle(Sumi.ink)
            }
            Spacer()
            if let version = controller.activeVersion {
                Text("POLICY V\(version)")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }
            Button(controller.isSaving ? "SAVING" : "SAVE CHANGES") { controller.save() }
                .buttonStyle(SettingsButtonStyle())
                .disabled(controller.isSaving || controller.isReadOnly)
        }
        .padding(.horizontal, 28)
        .frame(height: 74)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }

    private var automationSection: some View {
        SettingsCard(title: "AUTOMATION", detail: "A pause takes effect through the shared policy store before the next autonomous action.") {
            HStack(spacing: 12) {
                Button(controller.draft.isPaused ? "RESUME AUTOMATION" : "PAUSE AUTOMATION") {
                    controller.setPaused(!controller.draft.isPaused)
                }
                .buttonStyle(SettingsButtonStyle())
                .accessibilityLabel(controller.draft.isPaused ? "Resume all automation" : "Pause all automation")

                Text(controller.draft.isPaused ? "PAUSED" : "RUNNING")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(controller.draft.isPaused ? Sumi.seal : Sumi.okay)
            }

            Picker("Operating mode", selection: $controller.draft.operatingMode) {
                Text("Observe only").tag(OperatingMode.observe)
                Text("Suggest plans").tag(OperatingMode.suggest)
                Text("Assist after approval").tag(OperatingMode.assist)
                Text("Fully autonomous").tag(OperatingMode.autonomous)
            }
            .pickerStyle(.segmented)

            if let version = controller.previousPolicyVersion {
                Button("ROLL BACK TO POLICY V\(version)") { confirmingPolicyRollback = true }
                    .buttonStyle(SettingsButtonStyle())
                    .disabled(controller.isSaving || controller.isReadOnly)
                    .accessibilityHint("Restores the previous settings as a new policy version")
            }
        }
    }

    private var scheduleSection: some View {
        SettingsCard(title: "SCHEDULE", detail: "Times stay local to \(TimeZone.current.identifier). Capacity limits planned work after fixed calendar commitments.") {
            HStack(spacing: 18) {
                LocalTimeField(title: "Work starts", time: $controller.draft.workStart)
                LocalTimeField(title: "Work ends", time: $controller.draft.workEnd)
                LocalTimeField(title: "Quiet starts", time: $controller.draft.quietStart)
                LocalTimeField(title: "Quiet ends", time: $controller.draft.quietEnd)
            }
            HStack(spacing: 18) {
                LocalTimeField(title: "Nightly planning", time: $controller.draft.nightlyPlanningTime)
                LocalTimeField(title: "Morning confirmation", time: $controller.draft.morningConfirmationTime)
            }
            Stepper("Planning capacity: \(controller.draft.capacityPercent)%", value: $controller.draft.capacityPercent, in: 25...100, step: 5)
        }
    }

    private var calendarSection: some View {
        SettingsCard(title: "CALENDARS", detail: "Use EventKit calendar identifiers. Leave visible calendars empty to read all available calendars.") {
            TextField("Visible calendar IDs, comma separated", text: $controller.draft.visibleCalendarIdentifiers)
            TextField("Scheduling calendar ID", text: $controller.draft.schedulingCalendarIdentifier)
        }
    }

    private var privacySection: some View {
        SettingsCard(title: "AI + DATA RETENTION", detail: AIProviderCapabilities.production.settingsSummary) {
            Toggle("Analyze Screenwatch screenshots", isOn: $controller.draft.screenshotAnalysisEnabled)
            Picker("AI provider", selection: $controller.draft.aiProvider) {
                ForEach(AIProviderSelection.allCases, id: \.self) { provider in
                    let capability = AIProviderCapabilities.production[provider]
                    Text(capability.settingsLabel)
                        .tag(provider)
                        .disabled(!capability.isSelectable)
                }
            }
            Picker("Remote evidence", selection: $controller.draft.remoteEvidencePolicy) {
                Text("Local only").tag(RemoteEvidencePolicy.localOnly)
                Text("Redacted metadata only").tag(RemoteEvidencePolicy.redactedMetadataOnly)
                Text("Explicit private content").tag(RemoteEvidencePolicy.explicitPrivateContent)
            }
            .disabled(
                controller.draft.aiProvider != .remoteOpenAI
                    || !AIProviderCapabilities.production[.remoteOpenAI].isSelectable
            )
            HStack(spacing: 18) {
                RetentionField(title: "Screenshots", days: $controller.draft.rawScreenshotRetentionDays)
                RetentionField(title: "Extracted text", days: $controller.draft.extractedTextRetentionDays)
                RetentionField(title: "Diagnostics", days: $controller.draft.diagnosticRetentionDays)
            }
        }
    }

    private var wakeSection: some View {
        SettingsCard(title: "WAKE INTERVENTIONS", detail: "Disabled by default. Enabling requires explicit confirmation and stays bounded by this window and daily limit.") {
            Toggle("Allow wake interventions", isOn: Binding(
                get: { controller.draft.wakeEligible },
                set: { enabled in
                    if enabled {
                        confirmingWakeEnable = true
                    } else {
                        controller.requestWakeChange(false)
                    }
                }
            ))
            HStack(spacing: 18) {
                LocalTimeField(title: "Window starts", time: $controller.draft.wakeStart)
                LocalTimeField(title: "Window ends", time: $controller.draft.wakeEnd)
                Stepper("Daily maximum: \(controller.draft.maximumDailyWakeInterventions)", value: $controller.draft.maximumDailyWakeInterventions, in: 1...3)
            }
            .disabled(!controller.draft.wakeEligible)
            VStack(alignment: .leading, spacing: 6) {
                Text("QUIET DAYS").font(Sumi.label(9)).sumiLabelTracking().foregroundStyle(Sumi.muted)
                HStack(spacing: 10) {
                    ForEach(Weekday.allCases, id: \.self) { weekday in
                        Toggle(weekdayLabel(weekday), isOn: Binding(
                            get: { controller.draft.wakeQuietWeekdays.contains(weekday) },
                            set: { enabled in
                                if enabled {
                                    if !controller.draft.wakeQuietWeekdays.contains(weekday) { controller.draft.wakeQuietWeekdays.append(weekday) }
                                } else {
                                    controller.draft.wakeQuietWeekdays.removeAll { $0 == weekday }
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .disabled(!controller.draft.wakeEligible)
        }
    }

    private func weekdayLabel(_ weekday: Weekday) -> String {
        Calendar.current.shortWeekdaySymbols[max(0, min(Calendar.current.shortWeekdaySymbols.count - 1, weekday.rawValue - 1))]
    }

    private var dataSection: some View {
        SettingsCard(title: "LOCAL DATA", detail: "Retention cleanup, redacted diagnostics, and selective deletion are executed by the background agent.") {
            Button("OPEN LOCAL DATA FOLDER") { controller.openDataFolder() }
                .buttonStyle(SettingsButtonStyle())
                .accessibilityLabel("Open Zoid Coach local data folder")
            Button("EXPORT REDACTED DIAGNOSTICS") {
                Task { await performDataCommand(.exportRedactedDiagnostics) }
            }
            .buttonStyle(SettingsButtonStyle())
            HStack {
                DatePicker("Delete from", selection: $deleteRangeStart, displayedComponents: .date)
                DatePicker("through", selection: $deleteRangeEnd, displayedComponents: .date)
                Button("DELETE RANGE") { confirmingRangeDeletion = true }
                    .buttonStyle(SettingsButtonStyle())
            }
            Button("DELETE EXTRACTED CONVERSATION TEXT") { confirmingTextDeletion = true }
                .buttonStyle(SettingsButtonStyle())
            if let dataStatusMessage {
                Text(dataStatusMessage).font(Sumi.body(12)).foregroundStyle(Sumi.muted)
            }
            if let message = controller.statusMessage {
                Text(message)
                    .font(Sumi.body(12))
                    .foregroundStyle(message.contains("not saved") || message.contains("unavailable") ? Sumi.seal : Sumi.muted)
            }
        }
    }

    private func performDataCommand(_ command: AgentMutationCommand) async {
        do {
            let receipt = try await xpcClient.apply(command)
            dataStatusMessage = receipt.message
            if let path = receipt.artifactPath {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        } catch {
            dataStatusMessage = "The background agent could not complete this data request."
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Sumi.label(10)).sumiLabelTracking().foregroundStyle(Sumi.ink)
            Text(detail).font(Sumi.body(12)).foregroundStyle(Sumi.muted)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sumi.softPaper)
        .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
    }
}

private struct LocalTimeField: View {
    let title: String
    @Binding var time: LocalTime

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { date(from: time) },
            set: { time = localTime(from: $0) }
        ), displayedComponents: .hourAndMinute)
    }

    private func date(from value: LocalTime) -> Date {
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: value.hour, minute: value.minute)) ?? Date()
    }

    private func localTime(from date: Date) -> LocalTime {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

private struct RetentionField: View {
    let title: String
    @Binding var days: Int

    var body: some View {
        Stepper("\(title): \(days) days", value: $days, in: 0...3_650)
    }
}

private struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Sumi.label(9))
            .sumiLabelTracking()
            .foregroundStyle(Sumi.paper)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(configuration.isPressed ? Sumi.sealDeep : Sumi.ink)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}
