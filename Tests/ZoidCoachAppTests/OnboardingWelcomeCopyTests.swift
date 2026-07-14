import Foundation
import Testing
@testable import ZoidCoachApp

@Test
func arabicWelcomeLocalizesEveryVisibleAndAccessibleString() {
    let copy = OnboardingWelcomeCopy.localized(for: Locale(identifier: "ar_EG"))

    #expect(copy.eyebrow == "مرحبًا")
    #expect(copy.title.contains("العمل"))
    #expect(copy.body.contains("مدرب"))
    #expect(copy.note.contains("التذكيرات") || copy.note.contains("Reminders"))
    #expect(copy.progressTitle == "سجل الأوامر الخاص")
    #expect(copy.progressFooter.contains("محلي"))
    #expect(copy.setupProgress(1, 12) == "الإعداد · 1 من 12")
    #expect(copy.exitTitle == "الخروج الآن")
    #expect(copy.exitHint.contains("آخر خطوة محفوظة"))
    #expect(copy.readyStatus == "جاهز للمتابعة")
    #expect(copy.blockedStatus == "اختر مسارًا للمتابعة")
    #expect(copy.continueTitle == "متابعة")
    #expect(copy.stepTitles.count == 12)
    #expect(copy.stepTitles[0] == "مرحبًا")
    #expect(copy.completedState == "مكتملة")
    #expect(copy.currentState == "الحالية")
    #expect(copy.upcomingState == "قادمة")
    #expect(copy.stepAccessibilityLabel(1, copy.stepTitles[0]) == "الخطوة 1، مرحبًا")
    let localizedError = copy.setupErrorLabel("PolicyStoreError could not load existing settings")
    #expect(localizedError == "تعذر إكمال الإعداد. حاول مرة أخرى، أو اخرج الآن واستأنف الإعداد لاحقًا.")
    #expect(!localizedError.contains("PolicyStoreError"))
    #expect(!localizedError.contains("existing settings"))
    #expect(copy.accessibilitySummary.contains(copy.title))
    #expect(copy.isRightToLeft)

    let visibleAndAccessibleCopy = [
        copy.eyebrow, copy.title, copy.body, copy.note, copy.progressTitle, copy.progressFooter,
        copy.setupProgress(1, 12), copy.exitTitle, copy.exitHint, copy.readyStatus,
        copy.blockedStatus, copy.continueTitle, copy.completedState, copy.currentState,
        copy.upcomingState, copy.stepAccessibilityLabel(1, copy.stepTitles[0]), localizedError
    ] + copy.stepTitles
    #expect(visibleAndAccessibleCopy.allSatisfy(hasNoUntranslatedEnglishCopy))
}

@Test
func englishWelcomeRemainsTheExactFallback() {
    let copy = OnboardingWelcomeCopy.localized(for: Locale(identifier: "en_US"))

    #expect(copy.eyebrow == "WELCOME")
    #expect(copy.title == "A quieter way to begin the work that matters.")
    #expect(copy.body.hasPrefix("Zoid 666 is a coach, not a replacement task manager."))
    #expect(copy.body.contains("Apple Reminders remains the system of record"))
    #expect(copy.note.hasPrefix("Keep creating, organizing, and editing connected tasks in Reminders."))
    #expect(copy.note.contains("Nothing is blocked or punished by default."))
    #expect(copy.progressTitle == "PRIVATE COMMAND LEDGER")
    #expect(copy.progressFooter == "LOCAL FIRST · RULES WORK WITHOUT AI")
    #expect(copy.setupProgress(1, 12) == "SETUP · 1 OF 12")
    #expect(copy.exitTitle == "EXIT FOR NOW")
    #expect(copy.readyStatus == "READY TO CONTINUE")
    #expect(copy.blockedStatus == "CHOOSE A PATH TO CONTINUE")
    #expect(copy.continueTitle == "CONTINUE")
    #expect(copy.stepTitles[0] == "Welcome")
    #expect(!copy.isRightToLeft)
}

@Test
func unsupportedLocaleFallsBackToEnglishWithoutMixedCopy() {
    let copy = OnboardingWelcomeCopy.localized(for: Locale(identifier: "fr_FR"))

    #expect(copy.title == "A quieter way to begin the work that matters.")
    #expect(copy.continueTitle == "CONTINUE")
    #expect(copy.stepTitles == [
        "Welcome", "Local privacy", "Reminders", "Screenwatch", "Notifications", "App inventory",
        "Classification", "Schedule", "Gaming policy", "Coaching mode", "Delivery test", "First daily plan"
    ])
    #expect(!copy.isRightToLeft)
}

@Test
func leavingArabicWelcomeRestoresTheExactEnglishLeftToRightShell() {
    let welcome = OnboardingWelcomeCopy.localized(
        for: Locale(identifier: "ar_EG"),
        isWelcomeStep: true
    )
    let nextStep = OnboardingWelcomeCopy.localized(
        for: Locale(identifier: "ar_EG"),
        isWelcomeStep: false
    )

    #expect(welcome.continueTitle == "متابعة")
    #expect(welcome.isRightToLeft)
    #expect(nextStep.setupProgress(2, 12) == "SETUP · 2 OF 12")
    #expect(nextStep.exitTitle == "EXIT FOR NOW")
    #expect(nextStep.readyStatus == "READY TO CONTINUE")
    #expect(nextStep.continueTitle == "CONTINUE")
    #expect(nextStep.stepTitles[1] == "Local privacy")
    #expect(nextStep.setupErrorLabel("Storage unavailable") == "Setup error. Storage unavailable")
    #expect(!nextStep.isRightToLeft)
}

@Test
func welcomeLayoutRemovesTheFixedRailAndReducesPaddingAtHostedWidths() {
    #expect(OnboardingWelcomeLayout(hostWidth: 1_000).showsProgressRail)
    #expect(OnboardingWelcomeLayout(hostWidth: 1_000).horizontalPadding == 44)

    #expect(!OnboardingWelcomeLayout(hostWidth: 759).showsProgressRail)
    #expect(OnboardingWelcomeLayout(hostWidth: 759).horizontalPadding == 44)

    #expect(!OnboardingWelcomeLayout(hostWidth: 519).showsProgressRail)
    #expect(OnboardingWelcomeLayout(hostWidth: 519).horizontalPadding == 20)
}

private func hasNoUntranslatedEnglishCopy(_ value: String) -> Bool {
    let approvedProductNames = ["Zoid", "Apple", "Reminders", "Mac", "Screenwatch"]
    let withoutProductNames = approvedProductNames.reduce(value) {
        $0.replacingOccurrences(of: $1, with: "")
    }
    return !withoutProductNames.unicodeScalars.contains {
        (65...90).contains(Int($0.value)) || (97...122).contains(Int($0.value))
    }
}
