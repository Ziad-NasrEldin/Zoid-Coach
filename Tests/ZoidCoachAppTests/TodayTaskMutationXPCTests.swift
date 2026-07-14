import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func pendingMutationIdentitySurvivesClientRelaunchUntilCompletion() throws {
    let suiteName = "zoid666-mutation-client-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else { return }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let firstClient = TaskMutationClientState(defaults: defaults, namespace: "test-agent")
    let first = firstClient.request(command: .complete, taskID: "task-1")
    let relaunchedClient = TaskMutationClientState(defaults: defaults, namespace: "test-agent")
    let retried = relaunchedClient.request(command: .complete, taskID: "task-1")
    #expect(retried.operationID == first.operationID)
    #expect(retried.requestedAt == first.requestedAt)

    relaunchedClient.complete(retried)
    let nextGesture = relaunchedClient.request(command: .complete, taskID: "task-1")
    #expect(nextGesture.operationID != first.operationID)
}

@Test
func changedBlockReasonStartsANewUserOperation() throws {
    let suiteName = "zoid666-mutation-block-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else { return }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = TaskMutationClientState(defaults: defaults, namespace: "test-agent")

    let first = state.request(command: .block, taskID: "task-1", blockedReason: "Waiting for design")
    let corrected = state.request(command: .block, taskID: "task-1", blockedReason: "Waiting for approval")

    #expect(corrected.operationID != first.operationID)
}
