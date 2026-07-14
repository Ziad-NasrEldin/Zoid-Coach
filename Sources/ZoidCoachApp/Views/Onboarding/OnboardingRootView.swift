import AppKit
import SwiftUI
import ZoidCoachCore

struct OnboardingRootView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        GeometryReader { geometry in
            let layout = OnboardingWelcomeLayout(hostWidth: geometry.size.width)
            HStack(spacing: 0) {
                if coordinator.progress.currentStep != .welcome || layout.showsProgressRail {
                    progressRail
                    Rectangle().fill(Sumi.rule).frame(width: 1)
                }
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Rectangle().fill(Sumi.paleRule).frame(height: 1)
                    ScrollView {
                        stepContent
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(.horizontal, coordinator.progress.currentStep == .welcome ? layout.horizontalPadding : 44)
                            .padding(.vertical, 36)
                    }
                    Rectangle().fill(Sumi.paleRule).frame(height: 1)
                    controls
                }
            }
        }
        .environment(\.layoutDirection, welcomeCopy.isRightToLeft ? .rightToLeft : .leftToRight)
        .background(Sumi.paper)
        .foregroundStyle(Sumi.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.root")
        .task(id: coordinator.progress.currentStep) {
            await coordinator.inspectCurrentSource()
            if [.applicationInventory, .activityClassification].contains(
                coordinator.progress.currentStep
            ) {
                coordinator.loadApplicationInventory()
            }
            if coordinator.progress.currentStep == .firstDailyPlan {
                await coordinator.prepareFirstDailyPlan()
            }
            if coordinator.progress.currentStep == .deliveryTest {
                await coordinator.restoreTestPrompt()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await coordinator.applicationDidBecomeActive() }
        }
    }

    private var progressRail: some View {
        let copy = welcomeCopy
        VStack(alignment: .leading, spacing: 0) {
            Text(copy.progressTitle)
                .font(Sumi.label())
                .tracking(1.5)
                .padding(.bottom, 24)
            ForEach(Array(OnboardingProgress.stepSequence.enumerated()), id: \.element) {
                index, step in
                HStack(spacing: 10) {
                    Text(String(format: "%02d", index + 1))
                        .font(Sumi.label())
                        .foregroundStyle(step == coordinator.progress.currentStep ? Sumi.paper : Sumi.muted)
                        .frame(width: 26)
                    Text(shortTitle(for: step).uppercased(with: locale))
                        .font(Sumi.label())
                        .tracking(1.1)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(step == coordinator.progress.currentStep ? Sumi.ink : Color.clear)
                .accessibilityLabel(copy.stepAccessibilityLabel(index + 1, shortTitle(for: step)))
                .accessibilityValue(stepState(step))
            }
            Spacer()
            Text(copy.progressFooter)
                .font(Sumi.label(8))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 232)
        .background(Sumi.softPaper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.progress")
    }

    private var header: some View {
        let copy = welcomeCopy
        HStack {
            Text(copy.setupProgress(currentPosition, OnboardingProgress.stepSequence.count))
                .font(Sumi.label())
                .tracking(1.4)
            Spacer()
            Button(copy.exitTitle) { coordinator.exitToToday() }
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                .keyboardShortcut(.cancelAction)
                .disabled(coordinator.isWorking)
                .accessibilityHint(copy.exitHint)
                .accessibilityIdentifier("onboarding.exit")
        }
        .padding(.horizontal, 28)
        .frame(height: 58)
    }

    @ViewBuilder
    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch coordinator.progress.currentStep {
            case .welcome:
                let copy = welcomeCopy
                OnboardingEditorialStep(
                    eyebrow: copy.eyebrow,
                    title: copy.title,
                    bodyText: copy.body,
                    note: copy.note
                )
                .environment(\.layoutDirection, copy.isRightToLeft ? .rightToLeft : .leftToRight)
                .accessibilityLabel(copy.accessibilitySummary)
                .accessibilityIdentifier("onboarding.welcome.positioning")
            case .localPrivacy:
                OnboardingEditorialStep(
                    eyebrow: "LOCAL TRUTH",
                    title: "Your behavioral record stays on this Mac by default.",
                    bodyText: "Reminders, Screenwatch summaries, plans, and coaching history are stored locally. Zoid 666 does not require an account, employer dashboard, or remote AI service.",
                    note: "AI is optional. Rules-only coaching remains fully usable, and any later remote processing requires an explicit choice."
                )
            case .reminders:
                sourceStep(
                    step: .reminders,
                    eyebrow: "INTENT SOURCE",
                    title: "Connect Apple Reminders",
                    explanation: "Reminders tells Zoid 666 what you intended to do. Full access lets the app read tasks and update completion. If you decline, setup continues with manual local planning.",
                    grantTitle: "REQUEST REMINDERS ACCESS"
                )
                reminderListSelection
            case .screenwatch:
                sourceStep(
                    step: .screenwatch,
                    eyebrow: "BEHAVIOR SOURCE",
                    title: "Find Screenwatch",
                    explanation: "Screenwatch contributes time and application evidence. Zoid 666 checks the expected daily JSONL stream without showing captured titles, URLs, or screenshots here.",
                    grantTitle: "CHECK EXPECTED FOLDER"
                )
                screenshotAnalysisConsent
            case .notifications:
                sourceStep(
                    step: .notifications,
                    eyebrow: "DELIVERY",
                    title: "Allow bounded notifications",
                    explanation: "Notifications carry morning plans and small coaching choices. They are optional; every important action remains available in Today if you decline.",
                    grantTitle: "REQUEST NOTIFICATION ACCESS"
                )
                notificationDeliveryCheck
            case .applicationInventory:
                inventoryStep
            case .activityClassification:
                classificationStep
            case .schedule:
                scheduleStep
            case .gamingPolicy:
                gamingPolicyStep
            case .coachingMode:
                coachingModeStep
            case .deliveryTest:
                deliveryTestStep
            case .firstDailyPlan:
                firstDailyPlanStep
            }
            if let error = coordinator.errorMessage {
                Text(welcomeCopy.setupErrorLabel(error))
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.sealDeep)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Sumi.sealWash)
                .accessibilityLabel(welcomeCopy.setupErrorLabel(error))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.\(coordinator.progress.currentStep.rawValue)")
    }

    @ViewBuilder
    private var reminderListSelection: some View {
        if coordinator.progress.remindersAccess == .granted {
            VStack(alignment: .leading, spacing: 12) {
                Text("CHOOSE LISTS")
                    .font(Sumi.label())
                    .tracking(1.2)
                Text("Choose Include or Exclude for every current list. Zoid 666 saves each choice immediately and uses the list's stable Apple identifier even if its visible name changes.")
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.muted)
                switch coordinator.reminderListDiscovery {
                case .idle, .loading:
                    ProgressView("Loading Reminder lists...")
                        .accessibilityIdentifier("onboarding.reminders.lists.loading")
                case let .permissionRequired(message):
                    Text(message)
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.sealDeep)
                        .accessibilityIdentifier("onboarding.reminders.lists.permission")
                    Button("OPEN SYSTEM SETTINGS") {
                        coordinator.openSystemSettings(for: .reminders)
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .accessibilityIdentifier("onboarding.reminders.lists.permission-repair")
                case let .failed(message):
                    Text(message)
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.sealDeep)
                        .accessibilityIdentifier("onboarding.reminders.lists.error")
                    Button("RETRY LISTS") {
                        Task { await coordinator.loadReminderLists() }
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .keyboardShortcut("r", modifiers: [.option])
                    .accessibilityIdentifier("onboarding.reminders.lists.retry")
                case .empty:
                    Text("Apple Reminders returned no lists. Confirm local-only planning to continue.")
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.muted)
                        .accessibilityIdentifier("onboarding.reminders.lists.empty")
                    Button(
                        coordinator.progress.emptyReminderListFallbackConfirmed
                            ? "LOCAL-ONLY PLANNING CONFIRMED"
                            : "CONFIRM LOCAL-ONLY PLANNING"
                    ) {
                        coordinator.confirmEmptyReminderListFallback()
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .disabled(coordinator.progress.emptyReminderListFallbackConfirmed)
                    .keyboardShortcut("l", modifiers: [.option])
                    .accessibilityIdentifier("onboarding.reminders.lists.empty-confirm")
                case let .available(lists):
                    VStack(spacing: 0) {
                        ForEach(lists) { list in
                            reminderListRow(list)
                        }
                    }
                    .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("onboarding.reminders.lists")
                }
            }
        }
    }

    private func reminderListRow(_ list: ReminderListChoice) -> some View {
        let decision = coordinator.reminderListDecision(for: list.id)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(Sumi.body(14))
                Text(list.id)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Button(decision == true ? "INCLUDED" : "INCLUDE") {
                coordinator.setReminderListDecision(true, listID: list.id)
            }
            .buttonStyle(SumiActionButtonStyle(
                role: decision == true ? .primary : .quiet,
                size: .standard
            ))
            .accessibilityLabel("Include \(list.name)")
            .accessibilityValue(decision == true ? "Selected" : "Not selected")
            .accessibilityIdentifier("onboarding.reminders.list.\(list.id).include")
            Button(decision == false ? "EXCLUDED" : "EXCLUDE") {
                coordinator.setReminderListDecision(false, listID: list.id)
            }
            .buttonStyle(SumiActionButtonStyle(
                role: decision == false ? .primary : .quiet,
                size: .standard
            ))
            .accessibilityLabel("Exclude \(list.name)")
            .accessibilityValue(decision == false ? "Selected" : "Not selected")
            .accessibilityIdentifier("onboarding.reminders.list.\(list.id).exclude")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.reminders.list.\(list.id)")
    }

    private func sourceStep(
        step: OnboardingStep,
        eyebrow: String,
        title: String,
        explanation: String,
        grantTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingEditorialStep(
                eyebrow: eyebrow,
                title: title,
                bodyText: explanation,
                note: "Zoid 666 asks once. A denied or deferred choice is respected and can be repaired later in System Settings."
            )
            if let health = coordinator.sourceHealth[step] {
                OnboardingSourceStatus(health: health, step: step)
            } else {
                Text("STATUS · NOT CHECKED")
                    .font(Sumi.label())
                    .tracking(1.2)
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("onboarding.source.\(step.rawValue).status")
            }
            HStack(spacing: 10) {
                Button(grantTitle) {
                    Task { await coordinator.requestAccess(for: step) }
                }
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                .disabled(
                    coordinator.isWorking
                        || accessDecision(for: step) == .denied
                        || accessDecision(for: step) == .granted
                )
                .keyboardShortcut("g", modifiers: [.option])
                .accessibilityIdentifier("onboarding.source.\(step.rawValue).grant")
                Button("NOT NOW") { coordinator.deferAccess(for: step) }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .keyboardShortcut("d", modifiers: [.option])
                    .disabled(
                        coordinator.isWorking
                            || (step == .reminders
                                && (accessDecision(for: step) == .granted
                                    || coordinator.sourceHealth[.reminders]?.state == .healthy))
                    )
                    .accessibilityHint("Continues setup in degraded mode without asking again.")
                    .accessibilityIdentifier("onboarding.source.\(step.rawValue).defer")
                Button("RECHECK") {
                    Task { await coordinator.inspectCurrentSource() }
                }
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .standard))
                .disabled(coordinator.isWorking)
                .accessibilityIdentifier("onboarding.retry")
                repairButton(for: step)
            }
        }
    }

    @ViewBuilder
    private func repairButton(for step: OnboardingStep) -> some View {
        if step == .screenwatch {
            Button("CHOOSE FOLDER") { chooseScreenwatchFolder() }
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .standard))
                .disabled(coordinator.isWorking)
                .accessibilityHint("Choose the Screenwatch days folder. Access is remembered with a security-scoped bookmark.")
                .accessibilityIdentifier("onboarding.source.screenwatch.repair")
            if coordinator.screenwatchSetupStatus?.source == .alternateFolder {
                Button("USE DEFAULT") {
                    Task { await coordinator.useDefaultScreenwatchDirectory() }
                }
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .standard))
                .disabled(coordinator.isWorking)
                .accessibilityIdentifier("onboarding.source.screenwatch.use-default")
            }
        } else {
            Button("OPEN SYSTEM SETTINGS") {
                coordinator.openSystemSettings(for: step)
            }
            .buttonStyle(SumiActionButtonStyle(role: .text, size: .standard))
            .disabled(coordinator.isWorking)
            .accessibilityIdentifier("onboarding.source.\(step.rawValue).repair")
        }
    }

    private var notificationDeliveryCheck: some View {
        VStack(alignment: .leading, spacing: 8) {
            if coordinator.progress.notificationAccess == .granted {
                Button("VERIFY DELIVERY NOW") {
                    Task { await coordinator.runDeliveryTest() }
                }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(coordinator.isWorking)
                .accessibilityIdentifier("onboarding.notifications.delivery-test")
            }
            if let result = coordinator.deliveryResult {
                Text("DELIVERY · \(deliveryResultLabel(result.state)) · \(result.message)")
                    .font(Sumi.body(12))
                    .foregroundStyle(result.state == .failed ? Sumi.sealDeep : Sumi.muted)
                    .accessibilityIdentifier("onboarding.notifications.delivery-result")
            }
        }
    }

    private var screenshotAnalysisConsent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "ALLOW SCREENSHOT ANALYSIS FOR AMBIGUOUS ACTIVITY",
                isOn: $coordinator.screenshotAnalysisEnabled
            )
            .toggleStyle(SumiToggleStyle())
            .accessibilityIdentifier("onboarding.screenwatch.screenshot-analysis")
            Text(
                coordinator.screenshotAnalysisEnabled
                    ? "ON · Zoid 666 may inspect a Screenwatch screenshot only when app and time evidence cannot classify the activity. The screenshot stays local."
                    : "OFF · Screenshots are never inspected. Ambiguous activity remains unknown for later review."
            )
            .font(Sumi.body(12))
            .foregroundStyle(Sumi.muted)
            .accessibilityIdentifier("onboarding.screenwatch.screenshot-analysis.explanation")
        }
        .padding(14)
        .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func chooseScreenwatchFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Screenwatch Days Folder"
        panel.message = "Select the folder containing YYYY-MM-DD/log.jsonl directories."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await coordinator.selectScreenwatchDirectory(url) }
    }

    private func accessDecision(for step: OnboardingStep) -> OnboardingAccessDecision? {
        switch step {
        case .reminders: coordinator.progress.remindersAccess
        case .screenwatch: coordinator.progress.screenwatchAccess
        case .notifications: coordinator.progress.notificationAccess
        default: nil
        }
    }

    private var inventoryStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingEditorialStep(
                eyebrow: "APPLICATION INVENTORY",
                title: "Review what can appear in activity evidence.",
                bodyText: "This local scan combines installed apps with names already observed by Screenwatch. It does not inspect app content and does not classify anything for you.",
                note: coordinator.inventoryMessage
            )
            Button("SCAN AGAIN") { coordinator.loadApplicationInventory() }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .accessibilityIdentifier("onboarding.inventory.reload")
            if coordinator.inventory.isEmpty {
                Text("NO APPLICATIONS AVAILABLE · You can continue and classify them later in Settings.")
                    .font(Sumi.label())
                    .foregroundStyle(Sumi.muted)
                    .accessibilityIdentifier("onboarding.inventory.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(coordinator.inventory.prefix(12)) { application in
                        inventoryRow(application)
                    }
                }
                .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                .accessibilityIdentifier("onboarding.inventory.list")
                Text("Showing \(min(coordinator.inventory.count, 12)) of \(coordinator.inventory.count) apps. Full classification remains available in Settings.")
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.muted)
            }
        }
    }

    private func inventoryRow(_ application: AppInventoryItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(application.name).font(Sumi.body(14))
                Text(application.bundleIdentifier ?? "No bundle identifier")
                    .font(Sumi.label(9))
                    .foregroundStyle(Sumi.muted)
            }
            Spacer()
            Text(application.isObserved ? "OBSERVED" : "INSTALLED")
                .font(Sumi.label(9))
                .foregroundStyle(application.isObserved ? Sumi.seal : Sumi.muted)
        }
        .padding(12)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.inventory.app.\(application.normalizedName)")
    }

    private var classificationStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingEditorialStep(
                eyebrow: "ACTIVITY CLASSIFICATION",
                title: "Name work and gaming apps. Leave uncertainty automatic.",
                bodyText: "Classification helps Zoid 666 distinguish focused work from gaming without guessing. Automatic is the safe default and can be changed later.",
                note: "Only the app name is saved. Titles, URLs, screenshots, and captured content are not shown here."
            )
            if coordinator.inventory.isEmpty {
                Text("NO APPLICATIONS TO CLASSIFY · Continue with automatic behavior.")
                    .font(Sumi.label())
                    .foregroundStyle(Sumi.muted)
            } else {
                VStack(spacing: 14) {
                    ForEach(coordinator.inventory.prefix(12)) { application in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(application.name).font(Sumi.body(14))
                            Picker(
                                "Classification for \(application.name)",
                                selection: classificationBinding(for: application)
                            ) {
                                Text("AUTOMATIC").tag(AppClassificationChoice.automatic)
                                Text("WORK").tag(AppClassificationChoice.work)
                                Text("GAMING").tag(AppClassificationChoice.gaming)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("onboarding.classification.\(application.normalizedName)")
                        }
                    }
                }
            }
        }
    }

    private func classificationBinding(for application: AppInventoryItem) -> Binding<AppClassificationChoice> {
        Binding(
            get: { coordinator.classifications[application.name] ?? .automatic },
            set: { coordinator.setClassification($0, for: application.name) }
        )
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingEditorialStep(
                eyebrow: "BOUNDARIES",
                title: "Set work time and quiet time.",
                bodyText: "Work hours guide planning capacity. Quiet hours prevent coaching delivery. Overnight quiet windows are supported.",
                note: "These are starting boundaries, not surveillance rules. You can adjust them any time in Settings."
            )
            timePicker("WORK START", hour: $coordinator.workStartHour, minute: $coordinator.workStartMinute, id: "work-start")
            timePicker("WORK END", hour: $coordinator.workEndHour, minute: $coordinator.workEndMinute, id: "work-end")
            VStack(alignment: .leading, spacing: 8) {
                Text("WORK DAYS").font(Sumi.label()).tracking(1.2)
                HStack(spacing: 6) {
                    ForEach(Weekday.allCases, id: \.rawValue) { weekday in
                        let isSelected = coordinator.selectedWorkWeekdays.contains(weekday)
                        Button(shortWeekday(weekday)) {
                            coordinator.toggleWorkWeekday(weekday)
                        }
                        .buttonStyle(SumiActionButtonStyle(role: isSelected ? .primary : .quiet, size: .compact))
                        .accessibilityLabel("\(longWeekday(weekday)) work day")
                        .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        .accessibilityIdentifier("onboarding.schedule.weekday.\(weekday.rawValue)")
                    }
                }
            }
            Rectangle().fill(Sumi.paleRule).frame(height: 1)
            timePicker("QUIET START", hour: $coordinator.quietStartHour, minute: $coordinator.quietStartMinute, id: "quiet-start")
            timePicker("QUIET END", hour: $coordinator.quietEndHour, minute: $coordinator.quietEndMinute, id: "quiet-end")
            if let message = coordinator.scheduleValidationMessage {
                Text(message)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.schedule.validation")
            } else {
                Text(coordinator.scheduleSummary)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.okay)
                    .accessibilityIdentifier("onboarding.schedule.validation")
            }
        }
    }

    private func timePicker(_ title: String, hour: Binding<Int>, minute: Binding<Int>, id: String) -> some View {
        HStack {
            Text(title).font(Sumi.label()).tracking(1.2)
            Spacer()
            Picker("\(title) hour", selection: hour) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .labelsHidden()
            .frame(width: 72)
            .accessibilityLabel("\(title.capitalized) hour")
            .accessibilityIdentifier("onboarding.schedule.\(id).hour")
            Text(":").font(Sumi.body(14))
            Picker("\(title) minute", selection: minute) {
                ForEach(minuteOptions(including: minute.wrappedValue), id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .labelsHidden()
            .frame(width: 72)
            .accessibilityLabel("\(title.capitalized) minute")
            .accessibilityIdentifier("onboarding.schedule.\(id).minute")
        }
    }

    private func minuteOptions(including current: Int) -> [Int] {
        Array(Set([0, 15, 30, 45, current])).sorted()
    }

    private func shortWeekday(_ weekday: Weekday) -> String {
        ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][weekday.rawValue - 1]
    }

    private func longWeekday(_ weekday: Weekday) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][weekday.rawValue - 1]
    }

    private var gamingPolicyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingEditorialStep(
                eyebrow: "GAMING WITHOUT SHAME",
                title: "Choose the boundary that feels honest today.",
                bodyText: "Gaming is treated as a conscious tradeoff, never a moral failure. This starting posture controls how firmly the coach raises a choice when gaming competes with intended work.",
                note: "No option locks apps or punishes you. The coach always leaves the final decision with you."
            )
            choiceButton("FLEXIBLE", detail: "Notice the tradeoff, then leave the choice open.", choice: .flexible)
            choiceButton("BALANCED", detail: "Ask for a short work commitment before more gaming.", choice: .balanced)
            choiceButton("FIRM", detail: "Make the competing priority and daily budget explicit.", choice: .firm)
        }
    }

    private func choiceButton(
        _ title: String,
        detail: String,
        choice: OnboardingGamingPolicy
    ) -> some View {
        Button {
            coordinator.gamingPolicy = choice
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(coordinator.gamingPolicy == choice ? "●" : "○")
                    .font(Sumi.body(15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Sumi.label()).tracking(1.2)
                    Text(detail).font(Sumi.body(13)).foregroundStyle(Sumi.muted)
                }
                Spacer()
            }
            .padding(14)
            .contentShape(Rectangle())
            .overlay(Rectangle().stroke(
                coordinator.gamingPolicy == choice ? Sumi.ink : Sumi.rule,
                lineWidth: coordinator.gamingPolicy == choice ? 2 : 1
            ))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(coordinator.gamingPolicy == choice ? "Selected" : "Not selected")
        .accessibilityIdentifier("onboarding.gaming-policy.\(choice.rawValue)")
    }

    private var coachingModeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingEditorialStep(
                eyebrow: "COACHING ENGINE",
                title: "Rules-only works completely. AI remains optional.",
                bodyText: "Rules-only uses deterministic local coaching. Optional AI uses the configured local Codex CLI boundary and may be disabled later without losing your plan or history.",
                note: "Recommended: begin with rules-only. Selecting AI never grants permission to send screenshots or raw captured evidence."
            )
            coachingChoice(
                "RULES-ONLY · RECOMMENDED",
                detail: "Local deterministic guidance with no model dependency.",
                mode: .rulesOnly
            )
            coachingChoice(
                "OPTIONAL AI",
                detail: "Use the explicit Codex CLI provider boundary when available.",
                mode: .optionalAI
            )
        }
    }

    private func coachingChoice(
        _ title: String,
        detail: String,
        mode: InitialCoachingMode
    ) -> some View {
        Button {
            coordinator.selectCoachingMode(mode)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(coordinator.progress.coachingMode == mode ? "●" : "○")
                    .font(Sumi.body(15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Sumi.label()).tracking(1.1)
                    Text(detail).font(Sumi.body(13)).foregroundStyle(Sumi.muted)
                }
                Spacer()
            }
            .padding(14)
            .contentShape(Rectangle())
            .overlay(Rectangle().stroke(
                coordinator.progress.coachingMode == mode ? Sumi.ink : Sumi.rule,
                lineWidth: coordinator.progress.coachingMode == mode ? 2 : 1
            ))
        }
        .buttonStyle(.plain)
        .accessibilityValue(coordinator.progress.coachingMode == mode ? "Selected" : "Not selected")
        .accessibilityIdentifier("onboarding.coaching.\(mode.rawValue)")
    }

    private var deliveryTestStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingEditorialStep(
                eyebrow: "DELIVERY PROOF",
                title: "Complete one task and send one bounded prompt.",
                bodyText: "The local task checks the basic completion interaction. The notification test schedules one local prompt, contacts no remote service, and records an explicit result.",
                note: coordinator.progress.notificationAccess == .granted
                    ? "Run the test and confirm macOS accepted it."
                    : "Notifications were not granted. Continue in degraded mode and use Today for every coaching choice."
            )
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TEST TASK").font(Sumi.label()).tracking(1.2)
                    Text("Confirm one small next action can be completed.")
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.muted)
                }
                Spacer()
                Button(coordinator.testTaskCompleted ? "COMPLETED" : "MARK COMPLETE") {
                    coordinator.completeTestTask()
                }
                .buttonStyle(SumiActionButtonStyle(
                    role: coordinator.testTaskCompleted ? .quiet : .primary,
                    size: .standard
                ))
                .disabled(coordinator.testTaskCompleted)
                .accessibilityValue(coordinator.testTaskCompleted ? "Completed" : "Not completed")
                .accessibilityIdentifier("onboarding.delivery.test-task")
            }
            .padding(14)
            .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
            Button(coordinator.isWorking ? "TESTING…" : "SEND TEST PROMPT") {
                Task { await coordinator.runDeliveryTest() }
            }
            .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
            .disabled(coordinator.isWorking)
            .accessibilityIdentifier("onboarding.delivery.test")
            if let result = coordinator.deliveryResult {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RESULT · \(deliveryResultLabel(result.state))")
                        .font(Sumi.label()).tracking(1.2)
                    Text(result.message).font(Sumi.body(13))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background([.delivered, .scheduled].contains(result.state) ? Sumi.softPaper : Sumi.sealWash)
                .overlay(Rectangle().stroke(
                    [.delivered, .scheduled].contains(result.state) ? Sumi.rule : Sumi.seal,
                    lineWidth: 1
                ))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboarding.delivery.test-result")
            }
            if let prompt = coordinator.testPrompt {
                VStack(alignment: .leading, spacing: 10) {
                    Text(prompt.state == .responded ? "PROMPT RESOLVED" : "CHOOSE AN ACTION")
                        .font(Sumi.label())
                        .tracking(1.2)
                    Text(prompt.title).font(Sumi.body(15))
                    Text(prompt.summary).font(Sumi.body(13)).foregroundStyle(Sumi.muted)
                    if prompt.state.isUnresolved {
                        HStack(spacing: 8) {
                            ForEach(prompt.actions) { action in
                                Button(action.title.uppercased()) {
                                    Task { await coordinator.respondToTestPrompt(action.kind) }
                                }
                                .buttonStyle(SumiActionButtonStyle(
                                    role: action.role == .primary ? .primary : .quiet,
                                    size: .standard
                                ))
                                .disabled(coordinator.isWorking)
                                .accessibilityIdentifier("onboarding.delivery.prompt.\(action.kind.rawValue)")
                            }
                        }
                        Button("REFRESH PROMPT STATUS") {
                            Task { await coordinator.restoreTestPrompt() }
                        }
                        .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                        .disabled(coordinator.isWorking)
                        .accessibilityIdentifier("onboarding.delivery.prompt.refresh")
                    } else {
                        Text(coordinator.testPromptMessage ?? "Your choice is saved.")
                            .font(Sumi.body(13))
                            .foregroundStyle(Sumi.okay)
                    }
                }
                .padding(14)
                .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onboarding.delivery.prompt")
            }
        }
    }

    private var firstPlanSummary: String {
        let sourceCount = [
            coordinator.progress.remindersAccess,
            coordinator.progress.screenwatchAccess,
            coordinator.progress.notificationAccess
        ].compactMap { $0 }.filter { $0 == .granted }.count
        let coaching = coordinator.progress.coachingMode == .optionalAI ? "optional AI" : "rules-only"
        return "\(sourceCount) of 3 sources connected · \(coaching) coaching · work \(hour(coordinator.workStartHour))-\(hour(coordinator.workEndHour)) · quiet \(hour(coordinator.quietStartHour))-\(hour(coordinator.quietEndHour))."
    }

    private var firstDailyPlanStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingEditorialStep(
                eyebrow: "FIRST DAILY PLAN",
                title: "Prepare a real plan before setup finishes.",
                bodyText: "Zoid 666 must create and return visible plan items before it marks onboarding complete. If planning is unavailable, setup remains here without inventing success.",
                note: firstPlanSummary
            )
            if let result = coordinator.firstDailyPlanResult {
                Text(result.message)
                    .font(Sumi.body(13))
                    .foregroundStyle(result.state == .prepared ? Sumi.muted : Sumi.sealDeep)
                if result.state == .prepared {
                    VStack(spacing: 0) {
                        ForEach(result.items) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.isMainObjective ? "MAIN" : "PLAN")
                                    .font(Sumi.label(9))
                                    .foregroundStyle(item.isMainObjective ? Sumi.seal : Sumi.muted)
                                    .frame(width: 44, alignment: .leading)
                                Text(item.title).font(Sumi.body(14))
                                Spacer()
                                if let estimate = item.estimateMinutes {
                                    Text("\(estimate) MIN").font(Sumi.label(9)).foregroundStyle(Sumi.muted)
                                }
                            }
                            .padding(12)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Sumi.paleRule).frame(height: 1)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("onboarding.first-plan.item.\(item.id)")
                        }
                    }
                    .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                    .accessibilityIdentifier("onboarding.first-plan.items")
                }
            }
            Button(coordinator.isWorking ? "PREPARING…" : "PREPARE AGAIN") {
                Task { await coordinator.prepareFirstDailyPlan() }
            }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
            .disabled(coordinator.isWorking)
            .accessibilityIdentifier("onboarding.first-plan.prepare")
        }
    }

    private func hour(_ value: Int) -> String {
        String(format: "%02d:00", value)
    }

    private func deliveryResultLabel(_ state: OnboardingDeliveryResult.State) -> String {
        switch state {
        case .delivered: "DELIVERED"
        case .scheduled: "SCHEDULED"
        case .unavailable: "UNAVAILABLE"
        case .failed: "FAILED"
        case .todayFallback: "TODAY FALLBACK"
        }
    }

    private var controls: some View {
        let copy = welcomeCopy
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Spacer()
                continueStatus(copy)
                continueButton(copy)
            }
            VStack(alignment: .leading, spacing: 8) {
                continueStatus(copy)
                continueButton(copy)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func continueStatus(_ copy: OnboardingWelcomeCopy) -> some View {
        Text(coordinator.canContinue ? copy.readyStatus : copy.blockedStatus)
            .font(Sumi.label(9))
            .foregroundStyle(coordinator.canContinue ? Sumi.okay : Sumi.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func continueButton(_ copy: OnboardingWelcomeCopy) -> some View {
        Button(coordinator.progress.currentStep == .firstDailyPlan ? "OPEN TODAY" : copy.continueTitle) {
            Task { try? await coordinator.continueFromCurrentStep() }
        }
        .buttonStyle(SumiActionButtonStyle(role: .primary, size: .large))
        .disabled(!coordinator.canContinue || coordinator.isWorking)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("onboarding.continue")
    }

    private var currentPosition: Int {
        (OnboardingProgress.stepSequence.firstIndex(of: coordinator.progress.currentStep) ?? 0) + 1
    }

    private func shortTitle(for step: OnboardingStep) -> String {
        if coordinator.progress.currentStep == .welcome,
           let index = OnboardingProgress.stepSequence.firstIndex(of: step) {
            return welcomeCopy.stepTitles[index]
        }
        switch step {
        case .welcome: "Welcome"
        case .localPrivacy: "Local privacy"
        case .reminders: "Reminders"
        case .screenwatch: "Screenwatch"
        case .notifications: "Notifications"
        case .applicationInventory: "App inventory"
        case .activityClassification: "Classification"
        case .schedule: "Schedule"
        case .gamingPolicy: "Gaming policy"
        case .coachingMode: "Coaching mode"
        case .deliveryTest: "Delivery test"
        case .firstDailyPlan: "First daily plan"
        }
    }

    private func stepState(_ step: OnboardingStep) -> String {
        if coordinator.progress.currentStep == .welcome {
            if coordinator.progress.completedSteps.contains(step) { return welcomeCopy.completedState }
            if step == coordinator.progress.currentStep { return welcomeCopy.currentState }
            return welcomeCopy.upcomingState
        }
        if coordinator.progress.completedSteps.contains(step) { return "Completed" }
        if step == coordinator.progress.currentStep { return "Current" }
        return "Upcoming"
    }

    private var welcomeCopy: OnboardingWelcomeCopy {
        OnboardingWelcomeCopy.localized(
            for: locale,
            isWelcomeStep: coordinator.progress.currentStep == .welcome
        )
    }
}

private struct OnboardingEditorialStep: View {
    let eyebrow: String
    let title: String
    let bodyText: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(eyebrow).font(Sumi.label()).tracking(1.8).foregroundStyle(Sumi.seal)
            Text(title).font(Sumi.display(38)).tracking(-1).fixedSize(horizontal: false, vertical: true)
            Text(bodyText).font(Sumi.body(16)).lineSpacing(6).foregroundStyle(Sumi.ink)
                .frame(maxWidth: 680, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(note).font(Sumi.body(13)).lineSpacing(4).foregroundStyle(Sumi.muted)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Sumi.softPaper)
                .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingSourceStatus: View {
    let health: SourceHealth
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS · \(health.state.rawValue.uppercased())")
                .font(Sumi.label()).tracking(1.2)
            Text(health.detail).font(Sumi.body(14))
            Text(health.evidence).font(Sumi.body(12)).foregroundStyle(Sumi.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(health.state == .healthy ? Sumi.softPaper : Sumi.sealWash)
        .overlay(Rectangle().stroke(health.state == .healthy ? Sumi.rule : Sumi.seal, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.source.\(step.rawValue).status")
    }
}
