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

@Test
func terminalValidationClearsFailedClientIdentityForACorrectedGesture() throws {
    let suiteName = "zoid666-mutation-terminal-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else { return }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = TaskMutationClientState(defaults: defaults, namespace: "test-agent")
    let failed = state.request(command: .block, taskID: "task-1", blockedReason: "x")

    state.complete(failed)
    let corrected = state.request(command: .block, taskID: "task-1", blockedReason: "Waiting for approval")

    #expect(corrected.operationID != failed.operationID)
}

@Test
func pendingMutationIdentityUsesTheRuntimeIsolatedDefaultsSuite() throws {
    let first = try taskMutationQARuntime("first")
    let second = try taskMutationQARuntime("second")
    defer {
        if let suite = first.userDefaultsSuiteName {
            first.makeUserDefaults().removePersistentDomain(forName: suite)
        }
        if let suite = second.userDefaultsSuiteName {
            second.makeUserDefaults().removePersistentDomain(forName: suite)
        }
    }

    let initialClient = TodayDashboardXPCClient(runtimeEnvironment: first)
    let initial = initialClient.mutationState.request(command: .complete, taskID: "task-1")
    let relaunched = TodayDashboardXPCClient(runtimeEnvironment: first)
        .mutationState.request(command: .complete, taskID: "task-1")
    let otherRun = TodayDashboardXPCClient(runtimeEnvironment: second)
        .mutationState.request(command: .complete, taskID: "task-1")

    #expect(relaunched.operationID == initial.operationID)
    #expect(otherRun.operationID != initial.operationID)
}

private func taskMutationQARuntime(_ label: String) throws -> RuntimeEnvironment {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("task-mutation-client-\(label)-\(UUID().uuidString)", isDirectory: true)
    return try RuntimeEnvironment.resolve(
        arguments: [],
        processEnvironment: [:],
        packagedRuntime: .init(
            mode: .qa,
            qaRunRoot: root,
            appBundleIdentifier: RuntimeIdentity.qa.appBundleIdentifier
        ),
        executableSigningIdentifier: RuntimeIdentity.qa.appSigningIdentifier
    ).environment
}
