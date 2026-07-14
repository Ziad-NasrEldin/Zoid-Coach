import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func operationKeySurvivesStoreRelaunchAndReceiptsAreIdempotent() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-operation")
    defer { removeDatabaseFiles(at: databaseURL) }
    let id = UUID()
    let requestedAt = Date(timeIntervalSince1970: 1_752_489_600)

    do {
        let store = try TaskMutationOperationStore(databaseURL: databaseURL)
        let operation = try store.begin(id: id, taskID: "task-1", command: .complete, requestedAt: requestedAt)
        #expect(operation.state == .pending)
        try store.completeStep(operationID: id, step: "execution", at: requestedAt)
        try store.completeStep(operationID: id, step: "execution", at: requestedAt)
    }

    let reopened = try TaskMutationOperationStore(databaseURL: databaseURL)
    #expect(try reopened.load(id: id)?.requestedAt == requestedAt)
    #expect(try reopened.hasCompletedStep(operationID: id, step: "execution"))
}

@Test
func reusedOperationKeyCannotChangeItsMutation() throws {
    let databaseURL = temporaryDatabaseURL("task-mutation-conflict")
    defer { removeDatabaseFiles(at: databaseURL) }
    let store = try TaskMutationOperationStore(databaseURL: databaseURL)
    let id = UUID()
    _ = try store.begin(id: id, taskID: "task-1", command: .complete, requestedAt: Date())

    #expect(throws: TaskMutationOperationStoreError.operationKeyConflict) {
        try store.begin(id: id, taskID: "task-2", command: .start, requestedAt: Date())
    }
}

private func temporaryDatabaseURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-\(name)-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("zoid.sqlite")
}

private func removeDatabaseFiles(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}
