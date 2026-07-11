import Foundation
import Testing
@testable import ZoidCoachCore

@Test
func voiceBudgetReachesTheTwentyDollarCapAtThePublishedDailyBaseline() throws {
    let cairo = try #require(TimeZone(identifier: "Africa/Cairo"))
    let calendar = Calendar(identifier: .gregorian)
    let start = try #require(calendar.date(from: DateComponents(
        timeZone: cairo,
        year: 2026,
        month: 7,
        day: 1
    )))
    var ledger = VoiceUsageLedger(periodStart: start)

    for day in 0..<30 {
        ledger = ledger.recording(
            VoiceUsageSample(inputAudioSeconds: 3_600, outputAudioSeconds: 1_200),
            at: start.addingTimeInterval(TimeInterval(day * 86_400)),
            calendar: calendar,
            timeZone: cairo
        )
    }

    #expect(ledger.consumedUSDMicros == 19_800_000)
    #expect(ledger.status == .warningNinetyPercent)

    ledger = ledger.recording(
        VoiceUsageSample(inputAudioSeconds: 2_400, outputAudioSeconds: 0),
        at: start.addingTimeInterval(30 * 86_400),
        calendar: calendar,
        timeZone: cairo
    )

    #expect(ledger.consumedUSDMicros == VoiceUsageLedger.hardMonthlyLimitUSDMicros)
    #expect(ledger.status == .capReached)
    #expect(ledger.canStartCloudSession == false)
}

@Test
func newLocalMonthResetsVoiceSpendBeforeRecordingNewUsage() throws {
    let cairo = try #require(TimeZone(identifier: "Africa/Cairo"))
    let calendar = Calendar(identifier: .gregorian)
    let july = try #require(calendar.date(from: DateComponents(timeZone: cairo, year: 2026, month: 7, day: 1)))
    let august = try #require(calendar.date(from: DateComponents(timeZone: cairo, year: 2026, month: 8, day: 1)))
    let ledger = VoiceUsageLedger(periodStart: july, consumedUSDMicros: 19_000_000)

    let next = ledger.recording(
        VoiceUsageSample(inputAudioSeconds: 60, outputAudioSeconds: 0),
        at: august,
        calendar: calendar,
        timeZone: cairo
    )

    #expect(next.periodStart == august)
    #expect(next.consumedUSDMicros == 5_000)
    #expect(next.status == .withinBudget)
}

@Test
func inFlightBudgetReservationSurvivesCrashAndSettlesToActualUsage() throws {
    let start = Date(timeIntervalSince1970: 1_767_225_600)
    let original = VoiceUsageLedger(periodStart: start, consumedUSDMicros: 19_000_000)
    let reserved = try #require(original.reserving(id: "session", maximumUSDMicros: 20_000_000))

    #expect(reserved.committedUSDMicros == 20_000_000)
    #expect(reserved.canStartCloudSession == false)

    let settled = reserved.settling(
        reservationID: "session",
        sample: VoiceUsageSample(inputAudioSeconds: 60, outputAudioSeconds: 60)
    )
    #expect(settled.consumedUSDMicros == 19_023_000)
    #expect(settled.reservationsUSDMicros == nil)
}

@Test
func voiceActionPolicyAllowsReversibleToolsButConfirmsExternalEffects() {
    let openApp = VoiceToolDefinition(
        name: "open_application",
        description: "Open an installed application.",
        riskLevel: .reversibleLocal,
        requiresExplicitUserIntent: true
    )
    let sendMessage = VoiceToolDefinition(
        name: "send_message",
        description: "Send a message to another person.",
        riskLevel: .externalOrIrreversible,
        requiresExplicitUserIntent: true
    )
    let arbitraryShell = VoiceToolDefinition(
        name: "run_shell",
        description: "Run arbitrary shell text.",
        riskLevel: .forbidden,
        requiresExplicitUserIntent: true
    )

    #expect(VoiceActionPolicy.decision(for: openApp, hasExplicitUserIntent: true) == .allow)
    #expect(VoiceActionPolicy.decision(for: openApp, hasExplicitUserIntent: false) == .deny)
    #expect(VoiceActionPolicy.decision(for: sendMessage, hasExplicitUserIntent: true) == .requireApproval)
    #expect(VoiceActionPolicy.decision(for: arbitraryShell, hasExplicitUserIntent: true) == .deny)
}

@Test
func unconfirmedConversationFactsCannotAuthorizeActions() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let inferred = ConversationMemoryFact(
        id: "fact-1",
        kind: .commitment,
        value: "Send the proposal",
        sourceTurnID: "turn-1",
        isConfirmed: false,
        expiresAt: now.addingTimeInterval(3_600),
        createdAt: now,
        updatedAt: now
    )
    let confirmed = ConversationMemoryFact(
        id: "fact-2",
        kind: .commitment,
        value: "Send the proposal",
        sourceTurnID: "turn-1",
        isConfirmed: true,
        expiresAt: nil,
        createdAt: now,
        updatedAt: now
    )

    #expect(inferred.canAuthorizeAction(at: now) == false)
    #expect(confirmed.canAuthorizeAction(at: now) == true)
}
