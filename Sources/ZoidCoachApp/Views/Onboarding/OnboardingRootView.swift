import AppKit
import SwiftUI
import ZoidCoachCore

struct OnboardingRootView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        HStack(spacing: 0) {
            progressRail
            Rectangle().fill(Sumi.rule).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle().fill(Sumi.paleRule).frame(height: 1)
                ScrollView {
                    stepContent
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 36)
                }
                Rectangle().fill(Sumi.paleRule).frame(height: 1)
                controls
            }
        }
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
        }
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PRIVATE COMMAND LEDGER")
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
                    Text(shortTitle(for: step).uppercased())
                        .font(Sumi.label())
                        .tracking(1.1)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(step == coordinator.progress.currentStep ? Sumi.ink : Color.clear)
                .accessibilityLabel("Step \(index + 1), \(shortTitle(for: step))")
                .accessibilityValue(stepState(step))
            }
            Spacer()
            Text("LOCAL FIRST · RULES WORK WITHOUT AI")
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
        HStack {
            Text("SETUP · \(currentPosition) OF 12")
                .font(Sumi.label())
                .tracking(1.4)
            Spacer()
            Button("EXIT FOR NOW") { coordinator.exitToToday() }
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Opens Today. Setup resumes from the latest saved step after restart.")
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
                OnboardingEditorialStep(
                    eyebrow: "WELCOME",
                    title: "A quieter way to begin the work that matters.",
                    bodyText: "Zoid Coach connects your intended work in Reminders with what actually happens on this Mac. It helps you choose a realistic next action, notice drift, and recover without shame.",
                    note: "Today keeps your plan, source status, and unanswered coaching choices in one place. Nothing is blocked or punished by default."
                )
            case .localPrivacy:
                OnboardingEditorialStep(
                    eyebrow: "LOCAL TRUTH",
                    title: "Your behavioral record stays on this Mac by default.",
                    bodyText: "Reminders, Screenwatch summaries, plans, and coaching history are stored locally. Zoid Coach does not require an account, employer dashboard, or remote AI service.",
                    note: "AI is optional. Rules-only coaching remains fully usable, and any later remote processing requires an explicit choice."
                )
            case .reminders:
                sourceStep(
                    step: .reminders,
                    eyebrow: "INTENT SOURCE",
                    title: "Connect Apple Reminders",
                    explanation: "Reminders tells Zoid Coach what you intended to do. Full access lets the app read tasks and update completion. If you decline, setup continues with manual local planning.",
                    grantTitle: "REQUEST REMINDERS ACCESS"
                )
            case .screenwatch:
                sourceStep(
                    step: .screenwatch,
                    eyebrow: "BEHAVIOR SOURCE",
                    title: "Find Screenwatch",
                    explanation: "Screenwatch contributes time and application evidence. Zoid Coach checks the expected daily JSONL stream without showing captured titles, URLs, or screenshots here.",
                    grantTitle: "CHECK EXPECTED FOLDER"
                )
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
                OnboardingEditorialStep(
                    eyebrow: "FIRST PLAN",
                    title: "The quiet command center is ready.",
                    bodyText: "Today will show your intended work, current source health, a realistic next action, and any coaching choices still waiting for you.",
                    note: firstPlanSummary
                )
            }
            if let error = coordinator.errorMessage {
                Text(error)
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.sealDeep)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Sumi.sealWash)
                .accessibilityLabel("Setup error. \(error)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.\(coordinator.progress.currentStep.rawValue)")
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
                note: "Zoid Coach asks once. A denied or deferred choice is respected and can be repaired later in System Settings."
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
                .disabled(coordinator.isWorking || accessDecision(for: step) != nil)
                .keyboardShortcut("g", modifiers: [.option])
                .accessibilityIdentifier("onboarding.source.\(step.rawValue).grant")
                Button("NOT NOW") { coordinator.deferAccess(for: step) }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .keyboardShortcut("d", modifiers: [.option])
                    .disabled(coordinator.isWorking)
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
                bodyText: "Classification helps Zoid Coach distinguish focused work from gaming without guessing. Automatic is the safe default and can be changed later.",
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
            hourPicker("WORK START", value: $coordinator.workStartHour, id: "work-start")
            hourPicker("WORK END", value: $coordinator.workEndHour, id: "work-end")
            Rectangle().fill(Sumi.paleRule).frame(height: 1)
            hourPicker("QUIET START", value: $coordinator.quietStartHour, id: "quiet-start")
            hourPicker("QUIET END", value: $coordinator.quietEndHour, id: "quiet-end")
        }
    }

    private func hourPicker(_ title: String, value: Binding<Int>, id: String) -> some View {
        HStack {
            Text(title).font(Sumi.label()).tracking(1.2)
            Spacer()
            Picker(title, selection: value) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).tag(hour)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel(title.capitalized)
            .accessibilityIdentifier("onboarding.schedule.\(id)")
        }
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
                title: "Send one bounded test before relying on coaching.",
                bodyText: "The test schedules one local notification. It does not contact a remote service and it records an explicit pass, failure, or unavailable result.",
                note: coordinator.progress.notificationAccess == .granted
                    ? "Run the test and confirm macOS accepted it."
                    : "Notifications were not granted. Continue in degraded mode and use Today for every coaching choice."
            )
            Button(coordinator.isWorking ? "TESTING…" : "SEND TEST NOTIFICATION") {
                Task { await coordinator.runDeliveryTest() }
            }
            .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
            .disabled(coordinator.isWorking || coordinator.progress.notificationAccess != .granted)
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

    private func hour(_ value: Int) -> String {
        String(format: "%02d:00", value)
    }

    private func deliveryResultLabel(_ state: OnboardingDeliveryResult.State) -> String {
        switch state {
        case .delivered: "DELIVERED"
        case .scheduled: "SCHEDULED"
        case .unavailable: "UNAVAILABLE"
        case .failed: "FAILED"
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("BACK") { coordinator.goBack() }
                .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                .disabled(currentPosition == 1)
                .keyboardShortcut("[", modifiers: [.command])
                .accessibilityIdentifier("onboarding.back")
            Spacer()
            Text(coordinator.canContinue ? "READY TO CONTINUE" : "CHOOSE A PATH TO CONTINUE")
                .font(Sumi.label(9))
                .foregroundStyle(coordinator.canContinue ? Sumi.okay : Sumi.muted)
            Button(coordinator.progress.currentStep == .firstDailyPlan ? "OPEN TODAY" : "CONTINUE") {
                do { try coordinator.continueFromCurrentStep() } catch { }
            }
            .buttonStyle(SumiActionButtonStyle(role: .primary, size: .large))
            .disabled(!coordinator.canContinue || coordinator.isWorking)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("onboarding.continue")
        }
        .padding(.horizontal, 28)
        .frame(height: 72)
    }

    private var currentPosition: Int {
        (OnboardingProgress.stepSequence.firstIndex(of: coordinator.progress.currentStep) ?? 0) + 1
    }

    private func shortTitle(for step: OnboardingStep) -> String {
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
        if coordinator.progress.completedSteps.contains(step) { return "Completed" }
        if step == coordinator.progress.currentStep { return "Current" }
        return "Upcoming"
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
            Text(note).font(Sumi.body(13)).lineSpacing(4).foregroundStyle(Sumi.muted)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Sumi.softPaper)
                .overlay(Rectangle().stroke(Sumi.rule, lineWidth: 1))
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
