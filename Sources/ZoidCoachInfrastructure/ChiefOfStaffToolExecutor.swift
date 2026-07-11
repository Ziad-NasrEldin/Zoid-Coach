import Foundation
import ZoidCoachCore

public struct ChiefOfStaffToolDependencies: Sendable {
    public let snapshot: @Sendable () async throws -> TodaySnapshot
    public let applyTask: @Sendable (TaskActivityCommand, String) async throws -> TodaySnapshot
    public let openApplication: @Sendable (String, String?) async throws -> Bool
    public let searchWeb: @Sendable (String) async throws -> Bool
    public let findFiles: @Sendable (String, Int) async throws -> [String]
    public let openFile: @Sendable (String) async throws -> Bool
    public let createReminder: @Sendable (String, Date?, String?) async throws -> SourceTask
    public let completeReminder: @Sendable (String) async throws -> SourceTask
    public let createFocusBlock: @Sendable (String, Date, Date) async throws -> CalendarCommitment?
    public let createCalendarCommitment: @Sendable (String, Date, Date) async throws -> CalendarCommitment?
    public let setAutomationPaused: @Sendable (Bool) async throws -> UserPolicy
    public let startCodexJob: @Sendable (String, String, CodexJobSandbox) async throws -> CodexJob
    public let codexJob: @Sendable (String) async throws -> CodexJob?
    public let cancelCodexJob: @Sendable (String) async throws -> CodexJob
    public let saveMemory: @Sendable (ConversationMemoryFact) async throws -> Void
    public let deleteMemory: @Sendable (String) async throws -> Void
    public let loadMemory: @Sendable (String) async throws -> ConversationMemoryFact?
    public let activeMemories: @Sendable () async throws -> [ConversationMemoryFact]
    public let deleteTranscripts: @Sendable () async throws -> Void
    public let selectScreenContext: @Sendable (String, Int) async throws -> ScreenContextSelection

    public init(
        snapshot: @escaping @Sendable () async throws -> TodaySnapshot,
        applyTask: @escaping @Sendable (TaskActivityCommand, String) async throws -> TodaySnapshot,
        openApplication: @escaping @Sendable (String, String?) async throws -> Bool,
        searchWeb: @escaping @Sendable (String) async throws -> Bool,
        findFiles: @escaping @Sendable (String, Int) async throws -> [String],
        openFile: @escaping @Sendable (String) async throws -> Bool,
        createReminder: @escaping @Sendable (String, Date?, String?) async throws -> SourceTask,
        completeReminder: @escaping @Sendable (String) async throws -> SourceTask,
        createFocusBlock: @escaping @Sendable (String, Date, Date) async throws -> CalendarCommitment?,
        createCalendarCommitment: @escaping @Sendable (String, Date, Date) async throws -> CalendarCommitment?,
        setAutomationPaused: @escaping @Sendable (Bool) async throws -> UserPolicy,
        startCodexJob: @escaping @Sendable (String, String, CodexJobSandbox) async throws -> CodexJob,
        codexJob: @escaping @Sendable (String) async throws -> CodexJob?,
        cancelCodexJob: @escaping @Sendable (String) async throws -> CodexJob,
        saveMemory: @escaping @Sendable (ConversationMemoryFact) async throws -> Void,
        deleteMemory: @escaping @Sendable (String) async throws -> Void,
        loadMemory: @escaping @Sendable (String) async throws -> ConversationMemoryFact?,
        activeMemories: @escaping @Sendable () async throws -> [ConversationMemoryFact],
        deleteTranscripts: @escaping @Sendable () async throws -> Void,
        selectScreenContext: @escaping @Sendable (String, Int) async throws -> ScreenContextSelection
    ) {
        self.snapshot = snapshot
        self.applyTask = applyTask
        self.openApplication = openApplication
        self.searchWeb = searchWeb
        self.findFiles = findFiles
        self.openFile = openFile
        self.createReminder = createReminder
        self.completeReminder = completeReminder
        self.createFocusBlock = createFocusBlock
        self.createCalendarCommitment = createCalendarCommitment
        self.setAutomationPaused = setAutomationPaused
        self.startCodexJob = startCodexJob
        self.codexJob = codexJob
        self.cancelCodexJob = cancelCodexJob
        self.saveMemory = saveMemory
        self.deleteMemory = deleteMemory
        self.loadMemory = loadMemory
        self.activeMemories = activeMemories
        self.deleteTranscripts = deleteTranscripts
        self.selectScreenContext = selectScreenContext
    }
}

public struct ChiefOfStaffToolExecutor: VoiceToolActionExecuting, Sendable {
    private let dependencies: ChiefOfStaffToolDependencies
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String

    public init(
        dependencies: ChiefOfStaffToolDependencies,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.dependencies = dependencies
        self.now = now
        self.makeID = makeID
    }

    public func execute(toolName: String, argumentsJSON: String) async throws -> String {
        let data = Data(argumentsJSON.utf8)
        switch toolName {
        case "get_daily_brief":
            return try encode(try await dependencies.snapshot())
        case "set_active_task":
            let arguments = try decode(TaskArguments.self, data)
            guard let command = TaskActivityCommand(rawValue: arguments.command) else {
                throw ChiefOfStaffToolError.invalidArguments
            }
            return try encode(try await dependencies.applyTask(command, arguments.taskID))
        case "open_application":
            let arguments = try decode(ApplicationArguments.self, data)
            return try encode(OKResult(ok: try await dependencies.openApplication(arguments.name, arguments.bundleIdentifier)))
        case "search_web":
            let arguments = try decode(QueryArguments.self, data)
            return try encode(OKResult(ok: try await dependencies.searchWeb(arguments.query)))
        case "find_files":
            let arguments = try decode(FileSearchArguments.self, data)
            return try encode(PathsResult(paths: try await dependencies.findFiles(arguments.query, min(max(arguments.limit ?? 8, 1), 20))))
        case "open_file":
            let arguments = try decode(PathArguments.self, data)
            return try encode(OKResult(ok: try await dependencies.openFile(arguments.path)))
        case "create_reminder":
            let arguments = try decode(ReminderArguments.self, data)
            return try encode(try await dependencies.createReminder(arguments.title, arguments.dueDate, arguments.listIdentifier))
        case "complete_reminder":
            let arguments = try decode(ReminderIDArguments.self, data)
            return try encode(try await dependencies.completeReminder(arguments.reminderID))
        case "create_focus_block":
            let arguments = try decode(FocusBlockArguments.self, data)
            guard arguments.end > arguments.start else { throw ChiefOfStaffToolError.invalidArguments }
            return try encode(try await dependencies.createFocusBlock(arguments.title, arguments.start, arguments.end))
        case "create_calendar_commitment":
            let arguments = try decode(FocusBlockArguments.self, data)
            guard arguments.end > arguments.start else { throw ChiefOfStaffToolError.invalidArguments }
            return try encode(try await dependencies.createCalendarCommitment(arguments.title, arguments.start, arguments.end))
        case "pause_automation":
            return try encode(try await dependencies.setAutomationPaused(true))
        case "resume_automation":
            return try encode(try await dependencies.setAutomationPaused(false))
        case "start_codex_job":
            let arguments = try decode(CodexStartArguments.self, data)
            let sandbox = arguments.allowLocalEdits == true ? CodexJobSandbox.workspaceWrite : .readOnly
            return try encode(try await dependencies.startCodexJob(arguments.workspacePath, arguments.objective, sandbox))
        case "codex_job_status":
            let arguments = try decode(JobIDArguments.self, data)
            return try encode(try await dependencies.codexJob(arguments.jobID))
        case "cancel_codex_job":
            let arguments = try decode(JobIDArguments.self, data)
            return try encode(try await dependencies.cancelCodexJob(arguments.jobID))
        case "remember_fact":
            let arguments = try decode(MemoryArguments.self, data)
            guard let kind = ConversationMemoryKind(rawValue: arguments.kind) else {
                throw ChiefOfStaffToolError.invalidArguments
            }
            let date = now()
            let fact = ConversationMemoryFact(
                id: makeID(),
                kind: kind,
                value: arguments.value,
                sourceTurnID: arguments.sourceTurnID,
                isConfirmed: true,
                expiresAt: nil,
                createdAt: date,
                updatedAt: date
            )
            try await dependencies.saveMemory(fact)
            return try encode(fact)
        case "forget_memory":
            let arguments = try decode(MemoryIDArguments.self, data)
            try await dependencies.deleteMemory(arguments.memoryID)
            return try encode(OKResult(ok: true))
        case "correct_memory":
            let arguments = try decode(MemoryCorrectionArguments.self, data)
            guard let existing = try await dependencies.loadMemory(arguments.memoryID) else {
                throw ChiefOfStaffToolError.invalidArguments
            }
            let corrected = ConversationMemoryFact(
                id: existing.id,
                kind: .correction,
                value: arguments.value,
                sourceTurnID: existing.sourceTurnID,
                isConfirmed: true,
                expiresAt: nil,
                createdAt: existing.createdAt,
                updatedAt: now()
            )
            try await dependencies.saveMemory(corrected)
            return try encode(corrected)
        case "explain_memory":
            let arguments = try decode(MemoryIDArguments.self, data)
            return try encode(try await dependencies.loadMemory(arguments.memoryID))
        case "export_voice_memory":
            return try encode(try await dependencies.activeMemories())
        case "delete_transcripts":
            try await dependencies.deleteTranscripts()
            return try encode(OKResult(ok: true))
        case "select_screen_context":
            let arguments = try decode(ScreenContextArguments.self, data)
            return try encode(try await dependencies.selectScreenContext(arguments.reason, min(max(arguments.limit ?? 2, 1), 4)))
        default:
            throw ChiefOfStaffToolError.unsupportedTool
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(type, from: data) }
        catch { throw ChiefOfStaffToolError.invalidArguments }
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private struct OKResult: Codable { let ok: Bool }
    private struct PathsResult: Codable { let paths: [String] }
    private struct TaskArguments: Decodable { let taskID: String; let command: String }
    private struct ApplicationArguments: Decodable { let name: String; let bundleIdentifier: String? }
    private struct QueryArguments: Decodable { let query: String }
    private struct FileSearchArguments: Decodable { let query: String; let limit: Int? }
    private struct PathArguments: Decodable { let path: String }
    private struct ReminderArguments: Decodable { let title: String; let dueDate: Date?; let listIdentifier: String? }
    private struct ReminderIDArguments: Decodable { let reminderID: String }
    private struct FocusBlockArguments: Decodable { let title: String; let start: Date; let end: Date }
    private struct CodexStartArguments: Decodable { let workspacePath: String; let objective: String; let allowLocalEdits: Bool? }
    private struct JobIDArguments: Decodable { let jobID: String }
    private struct MemoryArguments: Decodable { let kind: String; let value: String; let sourceTurnID: String? }
    private struct MemoryIDArguments: Decodable { let memoryID: String }
    private struct MemoryCorrectionArguments: Decodable { let memoryID: String; let value: String }
    private struct ScreenContextArguments: Decodable { let reason: String; let limit: Int? }
}

public enum ChiefOfStaffToolError: LocalizedError {
    case invalidArguments
    case unsupportedTool

    public var errorDescription: String? {
        switch self {
        case .invalidArguments: "The voice command arguments are invalid."
        case .unsupportedTool: "The voice tool is not supported by the local executor."
        }
    }
}
