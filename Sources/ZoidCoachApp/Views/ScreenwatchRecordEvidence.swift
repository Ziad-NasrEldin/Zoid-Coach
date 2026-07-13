import Foundation

struct ScreenwatchRecordEvidence: Equatable {
    let sourcePath: String
    let lastValidRecordText: String?

    init?(
        status: ScreenwatchSetupStatus,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        guard let sourcePath = status.sourcePath else { return nil }
        self.sourcePath = sourcePath
        self.lastValidRecordText = status.lastValidRecordAt.map {
            Self.format($0, locale: locale, timeZone: timeZone)
        }
    }

    var accessibilitySummary: String {
        if let lastValidRecordText {
            return "Screenwatch folder: \(sourcePath). Last valid record: \(lastValidRecordText)."
        }
        return "Screenwatch folder: \(sourcePath). No valid record is available yet."
    }

    private static func format(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
