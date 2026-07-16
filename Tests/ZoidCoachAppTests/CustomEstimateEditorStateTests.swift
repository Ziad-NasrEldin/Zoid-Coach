import AppKit
import SwiftUI
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Custom estimate editor interaction state", .serialized)
struct CustomEstimateEditorStateTests {
    @Test
    func estimateSurfaceModesMountExactlyOneSurface() {
        #expect(EstimateSurfaceMode.today.showsToday)
        #expect(!EstimateSurfaceMode.today.showsPlanEditor)
        #expect(!EstimateSurfaceMode.planEditor.showsToday)
        #expect(EstimateSurfaceMode.planEditor.showsPlanEditor)
    }

    @Test
    func estimateSurfaceModesExposeStableAccessibilityContracts() {
        #expect(EstimateSurfaceMode.today.accessibilityIdentifier == "today.mode.command")
        #expect(EstimateSurfaceMode.today.accessibilityLabel == "Show Today command view")
        #expect(EstimateSurfaceMode.planEditor.accessibilityIdentifier == "today.mode.plan-editor")
        #expect(EstimateSurfaceMode.planEditor.accessibilityLabel == "Show Plan Editor estimate controls")
    }

    @Test
    func estimateSurfaceSwitchingIsBlockedWhileAnEditorIsPresented() {
        #expect(EstimateSurfaceMode.today.canSwitch(editorIsPresented: false))
        #expect(!EstimateSurfaceMode.today.canSwitch(editorIsPresented: true))
        #expect(EstimateSurfaceMode.planEditor.canSwitch(editorIsPresented: false))
        #expect(!EstimateSurfaceMode.planEditor.canSwitch(editorIsPresented: true))
    }

    @Test
    func planEditorKeepsSwitchingBlockedUntilEveryEditorCloses() {
        var presentation = EstimateEditorPresentationState()
        presentation.setPresented(true, taskID: "first")
        presentation.setPresented(true, taskID: "second")

        presentation.setPresented(false, taskID: "first")

        #expect(presentation.presentedTaskIDs == ["second"])
        #expect(presentation.hasPresentedEditor)
        #expect(!EstimateSurfaceMode.planEditor.canSwitch(
            editorIsPresented: presentation.hasPresentedEditor
        ))

        presentation.setPresented(false, taskID: "second")

        #expect(!presentation.hasPresentedEditor)
        #expect(EstimateSurfaceMode.planEditor.canSwitch(
            editorIsPresented: presentation.hasPresentedEditor
        ))
    }

    @Test
    func planEditorRemovesPresentationForRowsThatDisappear() {
        var presentation = EstimateEditorPresentationState()
        presentation.setPresented(true, taskID: "removed")
        presentation.setPresented(true, taskID: "retained")

        presentation.retain(taskIDs: ["retained"])

        #expect(presentation.presentedTaskIDs == ["retained"])
        #expect(presentation.hasPresentedEditor)
    }

    @Test
    func planEditorSnapshotRefreshClearsPresentationWhenNoRowsRemain() {
        var presentation = EstimateEditorPresentationState()
        presentation.setPresented(true, taskID: "expired")

        presentation.retain(taskIDs: [])

        #expect(presentation.presentedTaskIDs.isEmpty)
        #expect(!presentation.hasPresentedEditor)
    }

    @Test
    func closingOnePlanEditorDoesNotDiscardSiblingDraft() {
        var presentation = EstimateEditorPresentationState()
        var siblingDraft = CustomEstimateEditorState()
        siblingDraft.open(initialMinutes: nil)
        siblingDraft.input = " 25 "
        presentation.setPresented(true, taskID: "closed")
        presentation.setPresented(true, taskID: "sibling")

        presentation.setPresented(false, taskID: "closed")

        #expect(presentation.presentedTaskIDs == ["sibling"])
        #expect(presentation.hasPresentedEditor)
        #expect(siblingDraft.isPresented)
        #expect(siblingDraft.input == " 25 ")
    }

    @Test
    func editorStoreReportsPresentationUntilCancelOrSuccessfulSubmit() {
        var store = CustomEstimateEditorStateStore()
        #expect(!store.hasPresentedEditor)

        var state = store["task"]
        state.open(initialMinutes: nil)
        store["task"] = state
        #expect(store.hasPresentedEditor)

        state = store["task"]
        state.input = "0"
        #expect(!state.submit { _ in Issue.record("invalid estimate persisted") })
        store["task"] = state
        #expect(store.hasPresentedEditor)

        state = store["task"]
        state.cancel()
        store["task"] = state
        #expect(!store.hasPresentedEditor)

        state = store["task"]
        state.open(initialMinutes: nil)
        state.input = "25"
        #expect(state.submit { _ in })
        store["task"] = state
        #expect(!store.hasPresentedEditor)
    }

    @Test
    func planEditorEstimateAffordanceRemainsReachableWithNonNilSnapshot() throws {
        let main = DailyPlanEntry(
            reminderID: "main",
            rank: 1,
            isMainObjective: true,
            estimateMinutes: nil
        )
        let alreadyEstimated = DailyPlanEntry(
            reminderID: "secondary",
            rank: 2,
            isMainObjective: false,
            estimateMinutes: 45
        )
        let snapshot = dashboardEstimateSnapshot(rows: [
            dashboardEstimateTask(id: "main", title: "Write proposal"),
            dashboardEstimateTask(id: "secondary", title: "Send notes"),
        ])

        let missingEstimate = DashboardEstimatePlanningState.items(
            dailyPlan: [alreadyEstimated, main],
            snapshot: snapshot
        )
        let confirmedMain = DashboardEstimatePlanningState.items(
            dailyPlan: [DailyPlanEntry(
                reminderID: "main",
                rank: 1,
                isMainObjective: true,
                estimateMinutes: 25
            )],
            snapshot: snapshot
        )
        let refreshedWithoutTransientRow = DashboardEstimatePlanningState.items(
            dailyPlan: [main],
            snapshot: dashboardEstimateSnapshot(rows: []),
            liveTaskTitles: ["main": "Write proposal"]
        )

        #expect(missingEstimate.map(\.id) == ["main"])
        #expect(missingEstimate.first?.taskTitle == "Write proposal")
        #expect(confirmedMain.map(\.id) == ["main"])
        #expect(confirmedMain.first?.entry.estimateMinutes == 25)
        #expect(refreshedWithoutTransientRow.map(\.taskTitle) == ["Write proposal"])
    }

    @Test
    func planEditorEstimateAffordanceUsesLiveTitleForMissingEstimate() throws {
        let entry = DailyPlanEntry(
            reminderID: "local-task",
            rank: 2,
            isMainObjective: false,
            estimateMinutes: nil
        )
        let item = try #require(DashboardEstimatePlanningState.items(
            dailyPlan: [entry],
            snapshot: dashboardEstimateSnapshot(rows: []),
            liveTaskTitles: ["local-task": "Local planning task"]
        ).first)

        #expect(item.id == "local-task")
        #expect(item.taskTitle == "Local planning task")
    }

    @Test
    func planEditorPaddedValidEstimateRoutesExactlyOneMutation() throws {
        let entry = DailyPlanEntry(
            reminderID: "main",
            rank: 1,
            isMainObjective: true,
            estimateMinutes: nil
        )
        let item = try #require(DashboardEstimatePlanningState.items(
            dailyPlan: [entry],
            snapshot: dashboardEstimateSnapshot(rows: [
                dashboardEstimateTask(id: "main", title: "Write proposal"),
            ])
        ).first)
        var editor = CustomEstimateEditorState()
        var mutations: [(Int, String)] = []
        editor.open(initialMinutes: nil)
        editor.input = " 25 "

        let firstAccepted = editor.submit { minutes in
            item.persist(minutes: minutes) { persistedMinutes, persistedEntry in
                mutations.append((persistedMinutes, persistedEntry.reminderID))
            }
        }
        let secondAccepted = editor.submit { _ in
            Issue.record("closed Plan Editor submitted twice")
        }

        #expect(firstAccepted)
        #expect(!secondAccepted)
        #expect(mutations.count == 1)
        #expect(mutations.first?.0 == 25)
        #expect(mutations.first?.1 == "main")
    }

    @Test
    func tracePathRejectsTraversalOutsideQAContainment() {
        #expect(
            CustomEstimateEditorTrace.resolveTraceURL(environment: [
                "ZOID_COACH_QA_EDITOR_TRACE_PATH": "/private/tmp/zoid-666-zc011007-proof/../escaped.log",
            ]) == nil
        )
    }

    @Test
    func tracePathAcceptsCanonicalFileWithinQAContainment() {
        #expect(
            CustomEstimateEditorTrace.resolveTraceURL(environment: [
                "ZOID_COACH_QA_RUN_ROOT": "/private/tmp/zoid-666-zc011007-proof",
            ])?.path == "/private/tmp/zoid-666-zc011007-proof/editor-trace.log"
        )
    }

    @Test
    func tracePathRejectsSymlinkEscapeOutsideQAContainment() throws {
        let root = URL(fileURLWithPath: "/private/tmp/zoid-666-zc011007-trace-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: URL(fileURLWithPath: "/private/tmp")
        )
        #expect(
            CustomEstimateEditorTrace.resolveTraceURL(environment: [
                "ZOID_COACH_QA_EDITOR_TRACE_PATH": root.appendingPathComponent("escape/editor-trace.log").path,
            ]) == nil
        )
    }

    @Test
    func confirmedEstimateUsesExactSharedAccessibilityCopy() {
        #expect(
            CustomEstimateEditorState.confirmationAccessibilityLabel(minutes: 25)
                == "Time estimate confirmed: 25 MIN"
        )
    }

    @Test(arguments: [
        ("", "Enter an estimate in minutes."),
        ("   ", "Enter an estimate in minutes."),
        ("\u{00A0}\u{2003}", "Enter an estimate in minutes."),
        ("0", "Estimate must be at least 1 minute."),
        ("-15", "Estimate must be at least 1 minute."),
        ("1.5", "Use a whole number of minutes, such as 25."),
        ("tomorrow", "Use a whole number of minutes, such as 25."),
        ("٢٥", "Use a whole number of minutes, such as 25."),
        ("25,0", "Use a whole number of minutes, such as 25."),
        ("481", "Estimate must be 480 minutes or less. Split larger work into smaller tasks."),
    ])
    func invalidReturnRetainsExactCorrectionState(rawInput: String, expectedMessage: String) {
        var state = CustomEstimateEditorState()
        var persistenceCount = 0
        state.open(initialMinutes: nil)
        state.input = rawInput
        let initialFocusRequest = state.focusRequest
        let initialPresentationID = state.presentationID

        let accepted = state.submit { _ in persistenceCount += 1 }

        #expect(!accepted)
        #expect(state.isPresented)
        #expect(state.input == rawInput)
        #expect(state.validationMessage == expectedMessage)
        #expect(state.focusRequest == initialFocusRequest + 1)
        #expect(state.presentationID == initialPresentationID)
        #expect(persistenceCount == 0)
    }

    @Test
    func paddedValidReturnPersistsExactlyOnceAndClosesAcrossRapidResubmit() {
        var state = CustomEstimateEditorState()
        var persisted: [Int] = []
        state.open(initialMinutes: 45)
        state.input = " 25 "

        let firstAccepted = state.submit { persisted.append($0) }
        let secondAccepted = state.submit { persisted.append($0) }

        #expect(firstAccepted)
        #expect(!secondAccepted)
        #expect(persisted == [25])
        #expect(!state.isPresented)
        #expect(state.validationMessage == nil)
    }

    @Test
    func dashboardAndTodayParentSurfaceStatesDoNotResetEachOther() {
        var dashboard = CustomEstimateEditorState()
        var today = CustomEstimateEditorState()
        dashboard.open(initialMinutes: 30)
        today.open(initialMinutes: 60)
        dashboard.input = "0"
        today.input = " 90 "

        _ = dashboard.submit { _ in Issue.record("invalid dashboard value persisted") }

        #expect(dashboard.isPresented)
        #expect(dashboard.input == "0")
        #expect(dashboard.validationMessage != nil)
        #expect(today.isPresented)
        #expect(today.input == " 90 ")
        #expect(today.validationMessage == nil)
    }

    @Test
    func invalidReturnSurvivesTodayStripRemountByTaskIdentity() {
        let taskID = "task-a"
        let exactDraft = " \u{00A0}\u{2003}"
        var store = CustomEstimateEditorStateStore()
        var persisted: [Int] = []
        var mounted = store[taskID]
        mounted.open(initialMinutes: nil)
        mounted.input = exactDraft
        let presentationID = mounted.presentationID
        let focusRequest = mounted.focusRequest

        #expect(!mounted.submit { persisted.append($0) })
        store[taskID] = mounted

        let remounted = store[taskID]
        #expect(remounted.isPresented)
        #expect(remounted.input == exactDraft)
        #expect(remounted.validationMessage == "Enter an estimate in minutes.")
        #expect(remounted.focusRequest == focusRequest + 1)
        #expect(remounted.presentationID == presentationID)
        #expect(persisted.isEmpty)
    }

    @Test
    func todayEditorStateIsIndependentByTaskAndFromDashboardSurface() {
        var todayStore = CustomEstimateEditorStateStore()
        var todayTaskA = todayStore["task-a"]
        todayTaskA.open(initialMinutes: nil)
        todayTaskA.input = "0"
        _ = todayTaskA.submit { _ in Issue.record("invalid Today value persisted") }
        todayStore["task-a"] = todayTaskA

        var dashboard = CustomEstimateEditorState()
        dashboard.open(initialMinutes: 60)
        dashboard.input = " 90 "

        #expect(todayStore["task-a"].validationMessage != nil)
        #expect(!todayStore["task-b"].isPresented)
        #expect(todayStore["task-b"].input.isEmpty)
        #expect(dashboard.isPresented)
        #expect(dashboard.input == " 90 ")
        #expect(dashboard.validationMessage == nil)
    }

    @Test
    func cancelAndSuccessRemoveTodayStateWithoutLeakingOnReopen() {
        let taskID = "task-a"
        var store = CustomEstimateEditorStateStore()
        var cancelled = store[taskID]
        cancelled.open(initialMinutes: nil)
        cancelled.input = "0"
        _ = cancelled.submit { _ in Issue.record("invalid value persisted") }
        store[taskID] = cancelled
        cancelled.cancel()
        store[taskID] = cancelled

        #expect(!store.contains(taskID))
        #expect(store[taskID].input.isEmpty)
        #expect(store[taskID].validationMessage == nil)

        var reopened = store[taskID]
        reopened.open(initialMinutes: nil)
        reopened.input = " 25 "
        store[taskID] = reopened
        var remounted = store[taskID]
        var persisted: [Int] = []
        #expect(remounted.submit { persisted.append($0) })
        store[taskID] = remounted

        #expect(persisted == [25])
        #expect(!store.contains(taskID))
        #expect(!store[taskID].isPresented)
        #expect(store[taskID].input.isEmpty)
        #expect(store[taskID].validationMessage == nil)
    }

    @Test
    func disappearingTaskRemovesOnlyItsTodayEditorState() {
        var store = CustomEstimateEditorStateStore()
        for taskID in ["task-a", "task-b"] {
            var state = store[taskID]
            state.open(initialMinutes: nil)
            store[taskID] = state
        }

        store.retain(taskIDs: ["task-b"])

        #expect(!store.contains("task-a"))
        #expect(store.contains("task-b"))
    }

    @Test
    func activatingTodayHostIsIdempotentAndKeepsOneOwnershipRecord() {
        let taskID = "task-a"
        var store = CustomEstimateEditorStateStore()
        var state = store[taskID]
        state.open(initialMinutes: nil)
        store[taskID] = state
        for _ in 0..<10_000 {
            store.activateHost(path: "plan", taskID: taskID)
        }

        #expect(store.hostOwnershipCount == 1)
        #expect(store.isActiveHost(path: "plan", taskID: taskID))
        #expect(!store.isActiveHost(path: "focus", taskID: taskID))
        #expect(store[taskID] == state)
    }

    @Test
    func competingTodayPathsRemainExclusiveAcrossTransientSamePathRemount() {
        let taskID = "task-a"
        var store = CustomEstimateEditorStateStore()
        var state = store[taskID]
        state.open(initialMinutes: nil)
        state.input = "   "
        _ = state.submit { _ in Issue.record("invalid value persisted") }
        store[taskID] = state
        store.activateHost(path: "plan", taskID: taskID)

        for _ in 0..<1_000 {
            #expect(store.isActiveHost(path: "plan", taskID: taskID))
            #expect(!store.isActiveHost(path: "focus", taskID: taskID))
        }
        #expect(store[taskID].isPresented)
        #expect(store[taskID].input == "   ")
        #expect(store[taskID].validationMessage == "Enter an estimate in minutes.")
        #expect(store[taskID].focusRequest == state.focusRequest)
        #expect(store[taskID].presentationID == state.presentationID)

        store.activateHost(path: "focus", taskID: taskID)

        #expect(store.isActiveHost(path: "focus", taskID: taskID))
        #expect(!store.isActiveHost(path: "plan", taskID: taskID))
        #expect(store.hostOwnershipCount == 1)
    }

    @MainActor
    @Test
    func activePathReadsStayAtOneMountAcrossBoundedViewInvalidations() async {
        let box = HostMountBox()
        box.store.activateHost(path: "plan", taskID: "task-a")
        let host = NSHostingView(rootView: HostMountRegressionProbe(
            isActive: { box.store.isActiveHost(path: "plan", taskID: "task-a") },
            appeared: { box.mountCount += 1 },
            completed: { box.completed = true }
        ))
        host.frame = CGRect(x: 0, y: 0, width: 200, height: 80)
        host.layoutSubtreeIfNeeded()

        #expect(await waitUntil { box.completed })
        #expect(box.mountCount == 1)
        #expect(box.store.hostOwnershipCount == 1)
        withExtendedLifetime(host) {}
    }

    @MainActor
    @Test(arguments: [
        UInt16(36),
        UInt16(76),
    ])
    func physicalReturnSynchronizesExactTextAndRetainsInvalidEditorFocusRequestAndError(
        keyCode: UInt16
    ) {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let initialFocusRequest = box.state.focusRequest
        let field = CustomEstimateTextField(string: "\u{00A0}\u{2003}")
        field.onReturn = { exactText in
            box.returnCallbackCount += 1
            box.state.input = exactText
            _ = box.state.submit { box.persisted.append($0) }
        }

        let handled = field.handleReturn(
            keyEvent(keyCode: keyCode),
            exactText: field.stringValue
        )

        #expect(handled)
        #expect(field.accessibilityRole() == .textField)
        #expect(box.returnCallbackCount == 1)
        #expect(box.state.input == "\u{00A0}\u{2003}")
        #expect(box.state.isPresented)
        #expect(box.state.validationMessage == "Enter an estimate in minutes.")
        #expect(box.state.focusRequest == initialFocusRequest + 1)
        #expect(box.persisted.isEmpty)
    }

    @MainActor
    @Test
    func rapidPhysicalReturnPersistsPaddedValidInputExactlyOnce() {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let field = CustomEstimateTextField(string: " 25 ")
        field.onReturn = { exactText in
            box.returnCallbackCount += 1
            box.state.input = exactText
            _ = box.state.submit { box.persisted.append($0) }
        }

        let returnEvent = keyEvent(keyCode: 36)
        let firstHandled = field.handleReturn(returnEvent, exactText: field.stringValue)
        let secondHandled = field.handleReturn(returnEvent, exactText: field.stringValue)

        #expect(firstHandled)
        #expect(secondHandled)
        #expect(box.returnCallbackCount == 2)
        #expect(box.state.input == " 25 ")
        #expect(box.persisted == [25])
        #expect(!box.state.isPresented)
        #expect(box.state.validationMessage == nil)
    }

    @MainActor
    @Test(arguments: [UInt16(48), UInt16(53), UInt16(123)])
    func tabEscapeAndNonReturnKeysPassThroughWithoutSubmitting(keyCode: UInt16) {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let initialFocusRequest = box.state.focusRequest
        let field = CustomEstimateTextField(string: "25")
        field.onReturn = { _ in box.returnCallbackCount += 1 }

        let handled = field.handleReturn(
            keyEvent(keyCode: keyCode),
            exactText: field.stringValue
        )

        #expect(!handled)
        #expect(box.returnCallbackCount == 0)
        #expect(box.state.input.isEmpty)
        #expect(box.state.isPresented)
        #expect(box.state.validationMessage == nil)
        #expect(box.state.focusRequest == initialFocusRequest)
        #expect(box.persisted.isEmpty)
    }

    @MainActor
    @Test
    func monitorInstallsOnceAndInterceptsOnlyItsExactCurrentEditor() {
        let box = InteractionBox()
        let field = CustomEstimateTextField(string: "")
        let editor = NSTextView()
        editor.string = " 25 "
        let otherResponder = NSTextView()
        field.onReturn = { exactText in
            box.returnCallbackCount += 1
            box.state.input = exactText
        }
        field.installKeyMonitorIfNeeded()
        field.installKeyMonitorIfNeeded()
        defer { field.removeKeyMonitor() }

        let returnEvent = keyEvent(keyCode: 36)
        let passedThrough = field.filteredEvent(
            returnEvent,
            editor: editor,
            firstResponder: otherResponder
        )
        let consumed = field.filteredEvent(
            returnEvent,
            editor: editor,
            firstResponder: editor
        )

        #expect(field.hasInstalledKeyMonitor)
        #expect(field.keyMonitorInstallCount == 1)
        #expect(passedThrough === returnEvent)
        #expect(consumed == nil)
        #expect(field.lastReturnHandling == .monitor)
        #expect(field.returnHandlingCount == 1)
        #expect(box.returnCallbackCount == 1)
        #expect(box.state.input == " 25 ")
    }

    @MainActor
    @Test(arguments: [
        (NSTextMovement.return.rawValue, true),
        (NSTextMovement.tab.rawValue, false),
        (NSTextMovement.backtab.rawValue, false),
        (NSTextMovement.cancel.rawValue, false),
        (NSTextMovement.other.rawValue, false),
    ])
    func endEditingFallbackSubmitsOnlyReturnMovement(
        movementValue: Int,
        expectsSubmission: Bool
    ) {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let initialFocusRequest = box.state.focusRequest
        let input = CustomEstimateInputField(
            text: Binding(
                get: { box.state.input },
                set: { box.state.input = $0 }
            ),
            focusRequest: box.state.focusRequest,
            submit: { exactText in
                box.returnCallbackCount += 1
                box.state.input = exactText
                return box.state.submit { box.persisted.append($0) }
            }
        )
        let coordinator = input.makeCoordinator()
        let field = CustomEstimateTextField(string: "\u{00A0}\u{2003}")

        coordinator.controlTextDidEndEditing(Notification(
            name: NSControl.textDidEndEditingNotification,
            object: field,
            userInfo: [NSText.movementUserInfoKey: movementValue]
        ))

        if expectsSubmission {
            #expect(box.returnCallbackCount == 1)
            #expect(box.state.input == "\u{00A0}\u{2003}")
            #expect(box.state.isPresented)
            #expect(box.state.validationMessage == "Enter an estimate in minutes.")
            #expect(box.state.focusRequest == initialFocusRequest + 1)
        } else {
            #expect(box.returnCallbackCount == 0)
            #expect(box.state.input.isEmpty)
            #expect(box.state.validationMessage == nil)
            #expect(box.state.focusRequest == initialFocusRequest)
        }
        #expect(box.persisted.isEmpty)
    }

    @MainActor
    @Test
    func endEditingReturnPersistsPaddedValidInputExactlyOnceAndCloses() {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let input = CustomEstimateInputField(
            text: Binding(
                get: { box.state.input },
                set: { box.state.input = $0 }
            ),
            focusRequest: box.state.focusRequest,
            submit: { exactText in
                box.returnCallbackCount += 1
                box.state.input = exactText
                return box.state.submit { box.persisted.append($0) }
            }
        )
        let coordinator = input.makeCoordinator()
        let field = CustomEstimateTextField(string: " 25 ")

        coordinator.controlTextDidEndEditing(Notification(
            name: NSControl.textDidEndEditingNotification,
            object: field,
            userInfo: [NSText.movementUserInfoKey: NSTextMovement.return.rawValue]
        ))

        #expect(box.returnCallbackCount == 1)
        #expect(box.state.input == " 25 ")
        #expect(box.persisted == [25])
        #expect(!box.state.isPresented)
        #expect(box.state.validationMessage == nil)
    }

    @MainActor
    @Test
    func twoConsecutiveInvalidReturnsCarryFocusGenerationAcrossRemount() {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let initialFocusRequest = box.state.focusRequest
        func input() -> CustomEstimateInputField {
            CustomEstimateInputField(
                text: Binding(
                    get: { box.state.input },
                    set: { box.state.input = $0 }
                ),
                focusRequest: box.state.focusRequest,
                submit: { exactText in
                    box.returnCallbackCount += 1
                    box.state.input = exactText
                    return box.state.submit { box.persisted.append($0) }
                }
            )
        }
        let coordinator = input().makeCoordinator()
        let field = CustomEstimateTextField(string: "")

        coordinator.controlTextDidEndEditing(Notification(
            name: NSControl.textDidEndEditingNotification,
            object: field,
            userInfo: [NSText.movementUserInfoKey: NSTextMovement.return.rawValue]
        ))
        #expect(field.lastReturnHandling == .endEditingFallback)
        #expect(field.returnHandlingCount == 1)
        #expect(field.requestedFocusGeneration == initialFocusRequest + 1)

        coordinator.parent = input()
        field.stringValue = "   "
        coordinator.controlTextDidEndEditing(Notification(
            name: NSControl.textDidEndEditingNotification,
            object: field,
            userInfo: [NSText.movementUserInfoKey: NSTextMovement.return.rawValue]
        ))

        #expect(box.returnCallbackCount == 2)
        #expect(box.state.focusRequest == initialFocusRequest + 2)
        #expect(field.lastReturnHandling == .endEditingFallback)
        #expect(field.returnHandlingCount == 2)
        #expect(field.requestedFocusGeneration == initialFocusRequest + 2)
        #expect(box.state.input == "   ")
        #expect(box.state.validationMessage == "Enter an estimate in minutes.")
        #expect(box.persisted.isEmpty)

        let remountedField = CustomEstimateTextField(string: box.state.input)
        remountedField.requestFocus(
            presentationID: box.state.presentationID,
            generation: box.state.focusRequest
        )
        #expect(remountedField.requestedFocusGeneration == initialFocusRequest + 2)
    }

    @MainActor
    @Test
    func detachedFocusLeaseExpiresWithoutRetainingIdentityOrStealingFocus() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 60),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        let field = CustomEstimateTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        container.addSubview(field)
        field.requestFocus(presentationID: UUID(), generation: 1)
        field.removeFromSuperview()

        let expired = await waitUntil { !field.isFocusLeaseActive }

        #expect(expired)
        #expect(field.window == nil)
        #expect(!field.hasInputFocus)
        #expect(!field.isFocusLeaseActive)
        #expect(field.requestedPresentationID == nil)
        #expect(field.requestedFocusGeneration == nil)
    }

    @MainActor
    @Test
    func focusLeaseSurvivesTransientWindowDetachmentUntilSameEditorReattaches() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        let field = CustomEstimateTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        let otherField = NSTextField(frame: NSRect(x: 100, y: 0, width: 80, height: 24))
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        container.addSubview(field)
        container.addSubview(otherField)
        let presentationID = UUID()
        field.stringValue = "draft"
        field.installKeyMonitorIfNeeded()
        let monitorInstallCount = field.keyMonitorInstallCount
        field.requestFocus(presentationID: presentationID, generation: 1)

        field.removeFromSuperview()
        #expect(field.window == nil)
        #expect(field.isFocusLeaseActive)
        #expect(field.hasInstalledKeyMonitor)
        let detachedEditor = NSTextView()
        let detachedReturn = keyEvent(keyCode: 36)
        let detachedResult = field.filteredEvent(
            detachedReturn,
            editor: field.currentEditor(),
            firstResponder: detachedEditor
        )
        #expect(detachedResult === detachedReturn)
        #expect(field.returnHandlingCount == 0)
        container.addSubview(field)
        #expect(field.window === window)
        #expect(field.hasInputFocus)
        #expect(field.currentEditor()?.selectedRange == NSRange(location: 5, length: 0))
        #expect(field.hasInstalledKeyMonitor)
        #expect(field.keyMonitorInstallCount == monitorInstallCount)

        #expect(window.makeFirstResponder(otherField))
        let recoveredAfterReattach = await waitUntil { field.hasInputFocus }
        #expect(recoveredAfterReattach)
        #expect(field.hasInputFocus)
        #expect(field.requestedPresentationID == presentationID)
        #expect(field.requestedFocusGeneration == 1)
        field.cancelFocusLease()
    }

    @MainActor
    @Test
    func focusLeaseRecoversFromPostAttemptFocusTheftAndStopsAfterCancellation() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        let field = CustomEstimateTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        let otherField = NSButton(frame: NSRect(x: 100, y: 0, width: 80, height: 24))
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        container.addSubview(field)
        container.addSubview(otherField)
        let presentationID = UUID()

        field.requestFocus(presentationID: presentationID, generation: 1)
        #expect(field.hasInputFocus)
        #expect(field.currentEditor()?.selectedRange == NSRange(location: 0, length: 0))
        #expect(window.firstResponder === field.currentEditor())
        #expect(window.makeFirstResponder(otherField))
        #expect(!field.hasInputFocus)

        let recoveredAfterTheft = await waitUntil { field.hasInputFocus }
        #expect(recoveredAfterTheft)
        #expect(field.hasInputFocus)
        #expect(field.appliedFocusGeneration == 1)
        #expect(field.currentEditor()?.selectedRange == NSRange(location: 0, length: 0))

        field.cancelFocusLease()
        #expect(window.makeFirstResponder(otherField))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(!field.hasInputFocus)
        #expect(!field.isFocusLeaseActive)
    }

    @MainActor
    @Test
    func focusLeaseCancelsOnSuccessAndTeardownAndSupersedesOlderIdentity() {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let input = CustomEstimateInputField(
            text: Binding(
                get: { box.state.input },
                set: { box.state.input = $0 }
            ),
            focusRequest: box.state.focusRequest,
            presentationID: box.state.presentationID,
            submit: { exactText in
                box.state.input = exactText
                return box.state.submit { box.persisted.append($0) }
            }
        )
        let coordinator = input.makeCoordinator()
        let field = CustomEstimateTextField(string: " 25 ")
        let olderPresentationID = UUID()
        field.requestFocus(presentationID: olderPresentationID, generation: 1)
        field.requestFocus(presentationID: box.state.presentationID, generation: 2)
        #expect(field.requestedPresentationID == box.state.presentationID)
        #expect(field.requestedFocusGeneration == 2)
        #expect(field.isFocusLeaseActive)

        #expect(coordinator.submit(" 25 ", refocusing: field))
        #expect(box.persisted == [25])
        #expect(!field.isFocusLeaseActive)
        #expect(field.requestedPresentationID == nil)
        #expect(field.requestedFocusGeneration == nil)

        field.requestFocus(presentationID: UUID(), generation: 3)
        CustomEstimateInputField.dismantleNSView(field, coordinator: coordinator)
        #expect(!field.isFocusLeaseActive)
        #expect(field.requestedPresentationID == nil)
        #expect(field.requestedFocusGeneration == nil)
    }

    @MainActor
    @Test
    func dismantleAndDeinitRemoveOwnedKeyMonitors() {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let input = CustomEstimateInputField(
            text: Binding(
                get: { box.state.input },
                set: { box.state.input = $0 }
            ),
            focusRequest: box.state.focusRequest,
            submit: { _ in false }
        )
        let coordinator = input.makeCoordinator()
        let dismantledField = CustomEstimateTextField(string: "")
        dismantledField.onMonitorRemoved = { box.monitorRemovalCount += 1 }
        dismantledField.installKeyMonitorIfNeeded()

        CustomEstimateInputField.dismantleNSView(
            dismantledField,
            coordinator: coordinator
        )

        #expect(!dismantledField.hasInstalledKeyMonitor)
        #expect(box.monitorRemovalCount == 1)

        weak var releasedField: CustomEstimateTextField?
        autoreleasepool {
            var field: CustomEstimateTextField? = CustomEstimateTextField(string: "")
            field?.onMonitorRemoved = { box.monitorRemovalCount += 1 }
            field?.installKeyMonitorIfNeeded()
            releasedField = field
            field = nil
        }

        #expect(releasedField == nil)
        #expect(box.monitorRemovalCount == 2)
    }

    @Test
    func legacyParserBoundariesRemainExact() {
        #expect(TaskEstimateInput.parse(" 1 ") == .success(1))
        #expect(TaskEstimateInput.parse("480") == .success(480))
        #expect(TaskEstimateInput.parse("0") == .failure(.nonPositive))
        #expect(TaskEstimateInput.parse("481") == .failure(.tooLarge(maximum: 480)))
        #expect(TaskEstimateInput.parse("٢٥") == .failure(.malformed))
        #expect(TaskEstimateInput.parse("25,0") == .failure(.malformed))
    }

    @MainActor
    private final class InteractionBox {
        var state = CustomEstimateEditorState()
        var persisted: [Int] = []
        var returnCallbackCount = 0
        var monitorRemovalCount = 0
    }

    @MainActor
    private final class HostMountBox {
        var store = CustomEstimateEditorStateStore()
        var mountCount = 0
        var completed = false
    }

    private struct HostMountRegressionProbe: View {
        @State private var invalidationCount = 0
        let isActive: () -> Bool
        let appeared: () -> Void
        let completed: () -> Void

        var body: some View {
            Text(isActive() ? "active \(invalidationCount)" : "inactive")
                .onAppear(perform: appeared)
                .task {
                    for _ in 0..<250 {
                        invalidationCount += 1
                        await Task.yield()
                    }
                    completed()
                }
        }
    }

    @MainActor
    private func keyEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

private func dashboardEstimateTask(id: String, title: String) -> TodayTaskRow {
    TodayTaskRow(
        taskID: id,
        title: title,
        estimateMinutes: 25,
        dueDate: nil,
        urgency: .medium,
        state: .ready,
        isMainObjective: id == "main"
    )
}

private func dashboardEstimateSnapshot(rows: [TodayTaskRow]) -> TodaySnapshot {
    TodaySnapshot(
        localDate: Date(timeIntervalSince1970: 1_800_000_000),
        timeZoneIdentifier: "UTC",
        mainObjective: rows.first(where: \.isMainObjective)?.title,
        taskRows: rows,
        activeTask: nil,
        recommendation: NextTaskRecommendation(
            taskID: rows.first?.taskID,
            sentence: "Continue with the plan",
            reasons: []
        ),
        behavior: BehaviorSummary(),
        coverage: TelemetryCoverage(
            isLimited: false,
            explanation: "Current",
            lastObservationAt: nil
        ),
        gaming: GamingStatus(
            budgetMinutes: 60,
            usedMinutes: 0,
            unlockedRemainingMinutes: 0,
            nextUnlockReason: "Complete the main objective",
            confidenceIsLimited: false
        ),
        sourceFreshnessExplanation: "Current"
    )
}
