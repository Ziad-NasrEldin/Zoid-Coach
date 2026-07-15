import AppKit
import SwiftUI
import Testing
@testable import ZoidCoachApp

@Suite("Custom estimate editor interaction state")
struct CustomEstimateEditorStateTests {
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
        container.addSubview(field)
        field.requestFocus(presentationID: UUID(), generation: 1)
        field.removeFromSuperview()

        try? await Task.sleep(for: .milliseconds(220))

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
        container.addSubview(field)
        container.addSubview(otherField)
        let presentationID = UUID()
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
        #expect(field.hasInstalledKeyMonitor)
        #expect(field.keyMonitorInstallCount == monitorInstallCount)

        #expect(window.makeFirstResponder(otherField))
        try? await Task.sleep(for: .milliseconds(80))
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
        let otherField = NSTextField(frame: NSRect(x: 100, y: 0, width: 80, height: 24))
        window.contentView = container
        container.addSubview(field)
        container.addSubview(otherField)
        let presentationID = UUID()

        field.requestFocus(presentationID: presentationID, generation: 1)
        #expect(field.hasInputFocus)
        #expect(window.makeFirstResponder(otherField))
        #expect(!field.hasInputFocus)

        try? await Task.sleep(for: .milliseconds(80))
        #expect(field.hasInputFocus)
        #expect(field.appliedFocusGeneration == 1)

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
}
