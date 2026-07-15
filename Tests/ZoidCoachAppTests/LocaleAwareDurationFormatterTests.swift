import Foundation
import Testing
@testable import ZoidCoachApp

@Test func wideMinuteDurationsRespectEnglishPluralRules() {
    let formatter = LocaleAwareDurationFormatter(locale: Locale(identifier: "en_US"))

    #expect(formatter.wide(minutes: 0) == "0 minutes")
    #expect(formatter.wide(minutes: 1) == "1 minute")
    #expect(formatter.wide(minutes: 12) == "12 minutes")
}

@Test func compactMinuteDurationsRespectTheInjectedLocale() {
    let formatter = LocaleAwareDurationFormatter(locale: Locale(identifier: "fr_FR"))

    #expect(formatter.compact(minutes: 0) == "0\u{00a0}min")
    #expect(formatter.compact(minutes: 1) == "1\u{00a0}min")
    #expect(formatter.compact(minutes: 12) == "12\u{00a0}min")
}
