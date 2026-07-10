import AtollExtensionKit
import Foundation
import Network
import ZoidCoachCore

public enum AtollPromptActionOutcome: Equatable, Sendable {
    case applied(PromptResponseEffect)
    case replayed
}

public final class AtollPromptActionHandler: @unchecked Sendable {
    private let promptStore: PromptInboxStore
    private let effectRouter: PromptResponseEffectRouter

    public init(promptStore: PromptInboxStore, effectRouter: PromptResponseEffectRouter) {
        self.promptStore = promptStore
        self.effectRouter = effectRouter
    }

    public func respond(promptID: String, action: PromptActionKind, actionToken: String) throws -> AtollPromptActionOutcome {
        let result = try promptStore.respond(
            promptID: promptID,
            action: action,
            actionToken: actionToken,
            surface: .atoll
        )
        let effect = try effectRouter.apply(result)
        try promptStore.markEffectApplied(responseID: result.response.id)
        return result.wasApplied ? .applied(effect) : .replayed
    }
}

public struct AtollPromptDescriptorBuilder: Sendable {
    public let bundleIdentifier: String

    public init(bundleIdentifier: String = "com.ziadnasreldin.ZoidCoach") {
        self.bundleIdentifier = bundleIdentifier
    }

    public func descriptor(
        for episode: PromptEpisode,
        loopbackPort: UInt16,
        presentationCapability: String
    ) -> AtollNotchExperienceDescriptor {
        let webContent = AtollWidgetWebContentDescriptor(
            html: html(
                for: episode,
                loopbackPort: loopbackPort,
                presentationCapability: presentationCapability
            ),
            preferredHeight: 168,
            isTransparent: true,
            allowLocalhostRequests: true,
            allowRemoteRequests: false,
            maximumContentWidth: 480
        )
        return AtollNotchExperienceDescriptor(
            id: "zoid-coach.prompt.\(episode.id)",
            bundleIdentifier: bundleIdentifier,
            priority: .high,
            accentColor: AtollColorDescriptor(
                red: 194.0 / 255.0,
                green: 58.0 / 255.0,
                blue: 46.0 / 255.0
            ),
            metadata: [
                "promptID": episode.id,
                "decisionKey": episode.decisionKey,
                "promptType": episode.type
            ],
            tab: .init(
                title: "Zoid Coach",
                iconSymbolName: "sparkles",
                preferredHeight: 260,
                sections: [],
                webContent: webContent,
                allowWebInteraction: true,
                footnote: "This decision stays available in Zoid Coach and notifications."
            ),
            durationHint: episode.expiresAt.map { max(1, $0.timeIntervalSinceNow) }
        )
    }

    public func html(
        for episode: PromptEpisode,
        loopbackPort: UInt16,
        presentationCapability: String
    ) -> String {
        let question: String = switch episode.type {
        case "MEETING_CANDIDATE": "Would you like me to add it to your calendar?"
        case "PLAN_READY": "Would you like me to reserve this plan?"
        case "PLAN_CHANGED": "Would you like to keep these changes?"
        default: "What would you like me to do?"
        }
        let buttons = episode.actions.map { action in
            let token = PromptResponseToken.make(promptID: episode.id, action: action.kind)
            let endpoint = endpointURL(
                promptID: episode.id,
                action: action.kind,
                actionToken: token,
                loopbackPort: loopbackPort,
                presentationCapability: presentationCapability
            ).absoluteString
            let cssClass = action.role == .primary ? "primary" : action.role == .destructive ? "destructive" : "secondary"
            return "<button class=\"\(cssClass)\" data-endpoint=\"\(escapeHTML(endpoint))\">\(escapeHTML(action.title))</button>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        :root{color-scheme:light;--ink:#0d0a0a;--paper:#fff;--soft:#fafafa;--mist:#f5f5f5;--muted:#545554;--rule:#e0e0e0;--seal:#c23a2e;--seal-deep:#8f211a;--seal-wash:#f5e5e3}*{box-sizing:border-box}body{margin:0;padding:12px;font:13px "Times New Roman",Baskerville,Georgia,serif;color:var(--ink);background:var(--paper);animation:open .2s cubic-bezier(.16,1,.3,1)}@keyframes open{from{opacity:0;transform:translateY(-5px)}to{opacity:1;transform:none}}@media(prefers-reduced-motion:reduce){body{animation:none}}.title{font-size:17px;font-weight:400;line-height:1.15;padding-bottom:7px;border-bottom:1px solid var(--rule)}.summary{color:var(--muted);line-height:1.4;margin:8px 0;max-height:54px;overflow:hidden}.question{font-size:12px;font-weight:600;letter-spacing:.04em;line-height:1.35;margin-bottom:12px}.actions{display:flex;gap:7px;flex-wrap:wrap}button{border:1px solid var(--rule);border-radius:0;padding:8px 11px;color:var(--ink);background:var(--paper);font:600 10px "Times New Roman",Baskerville,Georgia,serif;letter-spacing:.1em;text-transform:uppercase;cursor:pointer}button:hover{border-color:var(--ink)}button:focus-visible{outline:1px solid var(--seal);outline-offset:2px}button.primary{color:var(--paper);background:var(--ink);border-color:var(--ink)}button.primary:hover{background:var(--seal);border-color:var(--seal)}button.destructive{color:var(--seal-deep);background:var(--seal-wash);border-color:var(--seal)}button.destructive:hover{color:var(--paper);background:var(--seal)}button:disabled{color:var(--muted);background:var(--mist);border-color:var(--rule);cursor:default}.status{min-height:18px;margin-top:9px;color:var(--muted);font-size:10px}
        </style></head><body><div class="title">\(escapeHTML(episode.title))</div><div class="summary">\(escapeHTML(episode.summary))</div><div class="question">\(escapeHTML(question))</div><div class="actions">\(buttons)</div><div class="status" role="status" aria-live="polite"></div>
        <script>
        const status=document.querySelector('.status');document.querySelectorAll('button').forEach(button=>button.addEventListener('click',async()=>{document.querySelectorAll('button').forEach(item=>item.disabled=true);status.textContent='Saving...';try{const response=await fetch(button.dataset.endpoint,{method:'POST',cache:'no-store',credentials:'omit'});if(!response.ok)throw new Error('rejected');status.textContent='Saved';}catch(error){document.querySelectorAll('button').forEach(item=>item.disabled=false);status.textContent='Could not save. Use Zoid Coach or the notification.';}}));
        </script></body></html>
        """
    }

    public func endpointURL(
        promptID: String,
        action: PromptActionKind,
        actionToken: String,
        loopbackPort: UInt16,
        presentationCapability: String
    ) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(loopbackPort)
        components.path = "/v1/prompts/\(promptID)/actions/\(action.rawValue)"
        components.queryItems = [
            URLQueryItem(name: "token", value: actionToken),
            URLQueryItem(name: "capability", value: presentationCapability),
        ]
        return components.url!
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

public final class AtollPromptLoopbackServer: @unchecked Sendable {
    private let handler: AtollPromptActionHandler
    private let commandCenterController: AtollCommandCenterController?
    private let queue = DispatchQueue(label: "com.ziadnasreldin.ZoidCoach.atoll-loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var readyPort: UInt16?
    private var presentationCapabilities: [String: (value: String, expiresAt: Date)] = [:]
    private var commandCenterCapability: (value: String, expiresAt: Date)?

    public init(handler: AtollPromptActionHandler, commandCenterController: AtollCommandCenterController? = nil) {
        self.handler = handler
        self.commandCenterController = commandCenterController
    }

    public func authorizeCommandCenter(presentationCapability: String, lifetime: TimeInterval = 30 * 60) {
        lock.withLock {
            commandCenterCapability = (presentationCapability, Date().addingTimeInterval(lifetime))
        }
    }

    public func authorize(promptID: String, presentationCapability: String, lifetime: TimeInterval = 10 * 60) {
        lock.withLock {
            presentationCapabilities[promptID] = (presentationCapability, Date().addingTimeInterval(lifetime))
        }
    }

    deinit { stop() }

    public func start() async throws -> UInt16 {
        if let port = lock.withLock({ readyPort }) { return port }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let newListener = try NWListener(using: parameters)
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { listener = newListener }
            let resumeGate = AtollPromptContinuationGate()
            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = newListener?.port?.rawValue else { return }
                    guard resumeGate.claim() else { return }
                    self.lock.withLock { self.readyPort = port }
                    continuation.resume(returning: port)
                case let .failed(error):
                    if resumeGate.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if resumeGate.claim() { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.receiveRequest(on: connection, accumulated: Data())
            }
            newListener.start(queue: queue)
        }
    }

    public func stop() {
        let current = lock.withLock { () -> NWListener? in
            let value = listener
            listener = nil
            readyPort = nil
            presentationCapabilities.removeAll()
            commandCenterCapability = nil
            return value
        }
        current?.cancel()
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.start(queue: queue)
        receiveMore(on: connection, accumulated: accumulated)
    }

    private func receiveMore(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var request = accumulated
            if let data { request.append(data) }
            if request.count > 16_384 {
                self.send(status: 413, body: "request too large", on: connection)
            } else if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.handle(request, on: connection)
            } else if isComplete || error != nil {
                self.send(status: 400, body: "invalid request", on: connection)
            } else {
                self.receiveMore(on: connection, accumulated: request)
            }
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first
        else {
            send(status: 400, body: "invalid request", on: connection)
            return
        }
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else {
            send(status: 400, body: "invalid request", on: connection)
            return
        }
        if parts[0] == "OPTIONS" {
            send(status: 204, body: "", on: connection)
            return
        }
        guard let components = URLComponents(string: "http://127.0.0.1\(parts[1])")
        else {
            send(status: 400, body: "invalid request", on: connection)
            return
        }
        let path = components.path.split(separator: "/").map(String.init)
        if path.count >= 3, path[0] == "v1", path[1] == "command-center", let commandCenterController {
            guard requestOriginIsAllowed(request), let query = uniqueQuery(components.queryItems),
                  let capability = query["capability"], commandCenterCapabilityIsValid(capability)
            else {
                send(status: 404, body: "not found", on: connection)
                return
            }
            Task {
                let response = await commandCenterController.handle(method: parts[0], path: path, query: query)
                self.send(status: response.status, body: String(decoding: response.body, as: UTF8.self), on: connection)
            }
            return
        }
        guard parts[0] == "POST" else {
            send(status: 405, body: "method not allowed", on: connection)
            return
        }
        guard path.count == 5,
              path[0] == "v1",
              path[1] == "prompts",
              path[3] == "actions",
              let action = PromptActionKind(rawValue: path[4]),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              let presentationCapability = components.queryItems?.first(where: { $0.name == "capability" })?.value,
              promptCapabilityIsValid(presentationCapability, promptID: path[2])
        else {
            send(status: 404, body: "not found", on: connection)
            return
        }
        do {
            let outcome = try handler.respond(promptID: path[2], action: action, actionToken: token)
            let body = outcome == .replayed ? "{\"status\":\"already_applied\"}" : "{\"status\":\"applied\"}"
            send(status: 200, body: body, on: connection)
        } catch {
            send(status: 409, body: "{\"status\":\"rejected\"}", on: connection)
        }
    }

    private func uniqueQuery(_ items: [URLQueryItem]?) -> [String: String]? {
        var result: [String: String] = [:]
        for item in items ?? [] {
            guard result[item.name] == nil, let value = item.value else { return nil }
            result[item.name] = value
        }
        return result
    }

    private func requestOriginIsAllowed(_ request: String) -> Bool {
        let origin = request.components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("origin:") }?
            .dropFirst("origin:".count)
            .trimmingCharacters(in: .whitespaces)
        return origin == nil || origin == "null"
    }

    private func commandCenterCapabilityIsValid(_ candidate: String) -> Bool {
        lock.withLock {
            guard let capability = commandCenterCapability,
                  capability.expiresAt > Date(), capability.value == candidate
            else { return false }
            return true
        }
    }

    private func promptCapabilityIsValid(_ candidate: String, promptID: String) -> Bool {
        lock.withLock {
            guard let capability = presentationCapabilities[promptID] else { return false }
            guard capability.expiresAt > Date() else {
                presentationCapabilities.removeValue(forKey: promptID)
                return false
            }
            return capability.value == candidate
        }
    }

    private func send(status: Int, body: String, on connection: NWConnection) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 409: reason = "Conflict"
        case 413: reason = "Content Too Large"
        default: reason = "Error"
        }
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: null\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nVary: Origin\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

private final class AtollPromptContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}

public actor AtollPromptBridge {
    private let promptStore: PromptInboxStore
    private let server: AtollPromptLoopbackServer
    private let descriptorBuilder: AtollPromptDescriptorBuilder
    private let rpcClient: AtollRPCClient

    public init(
        promptStore: PromptInboxStore,
        effectRouter: PromptResponseEffectRouter,
        descriptorBuilder: AtollPromptDescriptorBuilder = AtollPromptDescriptorBuilder(),
        rpcClient: AtollRPCClient = AtollRPCClient()
    ) {
        self.promptStore = promptStore
        server = AtollPromptLoopbackServer(
            handler: AtollPromptActionHandler(promptStore: promptStore, effectRouter: effectRouter)
        )
        self.descriptorBuilder = descriptorBuilder
        self.rpcClient = rpcClient
    }

    public func present(_ episode: PromptEpisode) async throws {
        let port = try await server.start()
        let presentationCapability = UUID().uuidString
        server.authorize(promptID: episode.id, presentationCapability: presentationCapability)
        let descriptor = descriptorBuilder.descriptor(
            for: episode,
            loopbackPort: port,
            presentationCapability: presentationCapability
        )
        try await rpcClient.presentNotchExperience(descriptor)
        _ = try promptStore.present(promptID: episode.id)
    }

    public func stop() {
        server.stop()
    }
}
