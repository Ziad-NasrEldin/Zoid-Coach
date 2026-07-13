import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZoidCoachCore
import ZoidCoachInfrastructure

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var modalCoordinator: SumiModalCoordinator
    @EnvironmentObject private var voiceModel: VoiceConversationModel
    @StateObject private var controller = SettingsPolicyController()
    @State private var actionAudit: [ActionAuditEntry] = []
    @State private var actionAuditError: String?
    @State private var deleteRangeStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var deleteRangeEnd = Date()
    @State private var dataStatusMessage: String?
    @State private var privacyInventory: PrivacyStoredDataInventory?
    @State private var recentBehaviorSessions: [PrivacyBehaviorSession] = []
    @State private var isLoadingPrivacyInventory = true
    @State private var calendarChoices: [CalendarChoice] = []
    @State private var calendarAccessMessage: String?
    @State private var isLoadingCalendars = true
    @State private var selectedCategory = SettingsCategory.command
    @State private var geminiAPIKey = ""
    @State private var voiceSettingsMessage: String?
    @State private var captureConfiguration = (try? NativeCaptureConfigurationStore().load()) ?? .legacy
    @State private var captureConfigurationMessage: String?
    @State private var showsRemoteEvidencePreview = false
    private let xpcClient = TodayDashboardXPCClient(
        runtimeEnvironment: RuntimeEnvironment.current()
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader

            HStack(alignment: .top, spacing: 24) {
                settingsNavigation

                VStack(alignment: .leading, spacing: 18) {
                    if let conflict = controller.saveConflict {
                        SettingsPolicyConflictBanner(
                            conflict: conflict,
                            keepCurrent: controller.keepCurrentWinningValues,
                            reapply: { controller.reapplyMyChanges() }
                        )
                    }
                    if let message = controller.statusMessage {
                        Text(message)
                            .font(Sumi.body(12))
                            .foregroundStyle(
                                controller.saveConflict == nil && !message.contains("not saved")
                                    ? Sumi.muted
                                    : Sumi.seal
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.policyStatus")
                    }
                    categoryIntroduction
                    selectedCategoryContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .background(Sumi.softPaper)
        }
        .task { await refreshActionAudit() }
        .task { await refreshPrivacyInventory() }
        .task { await refreshCalendars() }
        .task { await controller.loadReminderLists() }
        .onAppear {
            controller.setReminderListPolicySavedHandler {
                model.refreshReminderTasks()
            }
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
                            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                        }
                    }
                }
            }
            Button("REFRESH AUDIT") { Task { await refreshActionAudit() } }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
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
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SETTINGS / POLICY")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("Shape how Zoid 666 works")
                    .font(Sumi.display(30))
                    .tracking(-0.7)
                    .foregroundStyle(Sumi.ink)
            }
            Spacer()

            HStack(spacing: 0) {
                SettingsHeaderFact(
                    label: "AUTOMATION",
                    value: controller.draft.isPaused ? "PAUSED" : "RUNNING",
                    isAttention: controller.draft.isPaused
                )
                SettingsHeaderFact(
                    label: "MODE",
                    value: operatingModeLabel(controller.draft.operatingMode).uppercased()
                )
                SettingsHeaderFact(label: "BUILD", value: AppBuildIdentity.current.shortLabel)
                    .accessibilityLabel("Build identity \(AppBuildIdentity.current.identity)")
                    .accessibilityIdentifier("settings.buildIdentity")
                    .help(AppBuildIdentity.current.identity)
                if let version = controller.activeVersion {
                    SettingsHeaderFact(label: "POLICY", value: "V\(version)")
                }
            }

            if controller.hasUnsavedChanges || controller.isSaving {
                Button(controller.isSaving ? "SAVING" : "SAVE CHANGES") {
                    controller.save()
                }
                    .buttonStyle(SumiActionButtonStyle(role: .accent, size: .large))
                    .disabled(controller.isSaving || controller.isReadOnly)
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                    Text("SAVED")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                }
                .foregroundStyle(Sumi.paper)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Sumi.ink)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("All changes saved")
            }
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 88)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
    }

    private var settingsNavigation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("POLICY CHAPTERS")
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            ForEach(SettingsCategory.allCases) { category in
                SettingsCategoryButton(
                    category: category,
                    isSelected: selectedCategory == category
                ) {
                    selectedCategory = category
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("LOCAL-FIRST")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                Text("Policy changes are versioned and remain on this Mac.")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Sumi.sealWash)
            .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        }
        .frame(width: 190)
        .background(Sumi.paper)
        .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
    }

    private var categoryIntroduction: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(selectedCategory.number)
                .font(Sumi.label(10))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.paper)
                .frame(width: 38, height: 38)
                .background(Sumi.seal)

            VStack(alignment: .leading, spacing: 5) {
                Text(selectedCategory.title.uppercased())
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.sealDeep)
                Text(selectedCategory.summary)
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sumi.sealWash)
        .overlay { Rectangle().stroke(Sumi.seal.opacity(0.34), lineWidth: 1) }
    }

    @ViewBuilder
    private var selectedCategoryContent: some View {
        switch selectedCategory {
        case .command:
            automationSection
            scheduleSection
        case .signals:
            remindersConnectionSection
            screenwatchConnectionSection
            notificationDeliverySection
            reminderListsSection
            appClassificationSection
            calendarSection
            captureSection
        case .intelligence:
            voiceSection
            privacySection
            wakeSection
        case .records:
            dataSection
            actionAuditSection
        }
    }

    private var notificationDeliverySection: some View {
        SettingsCard(
            title: "NOTIFICATION DELIVERY",
            detail: "See current macOS access, the last local delivery outcomes, and a direct repair path. Every unresolved decision remains available in Today."
        ) {
            NotificationDeliveryHealthView()
        }
    }

    private var remindersConnectionSection: some View {
        SettingsCard(
            title: "APPLE REMINDERS CONNECTION",
            detail: "See current permission, the last confirmed task refresh, and a direct recovery path. Refresh only reads task metadata and never changes a Reminder."
        ) {
            RemindersConnectionView(
                isLocalOnlyPlanningSelected: controller.draft.reminderListPolicy.isConfigured
                    && controller.draft.reminderListPolicy.decisions.allSatisfy { !$0.isIncluded }
            ) {
                controller.configureReminderListsLocalOnly()
                _ = controller.save()
            }
        }
    }

    private var screenwatchConnectionSection: some View {
        SettingsCard(
            title: "SCREENWATCH CONNECTION",
            detail: "Inspect the current local source, repair a moved or invalid folder, choose an alternate days folder, or return to the expected location without exposing captured content."
        ) {
            ScreenwatchConnectionView()
        }
    }

    private var reminderListsSection: some View {
        SettingsCard(
            title: "REMINDER LISTS",
            detail: "Choose which Apple Reminder lists may enter Today and agent planning. Choices use stable identifiers, so renaming a list does not change the policy."
        ) {
            switch controller.reminderListDiscovery {
            case .idle, .loading:
                ProgressView("Loading Reminder lists...")
                    .accessibilityIdentifier("settings.reminders.lists.loading")
            case let .permissionRequired(message):
                Text(message)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.sealDeep)
                    .accessibilityIdentifier("settings.reminders.lists.permission")
                Button("OPEN REMINDERS SETTINGS") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .accessibilityIdentifier("settings.reminders.lists.permission-repair")
                Button("RECHECK LISTS") {
                    Task { await controller.loadReminderLists() }
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .keyboardShortcut("r", modifiers: [.option, .shift])
                .accessibilityIdentifier("settings.reminders.lists.permission-recheck")
            case let .failed(message):
                Text(message).font(Sumi.body(12)).foregroundStyle(Sumi.sealDeep)
                    .accessibilityIdentifier("settings.reminders.lists.error")
                Button("RETRY LISTS") { Task { await controller.loadReminderLists() } }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .keyboardShortcut("r", modifiers: [.option, .shift])
                    .accessibilityIdentifier("settings.reminders.lists.retry")
            case .empty:
                Text("No Apple Reminder lists are currently available. Local tasks remain usable.")
                    .font(Sumi.body(12)).foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("settings.reminders.lists.empty")
                Button(
                    controller.draft.reminderListPolicy.isConfigured
                        && controller.draft.reminderListPolicy.decisions.allSatisfy { !$0.isIncluded }
                        ? "LOCAL-ONLY PLANNING SELECTED"
                        : "USE LOCAL-ONLY PLANNING"
                ) {
                    controller.configureReminderListsLocalOnly()
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(
                    controller.draft.reminderListPolicy.isConfigured
                        && controller.draft.reminderListPolicy.decisions.allSatisfy { !$0.isIncluded }
                )
                .accessibilityIdentifier("settings.reminders.lists.empty-local-only")
            case let .available(lists):
                VStack(spacing: 0) {
                    ForEach(lists) { list in
                        settingsReminderListRow(list)
                    }
                }
                .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.reminders.lists")

                let currentIDs = Set(lists.map(\.id))
                let missingIDs = controller.draft.reminderListPolicy.decisions
                    .map(\.listID)
                    .filter { !currentIDs.contains($0) }
                if !missingIDs.isEmpty {
                    Text("Saved choices retained for unavailable list IDs: \(missingIDs.joined(separator: ", ")). They will apply again if those exact IDs return.")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("settings.reminders.lists.unavailable-saved")
                }
            }
        }
    }

    private func settingsReminderListRow(_ list: ReminderListChoice) -> some View {
        let decision = controller.draft.reminderListPolicy.decision(for: list.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name).font(Sumi.body(14))
                Text(list.id).font(Sumi.body(11)).foregroundStyle(Sumi.muted).textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Picker("Use \(list.name)", selection: Binding(
                get: { decision },
                set: { value in
                    guard let value else { return }
                    controller.setReminderListDecision(value, listID: list.id)
                }
            )) {
                Text("CHOOSE").tag(Bool?.none)
                Text("INCLUDE").tag(Bool?.some(true))
                Text("EXCLUDE").tag(Bool?.some(false))
            }
            .labelsHidden()
            .frame(width: 118)
            .accessibilityLabel("Reminder list policy for \(list.name)")
            .accessibilityValue(decision.map { $0 ? "Included" : "Excluded" } ?? "Not chosen")
            .accessibilityIdentifier("settings.reminders.list.\(list.id).decision")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.reminders.list.\(list.id)")
    }

    private var voiceSection: some View {
        SettingsCard(
            title: "ZOID VOICE",
            detail: "Gemini runs only during a visible live session. The wake phrase and cap fallback stay on this Mac."
        ) {
            HStack(spacing: 12) {
                Button(voiceModel.state == .idle || voiceModel.state == .disconnected ? "START VOICE" : "STOP VOICE") {
                    voiceModel.toggleSession()
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))

                Button(voiceModel.isMuted ? "UNMUTE" : "MUTE") {
                    voiceModel.setMuted(!voiceModel.isMuted)
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(voiceModel.state == .idle)

                Text(voiceModel.state.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(voiceModel.state == .listening ? Sumi.okay : Sumi.muted)
            }

            Text(voiceModel.statusMessage)
                .font(Sumi.body(12))
                .foregroundStyle(Sumi.muted)

            Picker("GLOBAL SHORTCUT", selection: $voiceModel.hotKeyPreset) {
                ForEach(VoiceHotKeyPreset.allCases) { preset in Text(preset.label).tag(preset) }
            }

            HStack(spacing: 10) {
                SecureField("Gemini API key", text: $geminiAPIKey)
                    .textFieldStyle(.roundedBorder)
                Button("SAVE TO KEYCHAIN") {
                    do {
                        try voiceModel.configureAPIKey(geminiAPIKey)
                        geminiAPIKey = ""
                        voiceSettingsMessage = "Gemini key saved securely in Keychain."
                    } catch { voiceSettingsMessage = error.localizedDescription }
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                Button("REMOVE") {
                    do {
                        try voiceModel.removeAPIKey()
                        voiceSettingsMessage = "Gemini key removed."
                    } catch { voiceSettingsMessage = error.localizedDescription }
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(!voiceModel.hasAPIKey)
            }

            if let usage = voiceModel.usage {
                let dollars = Double(usage.consumedUSDMicros) / 1_000_000
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("MONTHLY GEMINI CAP")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                        Spacer()
                        Text(String(format: "$%.2f / $20.00", dollars))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    ProgressView(
                        value: Double(usage.consumedUSDMicros),
                        total: Double(VoiceUsageLedger.hardMonthlyLimitUSDMicros)
                    )
                }
            }

            if let voiceSettingsMessage {
                Text(voiceSettingsMessage)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
            }

            Text("Wake phrase: Hey Zoid · Shortcut: \(voiceModel.hotKeyPreset.label) · Raw audio is never retained")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
        }
    }

    private var automationSection: some View {
        SettingsCard(title: "AUTOMATION", detail: "A pause takes effect through the shared policy store before the next autonomous action.") {
            HStack(spacing: 12) {
                Button(controller.draft.isPaused ? "RESUME AUTOMATION" : "PAUSE AUTOMATION") {
                    controller.setPaused(!controller.draft.isPaused)
                }
                .buttonStyle(SumiActionButtonStyle(role: controller.draft.isPaused ? .primary : .quiet, size: .standard))
                .accessibilityLabel(controller.draft.isPaused ? "Resume all automation" : "Pause all automation")

                Text(controller.draft.isPaused ? "PAUSED" : "RUNNING")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(controller.draft.isPaused ? Sumi.seal : Sumi.okay)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(controller.draft.isPaused ? Sumi.sealWash : Sumi.mist)
                    .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            }

            SumiChoiceRail(
                "OPERATING MODE",
                options: OperatingMode.allCases,
                selection: $controller.draft.operatingMode,
                title: operatingModeLabel
            )

            SumiChoiceRail(
                "COACHING LEVEL AFTER BASELINE",
                options: CoachingLevel.allCases,
                selection: $controller.draft.coachingLevel,
                title: coachingLevelLabel
            )
            Text("Gentle allows one dismissible gaming prompt per day. Accountability allows up to three, with at least one hour between separate sessions. The first seven complete observation days always stay quiet.")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .accessibilityIdentifier("settings.coaching-level.explanation")

            VStack(alignment: .leading, spacing: 12) {
                Text("GAMING ALLOWANCE")
                    .font(Sumi.label(10))
                    .sumiLabelTracking()
                SumiStepper(
                    "BASE AVAILABLE EACH DAY",
                    value: $controller.draft.gamingDailyBudgetMinutes,
                    in: 0...1_440,
                    step: 5,
                    valueLabel: { "\($0) MIN" }
                )
                .accessibilityIdentifier("settings.gaming.daily-budget")
                SumiStepper(
                    "UNLOCK AFTER PRIORITY COMPLETION",
                    value: $controller.draft.gamingPriorityTaskRewardMinutes,
                    in: 0...1_440,
                    step: 5,
                    valueLabel: { "\($0) MIN" }
                )
                .accessibilityIdentifier("settings.gaming.priority-reward")
                Text(gamingAllowanceExplanation)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.gaming.allowance-explanation")
            }

            if let version = controller.previousPolicyVersion {
                Button("ROLL BACK TO POLICY V\(version)") { presentConfirmation(.restorePolicy) }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .disabled(controller.isSaving || controller.isReadOnly)
                    .accessibilityHint("Restores the previous settings as a new policy version")
            }
        }
    }

    private var gamingAllowanceExplanation: String {
        let base = controller.draft.gamingDailyBudgetMinutes
        let reward = controller.draft.gamingPriorityTaskRewardMinutes
        if base == 0, reward == 0 {
            return "No gaming minutes are available during work windows. Gaming is still observed factually, and coaching remains non-punitive."
        }
        if reward == 0 {
            return "Up to \(base) minutes are available each day. Completing the priority objective does not add more time."
        }
        return "Start with \(base) minutes each day. Completing the priority objective unlocks \(reward) additional minutes once; used gaming time is never erased."
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
            SumiStepper(
                "PLANNING CAPACITY",
                value: $controller.draft.capacityPercent,
                in: 25...100,
                step: 5,
                valueLabel: { "\($0)%" }
            )
        }
    }

    private var appClassificationSection: some View {
        SettingsCard(
            title: "APP CLASSIFICATION",
            detail: "Work apps add to Working time. Gaming apps spend the Gaming budget. Saved choices apply only to future observed activity."
        ) {
            AppClassificationLedger(draft: $controller.draft)
        }
    }

    private var calendarSection: some View {
        SettingsCard(title: "CALENDARS", detail: "Choose which Apple Calendars count as commitments and where confirmed meetings are added.") {
            if isLoadingCalendars {
                Text("Loading Apple Calendars…")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
            } else if let calendarAccessMessage {
                HStack(alignment: .center, spacing: 12) {
                    Text(calendarAccessMessage)
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.muted)
                    Spacer(minLength: 12)
                    if model.calendarSelectionAvailability == .needsPermission {
                        Button("CONNECT CALENDAR") {
                            Task { await connectCalendar() }
                        }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    }
                }
            } else {
                ZoidCalendarMultiSelectionField(
                    label: "CALENDARS TO CHECK",
                    defaultTitle: "All calendars",
                    options: calendarChoicesIncludingSavedSelections,
                    selectedIdentifiers: Binding(
                        get: { controller.draft.visibleCalendarIdentifierList },
                        set: { controller.draft.visibleCalendarIdentifierList = $0 }
                    )
                )
                ZoidCalendarSingleSelectionField(
                    label: "ADD NEW MEETINGS TO",
                    defaultTitle: "Default calendar",
                    options: calendarChoicesIncludingSavedSelections,
                    selection: Binding(
                        get: { controller.draft.schedulingCalendarIdentifierValue },
                        set: { controller.draft.schedulingCalendarIdentifierValue = $0 }
                    )
                )
                Text("Zoid 666 checks selected calendars for conflicts. Focus blocks remain in the Zoid 666 calendar.")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
            }
        }
    }

    private var calendarChoicesIncludingSavedSelections: [CalendarChoice] {
        let savedIdentifiers = Set(controller.draft.visibleCalendarIdentifierList + [controller.draft.schedulingCalendarIdentifierValue].compactMap { $0 })
        let availableIdentifiers = Set(calendarChoices.map(\.id))
        let missingChoices = savedIdentifiers.subtracting(availableIdentifiers).sorted().map {
            CalendarChoice(id: $0, title: "Unavailable calendar", sourceTitle: "Saved selection", isWritable: false)
        }
        return calendarChoices + missingChoices
    }

    private func refreshCalendars() async {
        isLoadingCalendars = true
        defer { isLoadingCalendars = false }
        switch model.calendarSelectionAvailability {
        case .available:
            do {
                calendarChoices = try model.availableCalendarChoices()
                calendarAccessMessage = calendarChoices.isEmpty ? "No Apple Calendars are available on this Mac." : nil
            } catch {
                calendarAccessMessage = "Apple Calendars could not be loaded."
            }
        case .needsPermission:
            calendarAccessMessage = "Connect Apple Calendar to choose calendars by name."
        case .unavailable:
            calendarAccessMessage = "Calendar access is unavailable. Enable full access in System Settings."
        }
    }

    private func connectCalendar() async {
        await model.requestCalendarAccess()
        await refreshCalendars()
    }

    private var privacySection: some View {
        SettingsCard(title: "AI + DATA RETENTION", detail: AIProviderCapabilities.production.settingsSummary) {
            Toggle("Analyze Screenwatch screenshots", isOn: $controller.draft.screenshotAnalysisEnabled)
                .toggleStyle(SumiToggleStyle())
            SumiChoiceList(
                "AI PROVIDER",
                options: AIProviderSelection.allCases,
                selection: Binding(
                    get: { controller.draft.aiProvider },
                    set: { controller.draft.selectAIProvider($0) }
                ),
                title: { AIProviderCapabilities.production[$0].settingsLabel },
                isOptionEnabled: { AIProviderCapabilities.production[$0].isSelectable }
            )
            SumiChoiceRail(
                "REMOTE EVIDENCE",
                options: RemoteEvidencePolicy.allCases,
                selection: $controller.draft.remoteEvidencePolicy,
                title: remoteEvidenceLabel,
                help: remoteEvidenceHelp
            )
            .disabled(
                !controller.draft.aiProvider.usesRemoteProcessing
                    || !AIProviderCapabilities.production[controller.draft.aiProvider].isSelectable
            )
            Button(showsRemoteEvidencePreview ? "HIDE REQUEST PREVIEW" : "PREVIEW REQUEST DATA") {
                showsRemoteEvidencePreview.toggle()
            }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
            .accessibilityIdentifier("settings.ai.preview.toggle")
            if showsRemoteEvidencePreview {
                remoteEvidencePreview
            }
            if controller.draft.aiProvider == .codexCLI {
                VStack(alignment: .leading, spacing: 7) {
                    SumiControlLabel("CODEX MODEL")
                    SumiDropdown {
                        SumiSelectorLabel(controller.draft.codexCLIModel.settingsLabel, systemImage: "cpu")
                    } content: { dismiss in
                        ForEach(CodexCLIModel.allCases, id: \.self) { model in
                            SumiDropdownOption(
                                model.settingsLabel,
                                systemImage: "cpu",
                                isSelected: controller.draft.codexCLIModel == model
                            ) {
                                controller.draft.codexCLIModel = model
                                dismiss()
                            }
                        }
                    }
                    .accessibilityLabel("Codex model")
                    if controller.draft.codexCLIModel == .custom {
                        TextField("Model ID", text: $controller.draft.codexCLICustomModelID)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Custom Codex model ID")
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    SumiControlLabel("REASONING EFFORT")
                    SumiDropdown {
                        SumiSelectorLabel(controller.draft.codexCLIReasoningEffort.settingsLabel, systemImage: "brain")
                    } content: { dismiss in
                        ForEach(CodexCLIReasoningEffort.allCases, id: \.self) { effort in
                            SumiDropdownOption(
                                effort.settingsLabel,
                                systemImage: "brain",
                                isSelected: controller.draft.codexCLIReasoningEffort == effort
                            ) {
                                controller.draft.codexCLIReasoningEffort = effort
                                dismiss()
                            }
                        }
                    }
                    .accessibilityLabel("Codex reasoning effort")
                    Text("Available model IDs depend on your Codex account and rollout. Use Custom model ID for any model shown in Codex but not listed here.")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                }
            }
            Button("CLEAR AI CACHE AND REQUEST HISTORY") {
                presentConfirmation(.deleteAIMetadata)
            }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
            .accessibilityIdentifier("settings.ai.clear-cache")
            if let dataStatusMessage {
                Text(dataStatusMessage)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.ai.clear-cache.status")
            }
            HStack(spacing: 18) {
                RetentionField(title: "Screenshots", days: $controller.draft.rawScreenshotRetentionDays)
                RetentionField(title: "Extracted text", days: $controller.draft.extractedTextRetentionDays)
                RetentionField(title: "Diagnostics", days: $controller.draft.diagnosticRetentionDays)
            }
            HStack(spacing: 18) {
                RetentionField(title: "Behavior records", days: $controller.draft.behaviorRecordRetentionDays)
                RetentionField(title: "Task sessions", days: $controller.draft.taskSessionRetentionDays)
                RetentionField(title: "Prompts", days: $controller.draft.promptRetentionDays)
                RetentionField(title: "Reviews + learning", days: $controller.draft.reviewRetentionDays)
            }
            Text("Retention cleanup runs locally in the background. It removes expired Zoid 666 records only and never deletes Screenwatch source screenshots.")
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
        }
    }

    private var remoteEvidencePreview: some View {
        let preview = RemoteEvidencePreview.representative(for: controller.draft.remoteEvidencePolicy)
        return VStack(alignment: .leading, spacing: 8) {
            Text(preview.heading)
                .font(Sumi.label(10))
                .sumiLabelTracking()
            Text(preview.explanation)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
            Text(preview.payload)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Sumi.paper)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
                .accessibilityIdentifier("settings.ai.preview.payload")
            Text("NOT INCLUDED IN AUTOMATIC PLANNING · \(preview.excluded.joined(separator: ", "))")
                .font(Sumi.label(9))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.ai.preview.exclusions")
            Text("Screen images use a separate voice action only when you explicitly ask for visual context; every transmission is recorded locally.")
                .font(Sumi.body(10))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.ai.preview.voice-boundary")
        }
        .padding(12)
        .background(Sumi.mist)
        .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.ai.preview")
    }

    private var wakeSection: some View {
        SettingsCard(title: "WAKE INTERVENTIONS", detail: "Disabled by default. Enabling requires explicit confirmation and stays bounded by this window and daily limit.") {
            Toggle("Allow wake interventions", isOn: Binding(
                get: { controller.draft.wakeEligible },
                set: { enabled in
                    if enabled {
                        presentConfirmation(.enableWake)
                    } else {
                        controller.requestWakeChange(false)
                    }
                }
            ))
            .toggleStyle(SumiToggleStyle())
            HStack(spacing: 18) {
                LocalTimeField(title: "Window starts", time: $controller.draft.wakeStart)
                LocalTimeField(title: "Window ends", time: $controller.draft.wakeEnd)
                SumiStepper(
                    "DAILY MAXIMUM",
                    value: $controller.draft.maximumDailyWakeInterventions,
                    in: 1...3,
                    valueLabel: { "\($0) WAKE\($0 == 1 ? "" : "S")" }
                )
            }
            .disabled(!controller.draft.wakeEligible)
            VStack(alignment: .leading, spacing: 6) {
                Text("QUIET DAYS").font(Sumi.label(9)).sumiLabelTracking().foregroundStyle(Sumi.muted)
                HStack(spacing: 10) {
                    ForEach(Weekday.allCases, id: \.self) { weekday in
                        QuietDayButton(
                            title: weekdayLabel(weekday),
                            isSelected: controller.draft.wakeQuietWeekdays.contains(weekday)
                        ) {
                            toggleQuietDay(weekday)
                        }
                    }
                }
            }
            .disabled(!controller.draft.wakeEligible)
        }
    }

    private var captureSection: some View {
        SettingsCard(
            title: "NATIVE CAPTURE",
            detail: "Legacy Screenwatch remains the production source until parity is explicitly passed. Native capture uses a five-second metadata cadence and skips images after 90 seconds idle."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SumiControlLabel("CAPTURE MODE")
                HStack(spacing: 8) {
                    captureModeButton(.legacy, title: "LEGACY")
                    captureModeButton(.parity, title: "PARITY")
                    captureModeButton(.native, title: "NATIVE")
                }
                Text(captureModeExplanation)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                if !captureConfiguration.parityPassed {
                    Text("NATIVE LOCKED · Parity has not passed. Selecting Native is disabled; Parity captures app-owned data while legacy remains authoritative.")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SumiControlLabel("CAPTURED DISPLAYS")
                if connectedDisplayIDs.isEmpty {
                    Text("No active displays were reported by CoreGraphics.")
                        .font(Sumi.body(12)).foregroundStyle(Sumi.seal)
                } else {
                    Text(captureConfiguration.configuredDisplayIDs.isEmpty ? "All connected displays are selected." : "Only checked displays are selected.")
                        .font(Sumi.body(11)).foregroundStyle(Sumi.muted)
                    ForEach(Array(connectedDisplayIDs.enumerated()), id: \.element) { index, displayID in
                        Toggle("Display \(index + 1) · ID \(displayID)", isOn: Binding(
                            get: { captureConfiguration.configuredDisplayIDs.isEmpty || captureConfiguration.configuredDisplayIDs.contains(displayID) },
                            set: { enabled in updateDisplay(displayID, enabled: enabled) }
                        ))
                        .toggleStyle(SumiToggleStyle())
                    }
                    Button("CAPTURE ALL DISPLAYS") { saveCaptureConfiguration(displayIDs: []) }
                        .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                }
            }

            if let health = model.captureHealth {
                HStack(spacing: 18) {
                    SettingsHeaderFact(label: "MODE", value: health.isEnabled ? "NATIVE" : "LEGACY")
                    SettingsHeaderFact(label: "PROCESS", value: health.isRunning ? "RUNNING" : "STOPPED", isAttention: health.isEnabled && !health.isRunning)
                    SettingsHeaderFact(label: "LAST CAPTURE", value: health.lastCaptureAt?.formatted(date: .omitted, time: .shortened) ?? "NONE", isAttention: health.isEnabled && health.lastCaptureAt == nil)
                }
                Text(health.detail)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
                capturePermissionRow("SCREEN RECORDING", health.screenRecording, privacyAnchor: "Privacy_ScreenCapture")
                capturePermissionRow("ACCESSIBILITY", health.accessibility, privacyAnchor: "Privacy_Accessibility")
                capturePermissionRow("AUTOMATION", health.automation, privacyAnchor: "Privacy_Automation")
                VStack(alignment: .leading, spacing: 5) {
                    Text("CONFIGURED DISPLAYS").font(Sumi.label(9)).sumiLabelTracking().foregroundStyle(Sumi.muted)
                    Text(health.configuredDisplayIDs.isEmpty
                         ? "All connected displays"
                         : health.configuredDisplayIDs.map(String.init).joined(separator: ", "))
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.ink)
                }
            } else {
                Text("Capture health is unavailable. Native mode is not assumed active; legacy Screenwatch remains the safe default.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.seal)
            }
            Button("REFRESH LIVE HEALTH") { Task { await model.refreshCaptureHealth() } }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
            if let captureConfigurationMessage {
                Text(captureConfigurationMessage)
                    .font(Sumi.body(12))
                    .foregroundStyle(captureConfigurationMessage.contains("not saved") ? Sumi.seal : Sumi.muted)
            }
        }
    }

    private func captureModeButton(_ mode: NativeCaptureConfiguration.Mode, title: String) -> some View {
        Button(title) {
            saveCaptureConfiguration(mode: mode)
        }
        .buttonStyle(SumiActionButtonStyle(role: captureConfiguration.mode == mode ? .primary : .quiet, size: .standard))
        .disabled(mode == .native && !captureConfiguration.parityPassed)
        .accessibilityLabel("Use \(title.lowercased()) capture mode")
    }

    private var captureModeExplanation: String {
        switch captureConfiguration.mode {
        case .legacy: "Legacy Screenwatch is authoritative. Native capture is off."
        case .parity: "Both pipelines run, but only legacy data is ingested. Use this to validate parity safely."
        case .native: "App-owned native capture is authoritative. This state is available only after parity passes."
        }
    }

    private var connectedDisplayIDs: [UInt32] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private func updateDisplay(_ displayID: UInt32, enabled: Bool) {
        var selected = Set(captureConfiguration.configuredDisplayIDs.isEmpty ? connectedDisplayIDs : captureConfiguration.configuredDisplayIDs)
        if enabled { selected.insert(displayID) } else { selected.remove(displayID) }
        saveCaptureConfiguration(displayIDs: selected.sorted())
    }

    private func saveCaptureConfiguration(mode: NativeCaptureConfiguration.Mode? = nil, displayIDs: [UInt32]? = nil) {
        let requested = NativeCaptureConfiguration(
            mode: mode ?? captureConfiguration.mode,
            configuredDisplayIDs: displayIDs ?? captureConfiguration.configuredDisplayIDs,
            parityPassed: captureConfiguration.parityPassed
        )
        do {
            try NativeCaptureConfigurationStore().save(requested)
            captureConfiguration = requested
            controller.draft.captureMode = CaptureMode(rawValue: requested.mode.rawValue) ?? .legacy
            controller.draft.captureDisplayIDs = requested.configuredDisplayIDs
            guard controller.save() != nil else {
                captureConfigurationMessage = "Runtime capture configuration saved, but policy storage is read-only. The agent reloads runtime configuration within five seconds."
                return
            }
            captureConfigurationMessage = "Capture configuration and audited policy saved. The background agent reloads it within five seconds."
            Task {
                try? await Task.sleep(for: .seconds(6))
                await model.refreshCaptureHealth()
            }
        } catch {
            captureConfigurationMessage = "Capture configuration was not saved: \(error.localizedDescription)"
        }
    }

    private func capturePermissionRow(_ title: String, _ health: RuntimePermissionHealth, privacyAnchor: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(Sumi.label(9)).sumiLabelTracking()
            Spacer()
            Text(health.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(health == .granted || health == .notRequired ? Sumi.okay : Sumi.seal)
            if health == .denied || health == .unknown {
                Button("REPAIR") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacyAnchor)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
    }

    private func weekdayLabel(_ weekday: Weekday) -> String {
        Calendar.current.shortWeekdaySymbols[max(0, min(Calendar.current.shortWeekdaySymbols.count - 1, weekday.rawValue - 1))]
    }

    private var dataSection: some View {
        SettingsCard(title: "LOCAL DATA", detail: "Inspect what Zoid 666 stores on this Mac, export a reviewed redacted diagnostic file, or selectively delete local records. None of these controls require a cloud service.") {
            if isLoadingPrivacyInventory {
                ProgressView("Inspecting local data...")
                    .accessibilityIdentifier("settings.data.inventory.loading")
            } else if let privacyInventory {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("STORED DATA INVENTORY")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: privacyInventory.databaseBytes, countStyle: .file))
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.muted)
                    }
                    ForEach(privacyInventory.dataClasses) { dataClass in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dataClass.title).font(Sumi.body(12)).foregroundStyle(Sumi.ink)
                                Text(dataClass.detail).font(Sumi.body(10)).foregroundStyle(Sumi.muted)
                            }
                            Spacer(minLength: 12)
                            Text("\(dataClass.recordCount)")
                                .font(Sumi.label(9))
                                .sumiLabelTracking()
                                .foregroundStyle(dataClass.recordCount == 0 ? Sumi.muted : Sumi.sealDeep)
                        }
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(dataClass.title), \(dataClass.recordCount) records. \(dataClass.detail)")
                    }
                    Text("DATABASE SCHEMA V\(privacyInventory.schemaVersion) · \(privacyInventory.databasePath)")
                        .font(Sumi.label(7))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.muted)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(Sumi.softPaper)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
                .accessibilityIdentifier("settings.data.inventory")
            } else {
                Text("The local data inventory is unavailable. The background agent was not asked to delete or export anything.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.seal)
                    .accessibilityIdentifier("settings.data.inventory.unavailable")
            }

            Button("OPEN LOCAL DATA FOLDER") { controller.openDataFolder() }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .accessibilityLabel("Open Zoid 666 local data folder")

            VStack(alignment: .leading, spacing: 5) {
                Text("EXPORT PREVIEW")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                Text("The JSON export contains only its creation time, schema version, and grouped counts for action states, source health, prompts, and meeting suggestions. It excludes titles, conversation text, URLs, file paths, event names, payloads, screenshots, and credentials.")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Sumi.sealWash)
            .overlay { Rectangle().stroke(Sumi.seal.opacity(0.34), lineWidth: 1) }
            .accessibilityIdentifier("settings.data.export.preview")

            Button("CHOOSE EXPORT DESTINATION") { chooseExportDestination() }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .accessibilityIdentifier("settings.data.export.choose-destination")

            HStack(alignment: .bottom, spacing: 12) {
                SumiDateField("DELETE FROM", selection: $deleteRangeStart, displayedComponents: .date)
                SumiDateField("THROUGH", selection: $deleteRangeEnd, displayedComponents: .date)
                Button("DELETE RANGE") { presentConfirmation(.deleteRange) }
                    .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .large))
            }
            Text("The THROUGH date is included. Source screenshots owned by Screenwatch or other apps are never deleted.")
                .font(Sumi.body(10))
                .foregroundStyle(Sumi.muted)
            if !recentBehaviorSessions.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("RECENT BEHAVIOR SESSIONS")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                    ForEach(recentBehaviorSessions) { session in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.application).font(Sumi.body(12))
                                Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) - \(session.endedAt.formatted(date: .omitted, time: .shortened)) · \(session.recordCount) records")
                                    .font(Sumi.body(10))
                                    .foregroundStyle(Sumi.muted)
                            }
                            Spacer()
                            Button("DELETE SESSION") { presentConfirmation(.deleteBehaviorSession(session)) }
                                .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .compact))
                                .accessibilityLabel("Delete \(session.application) behavior session starting \(session.startedAt.formatted())")
                        }
                    }
                }
                .accessibilityIdentifier("settings.data.behavior-sessions")
            }
            Button("DELETE TODAY ONLY") { presentConfirmation(.deleteToday) }
                .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .standard))
            Button("DELETE EXTRACTED CONVERSATION TEXT") { presentConfirmation(.deleteExtractedText) }
                .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .standard))
            Button("DELETE ALL RAW BEHAVIOR METADATA") { presentConfirmation(.deleteRawBehavior) }
                .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .standard))
            Button("DELETE AI REQUEST METADATA") { presentConfirmation(.deleteAIMetadata) }
                .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .standard))
            Button("DELETE REVIEWS AND LEARNED RULES") { presentConfirmation(.deleteLearning) }
                .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .standard))
            Button("DELETE ALL ZOID 666 DATA") { presentConfirmation(.deleteAllData) }
                .buttonStyle(SumiActionButtonStyle(role: .destructive, size: .large))
                .accessibilityIdentifier("settings.data.delete-all")
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
            await model.refreshTodaySnapshot()
            await refreshPrivacyInventory()
        } catch {
            dataStatusMessage = "The background agent could not complete this data request."
        }
    }

    private func refreshPrivacyInventory() async {
        isLoadingPrivacyInventory = true
        let service = try? PrivacyDataService(
            databaseURL: RuntimeEnvironment.current().databaseURL,
            exportRoot: RuntimeEnvironment.current().exportRoot
        )
        privacyInventory = try? service?.storedDataInventory()
        recentBehaviorSessions = (try? service?.recentBehaviorSessions()) ?? []
        isLoadingPrivacyInventory = false
    }

    private func chooseExportDestination() {
        let panel = NSSavePanel()
        panel.title = "Export redacted Zoid 666 diagnostics"
        panel.prompt = "EXPORT REDACTED JSON"
        panel.nameFieldStringValue = "zoid-666-redacted-diagnostics.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await performDataCommand(.exportRedactedDiagnosticsTo(path: url.path)) }
    }

    private func operatingModeLabel(_ mode: OperatingMode) -> String {
        switch mode {
        case .observe: "Observe only"
        case .suggest: "Suggest plans"
        case .assist: "Approve actions"
        case .autonomous: "Autonomous"
        }
    }

    private func coachingLevelLabel(_ level: CoachingLevel) -> String {
        switch level {
        case .gentle: "Gentle"
        case .accountability: "Accountability"
        }
    }

    private func remoteEvidenceLabel(_ policy: RemoteEvidencePolicy) -> String {
        switch policy {
        case .localOnly: "Local only - remote AI off"
        case .redactedMetadataOnly: "Redacted metadata"
        case .explicitPrivateContent: "Private content"
        }
    }

    private func remoteEvidenceHelp(_ policy: RemoteEvidencePolicy) -> String {
        switch policy {
        case .localOnly:
            "Keeps all evidence on this Mac. Codex is not called; planning continues with deterministic rules."
        case .redactedMetadataOnly:
            "Sends anonymous task labels, dates, priority, carryover, deferral, and time statistics. Task titles and app names stay hidden."
        case .explicitPrivateContent:
            "Also sends real task titles and app names for more contextual advice. Screenshots, extracted text, and internal task IDs stay private."
        }
    }

    private func toggleQuietDay(_ weekday: Weekday) {
        if controller.draft.wakeQuietWeekdays.contains(weekday) {
            controller.draft.wakeQuietWeekdays.removeAll { $0 == weekday }
        } else {
            controller.draft.wakeQuietWeekdays.append(weekday)
        }
    }

    private func presentConfirmation(_ intent: SettingsConfirmation) {
        switch intent {
        case .enableWake:
            modalCoordinator.present(
                eyebrow: "HIGH-TRUST CAPABILITY",
                title: "Enable wake interventions?",
                message: "Zoid 666 may notify you during the configured wake window, up to the written daily limit. You can disable this capability here at any time.",
                confirmTitle: "I UNDERSTAND, ENABLE",
                confirmRole: .accent,
                confirm: {
                    controller.draft.wakeEligible = true
                    controller.save()
                },
                cancel: {
                    controller.draft.wakeEligible = false
                }
            )
        case .deleteRange:
            guard let range = PrivacyDeletionRange.inclusive(
                from: deleteRangeStart,
                through: deleteRangeEnd
            ) else {
                dataStatusMessage = "The DELETE FROM date must be on or before the THROUGH date."
                return
            }
            modalCoordinator.present(
                eyebrow: "LOCAL DATA / DESTRUCTIVE",
                title: "Delete the selected evidence?",
                message: "Local evidence from \(range.start.formatted(date: .abbreviated, time: .omitted)) through \(range.through.formatted(date: .abbreviated, time: .omitted)), including the full THROUGH date, will be deleted by the background agent. Source screenshots are not changed. This cannot be undone.",
                confirmTitle: "DELETE SELECTED RANGE",
                confirmRole: .destructive,
                confirm: {
                    Task { await performDataCommand(.deleteDataRange(start: range.start, end: range.exclusiveEnd)) }
                }
            )
        case .deleteToday:
            guard let range = PrivacyDeletionRange.inclusive(from: Date(), through: Date()) else { return }
            modalCoordinator.present(
                eyebrow: "LOCAL DATA / DESTRUCTIVE",
                title: "Delete today's local evidence?",
                message: "Plans, behavior records, extracted facts, and meeting suggestions dated today will be deleted. Source screenshots are not changed. This cannot be undone.",
                confirmTitle: "DELETE TODAY",
                confirmRole: .destructive,
                confirm: { Task { await performDataCommand(.deleteDataRange(start: range.start, end: range.exclusiveEnd)) } }
            )
        case let .deleteBehaviorSession(session):
            modalCoordinator.present(
                eyebrow: "LOCAL DATA / DESTRUCTIVE",
                title: "Delete this behavior session?",
                message: "\(session.recordCount) local \(session.application) behavior records from \(session.startedAt.formatted(date: .abbreviated, time: .shortened)) through \(session.endedAt.formatted(date: .omitted, time: .shortened)) will be deleted. Source screenshots are not changed. This cannot be undone.",
                confirmTitle: "DELETE SESSION",
                confirmRole: .destructive,
                confirm: {
                    Task {
                        await performDataCommand(.deleteBehaviorSession(
                            application: session.application,
                            startedAt: session.startedAt,
                            endedAt: session.endedAt
                        ))
                    }
                }
            )
        case .deleteExtractedText:
            modalCoordinator.present(
                eyebrow: "LOCAL DATA / DESTRUCTIVE",
                title: "Delete extracted conversation text?",
                message: "All locally extracted conversation text will be deleted. Source applications and their original messages are not changed. This cannot be undone.",
                confirmTitle: "DELETE EXTRACTED TEXT",
                confirmRole: .destructive,
                confirm: {
                    Task { await performDataCommand(.deleteExtractedConversationText) }
                }
            )
        case .deleteRawBehavior:
            presentDataDeletionConfirmation(
                title: "Delete all raw behavior metadata?",
                message: "All local behavior rows, screenshot indexes, analyses, and extracted facts will be deleted. Screenwatch and other source applications keep their original files.",
                confirmTitle: "DELETE BEHAVIOR METADATA",
                command: .deleteRawBehaviorMetadata
            )
        case .deleteAIMetadata:
            presentDataDeletionConfirmation(
                title: "Delete AI request metadata?",
                message: "Local model-run metadata, cached responses, Codex job records, and transmission receipts will be deleted. Keychain credentials are not changed.",
                confirmTitle: "DELETE AI METADATA",
                command: .deleteAIRequestMetadata
            )
        case .deleteLearning:
            presentDataDeletionConfirmation(
                title: "Delete reviews and learned rules?",
                message: "Local estimate-learning samples, aggregates, and planner trust history will be deleted. Future recommendations will begin learning again from defaults.",
                confirmTitle: "DELETE LEARNED DATA",
                command: .deleteReviewsAndLearnedRules
            )
        case .deleteAllData:
            presentDataDeletionConfirmation(
                title: "Delete all Zoid 666 data?",
                message: "Every local user record in the Zoid 666 database will be deleted, including plans, settings, prompts, activity, voice history, audit records, and learned data. The empty database schema remains so the app can restart safely. Source apps, source screenshots, and Keychain credentials are not changed. This cannot be undone.",
                confirmTitle: "DELETE ALL LOCAL DATA",
                command: .deleteAllUserData
            )
        case .restorePolicy:
            modalCoordinator.present(
                eyebrow: "POLICY HISTORY",
                title: "Restore the previous policy?",
                message: "Your current settings will remain in history. The previous settings will be saved as a new audited policy version.",
                confirmTitle: "RESTORE PREVIOUS POLICY",
                confirmRole: .primary,
                confirm: {
                    controller.rollbackToPreviousPolicy()
                }
            )
        }
    }

    private func presentDataDeletionConfirmation(
        title: String,
        message: String,
        confirmTitle: String,
        command: AgentMutationCommand
    ) {
        modalCoordinator.present(
            eyebrow: "LOCAL DATA / DESTRUCTIVE",
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            confirmRole: .destructive,
            confirm: { Task { await performDataCommand(command) } }
        )
    }
}

struct PrivacyDeletionRange: Equatable {
    let start: Date
    let through: Date
    let exclusiveEnd: Date

    static func inclusive(
        from start: Date,
        through end: Date,
        calendar: Calendar = .current
    ) -> PrivacyDeletionRange? {
        let startDay = calendar.startOfDay(for: start)
        let throughDay = calendar.startOfDay(for: end)
        guard startDay <= throughDay,
              let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: throughDay) else {
            return nil
        }
        return PrivacyDeletionRange(start: startDay, through: throughDay, exclusiveEnd: exclusiveEnd)
    }
}

private enum SettingsConfirmation {
    case enableWake
    case deleteRange
    case deleteToday
    case deleteBehaviorSession(PrivacyBehaviorSession)
    case deleteExtractedText
    case deleteRawBehavior
    case deleteAIMetadata
    case deleteLearning
    case deleteAllData
    case restorePolicy
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case command
    case signals
    case intelligence
    case records

    var id: Self { self }

    var number: String {
        switch self {
        case .command: "01"
        case .signals: "02"
        case .intelligence: "03"
        case .records: "04"
        }
    }

    var title: String {
        switch self {
        case .command: "Command"
        case .signals: "Signals"
        case .intelligence: "Intelligence"
        case .records: "Records"
        }
    }

    var navigationDetail: String {
        switch self {
        case .command: "Mode and schedule"
        case .signals: "Apps and calendars"
        case .intelligence: "AI, privacy, wake"
        case .records: "Local data and audit"
        }
    }

    var summary: String {
        switch self {
        case .command:
            "Set the operating boundary and the hours Zoid 666 plans around. These controls define when the system may act."
        case .signals:
            "Teach Zoid 666 which activity counts as work or gaming, then choose the calendars that represent real commitments."
        case .intelligence:
            "Choose what may be analyzed, what can leave this Mac, and whether high-trust wake interventions are allowed."
        case .records:
            "Inspect agent actions, export diagnostics, and control the local evidence Zoid 666 retains."
        }
    }
}

private struct SettingsHeaderFact: View {
    let label: String
    let value: String
    var isAttention = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Sumi.label(7))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
            Text(value)
                .font(Sumi.label(9))
                .sumiLabelTracking()
                .foregroundStyle(isAttention ? Sumi.seal : Sumi.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 78, minHeight: 42, alignment: .leading)
        .background(isAttention ? Sumi.sealWash : Sumi.paper)
        .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
    }
}

private struct SettingsCategoryButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Text(category.number)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(isSelected ? Sumi.paper : Sumi.seal)
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title.uppercased())
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                    Text(category.navigationDetail)
                        .font(Sumi.body(10))
                        .foregroundStyle(isSelected ? Sumi.paper.opacity(0.78) : Sumi.muted)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Sumi.paper : Sumi.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Sumi.seal : Sumi.paper)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        .accessibilityLabel("\(category.title), \(category.navigationDetail)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Sumi.seal)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(Sumi.label(10))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.ink)
                    Text(detail)
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sumi.paper)
        .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
    }
}

private struct LocalTimeField: View {
    let title: String
    @Binding var time: LocalTime

    var body: some View {
        SumiDateField(
            title,
            selection: Binding(
                get: { date(from: time) },
                set: { time = localTime(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
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
        SumiStepper(title, value: $days, in: 0...3_650, valueLabel: { "\($0) DAYS" })
    }
}

private struct ZoidCalendarMultiSelectionField: View {
    let label: String
    let defaultTitle: String
    let options: [CalendarChoice]
    @Binding var selectedIdentifiers: [String]

    private var selectedSet: Set<String> { Set(selectedIdentifiers) }

    private var summary: String {
        if selectedIdentifiers.isEmpty { return defaultTitle }
        if selectedIdentifiers.count == 1,
           let option = options.first(where: { $0.id == selectedIdentifiers[0] }) {
            return option.displayName
        }
        return "\(selectedIdentifiers.count) calendars"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SumiControlLabel(label)
            SumiDropdown {
                SumiSelectorLabel(summary, systemImage: "calendar")
            } content: { _ in
                SumiDropdownOption(
                    defaultTitle,
                    systemImage: selectedIdentifiers.isEmpty ? "checkmark" : "calendar.badge.clock",
                    isSelected: selectedIdentifiers.isEmpty
                ) {
                    selectedIdentifiers = []
                }
                SumiDropdownDivider()
                ForEach(options) { option in
                    SumiDropdownOption(
                        option.displayName,
                        systemImage: selectedSet.contains(option.id) ? "checkmark" : "calendar",
                        isSelected: selectedSet.contains(option.id)
                    ) {
                        toggle(option.id)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
            .accessibilityValue(summary)
            .help("Choose one or more calendars. Select All calendars to use every available calendar.")
        }
    }

    private func toggle(_ identifier: String) {
        if let index = selectedIdentifiers.firstIndex(of: identifier) {
            selectedIdentifiers.remove(at: index)
        } else {
            selectedIdentifiers.append(identifier)
        }
    }
}

private struct ZoidCalendarSingleSelectionField: View {
    let label: String
    let defaultTitle: String
    let options: [CalendarChoice]
    @Binding var selection: String?

    private var summary: String {
        guard let selection else { return defaultTitle }
        return options.first(where: { $0.id == selection })?.displayName ?? "Unavailable calendar"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SumiControlLabel(label)
            SumiDropdown {
                SumiSelectorLabel(summary, systemImage: "calendar")
            } content: { dismiss in
                SumiDropdownOption(
                    defaultTitle,
                    systemImage: selection == nil ? "checkmark" : "calendar.badge.plus",
                    isSelected: selection == nil
                ) {
                    selection = nil
                    dismiss()
                }
                SumiDropdownDivider()
                ForEach(options.filter(\.isWritable)) { option in
                    SumiDropdownOption(
                        option.displayName,
                        systemImage: selection == option.id ? "checkmark" : "calendar",
                        isSelected: selection == option.id
                    ) {
                        selection = option.id
                        dismiss()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
            .accessibilityValue(summary)
            .help("Choose the writable Apple Calendar used for newly confirmed meetings.")
        }
    }
}

private struct QuietDayButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(isSelected ? Sumi.paper : Sumi.ink)
                .frame(minWidth: 38, minHeight: 30)
                .background(isSelected ? Sumi.ink : Sumi.paper)
                .overlay { Rectangle().stroke(isSelected ? Sumi.ink : Sumi.rule, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Quiet day" : "Interventions allowed")
    }
}
