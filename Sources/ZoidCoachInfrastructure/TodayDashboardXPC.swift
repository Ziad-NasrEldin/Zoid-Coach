import Darwin
import Foundation
import Security
import ZoidCoachCore

public let todayDashboardMachServiceName = "com.ziadnasreldin.ZoidCoach.agent"

public protocol XPCConnectionAuthorizing: Sendable {
    func allows(_ connection: NSXPCConnection) -> Bool
}

public struct SameUserXPCConnectionAuthorizer: XPCConnectionAuthorizing, Sendable {
    private let expectedUserID: uid_t
    private let signingIdentifierPrefix: String

    public init(expectedUserID: uid_t = geteuid(), signingIdentifierPrefix: String = "com.ziadnasreldin.ZoidCoach") {
        self.expectedUserID = expectedUserID
        self.signingIdentifierPrefix = signingIdentifierPrefix
    }

    public func allows(_ connection: NSXPCConnection) -> Bool {
        guard connection.processIdentifier > 0,
              connection.effectiveUserIdentifier == expectedUserID,
              let own = Self.signingIdentity(),
              let peer = Self.signingIdentity(processIdentifier: connection.processIdentifier),
              own.identifier.hasPrefix(signingIdentifierPrefix),
              peer.identifier.hasPrefix(signingIdentifierPrefix) else { return false }
        if let ownTeam = own.teamIdentifier, let peerTeam = peer.teamIdentifier {
            return ownTeam == peerTeam
        }
        return own.teamIdentifier == nil && peer.teamIdentifier == nil
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
    func fetchTodaySnapshot(withReply reply: @escaping (Data?, String?) -> Void)
    func applyTaskCommand(_ command: String, taskID: String, withReply reply: @escaping (Data?, String?) -> Void)
    func fetchPromptInbox(withReply reply: @escaping (Data?, String?) -> Void)
    func respondToPrompt(_ command: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func applyAgentMutation(_ command: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func fetchActionAudit(withReply reply: @escaping (Data?, String?) -> Void)
}

public final class TodayDashboardXPCService: NSObject, NSXPCListenerDelegate {
    private let agent: TodayDashboardAgent
    private let listener: NSXPCListener
    private let authorizer: any XPCConnectionAuthorizing
    private let promptStore: PromptInboxStore?
    private let promptEffectRouter: PromptResponseEffectRouter?
    private let mutationRouter: AgentMutationRouter?

    public init(agent: TodayDashboardAgent, promptStore: PromptInboxStore? = nil, promptEffectRouter: PromptResponseEffectRouter? = nil, mutationRouter: AgentMutationRouter? = nil, machServiceName: String = todayDashboardMachServiceName, authorizer: any XPCConnectionAuthorizing = SameUserXPCConnectionAuthorizer()) {
        self.agent = agent
        self.promptStore = promptStore
        self.promptEffectRouter = promptEffectRouter
        self.mutationRouter = mutationRouter
        self.authorizer = authorizer
        listener = NSXPCListener(machServiceName: machServiceName)
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
        connection.exportedObject = TodayDashboardXPCEndpoint(agent: agent, promptStore: promptStore, promptEffectRouter: promptEffectRouter, mutationRouter: mutationRouter)
        connection.resume()
        return true
    }
}

private final class TodayDashboardXPCEndpoint: NSObject, TodayDashboardXPCProtocol {
    private let agent: TodayDashboardAgent
    private let promptStore: PromptInboxStore?
    private let promptEffectRouter: PromptResponseEffectRouter?
    private let mutationRouter: AgentMutationRouter?
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

    init(agent: TodayDashboardAgent, promptStore: PromptInboxStore?, promptEffectRouter: PromptResponseEffectRouter?, mutationRouter: AgentMutationRouter?) {
        self.agent = agent
        self.promptStore = promptStore
        self.promptEffectRouter = promptEffectRouter
        self.mutationRouter = mutationRouter
    }

    func fetchTodaySnapshot(withReply reply: @escaping (Data?, String?) -> Void) {
        do { reply(try encoder.encode(agent.snapshot()), nil) }
        catch { reply(nil, error.localizedDescription) }
    }

    func applyTaskCommand(_ command: String, taskID: String, withReply reply: @escaping (Data?, String?) -> Void) {
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

    func applyAgentMutation(_ command: Data, withReply reply: @escaping (Data?, String?) -> Void) {
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
}

private final class XPCReplyBox: @unchecked Sendable {
    private let reply: (Data?, String?) -> Void

    init(_ reply: @escaping (Data?, String?) -> Void) { self.reply = reply }

    func call(_ data: Data?, _ error: String?) { reply(data, error) }
}

public final class TodayDashboardXPCClient: @unchecked Sendable {
    private let machServiceName: String
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(machServiceName: String = todayDashboardMachServiceName) { self.machServiceName = machServiceName }

    public func fetchTodaySnapshot() async throws -> TodaySnapshot {
        try await call { proxy, reply in proxy.fetchTodaySnapshot(withReply: reply) }
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

    public func apply(_ command: AgentMutationCommand) async throws -> AgentMutationReceipt {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(command)
        return try await callData { proxy, reply in proxy.applyAgentMutation(data, withReply: reply) }
    }

    public func fetchActionAudit() async throws -> [ActionAuditEntry] {
        try await callData { proxy, reply in proxy.fetchActionAudit(withReply: reply) }
    }

    private func call(_ invocation: @escaping (any TodayDashboardXPCProtocol, @escaping (Data?, String?) -> Void) -> Void) async throws -> TodaySnapshot {
        try await callData(invocation)
    }

    private func callData<T: Decodable & Sendable>(_ invocation: @escaping (any TodayDashboardXPCProtocol, @escaping (Data?, String?) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
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
                try? await Task.sleep(for: .seconds(3))
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
    case remote(String)
    case timeout
    public var errorDescription: String? {
        switch self {
        case let .remote(message): return message
        case .timeout: return "The background agent did not respond within three seconds."
        }
    }
}
