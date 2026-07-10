import Foundation

public enum VoiceSessionState: String, Codable, CaseIterable, Sendable {
    case idle
    case activating
    case listening
    case thinking
    case speaking
    case localFallback = "local_fallback"
    case disconnected
}

public enum VoiceActivationSource: String, Codable, Sendable {
    case wakeWord = "wake_word"
    case globalHotkey = "global_hotkey"
    case menuBar = "menu_bar"
    case text
}

public struct VoiceSession: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let activationSource: VoiceActivationSource
    public let state: VoiceSessionState
    public let provider: String
    public let model: String
    public let startedAt: Date
    public let endedAt: Date?

    public init(
        id: String,
        activationSource: VoiceActivationSource,
        state: VoiceSessionState,
        provider: String,
        model: String,
        startedAt: Date,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.activationSource = activationSource
        self.state = state
        self.provider = provider
        self.model = model
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum ConversationRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct ConversationTurn: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let sessionID: String
    public let role: ConversationRole
    public let text: String
    public let isFinal: Bool
    public let createdAt: Date

    public init(id: String, sessionID: String, role: ConversationRole, text: String, isFinal: Bool, createdAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.text = text
        self.isFinal = isFinal
        self.createdAt = createdAt
    }
}

public enum ConversationMemoryKind: String, Codable, CaseIterable, Sendable {
    case goal
    case preference
    case commitment
    case correction
    case summary
}

public struct ConversationMemoryFact: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let kind: ConversationMemoryKind
    public let value: String
    public let sourceTurnID: String?
    public let isConfirmed: Bool
    public let expiresAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        kind: ConversationMemoryKind,
        value: String,
        sourceTurnID: String?,
        isConfirmed: Bool,
        expiresAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.sourceTurnID = sourceTurnID
        self.isConfirmed = isConfirmed
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func canAuthorizeAction(at date: Date) -> Bool {
        isConfirmed && (expiresAt.map { $0 > date } ?? true)
    }
}

public enum ToolRiskLevel: String, Codable, CaseIterable, Sendable {
    case readOnly = "read_only"
    case reversibleLocal = "reversible_local"
    case externalOrIrreversible = "external_or_irreversible"
    case forbidden
}

public struct VoiceToolDefinition: Equatable, Codable, Sendable {
    public let name: String
    public let description: String
    public let riskLevel: ToolRiskLevel
    public let requiresExplicitUserIntent: Bool
    public let parametersJSONSchema: String?

    public init(name: String, description: String, riskLevel: ToolRiskLevel, requiresExplicitUserIntent: Bool, parametersJSONSchema: String? = nil) {
        self.name = name
        self.description = description
        self.riskLevel = riskLevel
        self.requiresExplicitUserIntent = requiresExplicitUserIntent
        self.parametersJSONSchema = parametersJSONSchema
    }
}

public struct VoiceToolInvocation: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let sessionID: String
    public let toolName: String
    public let argumentsJSON: String
    public let originTurnID: String?
    public let originUserText: String?
    public let hasExplicitUserIntent: Bool
    public let requestedAt: Date

    public init(
        id: String,
        sessionID: String,
        toolName: String,
        argumentsJSON: String,
        originTurnID: String?,
        originUserText: String? = nil,
        hasExplicitUserIntent: Bool,
        requestedAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.originTurnID = originTurnID
        self.originUserText = originUserText
        self.hasExplicitUserIntent = hasExplicitUserIntent
        self.requestedAt = requestedAt
    }
}

public enum VoiceToolDecision: String, Codable, Sendable {
    case allow
    case requireApproval = "require_approval"
    case deny
}

public enum VoiceActionPolicy {
    public static func decision(for tool: VoiceToolDefinition, hasExplicitUserIntent: Bool) -> VoiceToolDecision {
        if tool.requiresExplicitUserIntent && !hasExplicitUserIntent { return .deny }
        switch tool.riskLevel {
        case .readOnly, .reversibleLocal: return .allow
        case .externalOrIrreversible: return .requireApproval
        case .forbidden: return .deny
        }
    }
}

public enum ApprovalState: String, Codable, Sendable {
    case pending
    case approved
    case denied
    case expired
}

public struct ApprovalRequest: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let invocationID: String
    public let reason: String
    public let state: ApprovalState
    public let createdAt: Date
    public let expiresAt: Date
    public let resolvedAt: Date?

    public init(
        id: String,
        invocationID: String,
        reason: String,
        state: ApprovalState,
        createdAt: Date,
        expiresAt: Date,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.invocationID = invocationID
        self.reason = reason
        self.state = state
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.resolvedAt = resolvedAt
    }
}

public enum VoiceToolExecutionStatus: String, Codable, Sendable {
    case executed
    case approvalRequired = "approval_required"
    case denied
    case failed
}

public struct VoiceToolExecutionResult: Equatable, Codable, Sendable {
    public let invocationID: String
    public let status: VoiceToolExecutionStatus
    public let message: String
    public let resultJSON: String?
    public let approval: ApprovalRequest?

    public init(
        invocationID: String,
        status: VoiceToolExecutionStatus,
        message: String,
        resultJSON: String? = nil,
        approval: ApprovalRequest? = nil
    ) {
        self.invocationID = invocationID
        self.status = status
        self.message = message
        self.resultJSON = resultJSON
        self.approval = approval
    }
}

public struct VoiceUsageSample: Equatable, Codable, Sendable {
    public let inputAudioSeconds: Int
    public let outputAudioSeconds: Int
    public let providerReportedUSDMicros: Int?

    public init(inputAudioSeconds: Int, outputAudioSeconds: Int, providerReportedUSDMicros: Int? = nil) {
        self.inputAudioSeconds = max(0, inputAudioSeconds)
        self.outputAudioSeconds = max(0, outputAudioSeconds)
        self.providerReportedUSDMicros = providerReportedUSDMicros
    }

    public var estimatedUSDMicros: Int {
        let input = Self.roundedUpCost(seconds: inputAudioSeconds, microsPerMinute: 5_000)
        let output = Self.roundedUpCost(seconds: outputAudioSeconds, microsPerMinute: 18_000)
        return max(input + output, providerReportedUSDMicros ?? 0)
    }

    private static func roundedUpCost(seconds: Int, microsPerMinute: Int) -> Int {
        guard seconds > 0 else { return 0 }
        return (seconds * microsPerMinute + 59) / 60
    }
}

public enum VoiceBudgetStatus: String, Codable, Sendable {
    case withinBudget = "within_budget"
    case warningSeventyPercent = "warning_seventy_percent"
    case warningNinetyPercent = "warning_ninety_percent"
    case capReached = "cap_reached"
}

public struct VoiceUsageLedger: Equatable, Codable, Sendable {
    public static let hardMonthlyLimitUSDMicros = 20_000_000
    public static let firstWarningUSDMicros = 14_000_000
    public static let secondWarningUSDMicros = 18_000_000

    public let periodStart: Date
    public let consumedUSDMicros: Int
    public let inputAudioSeconds: Int
    public let outputAudioSeconds: Int
    /// Conservative in-flight reservations. A process crash deliberately leaves the
    /// reservation charged, so restarting the app cannot bypass the monthly cap.
    public let reservationsUSDMicros: [String: Int]?

    public init(
        periodStart: Date,
        consumedUSDMicros: Int = 0,
        inputAudioSeconds: Int = 0,
        outputAudioSeconds: Int = 0,
        reservationsUSDMicros: [String: Int]? = nil
    ) {
        self.periodStart = periodStart
        self.consumedUSDMicros = min(max(0, consumedUSDMicros), Self.hardMonthlyLimitUSDMicros)
        self.inputAudioSeconds = max(0, inputAudioSeconds)
        self.outputAudioSeconds = max(0, outputAudioSeconds)
        self.reservationsUSDMicros = reservationsUSDMicros
    }

    public var committedUSDMicros: Int {
        min(Self.hardMonthlyLimitUSDMicros, consumedUSDMicros + (reservationsUSDMicros ?? [:]).values.reduce(0, +))
    }

    public var status: VoiceBudgetStatus {
        if committedUSDMicros >= Self.hardMonthlyLimitUSDMicros { return .capReached }
        if committedUSDMicros >= Self.secondWarningUSDMicros { return .warningNinetyPercent }
        if committedUSDMicros >= Self.firstWarningUSDMicros { return .warningSeventyPercent }
        return .withinBudget
    }

    public var canStartCloudSession: Bool { status != .capReached }

    public func recording(
        _ sample: VoiceUsageSample,
        at date: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> VoiceUsageLedger {
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let monthStart = localCalendar.dateInterval(of: .month, for: date)?.start ?? date
        let isSamePeriod = localCalendar.isDate(periodStart, equalTo: monthStart, toGranularity: .month)
        let baseCost = isSamePeriod ? consumedUSDMicros : 0
        let baseInput = isSamePeriod ? inputAudioSeconds : 0
        let baseOutput = isSamePeriod ? outputAudioSeconds : 0
        return VoiceUsageLedger(
            periodStart: monthStart,
            consumedUSDMicros: min(Self.hardMonthlyLimitUSDMicros, baseCost + sample.estimatedUSDMicros),
            inputAudioSeconds: baseInput + sample.inputAudioSeconds,
            outputAudioSeconds: baseOutput + sample.outputAudioSeconds,
            reservationsUSDMicros: isSamePeriod ? reservationsUSDMicros : nil
        )
    }

    public func reserving(id: String, maximumUSDMicros: Int) -> VoiceUsageLedger? {
        guard reservationsUSDMicros?[id] == nil else { return self }
        let available = Self.hardMonthlyLimitUSDMicros - committedUSDMicros
        guard available > 0 else { return nil }
        var reservations = reservationsUSDMicros ?? [:]
        reservations[id] = min(maximumUSDMicros, available)
        return VoiceUsageLedger(
            periodStart: periodStart,
            consumedUSDMicros: consumedUSDMicros,
            inputAudioSeconds: inputAudioSeconds,
            outputAudioSeconds: outputAudioSeconds,
            reservationsUSDMicros: reservations
        )
    }

    public func settling(reservationID: String, sample: VoiceUsageSample) -> VoiceUsageLedger {
        var reservations = reservationsUSDMicros ?? [:]
        guard reservations.removeValue(forKey: reservationID) != nil else { return self }
        return VoiceUsageLedger(
            periodStart: periodStart,
            consumedUSDMicros: consumedUSDMicros + sample.estimatedUSDMicros,
            inputAudioSeconds: inputAudioSeconds + sample.inputAudioSeconds,
            outputAudioSeconds: outputAudioSeconds + sample.outputAudioSeconds,
            reservationsUSDMicros: reservations.isEmpty ? nil : reservations
        )
    }
}

public struct VoiceBudgetReservation: Equatable, Codable, Sendable {
    public let id: String
    public let ledger: VoiceUsageLedger

    public init(id: String, ledger: VoiceUsageLedger) {
        self.id = id
        self.ledger = ledger
    }
}

public struct ScreenContextSelection: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let artifactIDs: [String]
    public let paths: [String]
    public let contentHashes: [String]
    public let reason: String
    public let selectedAt: Date
    public let mayTransmitPrivateContent: Bool

    public init(
        id: String,
        artifactIDs: [String],
        paths: [String],
        contentHashes: [String],
        reason: String,
        selectedAt: Date,
        mayTransmitPrivateContent: Bool
    ) {
        self.id = id
        self.artifactIDs = artifactIDs
        self.paths = paths
        self.contentHashes = contentHashes
        self.reason = reason
        self.selectedAt = selectedAt
        self.mayTransmitPrivateContent = mayTransmitPrivateContent
    }
}

public enum CodexJobState: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

public enum CodexJobSandbox: String, Codable, Sendable {
    case readOnly = "read_only"
    case workspaceWrite = "workspace_write"
}

public struct CodexJob: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let workspacePath: String
    public let objective: String
    public let sandbox: CodexJobSandbox
    public let state: CodexJobState
    public let createdAt: Date
    public let startedAt: Date?
    public let finishedAt: Date?
    public let resultSummary: String?
    public let redactedError: String?

    public init(
        id: String,
        workspacePath: String,
        objective: String,
        sandbox: CodexJobSandbox,
        state: CodexJobState,
        createdAt: Date,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        resultSummary: String? = nil,
        redactedError: String? = nil
    ) {
        self.id = id
        self.workspacePath = workspacePath
        self.objective = objective
        self.sandbox = sandbox
        self.state = state
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.resultSummary = resultSummary
        self.redactedError = redactedError
    }
}

public struct ChiefOfStaffContextPacket: Equatable, Codable, Sendable {
    public let generatedAt: Date
    public let snapshot: TodaySnapshot
    public let memories: [ConversationMemoryFact]
    public let activeCodexJobs: [CodexJob]
    public let upcomingCommitments: [CalendarCommitment]
    public let operatingMode: OperatingMode
    public let automationIsPaused: Bool
    public let schedule: SchedulePolicy

    public init(
        generatedAt: Date,
        snapshot: TodaySnapshot,
        memories: [ConversationMemoryFact],
        activeCodexJobs: [CodexJob],
        upcomingCommitments: [CalendarCommitment],
        operatingMode: OperatingMode,
        automationIsPaused: Bool,
        schedule: SchedulePolicy
    ) {
        self.generatedAt = generatedAt
        self.snapshot = snapshot
        self.memories = memories
        self.activeCodexJobs = activeCodexJobs
        self.upcomingCommitments = upcomingCommitments
        self.operatingMode = operatingMode
        self.automationIsPaused = automationIsPaused
        self.schedule = schedule
    }
}
