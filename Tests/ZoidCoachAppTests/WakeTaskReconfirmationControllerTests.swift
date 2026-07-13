import XCTest
@testable import ZoidCoachApp

@MainActor
final class WakeTaskReconfirmationControllerTests: XCTestCase {
    func testShortAbsenceKeepsTaskActiveAndExplainsCoverageBoundary() {
        let controller = WakeTaskReconfirmationController(longAbsenceThreshold: 300)
        let start = Date(timeIntervalSince1970: 1_000)

        controller.noteInactive(at: start)
        controller.reconcileActivation(
            activeTaskID: "task-1",
            taskTitle: "Prepare release notes",
            at: start.addingTimeInterval(120)
        )

        XCTAssertNil(controller.pendingConfirmation)
        XCTAssertEqual(controller.notice?.taskTitle, "Prepare release notes")
        XCTAssertEqual(controller.notice?.inactiveDuration, 120)
        XCTAssertTrue(controller.notice?.message.contains("Only observed activity counts as aligned work") == true)
    }

    func testLongAbsenceRequiresExplicitTaskConfirmation() {
        let controller = WakeTaskReconfirmationController(longAbsenceThreshold: 300)
        let start = Date(timeIntervalSince1970: 1_000)

        controller.noteInactive(at: start)
        controller.reconcileActivation(
            activeTaskID: "task-1",
            taskTitle: "Prepare release notes",
            at: start.addingTimeInterval(901)
        )

        XCTAssertEqual(controller.pendingConfirmation?.taskID, "task-1")
        XCTAssertEqual(controller.pendingConfirmation?.taskTitle, "Prepare release notes")
        XCTAssertEqual(controller.pendingConfirmation?.inactiveDuration, 901)
        XCTAssertNil(controller.notice)
    }

    func testContinuingAfterLongAbsenceClosesPromptAndShowsReconciliation() {
        let controller = WakeTaskReconfirmationController(longAbsenceThreshold: 300)
        let start = Date(timeIntervalSince1970: 1_000)
        controller.noteInactive(at: start)
        controller.reconcileActivation(
            activeTaskID: "task-1",
            taskTitle: "Prepare release notes",
            at: start.addingTimeInterval(600)
        )

        controller.confirmTaskIsStillActive()

        XCTAssertNil(controller.pendingConfirmation)
        XCTAssertEqual(controller.notice?.inactiveDuration, 600)
    }

    func testPausingAfterLongAbsenceClearsPromptWithoutClaimingAlignedTime() {
        let controller = WakeTaskReconfirmationController(longAbsenceThreshold: 300)
        let start = Date(timeIntervalSince1970: 1_000)
        controller.noteInactive(at: start)
        controller.reconcileActivation(
            activeTaskID: "task-1",
            taskTitle: "Prepare release notes",
            at: start.addingTimeInterval(600)
        )

        controller.confirmTaskWasInterrupted()

        XCTAssertNil(controller.pendingConfirmation)
        XCTAssertNil(controller.notice)
    }

    func testNoActiveTaskProducesNoWakeUI() {
        let controller = WakeTaskReconfirmationController(longAbsenceThreshold: 300)
        let start = Date(timeIntervalSince1970: 1_000)
        controller.noteInactive(at: start)

        controller.reconcileActivation(
            activeTaskID: nil,
            taskTitle: nil,
            at: start.addingTimeInterval(600)
        )

        XCTAssertNil(controller.pendingConfirmation)
        XCTAssertNil(controller.notice)
    }

    func testRepeatedInactiveEventsKeepOriginalAbsenceBoundary() {
        let controller = WakeTaskReconfirmationController(longAbsenceThreshold: 300)
        let start = Date(timeIntervalSince1970: 1_000)
        controller.noteInactive(at: start)
        controller.noteInactive(at: start.addingTimeInterval(120))

        controller.reconcileActivation(
            activeTaskID: "task-1",
            taskTitle: "Prepare release notes",
            at: start.addingTimeInterval(360)
        )

        XCTAssertEqual(controller.pendingConfirmation?.inactiveDuration, 360)
    }
}
