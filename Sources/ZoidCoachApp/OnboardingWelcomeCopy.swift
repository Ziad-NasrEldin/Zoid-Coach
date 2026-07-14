import Foundation

struct OnboardingWelcomeCopy {
    let eyebrow: String
    let title: String
    let body: String
    let note: String
    let progressTitle: String
    let progressFooter: String
    let setupProgress: (Int, Int) -> String
    let exitTitle: String
    let exitHint: String
    let readyStatus: String
    let blockedStatus: String
    let continueTitle: String
    let stepTitles: [String]
    let completedState: String
    let currentState: String
    let upcomingState: String
    let stepAccessibilityLabel: (Int, String) -> String
    let setupErrorLabel: (String) -> String
    let isRightToLeft: Bool

    static func localized(for locale: Locale) -> Self {
        if locale.language.languageCode?.identifier == "ar" {
            return arabic
        }
        return english
    }

    var accessibilitySummary: String {
        [title, body, note].joined(separator: " ")
    }

    private static let english = Self(
        eyebrow: "WELCOME",
        title: "A quieter way to begin the work that matters.",
        body: "Zoid 666 is a coach, not a replacement task manager. Apple Reminders remains the system of record for your connected tasks. Zoid 666 connects that intent with what actually happens on this Mac so it can help you choose a realistic next action, notice drift, and recover without shame.",
        note: "Keep creating, organizing, and editing connected tasks in Reminders. Use Today for your plan, source status, and unanswered coaching choices. Nothing is blocked or punished by default.",
        progressTitle: "PRIVATE COMMAND LEDGER",
        progressFooter: "LOCAL FIRST · RULES WORK WITHOUT AI",
        setupProgress: { "SETUP · \($0) OF \($1)" },
        exitTitle: "EXIT FOR NOW",
        exitHint: "Opens Today. Setup resumes from the latest saved step after restart.",
        readyStatus: "READY TO CONTINUE",
        blockedStatus: "CHOOSE A PATH TO CONTINUE",
        continueTitle: "CONTINUE",
        stepTitles: [
            "Welcome", "Local privacy", "Reminders", "Screenwatch", "Notifications", "App inventory",
            "Classification", "Schedule", "Gaming policy", "Coaching mode", "Delivery test", "First daily plan"
        ],
        completedState: "Completed",
        currentState: "Current",
        upcomingState: "Upcoming",
        stepAccessibilityLabel: { "Step \($0), \($1)" },
        setupErrorLabel: { "Setup error. \($0)" },
        isRightToLeft: false
    )

    private static let arabic = Self(
        eyebrow: "مرحبًا",
        title: "طريقة أهدأ لبدء العمل الذي يهمك.",
        body: "Zoid 666 مدرب، وليس بديلاً عن تطبيق إدارة المهام. يظل Apple Reminders المصدر الأساسي لمهامك المتصلة. يربط Zoid 666 بين ما تنوي فعله وما يحدث فعلاً على هذا الـ Mac ليساعدك على اختيار خطوة واقعية تالية، وملاحظة التشتت، والعودة إلى العمل من دون لوم.",
        note: "استمر في إنشاء مهامك المتصلة وتنظيمها وتعديلها في Reminders. استخدم «اليوم» لخطتك وحالة المصادر وخيارات التدريب التي تنتظر ردك. لا يتم حظر أي شيء أو معاقبتك عليه افتراضيًا.",
        progressTitle: "سجل الأوامر الخاص",
        progressFooter: "محلي أولاً · القواعد تعمل من دون ذكاء اصطناعي",
        setupProgress: { "الإعداد · \($0) من \($1)" },
        exitTitle: "الخروج الآن",
        exitHint: "يفتح شاشة اليوم. يُستأنف الإعداد من آخر خطوة محفوظة بعد إعادة التشغيل.",
        readyStatus: "جاهز للمتابعة",
        blockedStatus: "اختر مسارًا للمتابعة",
        continueTitle: "متابعة",
        stepTitles: [
            "مرحبًا", "الخصوصية المحلية", "التذكيرات", "Screenwatch", "الإشعارات", "قائمة التطبيقات",
            "التصنيف", "الجدول", "سياسة الألعاب", "نمط التدريب", "اختبار الإرسال", "الخطة اليومية الأولى"
        ],
        completedState: "مكتملة",
        currentState: "الحالية",
        upcomingState: "قادمة",
        stepAccessibilityLabel: { "الخطوة \($0)، \($1)" },
        setupErrorLabel: { "تعذر إكمال الإعداد. \($0)" },
        isRightToLeft: true
    )
}

struct OnboardingWelcomeLayout: Equatable {
    let showsProgressRail: Bool
    let horizontalPadding: CGFloat

    init(hostWidth: CGFloat) {
        showsProgressRail = hostWidth >= 760
        horizontalPadding = hostWidth >= 620 ? 44 : 20
    }
}
