import Darwin
import Foundation
import Security
import ZoidCoachCore

public let todayDashboardMachServiceName = RuntimeIdentity.production.machServiceName
private let terminalTaskMutationPrefix = "terminal-task-mutation:"

public struct TaskMutationRequest: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let command: TaskActivityCommand
    public let taskID: String
    public let blockedReason: String?
    public let requestedAt: Date

    public init(operationID: UUID, command: TaskActivityCommand, taskID: String, blockedReason: String? = nil, requestedAt: Date = Date()) {
        self.operationID = operationID
        self.command = command
        self.taskID = taskID
        self.blockedReason = blockedReason
        self.requestedAt = Date(timeIntervalSince1970: requestedAt.timeIntervalSince1970.rounded(.down))
    }
}

public struct CalendarPlanMutationRequest: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let day: Date

    public init(operationID: UUID, day: Date) {
        self.operationID = operationID
        self.day = Date(timeIntervalSince1970: day.timeIntervalSince1970.rounded(.down))
    }
}

public final class TaskMutationClientState: @unchecked Sendable {
    private let defaults: UserDefaults
    private let namespace: String
    private static let sharedLock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults = .standard, namespace: String) {
        self.defaults = defaults
        self.namespace = namespace
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    public func request(command: TaskActivityCommand, taskID: String, blockedReason: String? = nil) -> TaskMutationRequest {
        Self.sharedLock.withLock {
            let key = storageKey(command: command, taskID: taskID)
            if let data = defaults.data(forKey: key),
               let request = try? decoder.decode(TaskMutationRequest.self, from: data),
               request.blockedReason == blockedReason {
                return request
            }
            let request = TaskMutationRequest(
                operationID: UUID(),
                command: command,
                taskID: taskID,
                blockedReason: blockedReason
            )
            if let data = try? encoder.encode(request) { defaults.set(data, forKey: key) }
            return request
        }
    }

    public func complete(_ request: TaskMutationRequest) {
        Self.sharedLock.withLock {
            let key = storageKey(command: request.command, taskID: request.taskID)
            guard let data = defaults.data(forKey: key),
                  let stored = try? decoder.decode(TaskMutationRequest.self, from: data),
                  stored.operationID == request.operationID else { return }
            defaults.removeObject(forKey: key)
        }
    }

    public func pendingTaskRequests() -> [TaskMutationRequest] {
        Self.sharedLock.withLock {
            defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(taskStoragePrefix) }
                .compactMap { key in
                    defaults.data(forKey: key).flatMap { try? decoder.decode(TaskMutationRequest.self, from: $0) }
                }
                .sorted { $0.requestedAt < $1.requestedAt }
        }
    }

    public func calendarPlanRequest(day: Date) -> CalendarPlanMutationRequest {
        Self.sharedLock.withLock {
            let key = calendarPlanStorageKey
            if let data = defaults.data(forKey: key),
               let request = try? decoder.decode(CalendarPlanMutationRequest.self, from: data) {
                return request
            }
            let request = CalendarPlanMutationRequest(operationID: UUID(), day: day)
            if let data = try? encoder.encode(request) { defaults.set(data, forKey: key) }
            return request
        }
    }

    public func pendingCalendarPlanRequests() -> [CalendarPlanMutationRequest] {
        Self.sharedLock.withLock {
            guard let data = defaults.data(forKey: calendarPlanStorageKey),
                  let request = try? decoder.decode(CalendarPlanMutationRequest.self, from: data) else {
                return []
            }
            return [request]
        }
    }

    public func completeCalendarPlan(_ request: CalendarPlanMutationRequest) {
        Self.sharedLock.withLock {
            guard let data = defaults.data(forKey: calendarPlanStorageKey),
                  let stored = try? decoder.decode(CalendarPlanMutationRequest.self, from: data),
                  stored.operationID == request.operationID else { return }
            defaults.removeObject(forKey: calendarPlanStorageKey)
        }
    }

    private func storageKey(command: TaskActivityCommand, taskID: String) -> String {
        "\(taskStoragePrefix)\(command.rawValue).\(taskID)"
    }

    private var taskStoragePrefix: String { "zoid666.pending-task-mutation.\(namespace)." }
    private var calendarPlanStorageKey: String { "zoid666.pending-calendar-plan.\(namespace)" }
}

private final class XPCDataReplyBox: @unchecked Sendable {
    let reply: (Data?, String?) -> Void

    init(_ reply: @escaping (Data?, String?) -> Void) {
        self.reply = reply
    }

    public func calendarPlanRequest(day: Date) -> CalendarPlanMutationRequest {
        Self.sharedLock.withLock {
            let key = calendarPlanStorageKey
            if let data = defaults.data(forKey: key),
               let request = try? decoder.decode(CalendarPlanMutationRequest.self, from: data) {
                return request
            }
            let request = CalendarPlanMutationRequest(operationID: UUID(), day: day)
            if let data = try? encoder.encode(request) { defaults.set(data, forKey: key) }
            return request
        }
    }

    public func pendingCalendarPlanRequests() -> [CalendarPlanMutationRequest] {
        Self.sharedLock.withLock {
            guard let data = defaults.data(forKey: calendarPlanStorageKey),
                  let request = try? decoder.decode(CalendarPlanMutationRequest.self, from: data) else {
                return []
            }
            return [request]
        }
    }

    public func completeCalendarPlan(_ request: CalendarPlanMutationRequest) {
        Self.sharedLock.withLock {
            guard let data = defaults.data(forKey: calendarPlanStorageKey),
                  let stored = try? decoder.decode(CalendarPlanMutationRequest.self, from: data),
                  stored.operationID == request.operationID else { return }
            defaults.removeObject(forKey: calendarPlanStorageKey)
        }
    }

    private func storageKey(command: TaskActivityCommand, taskID: String) -> String {
        "\(taskStoragePrefix)\(command.rawValue).\(taskID)"
    }

    private var taskStoragePrefix: String { "zoid666.pending-task-mutation.\(namespace)." }
    private var calendarPlanStorageKey: String { "zoid666.pending-calendar-plan.\(namespace)" }
}

private final class XPCDataReplyBox: @unchecked Sendable {
    let reply: (Data?, String?) -> Void

    init(_ reply: @escaping (Data?, String?) -> Void) {
        self.reply = reply
    }
}

public struct TodayDashboardXPCConfiguration: Equatable, Sendable {
    public let machServiceName: String
    public let allowedSigningIdentifiers: Set<String>

    public init(runtimeEnvironment: RuntimeEnvironment) {
        machServiceName = runtimeEnvironment.identity.machServiceName
        allowedSigningIdentifiers = runtimeEnvironment.identity.allowedXPCSigningIdentifiers
    }
}

public protocol XPCConnectionAuthorizing: Sendable {
    func allows(_ connection: NSXPCConnection) -> Bool
}

public struct SameUserXPCConnectionAuthorizer: XPCConnectionAuthorizing, Sendable {
    private let expectedUserID: uid_t
    private let allowedSigningIdentifiers: Set<String>

    public init(
        expectedUserID: uid_t = geteuid(),
        allowedSigningIdentifiers: Set<String> = RuntimeIdentity.production.allowedXPCSigningIdentifiers
    ) {
        self.expectedUserID = expectedUserID
        self.allowedSigningIdentifiers = allowedSigningIdentifiers
    }

    public init(runtimeEnvironment: RuntimeEnvironment, expectedUserID: uid_t = geteuid()) {
        let configuration = TodayDashboardXPCConfiguration(
            runtimeEnvironment: runtimeEnvironment
        )
        self.init(
            expectedUserID: expectedUserID,
            allowedSigningIdentifiers: configuration.allowedSigningIdentifiers
        )
    }

    public func allows(_ connection: NSXPCConnection) -> Bool {
        guard connection.processIdentifier > 0,
              connection.effectiveUserIdentifier == expectedUserID,
              let own = Self.signingIdentity(),
              let peer = Self.signingIdentity(processIdentifier: connection.processIdentifier),
              Self.allowsSigningIdentity(identifier: own.identifier, allowedIdentifiers: allowedSigningIdentifiers),
              Self.allowsSigningIdentity(identifier: peer.identifier, allowedIdentifiers: allowedSigningIdentifiers) else { return false }
        if let ownTeam = own.teamIdentifier, let peerTeam = peer.teamIdentifier {
            return ownTeam == peerTeam
        }
        return own.teamIdentifier == nil && peer.teamIdentifier == nil
    }

    public static func allowsSigningIdentity(identifier: String, allowedIdentifiers: Set<String>) -> Bool {
        allowedIdentifiers.contains(identifier)
    }

    private static func signingIdentity(processIdentifier: pid_t? = nil) -> (identifier: String, teamIdentifier: String?)? {
        var code: SecCode?
        let status: OSStatus
        if let processIdentifier {
            let attributes = [kSecGuestAttributePid as String: NSNumber(value: processIdentifier)] as CFDictionary
            status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        } else {
            status = SecCodeCopySelf([], &code)
        }
        guard status == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let identifier = values[kSecCodeInfoIdentifier as String] as? String else { return nil }
        return (identifier, values[kSecCodeInfoTeamIdentifier as String] as? String)
    }
}

@objc public protocol TodayDashboardXPCProtocol {
    func fetchRuntimeSafety(withReply reply: @escaping (Data?, String?) -> Void)
    func fetchCaptureHealth(withReply reply: @escaping (Data?, String?) -> Void)
    func fetchTodaySnapshot(withReply reply: @escaping (Data?, String?) -> Void)
    func applyTaskCommand(_ command: String, taskID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func applyTaskMutation(_ request: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func blockTask(_ taskID: String, reason: String, withReply reply: @escaping (Data?, String?) -> Void)
    func fetchReminderCompletionSync(_ taskID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func retryReminderCompletion(_ taskID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func startSprint(_ taskID: String, durationMinutes: Int, withReply reply: @escaping (Data?, String?) -> Void)
    func startUnplannedTask(_ taskID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func skipPlanning(withReply reply: @escaping (Data?, String?) -> Void)
    func fetchPromptInbox(withReply reply: @escaping (Data?, String?) -> Void)
    func fetchPromptInboxTimeline(withReply reply: @escaping (Data?, String?) -> Void)
    func respondToPrompt(_ command: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func dismissPrompt(_ promptID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func createOnboardingTestPrompt(_ flowID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func fetchOnboardingTestPrompt(_ flowID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func applyAgentMutation(_ command: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func fetchActionAudit(withReply reply: @escaping (Data?, String?) -> Void)
    func retryFailedActions(_ commandIDs: [String], withReply reply: @escaping (Data?, String?) -> Void)
    func fetchVoiceContext(withReply reply: @escaping (Data?, String?) -> Void)
    func invokeVoiceTool(_ invocation: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func resolveVoiceApproval(_ approvalID: String, approved: Bool, withReply reply: @escaping (Data?, String?) -> Void)
    func saveVoiceSession(_ session: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func appendConversationTurn(_ turn: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func recordScreenContextTransmission(_ selection: Data, sessionID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func fetchVoiceUsage(withReply reply: @escaping (Data?, String?) -> Void)
    func recordVoiceUsage(_ sample: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func reserveVoiceBudget(withReply reply: @escaping (Data?, String?) -> Void)
    func settleVoiceBudget(_ reservationID: String, sample: Data, withReply reply: @escaping (Data?, String?) -> Void)
}

public final class TodayDashboardXPCService: NSObject, NSXPCListenerDelegate {
    private let agent: TodayDashboardAgent?
    private let listener: NSXPCListener
    private let authorizer: any XPCConnectionAuthorizing
    private let promptStore: PromptInboxStore?
    private let promptEffectRouter: PromptResponseEffectRouter?
    private let onboardingTestPrompts: OnboardingTestPromptService?
    private let mutationRouter: AgentMutationRouter?
    private let voiceController: VoiceAgentController?
    private let writeCircuitBreaker: DatabaseWriteCircuitBreaker
    private let captureHealthStore: AgentCaptureHealthStore?

    public init(
        agent: TodayDashboardAgent? = nil,
        promptStore: PromptInboxStore? = nil,
        promptEffectRouter: PromptResponseEffectRouter? = nil,
        onboardingTestPrompts: OnboardingTestPromptService? = nil,
        mutationRouter: AgentMutationRouter? = nil,
        voiceController: VoiceAgentController? = nil,
        writeCircuitBreaker: DatabaseWriteCircuitBreaker = DatabaseWriteCircuitBreaker(),
        captureHealthStore: AgentCaptureHealthStore? = nil,
        runtimeEnvironment: RuntimeEnvironment = .production(),
        machServiceName: String? = nil,
        authorizer: (any XPCConnectionAuthorizing)? = nil
    ) {
        let xpcConfiguration = TodayDashboardXPCConfiguration(
            runtimeEnvironment: runtimeEnvironment
        )
        self.agent = agent
        self.promptStore = promptStore
        self.promptEffectRouter = promptEffectRouter
        self.onboardingTestPrompts = onboardingTestPrompts
        self.mutationRouter = mutationRouter
        self.voiceController = voiceController
        self.writeCircuitBreaker = writeCircuitBreaker
        self.captureHealthStore = captureHealthStore
        self.authorizer = authorizer ?? SameUserXPCConnectionAuthorizer(runtimeEnvironment: runtimeEnvironment)
        listener = NSXPCListener(
            machServiceName: machServiceName ?? xpcConfiguration.machServiceName
        )
        super.init()
        listener.delegate = self
    }

    public func resume() { listener.resume() }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard authorizer.allows(connection) else {
            connection.invalidate()
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: TodayDashboardXPCProtocol.self)
        connection.exportedObject = TodayDashboardXPCEndpoint(agent: agent, promptStore: promptStore, promptEffectRouter: promptEffectRouter, onboardingTestPrompts: onboardingTestPrompts, mutationRouter: mutationRouter, voiceController: voiceController, writeCircuitBreaker: writeCircuitBreaker, captureHealthStore: captureHealthStore)
        connection.resume()
        return true
    }
}

private final class TodayDashboardXPCEndpoint: NSObject, TodayDashboardXPCProtocol {
    private let agent: TodayDashboardAgent?
    private let promptStore: PromptInboxStore?
    private let promptEffectRouter: PromptResponseEffectRouter?
    private let onboardingTestPrompts: OnboardingTestPromptService?
    private let mutationRouter: AgentMutationRouter?
    private let voiceController: VoiceAgentController?
    private let writeCircuitBreaker: DatabaseWriteCircuitBreaker
    private let captureHealthStore: AgentCaptureHealthStore?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let taskMutationDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
    init(agent: TodayDashboardAgent?, promptStore: PromptInboxStore?, promptEffectRouter: PromptResponseEffectRouter?, onboardingTestPrompts: OnboardingTestPromptService?, mutationRouter: AgentMutationRouter?, voiceController: VoiceAgentController?, writeCircuitBreaker: DatabaseWriteCircuitBreaker, captureHealthStore: AgentCaptureHealthStore?) {
        self.agent = agent
        self.promptStore = promptStore
        self.promptEffectRouter = promptEffectRouter
        self.onboardingTestPrompts = onboardingTestPrompts
        self.mutationRouter = mutationRouter
        self.voiceController = voiceController
        self.writeCircuitBreaker = writeCircuitBreaker
        self.captureHealthStore = captureHealthStore
    }

    func fetchRuntimeSafety(withReply reply: @escaping (Data?, String?) -> Void) {
        do { reply(try encoder.encode(writeCircuitBreaker.snapshot), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func fetchCaptureHealth(withReply reply: @escaping (Data?, String?) -> Void) {
        guard let captureHealthStore else { reply(nil, "Native capture health is unavailable."); return }
        do { reply(try encoder.encode(captureHealthStore.snapshot), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func fetchTodaySnapshot(withReply reply: @escaping (Data?, String?) -> Void) {
        guard let agent else { reply(nil, "The agent database is read-only and no dashboard snapshot is available."); return }
        do { reply(try encoder.encode(agent.snapshot()), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func applyTaskCommand(_ command: String, taskID: String, withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let agent else { reply(nil, "The agent database is unavailable."); return }
        guard let command = TaskActivityCommand(rawValue: command) else {
            reply(nil, "Unknown task command.")
            return
        }
        do { reply(try encoder.encode(agent.apply(command, taskID: taskID)), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func applyTaskMutation(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let agent else { reply(nil, "The agent database is unavailable."); return }
        do {
            let request = try taskMutationDecoder.decode(TaskMutationRequest.self, from: requestData)
            let snapshot = try agent.apply(
                request.command,
                taskID: request.taskID,
                blockedReason: request.blockedReason,
                operationID: request.operationID,
                now: request.requestedAt
            )
            reply(try encoder.encode(snapshot), nil)
        } catch {
            if let diagnostic = terminalTaskMutationDiagnostic(error) {
                reply(nil, terminalTaskMutationPrefix + diagnostic)
            } else {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func blockTask(_ taskID: String, reason: String, withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let agent else { reply(nil, "The agent database is unavailable."); return }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...240).contains(normalizedReason.count) else {
            reply(nil, "Explain the blocker in 3 to 240 characters.")
            return
        }
        do { reply(try encoder.encode(agent.apply(.block, taskID: taskID, blockedReason: normalizedReason)), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func fetchReminderCompletionSync(_ taskID: String, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let agent else { reply(nil, "The agent database is unavailable."); return }
        do { reply(try encoder.encode(agent.reminderCompletionSyncState(taskID: taskID)), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func retryReminderCompletion(_ taskID: String, withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let agent else { reply(nil, "The agent database is unavailable."); return }
        do { reply(try encoder.encode(agent.retryReminderCompletion(taskID: taskID)), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func startSprint(_ taskID: String, durationMinutes: Int, withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let agent else { reply(nil, "The agent database is unavailable."); return }
        do { reply(try encoder.encode(agent.startSprint(taskID: taskID, durationMinutes: durationMinutes)), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func startUnplannedTask(_ taskID: String, withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let agent else { reply(nil, "The agent database is unavailable."); return }
        do { reply(try encoder.encode(agent.startUnplannedTask(taskID)), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func skipPlanning(withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let agent else { reply(nil, "The agent database is unavailable."); return }
        do { reply(try encoder.encode(agent.skipPlanning()), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func fetchPromptInbox(withReply reply: @escaping (Data?, String?) -> Void) {
        guard let promptStore else { reply(try? encoder.encode([PromptEpisode]()), nil); return }
        do { reply(try encoder.encode(promptStore.unresolved()), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func fetchPromptInboxTimeline(withReply reply: @escaping (Data?, String?) -> Void) {
        guard let promptStore else { reply(try? encoder.encode(PromptInboxTimeline.empty), nil); return }
        do { reply(try encoder.encode(promptStore.timeline()), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func respondToPrompt(_ command: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let promptStore else { reply(nil, "The prompt inbox is unavailable."); return }
        do {
            let command = try decoder.decode(PromptResponseCommand.self, from: command)
            let result = try promptStore.respond(
                promptID: command.promptID,
                action: command.action,
                actionToken: command.actionToken,
                surface: command.surface
            )
            if let promptEffectRouter {
                _ = try promptEffectRouter.apply(result)
                try promptStore.markEffectApplied(responseID: result.response.id)
            }
            reply(try encoder.encode(result.episode), nil)
        } catch { reply(nil, error.localizedDescription) }
    }

    func dismissPrompt(_ promptID: String, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let promptStore else { reply(nil, "The prompt inbox is unavailable."); return }
        do { reply(try encoder.encode(promptStore.dismiss(promptID: promptID)), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func createOnboardingTestPrompt(
        _ flowID: String,
        withReply reply: @escaping (Data?, String?) -> Void
    ) {
        guard let onboardingTestPrompts else {
            reply(nil, "The onboarding prompt service is unavailable.")
            return
        }
        let replyBox = XPCDataReplyBox(reply)
        Task {
            do {
                let result = try await onboardingTestPrompts.createOrDeliver(flowID: flowID)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                replyBox.reply(try encoder.encode(result), nil)
            } catch {
                replyBox.reply(nil, error.localizedDescription)
            }
        }
    }

    func fetchOnboardingTestPrompt(
        _ flowID: String,
        withReply reply: @escaping (Data?, String?) -> Void
    ) {
        guard let onboardingTestPrompts else {
            reply(nil, "The onboarding prompt service is unavailable.")
            return
        }
        do { reply(try encoder.encode(onboardingTestPrompts.current(flowID: flowID)), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func applyAgentMutation(_ command: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let mutationRouter else { reply(nil, "The agent mutation router is unavailable."); return }
        let decoded: AgentMutationCommand
        do {
            decoded = try decoder.decode(AgentMutationCommand.self, from: command)
        } catch {
            reply(nil, error.localizedDescription)
            return
        }
        let replyBox = XPCReplyBox(reply)
        Task { [mutationRouter, decoded, replyBox] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                replyBox.call(try encoder.encode(try await mutationRouter.apply(decoded)), nil)
            } catch {
                replyBox.call(nil, error.localizedDescription)
            }
        }
    }

    func fetchActionAudit(withReply reply: @escaping (Data?, String?) -> Void) {
        guard let mutationRouter else { reply(nil, "The agent mutation router is unavailable."); return }
        do { reply(try encoder.encode(mutationRouter.recentActionAudit()), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func retryFailedActions(_ commandIDs: [String], withReply reply: @escaping (Data?, String?) -> Void) {
        guard let mutationRouter else { reply(nil, "The agent mutation router is unavailable."); return }
        do { reply(try encoder.encode(mutationRouter.retryFailedActions(commandIDs: commandIDs)), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func fetchVoiceContext(withReply reply: @escaping (Data?, String?) -> Void) {
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        let replyBox = XPCReplyBox(reply)
        Task { [voiceController, replyBox] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                replyBox.call(try encoder.encode(try await voiceController.context()), nil)
            }
            catch { replyBox.call(nil, error.localizedDescription) }
        }
    }

    func invokeVoiceTool(_ invocation: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        do {
            let decoded = try decoder.decode(VoiceToolInvocation.self, from: invocation)
            let replyBox = XPCReplyBox(reply)
            Task { [voiceController, replyBox] in
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                replyBox.call(try? encoder.encode(await voiceController.invoke(decoded)), nil)
            }
        } catch { reply(nil, error.localizedDescription) }
    }

    func resolveVoiceApproval(_ approvalID: String, approved: Bool, withReply reply: @escaping (Data?, String?) -> Void) {
        do { try writeCircuitBreaker.throwIfTripped() }
        catch { reply(nil, error.localizedDescription); return }
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        let replyBox = XPCReplyBox(reply)
        Task { [voiceController, replyBox] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            replyBox.call(try? encoder.encode(await voiceController.resolveApproval(id: approvalID, approved: approved)), nil)
        }
    }

    func saveVoiceSession(_ session: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        do {
            try voiceController.save(try decoder.decode(VoiceSession.self, from: session))
            reply(try encoder.encode(true), nil)
        } catch { reply(nil, error.localizedDescription) }
    }

    func appendConversationTurn(_ turn: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        do {
            try voiceController.append(try decoder.decode(ConversationTurn.self, from: turn))
            reply(try encoder.encode(true), nil)
        } catch { reply(nil, error.localizedDescription) }
    }

    func recordScreenContextTransmission(_ selection: Data, sessionID: String, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        do {
            try voiceController.recordTransmission(
                try decoder.decode(ScreenContextSelection.self, from: selection),
                sessionID: sessionID
            )
            reply(try encoder.encode(true), nil)
        } catch { reply(nil, error.localizedDescription) }
    }

    func fetchVoiceUsage(withReply reply: @escaping (Data?, String?) -> Void) {
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        do { reply(try encoder.encode(voiceController.usage()), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func recordVoiceUsage(_ sample: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        do {
            let sample = try decoder.decode(VoiceUsageSample.self, from: sample)
            reply(try encoder.encode(voiceController.record(sample)), nil)
        } catch { reply(nil, error.localizedDescription) }
    }

    func reserveVoiceBudget(withReply reply: @escaping (Data?, String?) -> Void) {
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        do { reply(try encoder.encode(voiceController.reserveCloudSession()), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func settleVoiceBudget(_ reservationID: String, sample: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let voiceController else { reply(nil, "The voice controller is unavailable."); return }
        do {
            let sample = try decoder.decode(VoiceUsageSample.self, from: sample)
            reply(try encoder.encode(voiceController.settleCloudSession(reservationID: reservationID, sample: sample)), nil)
        } catch { reply(nil, error.localizedDescription) }
    }
}

private final class XPCReplyBox: @unchecked Sendable {
    private let reply: (Data?, String?) -> Void

    init(_ reply: @escaping (Data?, String?) -> Void) { self.reply = reply }

    func call(_ data: Data?, _ error: String?) { reply(data, error) }
}

public final class TodayDashboardXPCClient: @unchecked Sendable {
    private let machServiceName: String?
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let mutationEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    let mutationState: TaskMutationClientState

    public init(machServiceName: String? = todayDashboardMachServiceName, pendingMutationDefaults: UserDefaults = .standard) {
        self.machServiceName = machServiceName
        mutationState = TaskMutationClientState(
            defaults: pendingMutationDefaults,
            namespace: machServiceName ?? "disabled"
        )
    }

    public convenience init(runtimeEnvironment: RuntimeEnvironment) {
        let configuration = TodayDashboardXPCConfiguration(
            runtimeEnvironment: runtimeEnvironment
        )
        self.init(
            machServiceName: configuration.machServiceName,
            pendingMutationDefaults: runtimeEnvironment.makeUserDefaults()
        )
    }

    public static var disabled: TodayDashboardXPCClient {
        TodayDashboardXPCClient(machServiceName: nil)
    }

    public var isEnabled: Bool { machServiceName != nil }
    public var configuredMachServiceName: String? { machServiceName }

    public func fetchTodaySnapshot() async throws -> TodaySnapshot {
        try await call { proxy, reply in proxy.fetchTodaySnapshot(withReply: reply) }
    }

    public func fetchRuntimeSafety() async throws -> AgentRuntimeSafetySnapshot {
        try await callData { proxy, reply in proxy.fetchRuntimeSafety(withReply: reply) }
    }

    public func fetchCaptureHealth() async throws -> AgentCaptureHealthSnapshot {
        try await callData { proxy, reply in proxy.fetchCaptureHealth(withReply: reply) }
    }

    public func apply(_ command: TaskActivityCommand, taskID: String) async throws -> TodaySnapshot {
        let request = mutationState.request(command: command, taskID: taskID)
        let data = try mutationEncoder.encode(request)
        do {
            let snapshot: TodaySnapshot = try await call { proxy, reply in proxy.applyTaskMutation(data, withReply: reply) }
            mutationState.complete(request)
            return snapshot
        } catch TodayDashboardXPCError.remote(let message) where message.hasPrefix(terminalTaskMutationPrefix) {
            mutationState.complete(request)
            throw TodayDashboardXPCError.remote(String(message.dropFirst(terminalTaskMutationPrefix.count)))
        }
    }

    public func apply(_ request: TaskMutationRequest) async throws -> TodaySnapshot {
        let data = try mutationEncoder.encode(request)
        return try await call { proxy, reply in proxy.applyTaskMutation(data, withReply: reply) }
    }

    public func reconcilePendingTaskMutations() async -> [TodaySnapshot] {
        var reconciled: [TodaySnapshot] = []
        for request in mutationState.pendingTaskRequests() {
            for attempt in 0..<8 {
                do {
                    let snapshot = try await apply(request)
                    mutationState.complete(request)
                    reconciled.append(snapshot)
                    break
                } catch TodayDashboardXPCError.remote(let message) where message.hasPrefix(terminalTaskMutationPrefix) {
                    mutationState.complete(request)
                    break
                } catch {
                    guard attempt < 7 else { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        return reconciled
    }

    public func schedulePlan(day: Date) async throws -> AgentMutationReceipt {
        let request = mutationState.calendarPlanRequest(day: day)
        let receipt = try await apply(.schedulePlan(day: request.day, operationID: request.operationID))
        mutationState.completeCalendarPlan(request)
        return receipt
    }

    public func reconcilePendingCalendarPlans() async -> [AgentMutationReceipt] {
        var reconciled: [AgentMutationReceipt] = []
        for request in mutationState.pendingCalendarPlanRequests() {
            for attempt in 0..<8 {
                do {
                    let receipt = try await apply(.schedulePlan(day: request.day, operationID: request.operationID))
                    mutationState.completeCalendarPlan(request)
                    reconciled.append(receipt)
                    break
                } catch {
                    guard attempt < 7 else { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        return reconciled
    }

    public func blockTask(taskID: String, reason: String) async throws -> TodaySnapshot {
        let request = mutationState.request(command: .block, taskID: taskID, blockedReason: reason)
        do {
            let snapshot = try await apply(request)
            mutationState.complete(request)
            return snapshot
        } catch TodayDashboardXPCError.remote(let message) where message.hasPrefix(terminalTaskMutationPrefix) {
            mutationState.complete(request)
            throw TodayDashboardXPCError.remote(String(message.dropFirst(terminalTaskMutationPrefix.count)))
        }
    }

    public func fetchReminderCompletionSync(taskID: String) async throws -> ReminderCompletionSyncState {
        try await callData { proxy, reply in
            proxy.fetchReminderCompletionSync(taskID, withReply: reply)
        }
    }

    public func retryReminderCompletion(taskID: String) async throws -> ReminderCompletionSyncState {
        try await callData { proxy, reply in
            proxy.retryReminderCompletion(taskID, withReply: reply)
        }
    }

    public func startSprint(taskID: String, durationMinutes: Int) async throws -> TodaySnapshot {
        try await call { proxy, reply in
            proxy.startSprint(taskID, durationMinutes: durationMinutes, withReply: reply)
        }
    }

    public func startUnplannedTask(_ taskID: String) async throws -> TodaySnapshot {
        try await call { proxy, reply in proxy.startUnplannedTask(taskID, withReply: reply) }
    }

    public func skipPlanning() async throws -> TodaySnapshot {
        try await call { proxy, reply in proxy.skipPlanning(withReply: reply) }
    }

    public func fetchPromptInbox() async throws -> [PromptEpisode] {
        try await callData { proxy, reply in proxy.fetchPromptInbox(withReply: reply) }
    }

    public func fetchPromptInboxTimeline() async throws -> PromptInboxTimeline {
        try await callData { proxy, reply in proxy.fetchPromptInboxTimeline(withReply: reply) }
    }

    public func respondToPrompt(_ command: PromptResponseCommand) async throws -> PromptEpisode {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(command)
        return try await callData { proxy, reply in proxy.respondToPrompt(data, withReply: reply) }
    }

    public func dismissPrompt(_ promptID: String) async throws -> PromptEpisode {
        try await callData { proxy, reply in proxy.dismissPrompt(promptID, withReply: reply) }
    }

    public func createOnboardingTestPrompt(flowID: String) async throws -> OnboardingTestPromptResult {
        try await callData { proxy, reply in
            proxy.createOnboardingTestPrompt(flowID, withReply: reply)
        }
    }

    public func fetchOnboardingTestPrompt(flowID: String) async throws -> PromptEpisode? {
        try await callData { proxy, reply in
            proxy.fetchOnboardingTestPrompt(flowID, withReply: reply)
        }
    }

    public func apply(_ command: AgentMutationCommand) async throws -> AgentMutationReceipt {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(command)
        return try await callData { proxy, reply in proxy.applyAgentMutation(data, withReply: reply) }
    }

    public func savePolicyMutation(
        _ request: PolicyMutationRequest
    ) async throws -> AgentMutationReceipt {
        try await apply(.savePolicyMutation(request))
    }

    public func fetchActionAudit() async throws -> [ActionAuditEntry] {
        try await callData { proxy, reply in proxy.fetchActionAudit(withReply: reply) }
    }

    public func retryFailedActions(commandIDs: [String]) async throws -> [ActionAuditEntry] {
        try await callData { proxy, reply in proxy.retryFailedActions(commandIDs, withReply: reply) }
    }

    public func fetchVoiceContext() async throws -> ChiefOfStaffContextPacket {
        try await callData { proxy, reply in proxy.fetchVoiceContext(withReply: reply) }
    }

    public func invokeVoiceTool(_ invocation: VoiceToolInvocation) async throws -> VoiceToolExecutionResult {
        let data = try encoded(invocation)
        return try await callData(timeout: .seconds(60)) { proxy, reply in proxy.invokeVoiceTool(data, withReply: reply) }
    }

    public func resolveVoiceApproval(id: String, approved: Bool) async throws -> VoiceToolExecutionResult {
        try await callData(timeout: .seconds(60)) { proxy, reply in
            proxy.resolveVoiceApproval(id, approved: approved, withReply: reply)
        }
    }

    public func saveVoiceSession(_ session: VoiceSession) async throws {
        let data = try encoded(session)
        let _: Bool = try await callData { proxy, reply in proxy.saveVoiceSession(data, withReply: reply) }
    }

    public func appendConversationTurn(_ turn: ConversationTurn) async throws {
        let data = try encoded(turn)
        let _: Bool = try await callData { proxy, reply in proxy.appendConversationTurn(data, withReply: reply) }
    }

    public func recordScreenContextTransmission(_ selection: ScreenContextSelection, sessionID: String) async throws {
        let data = try encoded(selection)
        let _: Bool = try await callData { proxy, reply in
            proxy.recordScreenContextTransmission(data, sessionID: sessionID, withReply: reply)
        }
    }

    public func fetchVoiceUsage() async throws -> VoiceUsageLedger {
        try await callData { proxy, reply in proxy.fetchVoiceUsage(withReply: reply) }
    }

    public func recordVoiceUsage(_ sample: VoiceUsageSample) async throws -> VoiceUsageLedger {
        let data = try encoded(sample)
        return try await callData { proxy, reply in proxy.recordVoiceUsage(data, withReply: reply) }
    }

    public func reserveVoiceBudget() async throws -> VoiceBudgetReservation {
        try await callData { proxy, reply in proxy.reserveVoiceBudget(withReply: reply) }
    }

    public func settleVoiceBudget(id: String, sample: VoiceUsageSample) async throws -> VoiceUsageLedger {
        let data = try encoded(sample)
        return try await callData { proxy, reply in
            proxy.settleVoiceBudget(id, sample: data, withReply: reply)
        }
    }

    private func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func call(_ invocation: @escaping (any TodayDashboardXPCProtocol, @escaping (Data?, String?) -> Void) -> Void) async throws -> TodaySnapshot {
        try await callData(invocation)
    }

    private func callData<T: Decodable & Sendable>(
        timeout: Duration = .seconds(3),
        _ invocation: @escaping (any TodayDashboardXPCProtocol, @escaping (Data?, String?) -> Void) -> Void
    ) async throws -> T {
        guard let machServiceName else { throw TodayDashboardXPCError.disabled }
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: machServiceName, options: [])
            connection.remoteObjectInterface = NSXPCInterface(with: TodayDashboardXPCProtocol.self)
            let gate = XPCResultGate<T>(continuation: continuation, connection: connection, decoder: decoder)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                gate.fail(error)
            } as! TodayDashboardXPCProtocol
            connection.resume()
            invocation(proxy) { data, error in
                gate.receive(data: data, remoteError: error)
            }
            Task {
                try? await Task.sleep(for: timeout)
                gate.fail(TodayDashboardXPCError.timeout)
            }
        }
    }
}

private final class XPCResultGate<Value: Decodable & Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private let continuation: CheckedContinuation<Value, Error>
    private let connection: NSXPCConnection
    private let decoder: JSONDecoder

    init(continuation: CheckedContinuation<Value, Error>, connection: NSXPCConnection, decoder: JSONDecoder) {
        self.continuation = continuation
        self.connection = connection
        self.decoder = decoder
    }

    func receive(data: Data?, remoteError: String?) {
        guard let data else {
            fail(TodayDashboardXPCError.remote(remoteError ?? "The agent did not return data."))
            return
        }
        do { succeed(try decoder.decode(Value.self, from: data)) }
        catch { fail(error) }
    }

    func succeed(_ value: Value) {
        guard finishOnce() else { return }
        connection.invalidate()
        continuation.resume(returning: value)
    }

    func fail(_ error: Error) {
        guard finishOnce() else { return }
        connection.invalidate()
        continuation.resume(throwing: error)
    }

    private func finishOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return false }
        isFinished = true
        return true
    }
}

public enum TodayDashboardXPCError: LocalizedError {
    case disabled
    case remote(String)
    case timeout
    public var errorDescription: String? {
        switch self {
        case .disabled: return "The background agent connection is disabled in this runtime."
        case let .remote(message): return message
        case .timeout: return "The background agent did not respond within three seconds."
        }
    }
}

private func terminalTaskMutationDiagnostic(_ error: Error) -> String? {
    if case let TodayDashboardAgentError.validationFailed(message) = error {
        return message
    }
    guard let error = error as? TaskExecutionStoreError else { return nil }
    switch error {
    case .invalidSprintDuration, .invalidBlockedReason, .sprintUnavailable, .sprintStillActive:
        return error.localizedDescription
    case .openDatabase, .schema, .read, .write:
        return nil
    }
}
