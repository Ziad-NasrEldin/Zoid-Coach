import Foundation
import SwiftUI
import ZoidCoachCore

struct SignedQATimeZonePickerControl {
    private static let crossDayCandidates = [
        "Pacific/Kiritimati",
        "Pacific/Pago_Pago"
    ]
    private static let sameDayCandidates = [
        "Africa/Nairobi",
        "Europe/Athens",
        "America/Vancouver",
        "America/Tijuana",
        "Pacific/Midway",
        "Etc/GMT+11",
        "Etc/GMT-14",
        "Pacific/Apia",
        "Asia/Tokyo",
        "UTC"
    ]
    private static let stabilityOffsets: [TimeInterval] = [-300, 0, 300]

    let isAvailable: Bool

    init(runtimeEnvironment: RuntimeEnvironment) {
        guard case .qa = runtimeEnvironment.mode,
              runtimeEnvironment.packageMode == .qa else {
            isAvailable = false
            return
        }
        isAvailable = true
    }

    func crossDayDestination(from sourceIdentifier: String, at date: Date) -> String? {
        destination(
            from: sourceIdentifier,
            at: date,
            candidates: Self.crossDayCandidates,
            shouldMatchSourceDay: false
        )
    }

    func sameDayDestination(from sourceIdentifier: String, at date: Date) -> String? {
        destination(
            from: sourceIdentifier,
            at: date,
            candidates: Self.sameDayCandidates,
            shouldMatchSourceDay: true
        )
    }

    private func destination(
        from sourceIdentifier: String,
        at date: Date,
        candidates: [String],
        shouldMatchSourceDay: Bool
    ) -> String? {
        guard isAvailable,
              TimeZone(identifier: sourceIdentifier) != nil else { return nil }
        return candidates.first { candidate in
            guard candidate != sourceIdentifier,
                  TimeZone(identifier: candidate) != nil else { return false }
            return Self.stabilityOffsets.allSatisfy { offset in
                let comparisonDate = date.addingTimeInterval(offset)
                guard let sourceDay = Self.localDayKey(
                    comparisonDate,
                    timeZoneIdentifier: sourceIdentifier
                ),
                let destinationDay = Self.localDayKey(
                    comparisonDate,
                    timeZoneIdentifier: candidate
                ) else { return false }
                return shouldMatchSourceDay
                    ? sourceDay == destinationDay
                    : sourceDay != destinationDay
            }
        }
    }

    private static func localDayKey(
        _ date: Date,
        timeZoneIdentifier: String
    ) -> DateComponents? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.era, .year, .month, .day], from: date)
    }
}

struct SignedQATimeZonePickerControls: View {
    @Binding private var selection: String
    private let sourceTimeZoneIdentifier: String
    private let control: SignedQATimeZonePickerControl
    private let now: () -> Date

    init(
        selection: Binding<String>,
        sourceTimeZoneIdentifier: String,
        runtimeEnvironment: RuntimeEnvironment = .current(),
        now: @escaping () -> Date = Date.init
    ) {
        _selection = selection
        self.sourceTimeZoneIdentifier = sourceTimeZoneIdentifier
        control = SignedQATimeZonePickerControl(runtimeEnvironment: runtimeEnvironment)
        self.now = now
    }

    var body: some View {
        if control.isAvailable {
            VStack(alignment: .leading, spacing: 6) {
                Text("SIGNED QA TIME-ZONE DRIVER")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)

                HStack(spacing: 8) {
                    Button("SELECT CROSS-DAY ZONE") {
                        if let destination = control.crossDayDestination(
                            from: sourceTimeZoneIdentifier,
                            at: now()
                        ) {
                            selection = destination
                        }
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .accessibilityLabel("Select a signed QA cross-day time zone")
                    .accessibilityHint("Changes only the settings draft so the normal save confirmation can be verified")
                    .accessibilityIdentifier("settings.schedule.time-zone.qa-cross-day")

                    Button("SELECT SAME-DAY ZONE") {
                        if let destination = control.sameDayDestination(
                            from: sourceTimeZoneIdentifier,
                            at: now()
                        ) {
                            selection = destination
                        }
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .accessibilityLabel("Select a signed QA same-day time zone")
                    .accessibilityHint("Changes only the settings draft so the no-warning path can be verified")
                    .accessibilityIdentifier("settings.schedule.time-zone.qa-same-day")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.schedule.time-zone.qa-controls")
        }
    }
}
