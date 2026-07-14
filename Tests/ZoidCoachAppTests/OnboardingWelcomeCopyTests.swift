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
    #expect(copy.setupErrorLabel("تفصيل") == "تعذر إكمال الإعداد. تفصيل")
    #expect(copy.accessibilitySummary.contains(copy.title))
    #expect(copy.isRightToLeft)
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
func welcomeLayoutRemovesTheFixedRailAndReducesPaddingAtHostedWidths() {
    #expect(OnboardingWelcomeLayout(hostWidth: 1_000).showsProgressRail)
    #expect(OnboardingWelcomeLayout(hostWidth: 1_000).horizontalPadding == 44)

    #expect(!OnboardingWelcomeLayout(hostWidth: 759).showsProgressRail)
    #expect(OnboardingWelcomeLayout(hostWidth: 759).horizontalPadding == 44)

    #expect(!OnboardingWelcomeLayout(hostWidth: 519).showsProgressRail)
    #expect(OnboardingWelcomeLayout(hostWidth: 519).horizontalPadding == 20)
}
