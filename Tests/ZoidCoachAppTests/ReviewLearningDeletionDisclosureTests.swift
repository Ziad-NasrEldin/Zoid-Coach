import Testing
@testable import ZoidCoachCore

@Test
func reviewLearningDeletionConfirmationDisclosesEveryDeletedCategoryAndPreservedFact() {
    let message = ReviewLearningDeletionDisclosure.confirmationMessage
    for expected in [
        "daily and weekly reviews",
        "personal notes",
        "corrections",
        "weekly experiments",
        "learned app-classification rules",
        "learning samples and aggregates",
        "planner trust cycles",
    ] {
        #expect(message.lowercased().contains(expected))
        #expect(ReviewLearningDeletionDisclosure.inventoryDetail.lowercased().contains(expected))
    }
    #expect(message.contains("Raw behavior records and task facts remain."))
    #expect(message.contains("Cancel leaves everything unchanged."))
    #expect(message.contains("This cannot be undone."))
    #expect(ReviewLearningDeletionDisclosure.confirmButtonTitle == "DELETE REVIEWS AND LEARNED RULES")
}

@Test
func reviewLearningDeletionSuccessCopyHandlesPositiveSingularAndRepeatZeroStates() {
    let singular = ReviewLearningDeletionDisclosure.successMessage(deletedCount: 1)
    let plural = ReviewLearningDeletionDisclosure.successMessage(deletedCount: 7)
    let zero = ReviewLearningDeletionDisclosure.successMessage(deletedCount: 0)
    let defensiveNegative = ReviewLearningDeletionDisclosure.successMessage(deletedCount: -1)

    #expect(singular.contains("Deleted 1 review and learning record."))
    #expect(plural.contains("Deleted 7 review and learning records."))
    #expect(zero.hasPrefix("Nothing remained to delete."))
    #expect(defensiveNegative == zero)
    #expect(zero.contains("already clear"))
    #expect(zero.contains("Raw behavior records and task facts remain."))
    #expect(plural.contains("Raw behavior records and task facts remain."))
    for expected in [
        "daily and weekly reviews",
        "personal notes",
        "corrections",
        "weekly experiments",
        "learned app-classification rules",
        "learning samples and aggregates",
        "planner trust cycles",
    ] {
        #expect(plural.lowercased().contains(expected))
        #expect(zero.lowercased().contains(expected))
    }
}
