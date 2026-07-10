import AtollExtensionKit
import Foundation
import Network
import OSLog
import ZoidCoachCore

public struct AtollCommandCenterDocumentBuilder: Sendable {
    public init() {}

    public func html(loopbackPort: UInt16, presentationCapability: String) -> String {
        let base = "http://127.0.0.1:\(loopbackPort)/v1/command-center"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        :root{color-scheme:light;--ink:#0d0a0a;--paper:#fff;--soft:#fafafa;--mist:#f5f5f5;--muted:#545554;--rule:#d8d8d8;--pale:#ededed;--seal:#c23a2e;--seal-deep:#8f211a;--seal-wash:#f5e5e3;--ok:#2f3a2f}*{box-sizing:border-box}html,body{width:100%;height:100%;margin:0;background:var(--paper)}body{padding:16px;font:14px "Times New Roman",Baskerville,Georgia,serif;color:var(--ink);overflow:hidden;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}.shell{height:100%;min-height:0;display:flex;flex-direction:column;animation:open .2s cubic-bezier(.16,1,.3,1)}@keyframes open{from{opacity:0}to{opacity:1}}@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation-duration:.01ms!important;transition-duration:.01ms!important}}.top{display:flex;align-items:center;justify-content:space-between;flex:none;padding:3px 0 12px;border-bottom:1px solid var(--rule);margin-bottom:12px}.brand{font-size:12px;font-weight:600;letter-spacing:.14em}.live{color:var(--ok);font-size:11px;letter-spacing:.1em}.tabs{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:0;flex:none;margin-bottom:12px;border:1px solid var(--rule)}.tab,.btn{min-width:0;min-height:36px;border:0;border-right:1px solid var(--rule);border-radius:0;background:var(--paper);color:var(--ink);font:600 11px "Times New Roman",Baskerville,Georgia,serif;letter-spacing:.11em;text-transform:uppercase;padding:9px 11px;cursor:pointer;transition:color .15s ease-out,background .15s ease-out,transform .1s ease}.tab:last-child{border-right:0}.tab:hover,.btn:hover{border-color:var(--seal);color:var(--seal)}.tab:active,.btn:active{transform:scale(.985)}.tab:focus-visible,.btn:focus-visible,.editor input:focus-visible,.editor select:focus-visible{outline:2px solid var(--seal);outline-offset:2px}.tab.active{background:var(--ink);color:var(--paper)}.btn.primary{background:var(--ink);border-color:var(--ink);color:var(--paper)}.btn.primary:hover{background:var(--seal);border-color:var(--seal)}.btn:disabled{opacity:.46;cursor:not-allowed;pointer-events:none}.panel{display:none;min-height:0;overflow-y:auto;padding-right:6px;overscroll-behavior:contain;scrollbar-gutter:stable;scrollbar-color:#b8b8b8 transparent}.panel.active{display:block;flex:1}.panel::-webkit-scrollbar{width:8px}.panel::-webkit-scrollbar-thumb{border-radius:999px;background:#b8b8b8}.hero,.card{border:1px solid var(--rule);border-radius:0;background:var(--paper);padding:13px;margin-bottom:9px}.hero{background:var(--mist);border-top:3px solid var(--ink)}.eyebrow{color:var(--seal);font-size:10px;font-weight:600;letter-spacing:.13em;text-transform:uppercase;margin-bottom:6px}.title{font-size:19px;font-weight:400;line-height:1.22}.copy{color:var(--muted);font-size:13px;line-height:1.42;margin-top:5px}.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:0;margin:9px 0;border:1px solid var(--rule)}.metric{min-width:0;border-right:1px solid var(--rule);padding:10px}.metric:last-child{border-right:0}.metric b{display:block;font-size:18px;font-weight:400}.metric span{color:var(--muted);font-size:10px;letter-spacing:.1em}.task-head,.row{display:flex;align-items:flex-start;justify-content:space-between;gap:10px}.task-title{font-size:14px;font-weight:600;line-height:1.3}.meta{color:var(--muted);font-size:11px;margin-top:4px}.actions{display:flex;flex-wrap:wrap;gap:6px;margin-top:9px}.btn{border:1px solid var(--rule);padding:8px 10px}.btn.danger{color:var(--seal-deep);background:var(--seal-wash);border-color:var(--seal)}.btn.danger:hover{color:var(--paper);background:var(--seal)}.status{min-height:18px;flex:none;color:var(--muted);font-size:11px;padding-top:6px}.pill{border:1px solid var(--rule);border-radius:0;padding:4px 7px;color:var(--muted);font-size:10px;letter-spacing:.08em;text-transform:uppercase;white-space:nowrap}.empty{color:var(--muted);padding:20px;text-align:center;background:var(--mist);border:1px solid var(--rule)}.editor{display:grid;grid-template-columns:1fr 1fr;gap:7px;margin-top:10px}.editor input,.editor select{min-width:0;border:1px solid var(--rule);border-radius:0;background:var(--paper);color:var(--ink);padding:10px;font:13px "Times New Roman",Baskerville,Georgia,serif}.editor .wide{grid-column:1/-1}.confirm{flex:none;padding:12px;margin-top:9px;background:var(--mist);border:1px solid var(--ink)}.confirm[hidden]{display:none}
        body{padding:8px 16px}.shell{position:relative}.tabs{margin-bottom:4px}.tab{min-height:26px;padding:5px 8px}.hero{padding:5px 8px;margin-bottom:7px}.hero .eyebrow{margin-bottom:2px}.hero .title{font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.hero .copy{display:none}.status{position:absolute;right:6px;bottom:2px;min-height:0;padding:2px 4px;margin:0;background:rgba(255,255,255,.92);z-index:2;pointer-events:none}@media(min-width:800px){#today.active{display:grid;grid-template-columns:minmax(0,1.45fr) minmax(0,1fr) auto;gap:6px;align-items:stretch}#today>.hero{grid-column:1;margin:0}#today>.metrics{grid-column:2;margin:0}#today>.actions{grid-column:3;margin:0;flex-wrap:nowrap;align-items:stretch}#today>.actions .btn{white-space:nowrap}#today>.card,#today>.eyebrow,#today>.empty{grid-column:1/-1}#today .metric{padding:4px 6px}#today .metric b{font-size:14px}#today .metric span{font-size:8px}#system.active{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px}#system .card{margin:0}}
        </style></head><body><div class="shell"><div class="tabs"><button class="tab active" data-tab="today">TODAY</button><button class="tab" data-tab="decisions">DECISIONS</button><button class="tab" data-tab="system">SYSTEM</button></div><section id="today" class="panel active"></section><section id="decisions" class="panel"></section><section id="system" class="panel"></section><div id="confirm" class="confirm" hidden><div class="eyebrow">Confirm action</div><div id="confirm-copy" class="copy"></div><div class="actions"><button id="confirm-cancel" class="btn">Cancel</button><button id="confirm-apply" class="btn primary">Confirm</button></div></div><div id="status" class="status"></div></div>
        <script>
        const base='\(base)',cap='\(escapeJavaScript(presentationCapability))',status=document.querySelector('#status'),confirmBox=document.querySelector('#confirm'),confirmCopy=document.querySelector('#confirm-copy');let state=null,pendingPath=null,scrollingUntil=0;
        const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
        const enc=v=>encodeURIComponent(String(v));
        async function api(path,method='GET'){status.textContent=method==='GET'?'Refreshing…':'Saving…';const join=path.includes('?')?'&':'?';const response=await fetch(base+path+join+'capability='+encodeURIComponent(cap),{method,cache:'no-store',credentials:'omit'});if(!response.ok)throw new Error(await response.text());const value=await response.json();status.textContent='';return value}
        function controls(task,observe){const map={ready:[['start','Start']],active:[['pause','Pause'],['complete','Complete']],paused:[['resume','Resume'],['complete','Complete']],blocked:[['resume','Unblock'],['reschedule','Reschedule']]};return (map[task.state]||[]).map(([cmd,label])=>`<button class="btn ${cmd==='start'?'primary':''}" data-task="${esc(task.taskID)}" data-command="${cmd}" ${observe&&cmd==='complete'?'disabled title="Observe mode does not change Reminders"':''}>${label}</button>`).join('')}
        function renderToday(){const s=state.snapshot,tasks=s.taskRows||[],inbox=s.unplannedReminders||[],b=s.behavior,g=s.gaming,observe=state.policy.operatingMode==='observe';document.querySelector('#today').innerHTML=`<div class="hero"><div class="eyebrow">Next responsible action</div><div class="title">${esc(s.recommendation.sentence)}</div><div class="copy">${esc(s.mainObjective||'No main objective selected')}</div></div><div class="metrics"><div class="metric"><b>${b.workMinutes}m</b><span>WORK</span></div><div class="metric"><b>${b.gamingMinutes}m</b><span>GAMING</span></div><div class="metric"><b>${b.distractingMinutes}m</b><span>DISTRACTING</span></div><div class="metric"><b>${g.unlockedRemainingMinutes}m</b><span>AVAILABLE</span></div></div><div class="actions"><button class="btn" data-action="draft-plan">Draft plan</button><button class="btn" data-action="schedule-plan" ${observe?'disabled title="Observe mode does not reserve Calendar blocks"':''}>Reserve plan</button></div>${tasks.length?tasks.map(t=>`<div class="card"><div class="task-head"><div><div class="task-title">${esc(t.title)}</div><div class="meta">${t.estimateMinutes}m · ${esc(t.urgency)} · ${t.elapsedMinutes}m elapsed</div></div><span class="pill">${esc(t.state)}</span></div><div class="actions">${controls(t,observe)}<button class="btn" data-task="${esc(t.taskID)}" data-command="block">Block</button><button class="btn" data-task="${esc(t.taskID)}" data-command="reschedule">Reschedule</button></div></div>`).join(''):'<div class="empty">No planned tasks yet.</div>'}${inbox.length?`<div class="eyebrow">Unplanned reminders</div>`+inbox.slice(0,6).map(r=>`<div class="card row"><div><div class="task-title">${esc(r.title)}</div><div class="meta">${esc(r.listName||'Reminders')}</div></div><button class="btn" data-task="${esc(r.reminderID)}" data-command="complete" ${observe?'disabled title="Observe mode does not change Reminders"':''}>Complete</button></div>`).join(''):''}`}
        function localInput(value){if(!value)return'';const d=new Date(value),p=n=>String(n).padStart(2,'0');return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`}
        function meetingEditor(p,observe){const id=esc(p.payload.candidateID),start=localInput(p.payload.start),duration=esc(p.payload.durationMinutes||'30');return `<div class="editor" data-editor="${id}"><input class="wide" name="title" value="${esc(p.payload.title||p.title)}"><input name="start" type="datetime-local" value="${start}"><input name="duration" type="number" min="5" step="5" value="${duration}"><select class="wide" name="destination"><option value="calendar">Calendar</option><option value="reminder">Reminder</option></select><button class="btn primary wide" data-save-meeting="${id}" ${observe?'disabled title="Observe mode does not add meetings"':''}>Save meeting</button></div>`}
        function renderDecisions(){const prompts=state.prompts||[],observe=state.policy.operatingMode==='observe',writes=new Set(['accept_plan','undo_plan_change','add_meeting']);document.querySelector('#decisions').innerHTML=prompts.length?prompts.map(p=>`<div class="card"><div class="eyebrow">${esc(p.type.replaceAll('_',' '))}</div><div class="title">${esc(p.title)}</div><div class="copy">${esc(p.summary)}</div><div class="actions">${p.actions.filter(a=>!(p.type==='MEETING_CANDIDATE'&&a.kind==='edit_meeting')).map(a=>`<button class="btn ${a.role==='primary'?'primary':''}" data-prompt="${esc(p.id)}" data-prompt-action="${esc(a.kind)}" ${observe&&writes.has(a.kind)?'disabled title="Observe mode does not change Apple data"':''}>${esc(a.title)}</button>`).join('')}</div>${p.type==='MEETING_CANDIDATE'?meetingEditor(p,observe):''}</div>`).join(''):'<div class="empty">No decisions need attention.</div>'}
        function renderSystem(){const s=state.snapshot,sources=s.sources||[],p=state.policy;document.querySelector('#system').innerHTML=`<div class="card"><div class="eyebrow">Automation</div><div class="task-head"><div><div class="title">${p.automationPause.isPaused?'Paused':'Running'}</div><div class="copy">${esc(p.operatingMode)} · ${esc(s.timeZoneIdentifier)}</div></div><button class="btn ${p.automationPause.isPaused?'primary':'danger'}" data-automation="${p.automationPause.isPaused?'resume':'pause'}">${p.automationPause.isPaused?'Resume':'Pause'}</button></div></div><div class="card"><div class="eyebrow">Gaming budget</div><div class="title">${s.gaming.unlockedRemainingMinutes} minutes available</div><div class="copy">${esc(s.gaming.nextUnlockReason)}</div></div>${sources.map(x=>`<div class="card row"><div><div class="task-title">${esc(x.sourceID)}</div><div class="meta">${esc(x.detail)}</div></div><span class="pill">${esc(x.state)}</span></div>`).join('')}`}
        function render(){const pos={};document.querySelectorAll('.panel').forEach(p=>pos[p.id]=p.scrollTop);renderToday();renderDecisions();renderSystem();bind();requestAnimationFrame(()=>document.querySelectorAll('.panel').forEach(p=>p.scrollTop=pos[p.id]||0))}
        async function refresh(){if(Date.now()<scrollingUntil)return;try{state=await api('/state');render()}catch(e){status.textContent='Command center unavailable'} }
        async function mutate(path,question){if(question){pendingPath=path;confirmCopy.textContent=question;confirmBox.hidden=false;return}try{const next=await api(path,'POST');if(next.snapshot){state=next;render()}else{status.textContent='Applied. Refreshing state…';await refresh()}}catch(e){status.textContent='Could not apply action'} }
        function bind(){document.querySelectorAll('.panel').forEach(p=>p.onscroll=()=>scrollingUntil=Date.now()+900);document.querySelectorAll('[data-task]').forEach(b=>b.onclick=()=>mutate('/tasks/'+enc(b.dataset.task)+'/'+b.dataset.command));document.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>mutate('/actions/'+b.dataset.action,b.dataset.action==='draft-plan'?'Replace today’s draft plan?':'Reserve this plan in Calendar and Reminders?'));document.querySelectorAll('[data-prompt]').forEach(b=>b.onclick=()=>mutate('/prompts/'+enc(b.dataset.prompt)+'/'+b.dataset.promptAction));document.querySelectorAll('[data-automation]').forEach(b=>b.onclick=()=>mutate('/automation/'+b.dataset.automation));document.querySelectorAll('[data-save-meeting]').forEach(b=>b.onclick=()=>{const e=b.closest('.editor'),local=e.querySelector('[name=start]').value,q=new URLSearchParams({title:e.querySelector('[name=title]').value,start:local?new Date(local).toISOString():'',duration:e.querySelector('[name=duration]').value,destination:e.querySelector('[name=destination]').value});mutate('/meetings/'+enc(b.dataset.saveMeeting)+'/save?'+q,'Add this meeting without opening Zoid Coach?')})}
        document.querySelector('#confirm-cancel').onclick=()=>{pendingPath=null;confirmBox.hidden=true};document.querySelector('#confirm-apply').onclick=()=>{const path=pendingPath;pendingPath=null;confirmBox.hidden=true;if(path)mutate(path)};document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{document.querySelectorAll('.tab,.panel').forEach(x=>x.classList.remove('active'));b.classList.add('active');document.querySelector('#'+b.dataset.tab).classList.add('active')});refresh();setInterval(refresh,5000);
        </script></body></html>
        """
    }

    private func escapeJavaScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
}

public struct AtollCommandCenterState: Codable, Equatable, Sendable {
    public let snapshot: TodaySnapshot
    public let prompts: [PromptEpisode]
    public let policy: UserPolicy

    public init(snapshot: TodaySnapshot, prompts: [PromptEpisode], policy: UserPolicy) {
        self.snapshot = snapshot
        self.prompts = prompts
        self.policy = policy
    }
}

public struct AtollCommandCenterHTTPResponse: Equatable, Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public struct AtollCommandCenterDependencies: @unchecked Sendable {
    public let snapshot: @Sendable () throws -> TodaySnapshot
    public let prompts: @Sendable () throws -> [PromptEpisode]
    public let policy: @Sendable () throws -> UserPolicy
    public let applyTask: @Sendable (TaskActivityCommand, String) throws -> TodaySnapshot
    public let respondToPrompt: @Sendable (String, PromptActionKind) throws -> Void
    public let applyMutation: @Sendable (AgentMutationCommand) async throws -> AgentMutationReceipt

    public init(
        snapshot: @escaping @Sendable () throws -> TodaySnapshot,
        prompts: @escaping @Sendable () throws -> [PromptEpisode],
        policy: @escaping @Sendable () throws -> UserPolicy,
        applyTask: @escaping @Sendable (TaskActivityCommand, String) throws -> TodaySnapshot,
        respondToPrompt: @escaping @Sendable (String, PromptActionKind) throws -> Void,
        applyMutation: @escaping @Sendable (AgentMutationCommand) async throws -> AgentMutationReceipt
    ) {
        self.snapshot = snapshot
        self.prompts = prompts
        self.policy = policy
        self.applyTask = applyTask
        self.respondToPrompt = respondToPrompt
        self.applyMutation = applyMutation
    }
}

public actor AtollCommandCenterController {
    private let dependencies: AtollCommandCenterDependencies
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }()

    public init(dependencies: AtollCommandCenterDependencies) {
        self.dependencies = dependencies
    }

    public func handle(method: String, path: [String], query: [String: String]) async -> AtollCommandCenterHTTPResponse {
        do {
            var snapshotOverride: TodaySnapshot?
            guard path.count >= 3, path[0] == "v1", path[1] == "command-center" else {
                return error(status: 404, message: "Not found")
            }
            if method == "GET", path == ["v1", "command-center", "state"] {
                return try stateResponse()
            }
            guard method == "POST" else { return error(status: 405, message: "Method not allowed") }
            let route = Array(path.dropFirst(2))
            if route.count == 3, route[0] == "tasks" {
                let taskID = route[1]
                let rawCommand = route[2]
                guard let command = TaskActivityCommand(rawValue: rawCommand) else {
                    return error(status: 400, message: "Unknown task command")
                }
                if command == .complete, try isObserveMode() { return observeModeError() }
                snapshotOverride = try dependencies.applyTask(command, taskID)
            } else if route.count == 3, route[0] == "prompts" {
                let promptID = route[1]
                let rawAction = route[2]
                guard let action = PromptActionKind(rawValue: rawAction) else {
                    return error(status: 400, message: "Unknown prompt action")
                }
                if [.acceptPlan, .undoPlanChange, .addMeeting].contains(action), try isObserveMode() {
                    return observeModeError()
                }
                try dependencies.respondToPrompt(promptID, action)
            } else if route == ["actions", "draft-plan"] {
                _ = try await dependencies.applyMutation(.draftPlan(day: Date(), overwriteExisting: true))
            } else if route == ["actions", "schedule-plan"] {
                if try isObserveMode() { return observeModeError() }
                _ = try await dependencies.applyMutation(.schedulePlan(day: Date()))
            } else if route.count == 2, route[0] == "automation" {
                let command = route[1]
                guard command == "pause" || command == "resume" else {
                    return error(status: 400, message: "Unknown automation command")
                }
                let current = try dependencies.policy()
                let updated = UserPolicy(
                    schemaVersion: current.schemaVersion,
                    operatingMode: current.operatingMode,
                    automationPause: command == "pause" ? .pausedIndefinitely : .running,
                    schedule: current.schedule,
                    calendar: current.calendar,
                    privacy: current.privacy,
                    wake: current.wake
                )
                _ = try await dependencies.applyMutation(.savePolicy(updated))
            } else if route.count == 3, route[0] == "meetings", route[2] == "save" {
                if try isObserveMode() { return observeModeError() }
                let candidateID = route[1]
                guard let title = query["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                      let rawStart = query["start"], let start = ISO8601DateFormatter().date(from: rawStart),
                      let rawDuration = query["duration"], let duration = Int(rawDuration), duration > 0,
                      let rawDestination = query["destination"], let destination = AgentMeetingDestination(rawValue: rawDestination)
                else { return error(status: 400, message: "Incomplete meeting") }
                _ = try await dependencies.applyMutation(.resolveMeetingCandidate(candidateID: candidateID, title: title, start: start, durationMinutes: duration, destination: destination))
            } else {
                return error(status: 404, message: "Not found")
            }
            do {
                return try stateResponse(snapshotOverride: snapshotOverride)
            } catch {
                return AtollCommandCenterHTTPResponse(status: 202, body: Data("{\"accepted\":true}".utf8))
            }
        } catch {
            return self.error(status: 409, message: error.localizedDescription)
        }
    }

    private func stateResponse(snapshotOverride: TodaySnapshot? = nil) throws -> AtollCommandCenterHTTPResponse {
        AtollCommandCenterHTTPResponse(
            status: 200,
            body: try encoder.encode(AtollCommandCenterState(
                snapshot: try snapshotOverride ?? dependencies.snapshot(),
                prompts: dependencies.prompts(),
                policy: dependencies.policy()
            ))
        )
    }

    private func error(status: Int, message: String) -> AtollCommandCenterHTTPResponse {
        let escaped = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return AtollCommandCenterHTTPResponse(status: status, body: Data("{\"error\":\"\(escaped)\"}".utf8))
    }

    private func isObserveMode() throws -> Bool {
        try dependencies.policy().operatingMode == .observe
    }

    private func observeModeError() -> AtollCommandCenterHTTPResponse {
        error(status: 409, message: "Observe mode does not change Calendar or Reminders")
    }
}

public actor AtollCommandCenterBridge {
    private let logger = Logger(subsystem: "com.ziadnasreldin.ZoidCoach", category: "AtollCommandCenterBridge")
    private let server: AtollPromptLoopbackServer
    private let documentBuilder: AtollCommandCenterDocumentBuilder
    private let bundleIdentifier: String
    private let rpcClient: any AtollNotchExperiencePresenting

    public init(
        promptActionHandler: AtollPromptActionHandler,
        controller: AtollCommandCenterController,
        documentBuilder: AtollCommandCenterDocumentBuilder = AtollCommandCenterDocumentBuilder(),
        rpcClient: any AtollNotchExperiencePresenting = AtollRPCClient(),
        bundleIdentifier: String = "com.ziadnasreldin.ZoidCoach"
    ) {
        server = AtollPromptLoopbackServer(handler: promptActionHandler, commandCenterController: controller)
        self.documentBuilder = documentBuilder
        self.rpcClient = rpcClient
        self.bundleIdentifier = bundleIdentifier
    }

    public func present() async throws {
        logger.info("Starting command center loopback server")
        let port = try await server.start()
        let capability = UUID().uuidString
        server.authorizeCommandCenter(presentationCapability: capability)
        let html = documentBuilder.html(loopbackPort: port, presentationCapability: capability)
        let descriptor = AtollNotchExperienceDescriptor(
            id: "zoid-coach.command-center",
            bundleIdentifier: bundleIdentifier,
            priority: .normal,
            accentColor: AtollColorDescriptor(red: 194.0 / 255.0, green: 58.0 / 255.0, blue: 46.0 / 255.0),
            metadata: [
                "surface": "command-center",
                "version": "2",
                // The custom Atoll host reads these backwards-compatible metadata hints.
                // Stock Atoll safely ignores them and keeps its compact extension sizing.
                "preferredWidth": "1400",
                "preferredHeight": "650"
            ],
            tab: .init(
                title: "Zoid Coach",
                iconSymbolName: "checkmark.circle.fill",
                preferredHeight: 420,
                sections: [],
                webContent: AtollWidgetWebContentDescriptor(
                    html: html,
                    preferredHeight: 420,
                    isTransparent: false,
                    allowLocalhostRequests: true,
                    allowRemoteRequests: false,
                    maximumContentWidth: nil
                ),
                allowWebInteraction: true
            )
        )
        logger.info("Presenting command center descriptor to A-Toll")
        try await rpcClient.presentNotchExperience(descriptor)
        logger.info("A-Toll accepted command center descriptor")
    }
}
