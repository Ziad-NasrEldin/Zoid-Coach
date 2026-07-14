import CoreGraphics
import Testing
@testable import ZoidCoachApp

@Test("Retention controls keep readable single-line values at constrained widths")
func retentionControlsKeepReadableValuesAtConstrainedWidths() {
    #expect(RetentionControlMetrics.fittedColumnCount(availableWidth: 660) == 3)
    #expect(RetentionControlMetrics.fittedColumnCount(availableWidth: 500) == 2)
    #expect(RetentionControlMetrics.fittedColumnCount(availableWidth: 320) == 1)
    #expect(RetentionControlMetrics.minimumValueWidth == 72)

    for days in [0, 30, 90, 365, 3_650] {
        let label = RetentionControlMetrics.valueLabel(days: days)
        #expect(label == "\(days) DAYS")
        #expect(!label.contains("\n"))
    }
}

@Test("Retention controls expose stable value and adjustment identifiers")
func retentionControlsExposeStableAccessibilityIdentifiers() {
    #expect(
        RetentionControlMetrics.valueIdentifier(title: "Behavior records")
            == "settings.retention.behavior-records.value"
    )
    #expect(
        RetentionControlMetrics.adjustmentIdentifier(title: "Behavior records", adjustment: -1)
            == "settings.retention.behavior-records.decrement"
    )
    #expect(
        RetentionControlMetrics.adjustmentIdentifier(title: "Behavior records", adjustment: 1)
            == "settings.retention.behavior-records.increment"
    )
    #expect(
        RetentionControlMetrics.valueIdentifier(title: "Reviews + learning")
            == "settings.retention.reviews-learning.value"
    )
}

@Test("Retention adjustments preserve the existing bounded binding semantics")
func retentionAdjustmentsRemainBounded() {
    #expect(RetentionControlMetrics.adjustedValue(90, adjustment: -1) == 89)
    #expect(RetentionControlMetrics.adjustedValue(90, adjustment: 1) == 91)
    #expect(RetentionControlMetrics.adjustedValue(0, adjustment: -1) == 0)
    #expect(RetentionControlMetrics.adjustedValue(3_650, adjustment: 1) == 3_650)
}
