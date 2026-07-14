import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Test
func keyboardReviewSelectsSessionsChronologicallyAndCyclesWithoutAPointer() {
    let later = reviewSession(idOffset: 600, application: "Safari", classification: .unknown)
    let earlier = reviewSession(idOffset: 0, application: "Xcode", classification: .work)
    var state = DailyReviewKeyboardFlowState(sourceDay: "2026-07-14", sessions: [later, earlier])

    #expect(state.selectedSessionID == earlier.id)
    #expect(state.selectedSession?.application == "Xcode")

    state.moveSelection(.next)
    #expect(state.selectedSessionID == later.id)

    state.moveSelection(.next)
    #expect(state.selectedSessionID == earlier.id)

    state.moveSelection(.previous)
    #expect(state.selectedSessionID == later.id)
}

@Test
func keyboardReviewRequiresAChangedClassificationBeforeApplyAndConfirmation() {
    let session = reviewSession(idOffset: 0, application: "Safari", classification: .unknown)
    var state = DailyReviewKeyboardFlowState(sourceDay: "2026-07-14", sessions: [session])

    #expect(state.selectedClassification == .unknown)
    #expect(state.pendingCorrection == nil)
    #expect(state.canConfirm == false)

    state.selectClassification(.work)
    #expect(state.pendingCorrection == DailyReviewKeyboardCorrection(
        sessionID: session.id,
        classification: .work
    ))
    #expect(state.canConfirm == false)

    #expect(state.recordAppliedCorrection() == true)
    #expect(state.pendingCorrection == nil)
    #expect(state.canConfirm == true)

    state.selectClassification(.gaming)
    #expect(state.pendingCorrection != nil)
    #expect(state.canConfirm == false)

    state.selectClassification(.work)
    #expect(state.pendingCorrection == nil)
    #expect(state.canConfirm == true)
}

@Test
func keyboardReviewDoesNotClaimAnInvalidOrFailedCorrectionWasApplied() {
    let session = reviewSession(idOffset: 0, application: "Safari", classification: .gaming)
    var state = DailyReviewKeyboardFlowState(sourceDay: "2026-07-14", sessions: [session])

    #expect(state.recordAppliedCorrection() == false)
    #expect(state.canConfirm == false)

    state.selectClassification(.gaming)
    #expect(state.recordAppliedCorrection() == false)
    #expect(state.canConfirm == false)
}

@Test
func keyboardReviewKeepsTheAppliedGateAcrossRefreshButResetsForAnotherDay() {
    let session = reviewSession(idOffset: 0, application: "Safari", classification: .unknown)
    var state = DailyReviewKeyboardFlowState(sourceDay: "2026-07-14", sessions: [session])
    state.selectClassification(.work)
    #expect(state.recordAppliedCorrection() == true)

    let corrected = reviewSession(idOffset: 0, application: "Safari", classification: .work)
    state.reconcile(sourceDay: "2026-07-14", sessions: [corrected])
    #expect(state.selectedSessionID == corrected.id)
    #expect(state.selectedClassification == .work)
    #expect(state.canConfirm == true)

    state.reconcile(sourceDay: "2026-07-15", sessions: [corrected])
    #expect(state.canConfirm == false)
}

@Test
func keyboardReviewShortcutRoutesAreVisibleCompleteAndCollisionFree() {
    let routes = DailyReviewKeyboardShortcut.allCases.map(\.descriptor)

    #expect(Set(routes.map(\.signature)).count == routes.count)
    #expect(routes.allSatisfy {
        !$0.modifiers.isSuperset(of: [.control, .option])
    })
    #expect(Set(DailyReviewKeyboardShortcut.allCases) == Set([
        .openReviews,
        .previousSession,
        .nextSession,
        .chooseWork,
        .chooseGaming,
        .chooseDistracting,
        .chooseIdle,
        .chooseUnknown,
        .applyCorrection,
        .confirmReview
    ]))
    #expect(DailyReviewKeyboardShortcut.applyCorrection.descriptor.visibleLegend == "command-shift-a")
    #expect(DailyReviewKeyboardShortcut.confirmReview.descriptor.visibleLegend == "command-shift-return")
}

@Test
func keyboardReviewNavigationShortcutIsVisibleAndRoutesOnlyToReviews() {
    let shortcut = DailyReviewKeyboardShortcut.openReviews.descriptor

    #expect(AppSection.reviews.dailyReviewKeyboardShortcut == .openReviews)
    #expect(AppSection.allCases.filter { $0.dailyReviewKeyboardShortcut != nil } == [.reviews])
    #expect(shortcut.signature == "command+option+r")
    #expect(shortcut.visibleLegend == "option-command-r")
    #expect(shortcut.glyphLegend == "⌥⌘r")
}

private func reviewSession(
    idOffset: TimeInterval,
    application: String,
    classification: BehaviorClassification
) -> DailyReviewSession {
    let start = Date(timeIntervalSince1970: 1_789_000_000 + idOffset)
    return DailyReviewSession(
        sourceDay: "2026-07-14",
        start: start,
        end: start.addingTimeInterval(300),
        application: application,
        classification: classification,
        observationCount: 3
    )
}
