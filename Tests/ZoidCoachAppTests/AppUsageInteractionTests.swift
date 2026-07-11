import Testing
@testable import ZoidCoachApp

@Test
func appUsagePopupDoesNotDismissDuringPanelOrSelectorInteraction() {
    #expect(AppUsagePopoverDismissalPolicy.shouldDismiss(
        isAnchorFocused: false,
        isPointerOverAnchor: false,
        isPointerOverPanel: true,
        isSelectorActive: false
    ) == false)

    #expect(AppUsagePopoverDismissalPolicy.shouldDismiss(
        isAnchorFocused: false,
        isPointerOverAnchor: false,
        isPointerOverPanel: false,
        isSelectorActive: true
    ) == false)

    #expect(AppUsagePopoverDismissalPolicy.shouldDismiss(
        isAnchorFocused: false,
        isPointerOverAnchor: false,
        isPointerOverPanel: false,
        isSelectorActive: false
    ))
}

@Test
func appUsagePopupDismissesAfterLeavingEveryInteractionRegion() {
    #expect(AppUsagePopoverDismissalPolicy.shouldDismiss(
        isAnchorFocused: false,
        isPointerOverAnchor: false,
        isPointerOverPanel: false,
        isSelectorActive: false
    ))
}
