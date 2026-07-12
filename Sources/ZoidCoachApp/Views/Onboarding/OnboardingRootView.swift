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
                .accessibilityHint("Opens Today. Setup resumes at this step after restart.")
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
            default:
                OnboardingEditorialStep(
                    eyebrow: "SETUP",
                    title: shortTitle(for: coordinator.progress.currentStep),
                    bodyText: "This setup step keeps your choices local and can be revisited before completion.",
                    note: "Continue when the choice reflects how you want Zoid Coach to behave."
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
                .disabled(coordinator.isWorking)
                .keyboardShortcut("g", modifiers: [.option])
                .accessibilityIdentifier("onboarding.source.\(step.rawValue).grant")
                Button("NOT NOW") { coordinator.deferAccess(for: step) }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .keyboardShortcut("d", modifiers: [.option])
                    .accessibilityHint("Continues setup in degraded mode without asking again.")
                    .accessibilityIdentifier("onboarding.source.\(step.rawValue).defer")
                Button("RECHECK") {
                    Task { await coordinator.inspectCurrentSource() }
                }
                .buttonStyle(SumiActionButtonStyle(role: .text, size: .standard))
                .accessibilityIdentifier("onboarding.retry")
            }
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
