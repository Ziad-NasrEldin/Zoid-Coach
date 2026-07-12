import Darwin
import Foundation
import Security
import ZoidCoachCore

public let todayDashboardMachServiceName = RuntimeIdentity.production.machServiceName

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
    func fetchPromptInbox(withReply reply: @escaping (Data?, String?) -> Void)
    func respondToPrompt(_ command: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func createOnboardingTestPrompt(_ flowID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func fetchOnboardingTestPrompt(_ flowID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func applyAgentMutation(_ command: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func fetchActionAudit(withReply reply: @escaping (Data?, String?) -> Void)
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

    func fetchPromptInbox(withReply reply: @escaping (Data?, String?) -> Void) {
        guard let promptStore else { reply(try? encoder.encode([PromptEpisode]()), nil); return }
        do { reply(try encoder.encode(promptStore.unresolved()), nil) }
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

    public init(machServiceName: String? = todayDashboardMachServiceName) {
        self.machServiceName = machServiceName
    }

    public convenience init(runtimeEnvironment: RuntimeEnvironment) {
        let configuration = TodayDashboardXPCConfiguration(
            runtimeEnvironment: runtimeEnvironment
        )
        self.init(machServiceName: configuration.machServiceName)
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
        try await call { proxy, reply in proxy.applyTaskCommand(command.rawValue, taskID: taskID, withReply: reply) }
    }

    public func fetchPromptInbox() async throws -> [PromptEpisode] {
        try await callData { proxy, reply in proxy.fetchPromptInbox(withReply: reply) }
    }

    public func respondToPrompt(_ command: PromptResponseCommand) async throws -> PromptEpisode {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(command)
        return try await callData { proxy, reply in proxy.respondToPrompt(data, withReply: reply) }
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
