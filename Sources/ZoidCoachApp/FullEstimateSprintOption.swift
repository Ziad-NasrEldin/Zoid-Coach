struct FullEstimateSprintOption: Equatable {
    let durationMinutes: Int

    init?(estimateMinutes: Int?, isUncertain: Bool) {
        guard !isUncertain,
              let estimateMinutes,
              (1...240).contains(estimateMinutes)
        else { return nil }
        durationMinutes = estimateMinutes
    }

    var menuTitle: String {
        "Full task estimate - \(durationMinutes) minutes"
    }

    var accessibilityLabel: String {
        "Start a \(durationMinutes)-minute sprint matching the full task estimate"
    }
}
