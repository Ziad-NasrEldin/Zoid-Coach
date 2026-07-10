import Foundation
import ZoidCoachCore

public protocol VoiceToolActionExecuting: Sendable {
    func execute(toolName: String, argumentsJSON: String) async throws -> String
}

public enum ChiefOfStaffToolRegistry {
    public static let definitions: [VoiceToolDefinition] = [
        .init(name: "get_daily_brief", description: "Read today's plan, next task, behavior, and source health.", riskLevel: .readOnly, requiresExplicitUserIntent: false),
        .init(name: "set_active_task", description: "Start, pause, resume, complete, block, or reschedule a task.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["taskID": .string, "command": .string], required: ["taskID", "command"])),
        .init(name: "open_application", description: "Open or focus an installed macOS application.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["name": .string, "bundleIdentifier": .string], required: ["name"])),
        .init(name: "search_web", description: "Open a web search in the default browser.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["query": .string], required: ["query"])),
        .init(name: "find_files", description: "Find local files using a bounded Spotlight query.", riskLevel: .readOnly, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["query": .string, "limit": .integer], required: ["query"])),
        .init(name: "open_file", description: "Open an existing local file in its default application.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["path": .string], required: ["path"])),
        .init(name: "create_reminder", description: "Create an Apple Reminder.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["title": .string, "dueDate": .dateTime, "listIdentifier": .string], required: ["title"])),
        .init(name: "complete_reminder", description: "Complete an existing Apple Reminder.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["reminderID": .string], required: ["reminderID"])),
        .init(name: "create_focus_block", description: "Reserve a Zoid-owned focus block in Calendar.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: calendarSchema),
        .init(name: "create_calendar_commitment", description: "Create an externally meaningful Calendar commitment.", riskLevel: .externalOrIrreversible, requiresExplicitUserIntent: true, parametersJSONSchema: calendarSchema),
        .init(name: "pause_automation", description: "Pause autonomous Zoid actions.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true),
        .init(name: "resume_automation", description: "Resume autonomous Zoid actions.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true),
        .init(name: "start_codex_job", description: "Start a scoped durable Codex job in a selected workspace.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["workspacePath": .string, "objective": .string, "allowLocalEdits": .boolean], required: ["workspacePath", "objective"])),
        .init(name: "codex_job_status", description: "Read the state of a durable Codex job.", riskLevel: .readOnly, requiresExplicitUserIntent: false, parametersJSONSchema: schema(["jobID": .string], required: ["jobID"])),
        .init(name: "cancel_codex_job", description: "Cancel a running Codex job.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["jobID": .string], required: ["jobID"])),
        .init(name: "remember_fact", description: "Save a confirmed goal, preference, commitment, or correction.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["kind": .string, "value": .string, "sourceTurnID": .string], required: ["kind", "value"])),
        .init(name: "forget_memory", description: "Delete one Zoid conversation memory fact.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["memoryID": .string], required: ["memoryID"])),
        .init(name: "correct_memory", description: "Correct an existing confirmed memory fact.", riskLevel: .reversibleLocal, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["memoryID": .string, "value": .string], required: ["memoryID", "value"])),
        .init(name: "explain_memory", description: "Explain the source and status of a recalled memory.", riskLevel: .readOnly, requiresExplicitUserIntent: false, parametersJSONSchema: schema(["memoryID": .string], required: ["memoryID"])),
        .init(name: "export_voice_memory", description: "Export confirmed Zoid memories as structured JSON.", riskLevel: .readOnly, requiresExplicitUserIntent: true),
        .init(name: "delete_transcripts", description: "Delete all locally retained voice transcripts.", riskLevel: .externalOrIrreversible, requiresExplicitUserIntent: true),
        .init(name: "select_screen_context", description: "Select relevant Screenwatch screenshots for this conversation.", riskLevel: .readOnly, requiresExplicitUserIntent: true, parametersJSONSchema: schema(["reason": .string, "limit": .integer], required: ["reason"]))
    ]

    public static let byName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })

    private static let calendarSchema = schema(
        ["title": .string, "start": .dateTime, "end": .dateTime],
        required: ["title", "start", "end"]
    )

    private enum ParameterKind: Sendable {
        case string, integer, boolean, dateTime

        var schema: [String: String] {
            switch self {
            case .string: ["type": "STRING"]
            case .integer: ["type": "INTEGER"]
            case .boolean: ["type": "BOOLEAN"]
            case .dateTime: ["type": "STRING", "format": "date-time"]
            }
        }
    }

    private static func schema(_ properties: [String: ParameterKind], required: [String]) -> String {
        let object: [String: Any] = [
            "type": "OBJECT",
            "properties": properties.mapValues(\.schema),
            "required": required
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data(#"{"properties":{},"type":"OBJECT"}"#.utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

public final class VoiceToolRouter: @unchecked Sendable {
    private let definitions: [String: VoiceToolDefinition]
    private let executor: any VoiceToolActionExecuting
    private let persistence: VoicePersistenceStore?
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String
    private let approvalClaimLock = NSLock()
    private var claimedApprovalIDs: Set<String> = []

    public init(
        definitions: [VoiceToolDefinition] = ChiefOfStaffToolRegistry.definitions,
        executor: any VoiceToolActionExecuting,
        persistence: VoicePersistenceStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.definitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
        self.executor = executor
        self.persistence = persistence
        self.now = now
        self.makeID = makeID
    }

    public func handle(_ invocation: VoiceToolInvocation) async -> VoiceToolExecutionResult {
        guard let definition = definitions[invocation.toolName] else {
            return .init(
                invocationID: invocation.id,
                status: .denied,
                message: "The requested tool is not in Zoid's allowlist."
            )
        }
        let hasExplicitIntent = ExplicitVoiceIntentPolicy.allows(invocation, definition: definition)
        let decision = VoiceActionPolicy.decision(
            for: definition,
            hasExplicitUserIntent: hasExplicitIntent
        )
        try? persistence?.save(invocation, riskLevel: definition.riskLevel, decision: decision)
        switch decision {
        case .deny:
            return .init(
                invocationID: invocation.id,
                status: .denied,
                message: "Zoid policy denied this action."
            )
        case .requireApproval:
            let createdAt = now()
            let approval = ApprovalRequest(
                id: makeID(),
                invocationID: invocation.id,
                reason: Self.approvalReason(for: invocation),
                state: .pending,
                createdAt: createdAt,
                expiresAt: createdAt.addingTimeInterval(120)
            )
            try? persistence?.save(approval)
            return .init(
                invocationID: invocation.id,
                status: .approvalRequired,
                message: approval.reason,
                approval: approval
            )
        case .allow:
            do {
                let result = try await executor.execute(
                    toolName: invocation.toolName,
                    argumentsJSON: invocation.argumentsJSON
                )
                return .init(
                    invocationID: invocation.id,
                    status: .executed,
                    message: "The requested action completed.",
                    resultJSON: result
                )
            } catch {
                return .init(
                    invocationID: invocation.id,
                    status: .failed,
                    message: error.localizedDescription
                )
            }
        }
    }

    public func resolveApproval(id: String, approved: Bool) async -> VoiceToolExecutionResult {
        guard claimApproval(id) else {
            return .init(invocationID: "", status: .denied, message: "This approval was already handled.")
        }
        guard let persistence,
              let request = try? persistence.approval(id: id),
              let invocation = try? persistence.invocation(id: request.invocationID) else {
            return .init(invocationID: "", status: .denied, message: "The approval request is unavailable.")
        }
        let date = now()
        guard request.state == .pending, request.expiresAt > date else {
            let expired = ApprovalRequest(
                id: request.id,
                invocationID: request.invocationID,
                reason: request.reason,
                state: .expired,
                createdAt: request.createdAt,
                expiresAt: request.expiresAt,
                resolvedAt: date
            )
            try? persistence.save(expired)
            return .init(invocationID: invocation.id, status: .denied, message: "The approval request expired.")
        }
        let resolved = ApprovalRequest(
            id: request.id,
            invocationID: request.invocationID,
            reason: request.reason,
            state: approved ? .approved : .denied,
            createdAt: request.createdAt,
            expiresAt: request.expiresAt,
            resolvedAt: date
        )
        try? persistence.save(resolved)
        guard approved else {
            return .init(invocationID: invocation.id, status: .denied, message: "The action was not approved.")
        }
        do {
            let result = try await executor.execute(
                toolName: invocation.toolName,
                argumentsJSON: invocation.argumentsJSON
            )
            return .init(
                invocationID: invocation.id,
                status: .executed,
                message: "The approved action completed.",
                resultJSON: result,
                approval: resolved
            )
        } catch {
            return .init(
                invocationID: invocation.id,
                status: .failed,
                message: error.localizedDescription,
                approval: resolved
            )
        }
    }

    private func claimApproval(_ id: String) -> Bool {
        approvalClaimLock.withLock {
            guard !claimedApprovalIDs.contains(id) else { return false }
            claimedApprovalIDs.insert(id)
            return true
        }
    }

    private static func approvalReason(for invocation: VoiceToolInvocation) -> String {
        let detail = invocation.argumentsJSON.count > 500
            ? String(invocation.argumentsJSON.prefix(500)) + "..."
            : invocation.argumentsJSON
        return "Approve \(invocation.toolName) with these arguments: \(detail)"
    }
}

public enum ExplicitVoiceIntentPolicy {
    public static func allows(_ invocation: VoiceToolInvocation, definition: VoiceToolDefinition) -> Bool {
        guard definition.requiresExplicitUserIntent else { return true }
        guard invocation.hasExplicitUserIntent else { return false }
        guard let raw = invocation.originUserText?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            // Retains compatibility for deterministic local command callers. Cloud callers always provide the utterance.
            return true
        }
        let text = raw.lowercased()
        let questionPrefixes = ["can you", "could you", "would you", "will you", "هل يمكنك", "ممكن"]
        guard !questionPrefixes.contains(where: { text.hasPrefix($0) }) else { return false }
        let requiredVerbs: [String: [String]] = [
            "set_active_task": ["start", "pause", "resume", "complete", "block", "reschedule", "ابدأ", "وقف", "كمل"],
            "open_application": ["open", "launch", "focus", "افتح"],
            "search_web": ["search", "look up", "google", "ابحث", "دور"],
            "find_files": ["find", "locate", "search", "لاقي", "دور"],
            "open_file": ["open", "افتح"],
            "create_reminder": ["remind", "add reminder", "create reminder", "فكرني"],
            "complete_reminder": ["complete", "mark done", "finish reminder", "خلص"],
            "create_focus_block": ["schedule", "block", "reserve", "حط", "احجز"],
            "create_calendar_commitment": ["schedule", "add", "create", "book", "حط", "احجز"],
            "pause_automation": ["pause", "stop", "وقف"],
            "resume_automation": ["resume", "start", "كمل"],
            "start_codex_job": ["codex", "build", "fix", "implement", "research", "ابدأ", "صلح"],
            "cancel_codex_job": ["cancel", "stop", "الغ", "وقف"],
            "remember_fact": ["remember", "save", "افتكر"],
            "forget_memory": ["forget", "delete memory", "انسى"],
            "correct_memory": ["correct", "change memory", "صحح"],
            "export_voice_memory": ["export", "download", "صدر"],
            "delete_transcripts": ["delete transcripts", "clear transcripts", "امسح المحادثات"],
            "select_screen_context": ["look at", "see my screen", "screen", "بص", "شوف"]
        ]
        guard let verbs = requiredVerbs[invocation.toolName] else { return false }
        return verbs.contains(where: text.contains)
    }
}
