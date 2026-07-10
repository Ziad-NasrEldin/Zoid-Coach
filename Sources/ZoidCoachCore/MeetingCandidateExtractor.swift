import Foundation

public enum MeetingCandidateConfidence: Int, Comparable, Codable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: MeetingCandidateConfidence, rhs: MeetingCandidateConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct MeetingEvidenceSpan: Equatable, Codable, Sendable {
    public let kind: String
    public let text: String
    public let location: Int
    public let length: Int

    public init(kind: String, text: String, location: Int, length: Int) {
        self.kind = kind
        self.text = text
        self.location = location
        self.length = length
    }
}

public struct MeetingCandidate: Equatable, Codable, Sendable {
    public let title: String
    public let start: Date
    public let durationMinutes: Int
    public let confidence: MeetingCandidateConfidence
    public let confidenceScore: Double
    public let requiresClarification: Bool
    public let sourceText: String
    public let participants: [String]
    public let startExpression: String
    public let location: String?
    public let callLink: String?
    public let timezoneIdentifier: String
    public let evidenceSpans: [MeetingEvidenceSpan]

    public init(
        title: String,
        start: Date,
        durationMinutes: Int,
        confidence: MeetingCandidateConfidence,
        requiresClarification: Bool,
        sourceText: String,
        confidenceScore: Double? = nil,
        participants: [String] = [],
        startExpression: String = "",
        location: String? = nil,
        callLink: String? = nil,
        timezoneIdentifier: String = TimeZone.current.identifier,
        evidenceSpans: [MeetingEvidenceSpan] = []
    ) {
        self.title = title
        self.start = start
        self.durationMinutes = durationMinutes
        self.confidence = confidence
        self.confidenceScore = min(max(confidenceScore ?? (confidence == .high ? 0.9 : confidence == .medium ? 0.7 : 0.4), 0), 1)
        self.requiresClarification = requiresClarification
        self.sourceText = sourceText
        self.participants = participants
        self.startExpression = startExpression
        self.location = location
        self.callLink = callLink
        self.timezoneIdentifier = timezoneIdentifier
        self.evidenceSpans = evidenceSpans
    }
}

public struct MeetingCandidateExtractor: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func extract(from text: String, observedAt: Date) -> MeetingCandidate? {
        let normalizedText = normalize(text)
        guard let dateExpression = firstMatch(#"\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|اليوم|بكرة|غدا|الأحد|الاثنين|الثلاثاء|الأربعاء|الخميس|الجمعة|السبت)\b"#, in: normalizedText)
        else { return nil }
        let contextualTime = firstMatch(#"\b(?:at|around|by|الساعة)\s*([0-1]?\d)(?::([0-5]\d))?\s*(am|pm|ص|م)?\b"#, in: normalizedText)
        let hasMeetingIntent = firstMatch(#"\b(meet(?:ing)?|call|appointment|موعد|اجتماع|مكالمة)\b"#, in: normalizedText) != nil
        let unprefixedTime = hasMeetingIntent
            ? firstMatch(#"\b([0-1]?\d)(?::([0-5]\d))?\s*(am|pm|ص|م)\b"#, in: normalizedText)
                ?? firstMatch(#"\b([01]?\d|2[0-3]):([0-5]\d)\b"#, in: normalizedText)
            : nil
        guard let timeExpression = contextualTime ?? unprefixedTime,
              let hourText = capture(timeExpression, at: 1),
              let hour = Int(hourText)
        else { return nil }

        let minute = capture(timeExpression, at: 2).flatMap(Int.init) ?? 0
        let meridiem = normalizeMeridiem(capture(timeExpression, at: 3)?.lowercased())
        guard let resolvedDate = resolveDate(
            expression: dateExpression.value.lowercased(),
            hour: hour,
            minute: minute,
            meridiem: meridiem,
            observedAt: observedAt
        ) else { return nil }

        let duration = durationMinutes(in: normalizedText) ?? 30
        let isExplicitTime = meridiem != nil || hour >= 8
        let callLink = firstMatch(#"https?://[^\s<>]+"#, in: normalizedText)?.value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?)"))
        let participants = participantNames(in: normalizedText)
        let location = explicitLocation(in: normalizedText)
        let expression = "\(dateExpression.value) \(timeExpression.value)"
        return MeetingCandidate(
            title: participants.isEmpty ? "Meeting detected" : "Meeting with \(participants.joined(separator: ", "))",
            start: resolvedDate,
            durationMinutes: duration,
            confidence: isExplicitTime ? .high : .medium,
            requiresClarification: !isExplicitTime,
            sourceText: text,
            confidenceScore: isExplicitTime ? 0.9 : 0.7,
            participants: participants,
            startExpression: expression,
            location: location,
            callLink: callLink,
            timezoneIdentifier: calendar.timeZone.identifier,
            evidenceSpans: [
                MeetingEvidenceSpan(kind: "date", text: dateExpression.value, location: dateExpression.result.range.location, length: dateExpression.result.range.length),
                MeetingEvidenceSpan(kind: "time", text: timeExpression.value, location: timeExpression.result.range.location, length: timeExpression.result.range.length)
            ]
        )
    }

    private func resolveDate(
        expression: String,
        hour: Int,
        minute: Int,
        meridiem: String?,
        observedAt: Date
    ) -> Date? {
        guard hour >= 0, hour <= 23, minute >= 0, minute <= 59 else { return nil }
        let startOfObservedDay = calendar.startOfDay(for: observedAt)
        let targetDay: Date
        switch expression {
        case "today", "اليوم":
            targetDay = startOfObservedDay
        case "tomorrow", "بكرة", "غدا":
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfObservedDay) else { return nil }
            targetDay = nextDay
        default:
            guard let targetWeekday = weekday(expression) else { return nil }
            let currentWeekday = calendar.component(.weekday, from: observedAt)
            var daysAhead = (targetWeekday - currentWeekday + 7) % 7
            if daysAhead == 0 { daysAhead = 7 }
            guard let nextTarget = calendar.date(byAdding: .day, value: daysAhead, to: startOfObservedDay) else { return nil }
            targetDay = nextTarget
        }

        var resolvedHour = hour
        if let meridiem {
            guard hour >= 1, hour <= 12 else { return nil }
            if meridiem == "pm", hour < 12 { resolvedHour += 12 }
            if meridiem == "am", hour == 12 { resolvedHour = 0 }
        }
        return calendar.date(bySettingHour: resolvedHour, minute: minute, second: 0, of: targetDay)
    }

    private func weekday(_ expression: String) -> Int? {
        [
            "sunday": 1,
            "monday": 2,
            "tuesday": 3,
            "wednesday": 4,
            "thursday": 5,
            "friday": 6,
            "saturday": 7,
            "الأحد": 1,
            "الاثنين": 2,
            "الثلاثاء": 3,
            "الأربعاء": 4,
            "الخميس": 5,
            "الجمعة": 6,
            "السبت": 7
        ][expression]
    }

    private func durationMinutes(in text: String) -> Int? {
        guard let match = firstMatch(#"\b(?:for|لمدة)\s+(\d+)\s*(minutes?|mins?|hours?|hrs?|دقيقة|دقائق|ساعة|ساعات)\b"#, in: text),
              let amountText = capture(match, at: 1),
              let amount = Int(amountText),
              let unit = capture(match, at: 2)?.lowercased()
        else { return nil }
        return unit.hasPrefix("h") || unit.hasPrefix("ساعة") ? amount * 60 : amount
    }

    private func normalize(_ text: String) -> String {
        let digits: [Character: Character] = ["٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9"]
        return String(text.map { digits[$0] ?? $0 })
    }

    private func normalizeMeridiem(_ value: String?) -> String? {
        switch value {
        case "م": "pm"
        case "ص": "am"
        default: value
        }
    }

    private func participantNames(in text: String) -> [String] {
        guard let match = firstMatch(#"\bwith\s+([\p{L}][\p{L}\s'-]{1,40}?)(?=\s+(?:today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|at|for)\b|[,.!?]|$)"#, in: text),
              let value = capture(match, at: 1)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return [] }
        let separator = try? NSRegularExpression(pattern: #"\s*(?:&|,|\band\b)\s*"#, options: [.caseInsensitive])
        let range = NSRange(value.startIndex..., in: value)
        let separated = separator?.stringByReplacingMatches(in: value, range: range, withTemplate: "|") ?? value
        return separated.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func explicitLocation(in text: String) -> String? {
        guard let match = firstMatch(#"\b(?:location|مكان)\s*[:\-]\s*([^\n,.!?]{2,80})"#, in: text),
              let value = capture(match, at: 1)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    private func firstMatch(_ pattern: String, in text: String) -> RegexMatch? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let result = expression.firstMatch(in: text, range: range),
              let swiftRange = Range(result.range, in: text)
        else { return nil }
        return RegexMatch(value: String(text[swiftRange]), result: result, text: text)
    }

    private func capture(_ match: RegexMatch, at index: Int) -> String? {
        guard index < match.result.numberOfRanges else { return nil }
        let range = match.result.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: match.text)
        else { return nil }
        return String(match.text[swiftRange])
    }
}

private struct RegexMatch {
    let value: String
    let result: NSTextCheckingResult
    let text: String
}
