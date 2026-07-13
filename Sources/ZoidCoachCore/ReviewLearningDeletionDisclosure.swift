public enum ReviewLearningDeletionDisclosure {
    public static let inventoryTitle = "Reviews and learned rules"

    public static let inventoryDetail = "Daily and weekly reviews, personal notes, corrections, weekly experiments, learned app-classification rules, learning samples and aggregates, and planner trust cycles. Raw behavior records and task facts are stored separately and remain when this category is deleted."

    public static let confirmationTitle = "Delete reviews and learned rules?"

    public static let confirmationMessage = "This deletes daily and weekly reviews, personal notes, corrections, weekly experiments, learned app-classification rules, learning samples and aggregates, and planner trust cycles from this Mac. Raw behavior records and task facts remain. Cancel leaves everything unchanged. After confirmation, future learning starts again from defaults. This cannot be undone."

    public static let confirmButtonTitle = "DELETE REVIEWS AND LEARNED RULES"

    public static func successMessage(deletedCount: Int) -> String {
        let count = max(0, deletedCount)
        guard count > 0 else {
            return "Nothing remained to delete. Daily and weekly reviews, personal notes, corrections, weekly experiments, learned app-classification rules, learning samples and aggregates, and planner trust cycles are already clear. Raw behavior records and task facts remain."
        }
        let noun = count == 1 ? "record" : "records"
        return "Deleted \(count) review and learning \(noun). Cleared categories include daily and weekly reviews, personal notes, corrections, weekly experiments, learned app-classification rules, learning samples and aggregates, and planner trust cycles. Raw behavior records and task facts remain."
    }
}
