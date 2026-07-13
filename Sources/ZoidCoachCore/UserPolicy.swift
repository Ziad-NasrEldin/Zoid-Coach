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
    private let pauseRequested: Bool
    public let resumesAtUTC: Date?

    public init(isPaused: Bool, resumesAtUTC: Date? = nil) {
        pauseRequested = isPaused
        self.resumesAtUTC = resumesAtUTC
    }

    public var isPaused: Bool { isActive(at: Date()) }
    public var isRequested: Bool { pauseRequested }

    public func isActive(at date: Date) -> Bool {
        guard pauseRequested else { return false }
        return resumesAtUTC.map { date < $0 } ?? true
    }

    public static func pausedForOneHour(from date: Date) -> AutomationPause {
        AutomationPause(isPaused: true, resumesAtUTC: date.addingTimeInterval(60 * 60))
    }

    public static func pausedUntilTomorrow(from date: Date, timeZone: TimeZone) -> AutomationPause {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: date)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? date.addingTimeInterval(24 * 60 * 60)
        return AutomationPause(isPaused: true, resumesAtUTC: startOfTomorrow)
    }

    public static let running = AutomationPause(isPaused: false)
    public static let pausedIndefinitely = AutomationPause(isPaused: true)

    private enum CodingKeys: String, CodingKey {
        case isPaused
        case resumesAtUTC
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pauseRequested = try container.decode(Bool.self, forKey: .isPaused)
        resumesAtUTC = try container.decodeIfPresent(Date.self, forKey: .resumesAtUTC)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pauseRequested, forKey: .isPaused)
        try container.encodeIfPresent(resumesAtUTC, forKey: .resumesAtUTC)
    }
}

public enum CoachingPauseDuration: String, Codable, CaseIterable, Hashable, Sendable {
    case oneHour
    case untilTomorrow
    case indefinitely

    public var label: String {
        switch self {
        case .oneHour: "1 hour"
        case .untilTomorrow: "Until tomorrow"
        case .indefinitely: "Indefinitely"
        }
    }

    public var selectionDescription: String {
        switch self {
        case .oneHour: "a one-hour pause"
        case .untilTomorrow: "a pause until tomorrow"
        case .indefinitely: "an indefinite pause"
        }
    }

    public func automationPause(from date: Date, timeZone: TimeZone) -> AutomationPause {
        switch self {
        case .oneHour:
            .pausedForOneHour(from: date)
        case .untilTomorrow:
            .pausedUntilTomorrow(from: date, timeZone: timeZone)
        case .indefinitely:
            .pausedIndefinitely
        }
    }
}

public struct SchedulePolicy: Codable, Equatable, Sendable {
    public let timeZoneIdentifier: String
    public let workWindows: [WeeklyWorkWindow]
    public let quietHours: DailyTimeWindow
    public let nightlyPlanningTime: LocalTime
    public let morningConfirmationTime: LocalTime
    public let planningCapacityPercent: Int
    public let defaultCoachingPauseDuration: CoachingPauseDuration?

    public var effectiveDefaultCoachingPauseDuration: CoachingPauseDuration {
        defaultCoachingPauseDuration ?? .indefinitely
    }

    public init(
        timeZoneIdentifier: String,
        workWindows: [WeeklyWorkWindow],
        quietHours: DailyTimeWindow,
        nightlyPlanningTime: LocalTime,
        morningConfirmationTime: LocalTime,
        planningCapacityPercent: Int,
        defaultCoachingPauseDuration: CoachingPauseDuration? = .indefinitely
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.workWindows = workWindows
        self.quietHours = quietHours
        self.nightlyPlanningTime = nightlyPlanningTime
        self.morningConfirmationTime = morningConfirmationTime
        self.planningCapacityPercent = planningCapacityPercent
        self.defaultCoachingPauseDuration = defaultCoachingPauseDuration
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
    case codexCLI
    case appleOnDevice
    case remoteOpenAI

    public var usesRemoteProcessing: Bool {
        self == .codexCLI || self == .remoteOpenAI
    }
}

public enum RemoteEvidencePolicy: String, Codable, CaseIterable, Sendable {
    case localOnly
    case redactedMetadataOnly
    case explicitPrivateContent
}

public enum CodexCLIModel: String, Codable, CaseIterable, Sendable {
    case gpt56Terra = "gpt-5.6-terra"
    case gpt55 = "gpt-5.5"
    case custom

    public var settingsLabel: String {
        switch self {
        case .gpt56Terra: "GPT-5.6 Terra (preview)"
        case .gpt55: "GPT-5.5"
        case .custom: "Custom model ID"
        }
    }
}

public enum CodexCLIReasoningEffort: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case xhigh

    public var settingsLabel: String { rawValue.uppercased() }
}

public struct PrivacyPolicy: Codable, Equatable, Sendable {
    public let screenshotAnalysisEnabled: Bool
    public let notificationPromptsEnabled: Bool?
    public let aiProvider: AIProviderSelection
    public let remoteEvidencePolicy: RemoteEvidencePolicy
    public let rawScreenshotRetentionDays: Int
    public let extractedTextRetentionDays: Int
    public let diagnosticRetentionDays: Int
    public let behaviorRecordRetentionDays: Int?
    public let taskSessionRetentionDays: Int?
    public let promptRetentionDays: Int?
    public let reviewRetentionDays: Int?
    public let codexCLIModel: CodexCLIModel?
    public let codexCLICustomModelID: String?
    public let codexCLIReasoningEffort: CodexCLIReasoningEffort?

    public var effectiveCodexCLIModel: CodexCLIModel { codexCLIModel ?? .gpt56Terra }
    public var effectiveNotificationPromptsEnabled: Bool { notificationPromptsEnabled ?? true }
    public var effectiveCodexCLIModelID: String {
        let customModelID = codexCLICustomModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if effectiveCodexCLIModel == .custom, !customModelID.isEmpty {
            return customModelID
        }
        return effectiveCodexCLIModel.rawValue
    }
    public var effectiveCodexCLIReasoningEffort: CodexCLIReasoningEffort { codexCLIReasoningEffort ?? .low }
    public var effectiveBehaviorRecordRetentionDays: Int { behaviorRecordRetentionDays ?? 90 }
    public var effectiveTaskSessionRetentionDays: Int { taskSessionRetentionDays ?? 365 }
    public var effectivePromptRetentionDays: Int { promptRetentionDays ?? 90 }
    public var effectiveReviewRetentionDays: Int { reviewRetentionDays ?? 365 }

    public init(
        screenshotAnalysisEnabled: Bool,
        notificationPromptsEnabled: Bool? = true,
        aiProvider: AIProviderSelection,
        remoteEvidencePolicy: RemoteEvidencePolicy,
        rawScreenshotRetentionDays: Int,
        extractedTextRetentionDays: Int,
        diagnosticRetentionDays: Int,
        behaviorRecordRetentionDays: Int? = 90,
        taskSessionRetentionDays: Int? = 365,
        promptRetentionDays: Int? = 90,
        reviewRetentionDays: Int? = 365,
        codexCLIModel: CodexCLIModel? = .gpt56Terra,
        codexCLICustomModelID: String? = nil,
        codexCLIReasoningEffort: CodexCLIReasoningEffort? = .low
    ) {
        self.screenshotAnalysisEnabled = screenshotAnalysisEnabled
        self.notificationPromptsEnabled = notificationPromptsEnabled
        self.aiProvider = aiProvider
        self.remoteEvidencePolicy = remoteEvidencePolicy
        self.rawScreenshotRetentionDays = rawScreenshotRetentionDays
        self.extractedTextRetentionDays = extractedTextRetentionDays
        self.diagnosticRetentionDays = diagnosticRetentionDays
        self.behaviorRecordRetentionDays = behaviorRecordRetentionDays
        self.taskSessionRetentionDays = taskSessionRetentionDays
        self.promptRetentionDays = promptRetentionDays
        self.reviewRetentionDays = reviewRetentionDays
        self.codexCLIModel = codexCLIModel
        self.codexCLICustomModelID = codexCLICustomModelID
        self.codexCLIReasoningEffort = codexCLIReasoningEffort
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

public enum AppClassificationChoice: String, Codable, CaseIterable, Sendable {
    case automatic
    case work
    case gaming
}

public enum ApplicationRuleCategory: String, Codable, CaseIterable, Sendable {
    case automatic
    case work
    case communication
    case gaming
}

public struct BehaviorPolicy: Codable, Equatable, Sendable {
    public let workApplications: [String]
    public let gamingApplications: [String]
    public let communicationApplications: [String]

    public init(
        workApplications: [String] = [],
        gamingApplications: [String] = [],
        communicationApplications: [String] = []
    ) {
        self.workApplications = workApplications.map(Self.normalize).sorted()
        self.gamingApplications = gamingApplications.map(Self.normalize).sorted()
        self.communicationApplications = communicationApplications.map(Self.normalize).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case workApplications
        case gamingApplications
        case communicationApplications
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            workApplications: try container.decodeIfPresent([String].self, forKey: .workApplications) ?? [],
            gamingApplications: try container.decodeIfPresent([String].self, forKey: .gamingApplications) ?? [],
            communicationApplications: try container.decodeIfPresent([String].self, forKey: .communicationApplications) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workApplications, forKey: .workApplications)
        try container.encode(gamingApplications, forKey: .gamingApplications)
        if !communicationApplications.isEmpty {
            try container.encode(communicationApplications, forKey: .communicationApplications)
        }
    }

    public func classificationOverride(for application: String) -> BehaviorClassification? {
        let normalized = Self.normalize(application)
        if workApplications.contains(normalized) { return .work }
        if gamingApplications.contains(normalized) { return .gaming }
        if communicationApplications.contains(normalized) { return .work }
        return nil
    }

    public func ruleCategory(for application: String) -> ApplicationRuleCategory {
        let normalized = Self.normalize(application)
        if workApplications.contains(normalized) { return .work }
        if communicationApplications.contains(normalized) { return .communication }
        if gamingApplications.contains(normalized) { return .gaming }
        return .automatic
    }

    public func choice(for application: String) -> AppClassificationChoice {
        switch classificationOverride(for: application) {
        case .work: .work
        case .gaming: .gaming
        default: .automatic
        }
    }

    public static func normalize(_ application: String) -> String {
        application.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum CaptureMode: String, Codable, CaseIterable, Sendable {
    case legacy
    case parity
    case native
}

public struct CapturePolicy: Codable, Equatable, Sendable {
    public let mode: CaptureMode
    public let configuredDisplayIDs: [UInt32]

    public init(mode: CaptureMode = .legacy, configuredDisplayIDs: [UInt32] = []) {
        self.mode = mode
        self.configuredDisplayIDs = Array(Set(configuredDisplayIDs)).sorted()
    }

    public static let legacy = CapturePolicy()
}

public struct ReminderListDecision: Codable, Equatable, Sendable {
    public let listID: String
    public let isIncluded: Bool

    public init(listID: String, isIncluded: Bool) {
        self.listID = listID
        self.isIncluded = isIncluded
    }
}

public struct ReminderListPolicy: Codable, Equatable, Sendable {
    public let isConfigured: Bool
    public let decisions: [ReminderListDecision]

    public init(
        isConfigured: Bool = false,
        decisions: [ReminderListDecision] = []
    ) {
        self.isConfigured = isConfigured
        self.decisions = decisions.sorted {
            if $0.listID == $1.listID { return !$0.isIncluded && $1.isIncluded }
            return $0.listID < $1.listID
        }
    }

    public static let legacyAllLists = ReminderListPolicy()

    public func decision(for listID: String) -> Bool? {
        decisions.first(where: { $0.listID == listID })?.isIncluded
    }

    public func includes(listID: String) -> Bool {
        guard isConfigured else { return true }
        return decision(for: listID) ?? false
    }

    public func includes(listID: String?) -> Bool {
        guard let listID else { return !isConfigured }
        return includes(listID: listID)
    }

    public func filteringExternalTasks<Task>(
        _ tasks: [Task],
        listID: (Task) -> String?
    ) -> [Task] {
        tasks.filter { includes(listID: listID($0)) }
    }
}

public struct UserPolicy: Codable, Equatable, Sendable {
    public static let schemaVersion = 5

    public let schemaVersion: Int
    public let operatingMode: OperatingMode
    public let automationPause: AutomationPause
    public let schedule: SchedulePolicy
    public let calendar: CalendarSelectionPolicy
    public let privacy: PrivacyPolicy
    public let wake: WakePolicyConfiguration
    public let behavior: BehaviorPolicy
    public let capture: CapturePolicy
    public let gaming: GamingPolicy
    public let reminderLists: ReminderListPolicy

    public init(
        schemaVersion: Int = UserPolicy.schemaVersion,
        operatingMode: OperatingMode,
        automationPause: AutomationPause,
        schedule: SchedulePolicy,
        calendar: CalendarSelectionPolicy,
        privacy: PrivacyPolicy,
        wake: WakePolicyConfiguration,
        behavior: BehaviorPolicy = BehaviorPolicy(),
        capture: CapturePolicy = .legacy,
        gaming: GamingPolicy = .balanced,
        reminderLists: ReminderListPolicy = .legacyAllLists
    ) {
        self.schemaVersion = schemaVersion
        self.operatingMode = operatingMode
        self.automationPause = automationPause
        self.schedule = schedule
        self.calendar = calendar
        self.privacy = privacy
        self.wake = wake
        self.behavior = behavior
        self.capture = capture
        self.gaming = gaming
        self.reminderLists = reminderLists
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case operatingMode
        case automationPause
        case schedule
        case calendar
        case privacy
        case wake
        case behavior
        case capture
        case gaming
        case reminderLists
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        operatingMode = try container.decode(OperatingMode.self, forKey: .operatingMode)
        automationPause = try container.decode(AutomationPause.self, forKey: .automationPause)
        schedule = try container.decode(SchedulePolicy.self, forKey: .schedule)
        calendar = try container.decode(CalendarSelectionPolicy.self, forKey: .calendar)
        privacy = try container.decode(PrivacyPolicy.self, forKey: .privacy)
        wake = try container.decode(WakePolicyConfiguration.self, forKey: .wake)
        behavior = try container.decodeIfPresent(BehaviorPolicy.self, forKey: .behavior) ?? BehaviorPolicy()
        capture = try container.decodeIfPresent(CapturePolicy.self, forKey: .capture) ?? .legacy
        gaming = try container.decodeIfPresent(GamingPolicy.self, forKey: .gaming) ?? .balanced
        reminderLists = try container.decodeIfPresent(
            ReminderListPolicy.self,
            forKey: .reminderLists
        ) ?? .legacyAllLists
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(operatingMode, forKey: .operatingMode)
        try container.encode(automationPause, forKey: .automationPause)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(calendar, forKey: .calendar)
        try container.encode(privacy, forKey: .privacy)
        try container.encode(wake, forKey: .wake)
        try container.encode(behavior, forKey: .behavior)
        try container.encode(capture, forKey: .capture)
        try container.encode(gaming, forKey: .gaming)
        if schemaVersion >= 5 {
            try container.encode(reminderLists, forKey: .reminderLists)
        }
    }

    public func upgradedToCurrentSchema() -> UserPolicy {
        UserPolicy(
            operatingMode: operatingMode,
            automationPause: automationPause,
            schedule: schedule,
            calendar: calendar,
            privacy: privacy,
            wake: wake,
            behavior: behavior,
            capture: capture,
            gaming: gaming,
            reminderLists: reminderLists
        )
    }

    public func canonicalizedForPolicyMutationDigest() -> UserPolicy {
        guard schemaVersion <= 4 else { return self }
        return UserPolicy(
            schemaVersion: 4,
            operatingMode: operatingMode,
            automationPause: automationPause,
            schedule: schedule,
            calendar: calendar,
            privacy: privacy,
            wake: wake,
            behavior: behavior,
            capture: capture,
            gaming: gaming,
            reminderLists: .legacyAllLists
        )
    }

    public func replacingAutomationPause(_ automationPause: AutomationPause) -> UserPolicy {
        UserPolicy(
            operatingMode: operatingMode,
            automationPause: automationPause,
            schedule: schedule,
            calendar: calendar,
            privacy: privacy,
            wake: wake,
            behavior: behavior,
            capture: capture,
            gaming: gaming,
            reminderLists: reminderLists
        )
    }

    public func replacingGamingPolicy(_ gaming: GamingPolicy) -> UserPolicy {
        UserPolicy(
            operatingMode: operatingMode,
            automationPause: automationPause,
            schedule: schedule,
            calendar: calendar,
            privacy: privacy,
            wake: wake,
            behavior: behavior,
            capture: capture,
            gaming: gaming,
            reminderLists: reminderLists
        )
    }

    public func replacingReminderListPolicy(_ reminderLists: ReminderListPolicy) -> UserPolicy {
        UserPolicy(
            operatingMode: operatingMode,
            automationPause: automationPause,
            schedule: schedule,
            calendar: calendar,
            privacy: privacy,
            wake: wake,
            behavior: behavior,
            capture: capture,
            gaming: gaming,
            reminderLists: reminderLists
        )
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
            ),
            gaming: .balanced
        )
    }

    public func validationViolations() -> [PolicyViolation] {
        var violations: [PolicyViolation] = []
        if schemaVersion != Self.schemaVersion {
            violations.append(.init(code: .unsupportedSchemaVersion, field: "schemaVersion"))
        }
        if automationPause.isRequested == false, automationPause.resumesAtUTC != nil {
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
        appendRetentionViolation(privacy.effectiveBehaviorRecordRetentionDays, field: "privacy.behaviorRecordRetentionDays", to: &violations)
        appendRetentionViolation(privacy.effectiveTaskSessionRetentionDays, field: "privacy.taskSessionRetentionDays", to: &violations)
        appendRetentionViolation(privacy.effectivePromptRetentionDays, field: "privacy.promptRetentionDays", to: &violations)
        appendRetentionViolation(privacy.effectiveReviewRetentionDays, field: "privacy.reviewRetentionDays", to: &violations)
        if !privacy.aiProvider.usesRemoteProcessing, privacy.remoteEvidencePolicy != .localOnly {
            violations.append(.init(code: .remotePolicyWithoutRemoteProvider, field: "privacy.remoteEvidencePolicy"))
        }
        appendApplicationClassificationViolations(to: &violations)
        let reminderListIDs = reminderLists.decisions.map(\.listID)
        if reminderListIDs.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            violations.append(.init(
                code: .emptyReminderListIdentifier,
                field: "reminderLists.decisions"
            ))
        }
        if Set(reminderListIDs).count != reminderListIDs.count {
            violations.append(.init(
                code: .duplicateReminderListIdentifier,
                field: "reminderLists.decisions"
            ))
        }
        if gaming.version != 1 {
            violations.append(.init(code: .unsupportedGamingPolicyVersion, field: "gaming.version"))
        }
        if !(0...1_440).contains(gaming.dailyBudgetMinutes) {
            violations.append(.init(code: .invalidGamingBudget, field: "gaming.dailyBudgetMinutes"))
        }
        if !(0...1_440).contains(gaming.priorityTaskRewardMinutes) {
            violations.append(.init(
                code: .invalidGamingReward,
                field: "gaming.priorityTaskRewardMinutes"
            ))
        }
        if !(5...1_440).contains(gaming.intentionalOverrideMinutes) {
            violations.append(.init(code: .invalidGamingBudget, field: "gaming.intentionalOverrideMinutes"))
        }
        if !(1...10).contains(gaming.dailyPromptCap) {
            violations.append(.init(code: .invalidGamingBudget, field: "gaming.dailyPromptCap"))
        }
        if !(5...1_440).contains(gaming.promptCooldownMinutes) {
            violations.append(.init(code: .invalidGamingBudget, field: "gaming.promptCooldownMinutes"))
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

    private func appendApplicationClassificationViolations(to violations: inout [PolicyViolation]) {
        for (field, applications) in [
            ("behavior.workApplications", behavior.workApplications),
            ("behavior.gamingApplications", behavior.gamingApplications),
            ("behavior.communicationApplications", behavior.communicationApplications)
        ] {
            if applications.contains(where: \ .isEmpty) {
                violations.append(.init(code: .emptyApplicationClassification, field: field))
            }
            if Set(applications).count != applications.count {
                violations.append(.init(code: .duplicateApplicationClassification, field: field))
            }
        }
        let work = Set(behavior.workApplications)
        let gaming = Set(behavior.gamingApplications)
        let communication = Set(behavior.communicationApplications)
        if !work.isDisjoint(with: gaming)
            || !work.isDisjoint(with: communication)
            || !gaming.isDisjoint(with: communication) {
            violations.append(.init(code: .applicationClassificationConflict, field: "behavior"))
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
        case emptyApplicationClassification
        case duplicateApplicationClassification
        case applicationClassificationConflict
        case unsupportedGamingPolicyVersion
        case invalidGamingBudget
        case invalidGamingReward
        case invalidWakeBudget
        case emptyReminderListIdentifier
        case duplicateReminderListIdentifier
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
