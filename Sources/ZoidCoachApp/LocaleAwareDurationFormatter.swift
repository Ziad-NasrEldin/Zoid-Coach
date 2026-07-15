import Foundation

struct LocaleAwareDurationFormatter: Equatable {
    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func wide(minutes: Int) -> String {
        format(minutes: minutes, width: .wide)
    }

    func compact(minutes: Int) -> String {
        format(minutes: minutes, width: .abbreviated)
    }

    private func format(
        minutes: Int,
        width: Measurement<UnitDuration>.FormatStyle.UnitWidth
    ) -> String {
        Measurement(value: Double(max(0, minutes)), unit: UnitDuration.minutes)
            .formatted(.measurement(width: width, usage: .asProvided).locale(locale))
    }
}
