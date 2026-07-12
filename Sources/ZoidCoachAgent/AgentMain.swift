import Darwin
import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

@main
struct ZoidCoachAgentMain {
    static func main() async {
        var activeRuntimeEnvironment: RuntimeEnvironment?
        let databaseWriteCircuitBreaker = DatabaseWriteCircuitBreaker()
        let captureHealthStore = AgentCaptureHealthStore(initial: AgentCaptureHealthSnapshot(
            isEnabled: false,
            isRunning: false,
            screenRecording: .unknown,
            accessibility: .unknown,
            automation: .notRequired,
            detail: "Capture runtime has not started"
        ))
        do {
            let packagedRuntime = try PackagedRuntimeMarker.current()
            let runtimeResolution = try RuntimeEnvironment.resolve(
                arguments: Array(CommandLine.arguments.dropFirst()),
                packagedRuntime: packagedRuntime
            )
            activeRuntimeEnvironment = runtimeResolution.environment
            if runtimeResolution.remainingArguments == ["--print-runtime-identity"] {
                print(Self.runtimeIdentityDescription(runtimeResolution.environment))
                return
            }
            let qaFixtureComposition: AuthorizedQAFixtureOSComposition? = if case .qa = runtimeResolution.environment.mode {
                try QAFixtureOSComposition.makeAuthorizedComposition(
                    runtimeEnvironment: runtimeResolution.environment
                )
            } else {
                nil
            }
            let qaFixtureAdapter = qaFixtureComposition?.adapter
            let fixtureAuthorization = qaFixtureComposition?.authorization
            let configuration = try AgentConfiguration(
                runtimeEnvironment: runtimeResolution.environment,
                arguments: runtimeResolution.remainingArguments
            )
            try AgentOSAdapterBoundary.validate(
                runtimeEnvironment: runtimeResolution.environment,
                operations: AgentOSAdapterBoundary.operations(
                    requestRemindersAccess: configuration.requestRemindersAccess,
                    printRemindersStatus: configuration.printRemindersStatus
                ),
                fixtureAuthorization: fixtureAuthorization,
                fixtureAdapter: qaFixtureAdapter
            )
            let captureConfigurationStore = NativeCaptureConfigurationStore(
                fileURL: runtimeResolution.environment.nativeCaptureConfigurationURL
            )
            let legacyScreenwatchSource: Result<ScreenwatchDirectoryLease, Error> = Result {
                try ScreenwatchSourceRepository(
                    runtimeEnvironment: runtimeResolution.environment
                ).resolveCanonicalSource()
            }
            try FileManager.default.createDirectory(
                at: configuration.nativeCaptureDirectory,
                withIntermediateDirectories: true
            )
            let nativeCaptureSource = try ScreenwatchDirectoryLease(
                rootURL: configuration.nativeCaptureDirectory,
                source: .nativeCapture
            )
            let activeScreenwatchSource: @Sendable () throws -> ScreenwatchDirectoryLease = {
                let mode = try captureConfigurationStore.load().mode
                return mode == .native ? nativeCaptureSource : try legacyScreenwatchSource.get()
            }
            var persistedCaptureConfiguration = try captureConfigurationStore.load()
            if configuration.nativeCapture || !configuration.captureDisplayIDs.isEmpty {
                persistedCaptureConfiguration = NativeCaptureConfiguration(
                    mode: configuration.nativeCapture && persistedCaptureConfiguration.mode == .legacy ? .parity : persistedCaptureConfiguration.mode,
                    configuredDisplayIDs: configuration.captureDisplayIDs.isEmpty
                        ? persistedCaptureConfiguration.configuredDisplayIDs
                        : configuration.captureDisplayIDs.sorted(),
                    parityPassed: persistedCaptureConfiguration.parityPassed
                )
                try captureConfigurationStore.save(persistedCaptureConfiguration)
            }
            if configuration.printRemindersStatus {
                if let qaFixtureAdapter {
                    print("Zoid Coach agent: QA Reminders status \(try qaFixtureAdapter.permission(.reminders).rawValue)")
                } else {
                    print("Zoid Coach agent: Apple Reminders status \(AgentPermissionRequester.remindersStatus())")
                }
                return
            }
            if configuration.requestRemindersAccess {
                if let qaFixtureAdapter {
                    let granted = try qaFixtureAdapter.permission(.reminders) == .granted
                    print(granted ? "Zoid Coach agent: QA Reminders access granted" : "Zoid Coach agent: QA Reminders access was not granted")
                } else {
                    let granted = try await AgentPermissionRequester.requestRemindersAccess()
                    print(granted ? "Zoid Coach agent: Apple Reminders access granted" : "Zoid Coach agent: Apple Reminders access was not granted")
                }
                return
            }
            if configuration.watch {
                ParentAppLauncher.launchForBackgroundScheduling(
                    runtimeEnvironment: runtimeResolution.environment
                )
            }
            let progressMonitor = AgentProgressMonitor()
            let watchdog = configuration.watch ? Self.startWatchdog(progressMonitor: progressMonitor) : nil
            defer { watchdog?.cancel() }
            captureHealthStore.update(AgentCaptureHealthSnapshot(
                isEnabled: persistedCaptureConfiguration.mode != .legacy,
                isRunning: false,
                screenRecording: .unknown,
                accessibility: .unknown,
                automation: .notRequired,
                configuredDisplayIDs: persistedCaptureConfiguration.configuredDisplayIDs,
                detail: persistedCaptureConfiguration.mode == .legacy ? "Legacy Screenwatch capture remains active" : "Native capture is starting"
            ))
            let nativeCaptureTask: Task<Void, Never>? = if configuration.watch {
                Task.detached(priority: .utility) {
                    let service = NativeScreenCaptureService(
                        configuration: .init(
                            daysDirectory: configuration.nativeCaptureDirectory,
                            configurationStore: captureConfigurationStore
                        ),
                        healthStore: captureHealthStore
                    )
                    await service.run()
                }
            } else {
                nil
            }
            defer { nativeCaptureTask?.cancel() }
            try AutonomousDatabaseMigrator(databaseURL: configuration.databaseURL).migrate()
            let archive = try ScreenwatchArchive(databaseURL: configuration.databaseURL)
            let policyStore = try PolicyStore(databaseURL: configuration.databaseURL)
            let planStore = try AutonomousPlanStore(
                databaseURL: configuration.databaseURL,
                timeZoneIdentifier: {
                    (try? policyStore.current()?.policy.schedule.timeZoneIdentifier) ?? TimeZone.current.identifier
                }
            )
            let reminderSnapshotStore = try ReminderSnapshotStore(databaseURL: configuration.databaseURL)
            let taskHistoryStore = try TaskHistoryStore(databaseURL: configuration.databaseURL)
            let learningStore = try LearningAggregateStore(databaseURL: configuration.databaseURL)
            let trustGateStore = try PlannerTrustGateStore(databaseURL: configuration.databaseURL)
            let promptStore = try PromptInboxStore(databaseURL: configuration.databaseURL)
            let actionOutbox = try ActionOutboxStore(databaseURL: configuration.databaseURL)
            let planUndoRequests = try PlanUndoRequestStore(databaseURL: configuration.databaseURL)
            let planScheduleRequests = try PlanScheduleRequestStore(databaseURL: configuration.databaseURL)
            try planUndoRequests.recoverInterrupted()
            try planScheduleRequests.recoverInterrupted()
            let promptEffectRouter = PromptResponseEffectRouter(
                outbox: actionOutbox,
                meetingArchive: archive,
                planUndoRequests: planUndoRequests,
                planScheduleRequests: planScheduleRequests,
                promptStore: promptStore,
                schedulingCalendarIdentifier: {
                    try policyStore.current()?.policy.calendar.schedulingCalendarIdentifier
                }
            )
            let checkpointStore = try ProcessingCheckpointStore(databaseURL: configuration.databaseURL)
            let maintenanceService = try? ScreenwatchMaintenanceService(
                databaseURL: configuration.databaseURL,
                screenwatchSource: activeScreenwatchSource()
            )
            let notificationCoordinator: PromptNotificationCoordinator
            if let qaFixtureAdapter {
                notificationCoordinator = PromptNotificationCoordinator(
                    promptStore: promptStore,
                    fixtureAdapter: qaFixtureAdapter,
                    runtimeEnvironment: runtimeResolution.environment
                ) { result in
                    _ = try? promptEffectRouter.apply(result)
                }
            } else {
                notificationCoordinator = PromptNotificationCoordinator(
                    promptStore: promptStore,
                    runtimeEnvironment: runtimeResolution.environment
                ) { result in
                    _ = try? promptEffectRouter.apply(result)
                }
            }
            notificationCoordinator.activate()
            if qaFixtureAdapter != nil {
                try await notificationCoordinator.processFixtureActions()
            }
            try Self.replayPendingPromptEffects(store: promptStore, router: promptEffectRouter)
            let initialVersionedPolicy: VersionedUserPolicy
            if let stored = try policyStore.current() {
                initialVersionedPolicy = stored
            } else {
                initialVersionedPolicy = try policyStore.save(UserPolicy.defaults())
            }
            let initialPolicy = initialVersionedPolicy.policy
            let todayDashboardAgent = try TodayDashboardAgent(databaseURL: configuration.databaseURL)
            let taskSource: any TaskSource
            let calendarSource: any CalendarSource & CalendarAvailabilitySource
            let notificationSource: any NotificationSource
            if let qaFixtureAdapter {
                taskSource = qaFixtureAdapter
                calendarSource = qaFixtureAdapter
                notificationSource = qaFixtureAdapter
            } else {
                taskSource = EventKitTaskSource()
                calendarSource = EventKitCalendarSource()
                notificationSource = UserNotificationActionSource(
                    runtimeEnvironment: runtimeResolution.environment
                )
            }
            let actionExecutor = ActionCommandExecutor(
                outbox: actionOutbox,
                tasks: taskSource,
                calendar: calendarSource,
                notifications: notificationSource,
                writeCircuitBreaker: databaseWriteCircuitBreaker
            )
            let planScheduler = AgentPlanScheduler(
                plans: planStore,
                reminders: reminderSnapshotStore,
                outbox: actionOutbox,
                calendar: calendarSource,
                learning: learningStore
            )
            if initialPolicy.operatingMode != .fullyAutomatic {
                _ = try actionOutbox.cancelPendingAutomaticPlanCommands()
            }
            if !initialPolicy.automationPause.isPaused {
                let execution = await actionExecutor.executeNext()
                try? Self.finalizeMeetingEffect(execution, outbox: actionOutbox, archive: archive)
            }
            let reminderPlanner = AgentReminderPlanner(
                fixtureAdapter: qaFixtureAdapter,
                planStore: planStore,
                reminderSnapshotStore: reminderSnapshotStore,
                taskHistoryStore: taskHistoryStore,
                learningStore: learningStore,
                advisorProvider: {
                    if configuration.useLocalAI {
                        return OllamaPlanningAdvisor()
                    }
                    let privacy = (try? policyStore.current()?.policy.privacy) ?? initialPolicy.privacy
                    switch privacy.aiProvider {
                    case .localOllama:
                        return OllamaPlanningAdvisor()
                    case .codexCLI:
                        return CodexCLIPlanningAdvisor(
                            remoteEvidencePolicy: privacy.remoteEvidencePolicy,
                            modelID: privacy.effectiveCodexCLIModelID,
                            reasoningEffort: privacy.effectiveCodexCLIReasoningEffort
                        )
                    case .disabled, .appleOnDevice, .remoteOpenAI:
                        return nil
                    }
                }
            )
            _ = try? await reminderPlanner.synchronizeReminderSource()
            await progressMonitor.markProgress()
            let mutationRouter = AgentMutationRouter(
                outbox: actionOutbox,
                stateStore: try AgentOwnedStateStore(databaseURL: configuration.databaseURL),
                taskHistory: taskHistoryStore,
                meetingArchive: archive,
                planScheduler: planScheduler,
                policyStore: policyStore,
                reminderSnapshots: reminderSnapshotStore,
                privacyData: try PrivacyDataService(
                    databaseURL: configuration.databaseURL,
                    exportRoot: runtimeResolution.environment.exportRoot
                ),
                writeCircuitBreaker: databaseWriteCircuitBreaker,
                draftPlan: { day, overwriteExisting in
                    let policy = try policyStore.current()?.policy ?? UserPolicy.defaults()
                    let behavior = try archive.recentBehaviorEvidence(since: Date().addingTimeInterval(-7 * 24 * 60 * 60))
                    let result = try await reminderPlanner.draftPlan(
                        for: day,
                        overwriteExisting: overwriteExisting,
                        recentBehavior: behavior,
                        availableFocusMinutes: await Self.availableFocusMinutes(policy: policy, day: day, calendar: calendarSource)
                    )
                    switch result {
                    case let .drafted(itemCount): return itemCount
                    case .retainedExisting: return try planStore.loadDailyPlan(for: day).count
                    case .remindersAccessUnavailable: return 0
                    }
                }
            )
            let voicePersistence = try VoicePersistenceStore(databaseURL: configuration.databaseURL)
            let codexJobs = CodexJobCoordinator(persistence: voicePersistence)
            try await codexJobs.recoverInterruptedJobs()
            let screenContextSelector = try ScreenContextSelector(databaseURL: configuration.databaseURL)
            let macActions = MacChiefOfStaffActions()
            let voiceToolExecutor = ChiefOfStaffToolExecutor(dependencies: ChiefOfStaffToolDependencies(
                snapshot: { try todayDashboardAgent.snapshot() },
                applyTask: { command, taskID in try todayDashboardAgent.apply(command, taskID: taskID) },
                openApplication: { name, bundleIdentifier in
                    try await macActions.openApplication(name: name, bundleIdentifier: bundleIdentifier)
                },
                searchWeb: { query in try await macActions.searchWeb(query: query) },
                findFiles: { query, limit in try await macActions.findFiles(query: query, limit: limit) },
                openFile: { path in try await macActions.openFile(path: path) },
                createReminder: { title, dueDate, listIdentifier in
                    try await taskSource.create(
                        title: title,
                        dueDate: dueDate,
                        listIdentifier: listIdentifier,
                        metadataMarker: "voice:\(UUID().uuidString)"
                    )
                },
                completeReminder: { reminderID in
                    try await taskSource.apply(.complete(at: Date()), to: reminderID)
                },
                createFocusBlock: { title, start, end in
                    let identifier = UUID().uuidString
                    return try await calendarSource.apply(.createBlock(CalendarBlockMutation(
                        title: title,
                        start: start,
                        end: end,
                        ownershipToken: "voice:\(identifier)",
                        planItemID: "voice:\(identifier)"
                    )))
                },
                createCalendarCommitment: { title, start, end in
                    let fingerprint = "voice-commitment:\(UUID().uuidString)"
                    let calendarIdentifier = try policyStore.current()?.policy.calendar.schedulingCalendarIdentifier
                    return try await calendarSource.apply(.createConfirmedMeeting(ConfirmedMeetingMutation(
                        title: title,
                        start: start,
                        end: end,
                        calendarIdentifier: calendarIdentifier,
                        fingerprint: fingerprint
                    )))
                },
                setAutomationPaused: { isPaused in
                    let current = try policyStore.current()?.policy ?? UserPolicy.defaults()
                    let updated = UserPolicy(
                        operatingMode: current.operatingMode,
                        automationPause: isPaused ? .pausedIndefinitely : .running,
                        schedule: current.schedule,
                        calendar: current.calendar,
                        privacy: current.privacy,
                        wake: current.wake,
                        behavior: current.behavior,
                        capture: current.capture,
                        gaming: current.gaming
                    )
                    return try policyStore.save(updated).policy
                },
                startCodexJob: { workspacePath, objective, sandbox in
                    try await codexJobs.start(
                        workspacePath: workspacePath,
                        objective: objective,
                        sandbox: sandbox
                    )
                },
                codexJob: { jobID in try await codexJobs.job(id: jobID) },
                cancelCodexJob: { jobID in try await codexJobs.cancel(jobID: jobID) },
                saveMemory: { fact in try voicePersistence.save(fact) },
                deleteMemory: { memoryID in try voicePersistence.deleteMemoryFact(id: memoryID) },
                loadMemory: { memoryID in try voicePersistence.memoryFact(id: memoryID) },
                activeMemories: { try voicePersistence.activeMemoryFacts(at: Date()) },
                deleteTranscripts: { try voicePersistence.deleteAllTranscripts() },
                selectScreenContext: { reason, limit in
                    let privacy = try policyStore.current()?.policy.privacy ?? UserPolicy.defaults().privacy
                    return try screenContextSelector.select(
                        reason: reason,
                        limit: limit,
                        mayTransmitPrivateContent: privacy.remoteEvidencePolicy == .explicitPrivateContent
                    )
                }
            ))
            let voiceController = VoiceAgentController(
                persistence: voicePersistence,
                toolRouter: VoiceToolRouter(executor: voiceToolExecutor, persistence: voicePersistence),
                snapshot: { try todayDashboardAgent.snapshot() },
                policy: { try policyStore.current()?.policy ?? UserPolicy.defaults() },
                activeCodexJobs: { try await codexJobs.activeJobs() },
                upcomingCommitments: {
                    let policy = try policyStore.current()?.policy ?? UserPolicy.defaults()
                    let now = Date()
                    return try await calendarSource.commitments(
                        from: now,
                        through: now.addingTimeInterval(30 * 60),
                        calendarIdentifiers: policy.calendar.visibleCalendarIdentifiers
                    )
                }
            )
            try voiceController.pruneExpiredTranscripts()
            let xpcService = TodayDashboardXPCService(
                agent: todayDashboardAgent,
                promptStore: promptStore,
                promptEffectRouter: promptEffectRouter,
                mutationRouter: mutationRouter,
                voiceController: voiceController,
                writeCircuitBreaker: databaseWriteCircuitBreaker,
                captureHealthStore: captureHealthStore,
                runtimeEnvironment: runtimeResolution.environment
            )
            xpcService.resume()
            let previousHeartbeat = try checkpointStore.checkpoint(sourceID: "agent-runtime")?.lastSuccessAt
            let startupDate = Date()
            try checkpointStore.recordSuccess(sourceID: "agent-runtime", at: startupDate)
            if let previousHeartbeat,
               let recovery = MissedNightlyRunCalculator().recoveryRun(
                   sleepStartedAt: previousHeartbeat,
                   wokeAt: startupDate,
                   policy: NightlyReplayPolicy(
                       timeZoneIdentifier: initialPolicy.schedule.timeZoneIdentifier,
                       planningTime: initialPolicy.schedule.nightlyPlanningTime
                   )
               ),
               let targetDay = Self.date(localDay: recovery.targetLocalDay, timeZoneIdentifier: initialPolicy.schedule.timeZoneIdentifier),
               try planStore.hasPlan(for: targetDay) == false {
                let behavior = try archive.recentBehaviorEvidence(since: startupDate.addingTimeInterval(-7 * 24 * 60 * 60))
                let result = try await reminderPlanner.draftPlan(
                    for: targetDay,
                    recentBehavior: behavior,
                    availableFocusMinutes: await Self.availableFocusMinutes(policy: initialPolicy, day: targetDay, calendar: calendarSource)
                )
                if case let .drafted(itemCount) = result {
                    await Self.enqueuePlanActions(
                        scheduler: planScheduler,
                        day: targetDay,
                        policy: initialPolicy,
                        policyVersion: initialVersionedPolicy.version,
                        checkpoints: checkpointStore,
                        trustGate: trustGateStore,
                        itemCount: itemCount,
                        outbox: actionOutbox,
                        plans: planStore
                    )
                    let prompt = try promptStore.enqueue(Self.planReadyPrompt(
                        for: targetDay,
                        itemCount: itemCount,
                        timeZoneIdentifier: initialPolicy.schedule.timeZoneIdentifier
                    ))
                    if prompt.wasInserted {
                        await Self.schedulePlanPrompt(
                            prompt.episode,
                            policy: initialPolicy,
                            notifications: notificationCoordinator
                        )
                    }
                    try checkpointStore.recordSuccess(
                        sourceID: "nightly-plan",
                        at: startupDate,
                        scheduledLocalDay: recovery.targetLocalDay,
                        timeZoneIdentifier: initialPolicy.schedule.timeZoneIdentifier,
                        missedTriggerAt: previousHeartbeat
                    )
                    print("Zoid Coach agent: recovered delayed overnight plan after wake")
                }
            }
            if configuration.draftPlan {
                let targetDay = configuration.planTomorrow ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() : Date()
                let behavior = try archive.recentBehaviorEvidence(since: Date().addingTimeInterval(-7 * 24 * 60 * 60))
                let result = try await reminderPlanner.draftPlan(
                    for: targetDay,
                    overwriteExisting: configuration.overwritePlan,
                    recentBehavior: behavior,
                    availableFocusMinutes: await Self.availableFocusMinutes(policy: initialPolicy, day: targetDay, calendar: calendarSource)
                )
                switch result {
                case let .drafted(itemCount):
                    await Self.enqueuePlanActions(
                        scheduler: planScheduler,
                        day: targetDay,
                        policy: initialPolicy,
                        policyVersion: initialVersionedPolicy.version,
                        checkpoints: checkpointStore,
                        trustGate: trustGateStore,
                        itemCount: itemCount,
                        outbox: actionOutbox,
                        plans: planStore
                    )
                    let prompt = try promptStore.enqueue(Self.planReadyPrompt(
                        for: targetDay,
                        itemCount: itemCount,
                        timeZoneIdentifier: initialPolicy.schedule.timeZoneIdentifier
                    ))
                    if prompt.wasInserted {
                        await Self.schedulePlanPrompt(
                            prompt.episode,
                            policy: initialPolicy,
                            notifications: notificationCoordinator
                        )
                    }
                    print("Zoid Coach agent: drafted \(itemCount) daily commitments")
                case .retainedExisting:
                    print("Zoid Coach agent: retained the existing daily plan")
                case .remindersAccessUnavailable:
                    print("Zoid Coach agent: Apple Reminders full access is unavailable")
                }
            }
            if configuration.watch {
                var lastAutomaticDraftAttempt: Date?
                var lastMaintenanceAttempt: Date?
                var lastDaytimeSourceCheck: Date?
                var lastCalendarSignature: String?
                while !Task.isCancelled {
                    do {
                    let versionedPolicy = try policyStore.current() ?? initialVersionedPolicy
                    let policy = versionedPolicy.policy
                    let resourceConstrained = Self.isResourceConstrained
                    if policy.operatingMode != .fullyAutomatic {
                        _ = try actionOutbox.cancelPendingAutomaticPlanCommands()
                    }
                    try checkpointStore.recordSuccess(sourceID: "agent-runtime", at: Date())
                    try Self.replayPendingPromptEffects(store: promptStore, router: promptEffectRouter)
                    if !resourceConstrained,
                       lastMaintenanceAttempt.map({ Date().timeIntervalSince($0) >= 6 * 60 * 60 }) ?? true {
                        _ = try? maintenanceService?.run(policy: policy, now: Date(), mode: .apply)
                        lastMaintenanceAttempt = Date()
                    }
                    let result: ScreenwatchIngestionResult
                    do {
                        result = try archive.ingestToday(from: try activeScreenwatchSource(), now: Date())
                        try? checkpointStore.recordSuccess(sourceID: "screenwatch-canonical-source", at: Date())
                    } catch {
                        try? checkpointStore.recordFailure(
                            sourceID: "screenwatch-canonical-source",
                            at: Date(),
                            diagnostic: String(describing: type(of: error))
                        )
                        result = ScreenwatchIngestionResult(insertedCount: 0, totalRecordsRead: 0)
                    }
                    let analysis = policy.privacy.screenshotAnalysisEnabled && !resourceConstrained
                        ? try await archive.analyzePendingWhatsAppScreenshots()
                        : MeetingAnalysisResult(screenshotsProcessed: 0, candidatesCreated: 0)
                    if policy.operatingMode != .observe {
                        try await Self.processMeetingPrompts(
                            archive: archive,
                            promptStore: promptStore,
                            notifications: notificationCoordinator,
                            policy: policy,
                            calendar: calendarSource
                        )
                    }
                    print("Zoid Coach agent: \(result.insertedCount) observations ingested, \(analysis.candidatesCreated) meeting candidates created")
                    _ = try? todayDashboardAgent.snapshot(now: Date())
                    let now = Date()
                    _ = try promptStore.expireDue()
                    if policy.automationPause.isPaused {
                        await progressMonitor.markProgress()
                        try await Task.sleep(for: .seconds(5))
                        continue
                    }
                    let execution = await actionExecutor.executeNext()
                    try? Self.finalizeMeetingEffect(execution, outbox: actionOutbox, archive: archive)
                    if let undo = try planUndoRequests.claimNext() {
                        do {
                            if let undoDay = Self.date(localDay: undo.dayKey, timeZoneIdentifier: policy.schedule.timeZoneIdentifier),
                               try planStore.restoreLatestRevision(for: undoDay) {
                                _ = try await planScheduler.enqueueSchedule(
                                    for: undoDay,
                                    policy: policy,
                                    policyVersion: versionedPolicy.version
                                )
                            }
                            try planUndoRequests.finish(undo, succeeded: true)
                        } catch {
                            try? planUndoRequests.finish(undo, succeeded: false)
                        }
                    }
                    if let request = try planScheduleRequests.claimNext() {
                        do {
                            let isExplicitApproval = !request.promptID.hasPrefix("automatic-plan:")
                            let shouldSchedule = policy.operatingMode == .fullyAutomatic
                                || (policy.operatingMode == .approvalRequired && isExplicitApproval)
                            if !shouldSchedule {
                                try planScheduleRequests.finish(request, succeeded: true)
                            } else if try trustGateStore.status().allowsAutomaticWrites,
                                      let approvedDay = Self.date(
                                    localDay: request.dayKey,
                                    timeZoneIdentifier: policy.schedule.timeZoneIdentifier
                                      ) {
                                _ = try await planScheduler.enqueueSchedule(
                                    for: approvedDay,
                                    policy: policy,
                                    policyVersion: versionedPolicy.version,
                                    origin: .approvedPlan
                                )
                                try planScheduleRequests.finish(request, succeeded: true)
                            } else {
                                try planScheduleRequests.finish(request, succeeded: false)
                            }
                        } catch {
                            try? planScheduleRequests.finish(request, succeeded: false)
                        }
                    }
                    if lastDaytimeSourceCheck.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
                        let reminderChanges = try? await reminderPlanner.synchronizeReminderSource()
                        let calendarSignature = try? await Self.calendarCommitmentSignature(
                            policy: policy,
                            day: now,
                            calendar: calendarSource
                        )
                        if calendarSignature != nil {
                            try? checkpointStore.recordSuccess(sourceID: "calendar-source", at: now)
                        }
                        let remindersChanged = reminderChanges.map {
                            $0.insertedCount + $0.updatedCount + $0.removedCount > 0
                        } ?? false
                        let calendarChanged = lastCalendarSignature != nil && calendarSignature != lastCalendarSignature
                        lastCalendarSignature = calendarSignature
                        lastDaytimeSourceCheck = now
                        if (remindersChanged || calendarChanged), try planStore.hasPlan(for: now) {
                            let behavior = try archive.recentBehaviorEvidence(since: now.addingTimeInterval(-7 * 24 * 60 * 60))
                            if case let .drafted(itemCount) = try await reminderPlanner.draftPlan(
                                for: now,
                                overwriteExisting: true,
                                recentBehavior: behavior,
                                availableFocusMinutes: await Self.availableFocusMinutes(policy: policy, day: now, calendar: calendarSource)
                            ) {
                                await Self.enqueuePlanActions(
                                    scheduler: planScheduler,
                                    day: now,
                                    policy: policy,
                                    policyVersion: versionedPolicy.version,
                                    checkpoints: checkpointStore,
                                    trustGate: trustGateStore,
                                    itemCount: itemCount,
                                    outbox: actionOutbox,
                                    plans: planStore
                                )
                                let prompt = try promptStore.enqueue(Self.planChangedPrompt(
                                    for: now,
                                    itemCount: itemCount,
                                    timeZoneIdentifier: policy.schedule.timeZoneIdentifier
                                ))
                                if prompt.wasInserted {
                                    _ = try? await notificationCoordinator.schedule(prompt.episode)
                                }
                            }
                        }
                    }
                    let nightlySchedule = NightlyPlanningSchedule(
                        hour: policy.schedule.nightlyPlanningTime.hour,
                        minute: policy.schedule.nightlyPlanningTime.minute
                    )
                    if let targetDay = nightlySchedule.targetDay(for: now),
                       lastAutomaticDraftAttempt.map({ now.timeIntervalSince($0) >= 15 * 60 }) ?? true {
                        let behavior = try archive.recentBehaviorEvidence(since: now.addingTimeInterval(-7 * 24 * 60 * 60))
                        let draft = try await reminderPlanner.draftPlan(
                            for: targetDay,
                            recentBehavior: behavior,
                            availableFocusMinutes: await Self.availableFocusMinutes(policy: policy, day: targetDay, calendar: calendarSource)
                        )
                        switch draft {
                        case let .drafted(itemCount):
                            await Self.enqueuePlanActions(
                                scheduler: planScheduler,
                                day: targetDay,
                                policy: policy,
                                policyVersion: versionedPolicy.version,
                                checkpoints: checkpointStore,
                                trustGate: trustGateStore,
                                itemCount: itemCount,
                                outbox: actionOutbox,
                                plans: planStore
                            )
                            let prompt = try promptStore.enqueue(Self.planReadyPrompt(
                                for: targetDay,
                                itemCount: itemCount,
                                timeZoneIdentifier: policy.schedule.timeZoneIdentifier
                            ))
                            if prompt.wasInserted {
                                await Self.schedulePlanPrompt(
                                    prompt.episode,
                                    policy: policy,
                                    notifications: notificationCoordinator
                                )
                            }
                            print("Zoid Coach agent: overnight draft prepared with \(itemCount) commitments")
                        case .retainedExisting:
                            print("Zoid Coach agent: overnight draft already exists")
                        case .remindersAccessUnavailable:
                            print("Zoid Coach agent: overnight draft is waiting for Apple Reminders access")
                        }
                        lastAutomaticDraftAttempt = now
                    }
                    await progressMonitor.markProgress()
                    try await Task.sleep(for: .seconds(resourceConstrained ? 30 : 5))
                    } catch {
                        try? checkpointStore.recordFailure(
                            sourceID: "agent-watch-loop",
                            at: Date(),
                            diagnostic: String(describing: type(of: error))
                        )
                        try? await Task.sleep(for: .seconds(10))
                    }
                }
            } else {
                let result: ScreenwatchIngestionResult
                do {
                    result = try archive.ingestToday(from: try activeScreenwatchSource(), now: Date())
                    try? checkpointStore.recordSuccess(sourceID: "screenwatch-canonical-source", at: Date())
                } catch {
                    try? checkpointStore.recordFailure(
                        sourceID: "screenwatch-canonical-source",
                        at: Date(),
                        diagnostic: String(describing: type(of: error))
                    )
                    result = ScreenwatchIngestionResult(insertedCount: 0, totalRecordsRead: 0)
                }
                let analysis = try await archive.analyzePendingWhatsAppScreenshots()
                try await Self.processMeetingPrompts(
                    archive: archive,
                    promptStore: promptStore,
                    notifications: notificationCoordinator,
                    policy: initialPolicy,
                    calendar: calendarSource
                )
                print("Zoid Coach agent: \(result.insertedCount) observations ingested, \(analysis.candidatesCreated) meeting candidates created")
                _ = try? todayDashboardAgent.snapshot(now: Date())
            }
        } catch let error as AgentOSAdapterBoundaryError {
            fputs("Zoid Coach agent refused QA OS access: \(error.localizedDescription)\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        } catch {
            databaseWriteCircuitBreaker.trip(reason: error.localizedDescription)
            fputs("Zoid Coach agent entered read-only mode: \(error.localizedDescription)\n", stderr)
            guard let activeRuntimeEnvironment else {
                fputs("Zoid Coach agent cannot start XPC without a validated runtime identity\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }
            let degradedService = TodayDashboardXPCService(
                writeCircuitBreaker: databaseWriteCircuitBreaker,
                captureHealthStore: captureHealthStore,
                runtimeEnvironment: activeRuntimeEnvironment
            )
            degradedService.resume()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private static func runtimeIdentityDescription(
        _ runtimeEnvironment: RuntimeEnvironment
    ) -> String {
        let mode: String
        let root: String
        switch runtimeEnvironment.mode {
        case .production:
            mode = "production"
            root = "-"
        case let .qa(runRoot):
            mode = "qa"
            root = runRoot.path
        }
        return [
            "package=\(runtimeEnvironment.packageMode?.rawValue ?? "unbundled")",
            "mode=\(mode)",
            "identity=\(runtimeEnvironment.identity.agentSigningIdentifier)",
            "root=\(root)",
        ].joined(separator: " ")
    }

    private static func planReadyPrompt(for day: Date, itemCount: Int, timeZoneIdentifier: String) -> PromptDraft {
        let dayKey = localDayKey(day, timeZoneIdentifier: timeZoneIdentifier)
        return PromptDraft(
            decisionKey: "plan-ready:\(dayKey)",
            type: "PLAN_READY",
            title: "Tomorrow's plan is ready",
            summary: "Zoid Coach selected \(itemCount) evidence-backed commitment\(itemCount == 1 ? "" : "s").",
            actions: [
                PromptAction(kind: .acceptPlan, title: "Accept", role: .primary),
                PromptAction(kind: .reviewPlan, title: "Review")
            ],
            payload: ["localDay": dayKey, "itemCount": String(itemCount)],
            expiresAt: Calendar.current.date(byAdding: .day, value: 1, to: day)
        )
    }

    private static func planChangedPrompt(for day: Date, itemCount: Int, timeZoneIdentifier: String) -> PromptDraft {
        let dayKey = localDayKey(day, timeZoneIdentifier: timeZoneIdentifier)
        return PromptDraft(
            decisionKey: "plan-changed:\(dayKey):\(itemCount)",
            type: "PLAN_CHANGED",
            title: "Today's plan changed",
            summary: "Calendar or Reminder changes produced \(itemCount) commitments.",
            actions: [
                PromptAction(kind: .reviewPlan, title: "Review", role: .primary),
                PromptAction(kind: .undoPlanChange, title: "Undo")
            ],
            payload: ["day": dayKey, "itemCount": String(itemCount)],
            expiresAt: Calendar.current.date(byAdding: .hour, value: 8, to: Date())
        )
    }

    private static func calendarCommitmentSignature(
        policy: UserPolicy,
        day: Date,
        calendar: any CalendarAvailabilitySource
    ) async throws -> String {
        var values: [String] = []
        for interval in policy.schedule.workIntervals(on: day) {
            let commitments = try await calendar.commitments(
                from: interval.start,
                through: interval.end,
                calendarIdentifiers: policy.calendar.visibleCalendarIdentifiers
            )
            values.append(contentsOf: commitments.map {
                "\($0.id)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)"
            })
        }
        return values.sorted().joined(separator: "\n")
    }

    private static func checkCalendar(
        for candidate: StoredMeetingCandidate,
        policy: UserPolicy,
        calendar: any CalendarAvailabilitySource
    ) async throws -> MeetingCalendarAssessment {
        let end = candidate.start.addingTimeInterval(TimeInterval(candidate.durationMinutes * 60))
        let commitments = try await calendar.commitments(
            from: candidate.start.addingTimeInterval(-15 * 60),
            through: end.addingTimeInterval(15 * 60),
            calendarIdentifiers: policy.calendar.visibleCalendarIdentifiers
        )
        let semanticCandidate = MeetingCandidate(
            title: candidate.title,
            start: candidate.start,
            durationMinutes: candidate.durationMinutes,
            confidence: candidate.confidence,
            requiresClarification: candidate.requiresClarification,
            sourceText: candidate.sourceEvidence,
            confidenceScore: candidate.confidenceScore,
            participants: candidate.participants,
            location: candidate.location,
            callLink: candidate.callLink,
            timezoneIdentifier: candidate.timezoneIdentifier
        )
        let events = commitments.map {
            ExistingMeetingEvent(
                id: $0.id,
                title: $0.title,
                start: $0.start,
                end: $0.end,
                participants: $0.participants
            )
        }
        switch MeetingCandidatePolicy().route(semanticCandidate, existingEvents: events) {
        case let .duplicate(existingEventID):
            guard let event = events.first(where: { $0.id == existingEventID }) else { return .clear }
            return .duplicate(event)
        case let .conflict(existingEventID):
            guard let event = events.first(where: { $0.id == existingEventID }) else { return .clear }
            return .conflict(event)
        case .readyForConfirmation, .needsClarification, .lowConfidence:
            return .clear
        }
    }

    private static func processMeetingPrompts(
        archive: ScreenwatchArchive,
        promptStore: PromptInboxStore,
        notifications: PromptNotificationCoordinator,
        policy: UserPolicy,
        calendar: any CalendarAvailabilitySource
    ) async throws {
        let promptByCandidateID = Dictionary(
            uniqueKeysWithValues: try promptStore.unresolved().compactMap { episode in
                episode.type == "MEETING_CANDIDATE"
                    ? episode.payload["candidateID"].map { ($0, episode) }
                    : nil
            }
        )
        let candidates = MeetingPromptBuilder.candidatesRequiringPromptWork(
            try archive.unresolvedMeetingCandidates(),
            unresolvedPrompts: Array(promptByCandidateID.values),
            limit: 12
        )
        for candidate in candidates {
            if let existing = promptByCandidateID[candidate.id] {
                guard existing.state == .queued else { continue }
                _ = try? await notifications.schedule(existing)
                continue
            }
            guard candidate.start > Date() else {
                try? archive.updateMeetingCandidate(candidate, state: "expired")
                continue
            }
            do {
                let assessment = try await checkCalendar(for: candidate, policy: policy, calendar: calendar)
                if case let .duplicate(event) = assessment {
                    try archive.updateMeetingCandidate(candidate, state: "duplicate_calendar", matchedEventID: event.id)
                    continue
                }
                if case let .conflict(event) = assessment {
                    try archive.updateMeetingCandidate(candidate, state: "conflict", matchedEventID: event.id)
                }
                let destination = policy.calendar.schedulingCalendarIdentifier ?? "Configured calendar"
                let prompt = try promptStore.enqueue(MeetingPromptBuilder.draft(
                    for: candidate,
                    calendarDestination: destination,
                    assessment: assessment
                ))
                guard prompt.episode.state == .queued else { continue }
                _ = try? await notifications.schedule(prompt.episode)
            } catch {
                continue
            }
        }
    }

    private static func localDayKey(_ date: Date, timeZoneIdentifier: String = TimeZone.current.identifier) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(localDay: String, timeZoneIdentifier: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: localDay)
    }

    private static func morningDeliveryDate(for episode: PromptEpisode, policy: UserPolicy) -> Date? {
        guard let localDay = episode.payload["localDay"],
              let day = date(localDay: localDay, timeZoneIdentifier: policy.schedule.timeZoneIdentifier),
              let timeZone = TimeZone(identifier: policy.schedule.timeZoneIdentifier)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            bySettingHour: policy.schedule.morningConfirmationTime.hour,
            minute: policy.schedule.morningConfirmationTime.minute,
            second: 0,
            of: day
        )
    }

    private static func replayPendingPromptEffects(
        store: PromptInboxStore,
        router: PromptResponseEffectRouter
    ) throws {
        for result in try store.pendingEffects() {
            _ = try router.apply(result)
        }
    }

    private static var isResourceConstrained: Bool {
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
    }

    private static func schedulePlanPrompt(
        _ episode: PromptEpisode,
        policy: UserPolicy,
        notifications: PromptNotificationCoordinator,
        now: Date = Date()
    ) async {
        let delivery = morningDeliveryDate(for: episode, policy: policy)
        _ = try? await notifications.schedule(episode, deliveryDate: delivery)
    }

    private static func enqueuePlanActions(
        scheduler: AgentPlanScheduler,
        day: Date,
        policy: UserPolicy,
        policyVersion: Int,
        checkpoints: ProcessingCheckpointStore,
        trustGate: PlannerTrustGateStore,
        itemCount: Int,
        outbox: ActionOutboxStore,
        plans: AutonomousPlanStore
    ) async {
        do {
            let plannedMinutes = try plans.loadDailyPlan(for: day).reduce(0) { $0 + $1.estimateMinutes }
            let stayedWithinCapacity = plannedMinutes <= policy.schedule.planningCapacityMinutes(on: day)
            let trust = try trustGate.recordShadowCycle(
                localDay: localDayKey(day, timeZoneIdentifier: policy.schedule.timeZoneIdentifier),
                planVersion: policyVersion,
                itemCount: itemCount,
                stayedWithinCapacity: stayedWithinCapacity
            )
            if policy.operatingMode == .observe {
                let result = try await scheduler.enqueueSchedule(
                    for: day,
                    policy: policy,
                    policyVersion: policyVersion,
                    origin: .automaticPlan
                )
                print("Zoid Coach agent: recorded \(result.scheduledBlockCount) Calendar and \(result.reminderMutationCount) Reminder would-do actions")
                return
            }
            if !trust.allowsAutomaticWrites {
                print("Zoid Coach agent: shadow cycle \(trust.observedCycleCount)/\(trust.requiredCycleCount) recorded without external writes")
                return
            }
            guard policy.operatingMode == .fullyAutomatic else {
                print("Zoid Coach agent: plan retained without external writes in \(policy.operatingMode.rawValue) mode")
                return
            }
            let result = try await scheduler.enqueueSchedule(
                for: day,
                policy: policy,
                policyVersion: policyVersion,
                origin: .automaticPlan
            )
            try checkpoints.recordSuccess(
                sourceID: "plan-actions",
                at: Date(),
                scheduledLocalDay: localDayKey(day, timeZoneIdentifier: policy.schedule.timeZoneIdentifier),
                timeZoneIdentifier: policy.schedule.timeZoneIdentifier
            )
            print("Zoid Coach agent: enqueued \(result.scheduledBlockCount) Calendar blocks and \(result.reminderMutationCount) Reminder updates")
            try enqueueWakeNotificationIfEligible(
                day: day,
                policy: policy,
                policyVersion: policyVersion,
                outbox: outbox,
                plans: plans,
                trustAllowsWakeWrites: trust.allowsWakeWrites
            )
        } catch {
            try? checkpoints.recordFailure(
                sourceID: "plan-actions",
                at: Date(),
                diagnostic: String(describing: type(of: error))
            )
            print("Zoid Coach agent: plan actions are waiting for Calendar or Reminders permission")
        }
    }

    private static func startWatchdog(progressMonitor: AgentProgressMonitor) -> Task<Void, Never> {
        let policy = AgentLivenessPolicy()
        return Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if await progressMonitor.requiresRestart(policy: policy) {
                    fputs("Zoid Coach agent watchdog: no successful progress for 180 seconds; restarting through launchd\n", stderr)
                    Foundation.exit(EXIT_FAILURE)
                }
            }
        }
    }

    private static func enqueueWakeNotificationIfEligible(
        day: Date,
        policy: UserPolicy,
        policyVersion: Int,
        outbox: ActionOutboxStore,
        plans: AutonomousPlanStore,
        trustAllowsWakeWrites: Bool
    ) throws {
        guard trustAllowsWakeWrites,
              policy.wake.isEligible,
              let timeZone = TimeZone(identifier: policy.schedule.timeZoneIdentifier) else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
           policy.wake.quietWeekdays?.contains(weekday) == true { return }
        let plan = try plans.loadDailyPlan(for: day)
        guard let main = plan.first(where: \.isMainObjective) else { return }
        let identifier = "wake:\(localDayKey(day, timeZoneIdentifier: policy.schedule.timeZoneIdentifier))"
        let completedInterventions = try outbox.recentCommands(limit: 1_000).filter {
            $0.type == .scheduleNotification
                && $0.entityID == identifier
                && $0.state != .cancelled
                && $0.state != .terminalFailure
        }.count
        let evidence = WakePlanEvidence(
            mainObjectiveScore: main.selectionScore ?? 0,
            plannedFocusMinutes: plan.reduce(0) { $0 + $1.estimateMinutes },
            completedInterventionsToday: completedInterventions
        )
        let wakePolicy = WakeUpPolicy(
            windowStartHour: policy.wake.window.start.hour,
            windowEndHour: policy.wake.window.end.hour,
            maximumDailyInterventions: policy.wake.maximumDailyInterventions
        )
        guard case let .eligible(reason) = wakePolicy.decision(for: evidence),
              let delivery = calendar.date(
                bySettingHour: policy.wake.window.start.hour,
                minute: policy.wake.window.start.minute,
                second: 0,
                of: day
              ) else { return }
        _ = try outbox.enqueue(
            type: .scheduleNotification,
            entityID: identifier,
            desiredState: .notification(
                NotificationDesiredState(
                    category: "WAKE_INTERVENTION",
                    title: "A critical commitment needs your attention",
                    body: reason,
                    promptID: identifier,
                    deliveryDate: delivery
                )
            ),
            planVersion: policyVersion
        )
    }

    private static func availableFocusMinutes(
        policy: UserPolicy,
        day: Date,
        calendar: any CalendarAvailabilitySource
    ) async -> Int {
        let workIntervals = policy.schedule.workIntervals(on: day)
        guard let start = workIntervals.map(\.start).min(),
              let end = workIntervals.map(\.end).max()
        else { return 0 }
        guard let commitments = try? await calendar.commitments(
            from: start,
            through: end,
            calendarIdentifiers: policy.calendar.visibleCalendarIdentifiers
        ) else {
            return 0
        }
        var occupiedSeconds: TimeInterval = 0
        for work in workIntervals {
            var merged: [DateInterval] = []
            for commitment in commitments.sorted(by: { $0.start < $1.start }) where commitment.ownershipToken == nil && commitment.end > work.start && commitment.start < work.end {
                let interval = DateInterval(start: max(commitment.start, work.start), end: min(commitment.end, work.end))
                if let last = merged.last, last.end >= interval.start {
                    merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
                } else {
                    merged.append(interval)
                }
            }
            occupiedSeconds += merged.reduce(0) { $0 + $1.duration }
        }
        return policy.schedule.planningCapacityMinutes(on: day, fixedCommitmentMinutes: Int(occupiedSeconds / 60))
    }

    private static func finalizeMeetingEffect(_ result: ActionExecutionResult, outbox: ActionOutboxStore, archive: ScreenwatchArchive) throws {
        let commandID: String
        let state: String
        switch result {
        case let .succeeded(id, _):
            commandID = id
            state = "scheduled"
        case let .terminalFailure(id, _):
            commandID = id
            state = "failed"
        default:
            return
        }
        guard let command = try outbox.command(commandID: commandID),
              command.type == .createConfirmedMeeting,
              let candidate = try archive.meetingCandidate(id: command.entityID)
        else { return }
        try archive.updateMeetingCandidate(candidate, state: state)
    }
}

private struct AgentConfiguration {
    let screenwatchDirectory: URL
    let databaseURL: URL
    let watch: Bool
    let draftPlan: Bool
    let overwritePlan: Bool
    let useLocalAI: Bool
    let requestRemindersAccess: Bool
    let planTomorrow: Bool
    let printRemindersStatus: Bool
    let nativeCapture: Bool
    let captureDisplayIDs: Set<UInt32>
    let nativeCaptureDirectory: URL

    func activeCaptureDirectory(using store: NativeCaptureConfigurationStore) -> URL {
        let mode = (try? store.load().mode) ?? .legacy
        return mode == .native ? nativeCaptureDirectory : screenwatchDirectory
    }

    init(runtimeEnvironment: RuntimeEnvironment, arguments: [String]) throws {
        let screenwatchDirectory = runtimeEnvironment.screenwatchDirectory
        let databaseURL = runtimeEnvironment.databaseURL
        var watch = true
        var draftPlan = false
        var overwritePlan = false
        var useLocalAI = false
        var requestRemindersAccess = false
        var planTomorrow = false
        var printRemindersStatus = false
        var nativeCapture = ProcessInfo.processInfo.environment["ZOID_COACH_NATIVE_CAPTURE"] == "1"
        var captureDisplayIDs = Set<UInt32>()
        var nativeCaptureDirectory = runtimeEnvironment.nativeCaptureDaysDirectory
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--watch":
                watch = true
                useLocalAI = true
            case "--draft-plan":
                draftPlan = true
            case "--overwrite-plan":
                draftPlan = true
                overwritePlan = true
            case "--ai-draft-plan":
                draftPlan = true
                useLocalAI = true
            case "--draft-tomorrow":
                draftPlan = true
                planTomorrow = true
            case "--request-reminders-access":
                watch = false
                requestRemindersAccess = true
            case "--reminders-status":
                watch = false
                printRemindersStatus = true
            case "--native-capture":
                nativeCapture = true
            case "--capture-displays":
                index += 1
                guard index < arguments.count else { throw AgentConfigurationError.missingValue("--capture-displays") }
                captureDisplayIDs = try Self.parseDisplayIDs(arguments[index])
            case "--native-capture-directory":
                index += 1
                guard index < arguments.count else { throw AgentConfigurationError.missingValue("--native-capture-directory") }
                nativeCaptureDirectory = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--once":
                watch = false
            default:
                throw AgentConfigurationError.unknownArgument(arguments[index])
            }
            index += 1
        }

        self.screenwatchDirectory = screenwatchDirectory
        self.databaseURL = databaseURL
        self.watch = watch
        self.draftPlan = draftPlan
        self.overwritePlan = overwritePlan
        self.useLocalAI = useLocalAI
        self.requestRemindersAccess = requestRemindersAccess
        self.planTomorrow = planTomorrow
        self.printRemindersStatus = printRemindersStatus
        self.nativeCapture = nativeCapture
        self.captureDisplayIDs = captureDisplayIDs
        guard NativeCapturePolicy.pathsDoNotCollide(native: nativeCaptureDirectory, legacy: screenwatchDirectory) else {
            throw AgentConfigurationError.captureDirectoryCollision
        }
        self.nativeCaptureDirectory = try runtimeEnvironment.validatedWritableURL(
            nativeCaptureDirectory,
            name: "native capture"
        )
    }

    static func parseDisplayIDs(_ value: String) throws -> Set<UInt32> {
        let values = value.split(separator: ",").map(String.init)
        guard !values.isEmpty else { return [] }
        let identifiers = values.compactMap(UInt32.init)
        guard identifiers.count == values.count else { throw AgentConfigurationError.invalidDisplayIDs(value) }
        return Set(identifiers)
    }
}

private enum AgentConfigurationError: LocalizedError {
    case missingValue(String)
    case unknownArgument(String)
    case invalidDisplayIDs(String)
    case captureDirectoryCollision

    var errorDescription: String? {
        switch self {
        case let .missingValue(argument): "Missing value for \(argument)"
        case let .unknownArgument(argument): "Unknown argument \(argument)"
        case let .invalidDisplayIDs(value): "Invalid comma-separated display IDs: \(value)"
        case .captureDirectoryCollision: "Native capture must use an app-owned directory separate from legacy Screenwatch."
        }
    }
}
