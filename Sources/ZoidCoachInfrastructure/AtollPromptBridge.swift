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
        return result.wasApplied ? .applied(effect) : .replayed
    }
}

public struct AtollPromptDescriptorBuilder: Sendable {
    public let bundleIdentifier: String

    public init(bundleIdentifier: String = "com.ziadnasreldin.ZoidCoach") {
        self.bundleIdentifier = bundleIdentifier
    }

    public func descriptor(for episode: PromptEpisode, loopbackPort: UInt16) -> AtollNotchExperienceDescriptor {
        let webContent = AtollWidgetWebContentDescriptor(
            html: html(for: episode, loopbackPort: loopbackPort),
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

    public func html(for episode: PromptEpisode, loopbackPort: UInt16) -> String {
        let buttons = episode.actions.map { action in
            let token = PromptResponseToken.make(promptID: episode.id, action: action.kind)
            let endpoint = endpointURL(
                promptID: episode.id,
                action: action.kind,
                actionToken: token,
                loopbackPort: loopbackPort
            ).absoluteString
            let cssClass = action.role == .primary ? "primary" : action.role == .destructive ? "destructive" : "secondary"
            return "<button class=\"\(cssClass)\" data-endpoint=\"\(escapeHTML(endpoint))\">\(escapeHTML(action.title))</button>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        :root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;padding:10px;font:13px -apple-system,BlinkMacSystemFont,sans-serif;color:#fff;background:transparent}.title{font-size:15px;font-weight:700;margin-bottom:5px}.summary{color:rgba(255,255,255,.72);line-height:1.35;margin-bottom:12px}.actions{display:flex;gap:8px;flex-wrap:wrap}button{border:1px solid rgba(255,255,255,.18);border-radius:10px;padding:8px 12px;color:#fff;background:rgba(255,255,255,.10);font:600 12px -apple-system;cursor:pointer}button.primary{background:#c23a2e;border-color:#df665a}button.destructive{color:#ffaaa3}button:disabled{opacity:.45;cursor:default}.status{min-height:18px;margin-top:9px;color:rgba(255,255,255,.68)}
        </style></head><body><div class="title">\(escapeHTML(episode.title))</div><div class="summary">\(escapeHTML(episode.summary))</div><div class="actions">\(buttons)</div><div class="status" role="status" aria-live="polite"></div>
        <script>
        const status=document.querySelector('.status');document.querySelectorAll('button').forEach(button=>button.addEventListener('click',async()=>{document.querySelectorAll('button').forEach(item=>item.disabled=true);status.textContent='Saving...';try{const response=await fetch(button.dataset.endpoint,{method:'POST',cache:'no-store',credentials:'omit'});if(!response.ok)throw new Error('rejected');status.textContent='Saved';}catch(error){document.querySelectorAll('button').forEach(item=>item.disabled=false);status.textContent='Could not save. Use Zoid Coach or the notification.';}}));
        </script></body></html>
        """
    }

    public func endpointURL(
        promptID: String,
        action: PromptActionKind,
        actionToken: String,
        loopbackPort: UInt16
    ) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(loopbackPort)
        components.path = "/v1/prompts/\(promptID)/actions/\(action.rawValue)"
        components.queryItems = [URLQueryItem(name: "token", value: actionToken)]
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
    private let queue = DispatchQueue(label: "com.ziadnasreldin.ZoidCoach.atoll-loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var readyPort: UInt16?

    public init(handler: AtollPromptActionHandler) {
        self.handler = handler
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
        guard parts[0] == "POST",
              let components = URLComponents(string: "http://127.0.0.1\(parts[1])")
        else {
            send(status: 405, body: "method not allowed", on: connection)
            return
        }
        let path = components.path.split(separator: "/").map(String.init)
        guard path.count == 5,
              path[0] == "v1",
              path[1] == "prompts",
              path[3] == "actions",
              let action = PromptActionKind(rawValue: path[4]),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value
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

    private func send(status: Int, body: String, on connection: NWConnection) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 409: reason = "Conflict"
        case 413: reason = "Content Too Large"
        default: reason = "Error"
        }
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
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

    public init(
        promptStore: PromptInboxStore,
        effectRouter: PromptResponseEffectRouter,
        descriptorBuilder: AtollPromptDescriptorBuilder = AtollPromptDescriptorBuilder()
    ) {
        self.promptStore = promptStore
        server = AtollPromptLoopbackServer(
            handler: AtollPromptActionHandler(promptStore: promptStore, effectRouter: effectRouter)
        )
        self.descriptorBuilder = descriptorBuilder
    }

    public func present(_ episode: PromptEpisode) async throws {
        let port = try await server.start()
        let descriptor = descriptorBuilder.descriptor(for: episode, loopbackPort: port)
        try await AtollClient.shared.presentNotchExperience(descriptor)
        _ = try promptStore.present(promptID: episode.id)
    }
}
