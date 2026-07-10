import Foundation

public enum OperatingMode: String, Codable, CaseIterable, Sendable {
    case observe
    case suggest
    case assist
    case autonomous

    // Source-compatible names for policies and call sites created before the
    // four-stage rollout model was made explicit.
    public static let suggestionsOnly = OperatingMode.suggest
    public static let approvalRequired = OperatingMode.assist
    public static let fullyAutomatic = OperatingMode.autonomous

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case Self.observe.rawValue:
            self = .observe
        case Self.suggest.rawValue, "suggestionsOnly":
            self = .suggest
        case Self.assist.rawValue, "approvalRequired":
            self = .assist
        case Self.autonomous.rawValue, "fullyAutomatic":
            self = .autonomous
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported operating mode: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum Weekday: Int, Codable, CaseIterable, Comparable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct LocalTime: Codable, Equatable, Hashable, Comparable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    public var minuteOfDay: Int { hour * 60 + minute }
}

public struct DailyTimeWindow: Codable, Equatable, Sendable {
    public let start: LocalTime
    public let end: LocalTime

    public init(start: LocalTime, end: LocalTime) {
        self.start = start
        self.end = end
    }

    public var crossesMidnight: Bool { end < start }
}

public struct WeeklyWorkWindow: Codable, Equatable, Sendable {
    public let weekdays: [Weekday]
    public let start: LocalTime
    public let end: LocalTime

    public init(weekdays: [Weekday], start: LocalTime, end: LocalTime) {
        self.weekdays = weekdays
        self.start = start
        self.end = end
    }
}

public struct AutomationPause: Codable, Equatable, Sendable {
    public let isPaused: Bool
    public let resumesAtUTC: Date?

    public init(isPaused: Bool, resumesAtUTC: Date? = nil) {
        self.isPaused = isPaused
        self.resumesAtUTC = resumesAtUTC
    }

    public static let running = AutomationPause(isPaused: false)
    public static let pausedIndefinitely = AutomationPause(isPaused: true)
}

public struct SchedulePolicy: Codable, Equatable, Sendable {
    public let timeZoneIdentifier: String
    public let workWindows: [WeeklyWorkWindow]
    public let quietHours: DailyTimeWindow
    public let nightlyPlanningTime: LocalTime
    public let morningConfirmationTime: LocalTime
    public let planningCapacityPercent: Int

    public init(
        timeZoneIdentifier: String,
        workWindows: [WeeklyWorkWindow],
        quietHours: DailyTimeWindow,
        nightlyPlanningTime: LocalTime,
        morningConfirmationTime: LocalTime,
        planningCapacityPercent: Int
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.workWindows = workWindows
        self.quietHours = quietHours
        self.nightlyPlanningTime = nightlyPlanningTime
        self.morningConfirmationTime = morningConfirmationTime
        self.planningCapacityPercent = planningCapacityPercent
    }
}

public struct CalendarSelectionPolicy: Codable, Equatable, Sendable {
    public let visibleCalendarIdentifiers: [String]
    public let schedulingCalendarIdentifier: String?

    public init(visibleCalendarIdentifiers: [String], schedulingCalendarIdentifier: String?) {
        self.visibleCalendarIdentifiers = visibleCalendarIdentifiers
        self.schedulingCalendarIdentifier = schedulingCalendarIdentifier
    }
}

public enum AIProviderSelection: String, Codable, CaseIterable, Sendable {
    case disabled
    case localOllama
    case appleOnDevice
    case remoteOpenAI
}

public enum RemoteEvidencePolicy: String, Codable, CaseIterable, Sendable {
    case localOnly
    case redactedMetadataOnly
    case explicitPrivateContent
}

public struct PrivacyPolicy: Codable, Equatable, Sendable {
    public let screenshotAnalysisEnabled: Bool
    public let aiProvider: AIProviderSelection
    public let remoteEvidencePolicy: RemoteEvidencePolicy
    public let rawScreenshotRetentionDays: Int
    public let extractedTextRetentionDays: Int
    public let diagnosticRetentionDays: Int

    public init(
        screenshotAnalysisEnabled: Bool,
        aiProvider: AIProviderSelection,
        remoteEvidencePolicy: RemoteEvidencePolicy,
        rawScreenshotRetentionDays: Int,
        extractedTextRetentionDays: Int,
        diagnosticRetentionDays: Int
    ) {
        self.screenshotAnalysisEnabled = screenshotAnalysisEnabled
        self.aiProvider = aiProvider
        self.remoteEvidencePolicy = remoteEvidencePolicy
        self.rawScreenshotRetentionDays = rawScreenshotRetentionDays
        self.extractedTextRetentionDays = extractedTextRetentionDays
        self.diagnosticRetentionDays = diagnosticRetentionDays
    }
}

public struct WakePolicyConfiguration: Codable, Equatable, Sendable {
    public let isEligible: Bool
    public let window: DailyTimeWindow
    public let maximumDailyInterventions: Int
    public let quietWeekdays: [Weekday]?

    public init(isEligible: Bool, window: DailyTimeWindow, maximumDailyInterventions: Int, quietWeekdays: [Weekday]? = nil) {
        self.isEligible = isEligible
        self.window = window
        self.maximumDailyInterventions = maximumDailyInterventions
        self.quietWeekdays = quietWeekdays
    }
}

public struct UserPolicy: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let operatingMode: OperatingMode
    public let automationPause: AutomationPause
    public let schedule: SchedulePolicy
    public let calendar: CalendarSelectionPolicy
    public let privacy: PrivacyPolicy
    public let wake: WakePolicyConfiguration

    public init(
        schemaVersion: Int = UserPolicy.schemaVersion,
        operatingMode: OperatingMode,
        automationPause: AutomationPause,
        schedule: SchedulePolicy,
        calendar: CalendarSelectionPolicy,
        privacy: PrivacyPolicy,
        wake: WakePolicyConfiguration
    ) {
        self.schemaVersion = schemaVersion
        self.operatingMode = operatingMode
        self.automationPause = automationPause
        self.schedule = schedule
        self.calendar = calendar
        self.privacy = privacy
        self.wake = wake
    }

    public static func defaults(timeZoneIdentifier: String = TimeZone.current.identifier) -> UserPolicy {
        UserPolicy(
            operatingMode: .autonomous,
            automationPause: .running,
            schedule: SchedulePolicy(
                timeZoneIdentifier: timeZoneIdentifier,
                workWindows: [
                    WeeklyWorkWindow(
                        weekdays: [.sunday, .monday, .tuesday, .wednesday, .thursday],
                        start: LocalTime(hour: 9, minute: 0),
                        end: LocalTime(hour: 18, minute: 0)
                    )
                ],
                quietHours: DailyTimeWindow(
                    start: LocalTime(hour: 23, minute: 0),
                    end: LocalTime(hour: 7, minute: 0)
                ),
                nightlyPlanningTime: LocalTime(hour: 22, minute: 30),
                morningConfirmationTime: LocalTime(hour: 8, minute: 0),
                planningCapacityPercent: 70
            ),
            calendar: CalendarSelectionPolicy(
                visibleCalendarIdentifiers: [],
                schedulingCalendarIdentifier: nil
            ),
            privacy: PrivacyPolicy(
                screenshotAnalysisEnabled: true,
                aiProvider: .localOllama,
                remoteEvidencePolicy: .localOnly,
                rawScreenshotRetentionDays: 30,
                extractedTextRetentionDays: 30,
                diagnosticRetentionDays: 14
            ),
            wake: WakePolicyConfiguration(
                isEligible: false,
                window: DailyTimeWindow(
                    start: LocalTime(hour: 7, minute: 0),
                    end: LocalTime(hour: 9, minute: 0)
                ),
                maximumDailyInterventions: 1
            )
        )
    }

    public func validationViolations() -> [PolicyViolation] {
        var violations: [PolicyViolation] = []
        if schemaVersion != Self.schemaVersion {
            violations.append(.init(code: .unsupportedSchemaVersion, field: "schemaVersion"))
        }
        if automationPause.isPaused == false, automationPause.resumesAtUTC != nil {
            violations.append(.init(code: .resumeDateWhileRunning, field: "automationPause.resumesAtUTC"))
        }
        if TimeZone(identifier: schedule.timeZoneIdentifier) == nil {
            violations.append(.init(code: .invalidTimeZone, field: "schedule.timeZoneIdentifier"))
        }
        if schedule.workWindows.isEmpty {
            violations.append(.init(code: .missingWorkWindow, field: "schedule.workWindows"))
        }
        for (index, window) in schedule.workWindows.enumerated() {
            appendTimeViolation(window.start, field: "schedule.workWindows[\(index)].start", to: &violations)
            appendTimeViolation(window.end, field: "schedule.workWindows[\(index)].end", to: &violations)
            if window.weekdays.isEmpty {
                violations.append(.init(code: .missingWeekday, field: "schedule.workWindows[\(index)].weekdays"))
            } else if Set(window.weekdays).count != window.weekdays.count {
                violations.append(.init(code: .duplicateWeekday, field: "schedule.workWindows[\(index)].weekdays"))
            }
            if window.start >= window.end {
                violations.append(.init(code: .invalidWorkWindow, field: "schedule.workWindows[\(index)]"))
            }
        }
        appendOverlappingWorkWindowViolations(to: &violations)
        appendTimeViolation(schedule.quietHours.start, field: "schedule.quietHours.start", to: &violations)
        appendTimeViolation(schedule.quietHours.end, field: "schedule.quietHours.end", to: &violations)
        if schedule.quietHours.start == schedule.quietHours.end {
            violations.append(.init(code: .emptyTimeWindow, field: "schedule.quietHours"))
        }
        appendTimeViolation(schedule.nightlyPlanningTime, field: "schedule.nightlyPlanningTime", to: &violations)
        appendTimeViolation(schedule.morningConfirmationTime, field: "schedule.morningConfirmationTime", to: &violations)
        if !(25...100).contains(schedule.planningCapacityPercent) {
            violations.append(.init(code: .invalidCapacityPercent, field: "schedule.planningCapacityPercent"))
        }
        let visibleIDs = calendar.visibleCalendarIdentifiers
        if visibleIDs.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            violations.append(.init(code: .emptyCalendarIdentifier, field: "calendar.visibleCalendarIdentifiers"))
        }
        if Set(visibleIDs).count != visibleIDs.count {
            violations.append(.init(code: .duplicateCalendarIdentifier, field: "calendar.visibleCalendarIdentifiers"))
        }
        if let schedulingID = calendar.schedulingCalendarIdentifier,
           schedulingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            violations.append(.init(code: .emptyCalendarIdentifier, field: "calendar.schedulingCalendarIdentifier"))
        }
        appendRetentionViolation(privacy.rawScreenshotRetentionDays, field: "privacy.rawScreenshotRetentionDays", to: &violations)
        appendRetentionViolation(privacy.extractedTextRetentionDays, field: "privacy.extractedTextRetentionDays", to: &violations)
        appendRetentionViolation(privacy.diagnosticRetentionDays, field: "privacy.diagnosticRetentionDays", to: &violations)
        if privacy.aiProvider != .remoteOpenAI, privacy.remoteEvidencePolicy != .localOnly {
            violations.append(.init(code: .remotePolicyWithoutRemoteProvider, field: "privacy.remoteEvidencePolicy"))
        }
        appendTimeViolation(wake.window.start, field: "wake.window.start", to: &violations)
        appendTimeViolation(wake.window.end, field: "wake.window.end", to: &violations)
        if wake.window.start == wake.window.end {
            violations.append(.init(code: .emptyTimeWindow, field: "wake.window"))
        }
        if !(0...3).contains(wake.maximumDailyInterventions) || (wake.isEligible && wake.maximumDailyInterventions == 0) {
            violations.append(.init(code: .invalidWakeBudget, field: "wake.maximumDailyInterventions"))
        }
        return violations
    }

    @discardableResult
    public func validated() throws -> UserPolicy {
        let violations = validationViolations()
        guard violations.isEmpty else { throw UserPolicyValidationError(violations: violations) }
        return self
    }

    private func appendTimeViolation(_ time: LocalTime, field: String, to violations: inout [PolicyViolation]) {
        if !(0...23).contains(time.hour) || !(0...59).contains(time.minute) {
            violations.append(.init(code: .invalidLocalTime, field: field))
        }
    }

    private func appendRetentionViolation(_ days: Int, field: String, to violations: inout [PolicyViolation]) {
        if !(0...3_650).contains(days) {
            violations.append(.init(code: .invalidRetention, field: field))
        }
    }

    private func appendOverlappingWorkWindowViolations(to violations: inout [PolicyViolation]) {
        for weekday in Weekday.allCases {
            let indexed = schedule.workWindows.enumerated().filter { $0.element.weekdays.contains(weekday) }
            for left in indexed.indices {
                for right in indexed.indices where right > left {
                    let first = indexed[left]
                    let second = indexed[right]
                    if first.element.start < second.element.end, second.element.start < first.element.end {
                        violations.append(.init(
                            code: .overlappingWorkWindows,
                            field: "schedule.workWindows[\(first.offset),\(second.offset)].\(weekday.rawValue)"
                        ))
                    }
                }
            }
        }
    }
}

public struct PolicyViolation: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case unsupportedSchemaVersion
        case resumeDateWhileRunning
        case invalidTimeZone
        case missingWorkWindow
        case invalidLocalTime
        case missingWeekday
        case duplicateWeekday
        case invalidWorkWindow
        case overlappingWorkWindows
        case emptyTimeWindow
        case invalidCapacityPercent
        case emptyCalendarIdentifier
        case duplicateCalendarIdentifier
        case invalidRetention
        case remotePolicyWithoutRemoteProvider
        case invalidWakeBudget
    }

    public let code: Code
    public let field: String

    public init(code: Code, field: String) {
        self.code = code
        self.field = field
    }
}

public struct UserPolicyValidationError: Error, Equatable, Sendable {
    public let violations: [PolicyViolation]

    public init(violations: [PolicyViolation]) {
        self.violations = violations
    }
}

public extension JSONEncoder {
    static var zoidPolicy: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var zoidPolicy: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
