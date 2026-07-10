import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func voicePersistenceRetainsDurableFactsAndPrunesExpiredTranscripts() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-voice-store-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let store = try VoicePersistenceStore(databaseURL: databaseURL)
    let now = Date(timeIntervalSince1970: 1_720_000_000)
    let session = VoiceSession(
        id: "session-1",
        activationSource: .globalHotkey,
        state: .listening,
        provider: "gemini",
        model: "gemini-3.1-flash-live-preview",
        startedAt: now.addingTimeInterval(-3_600)
    )
    let oldTurn = ConversationTurn(
        id: "turn-old",
        sessionID: session.id,
        role: .user,
        text: "Old private transcript",
        isFinal: true,
        createdAt: now.addingTimeInterval(-31 * 86_400)
    )
    let recentTurn = ConversationTurn(
        id: "turn-recent",
        sessionID: session.id,
        role: .assistant,
        text: "Your next task is ready.",
        isFinal: true,
        createdAt: now
    )
    let fact = ConversationMemoryFact(
        id: "fact-1",
        kind: .goal,
        value: "Ship Zoid Voice",
        sourceTurnID: recentTurn.id,
        isConfirmed: true,
        expiresAt: nil,
        createdAt: now,
        updatedAt: now
    )

    try store.save(session)
    try store.append(oldTurn)
    try store.append(recentTurn)
    try store.save(fact)
    try store.pruneTranscripts(olderThan: now.addingTimeInterval(-30 * 86_400))

    #expect(try store.turns(sessionID: session.id) == [recentTurn])
    #expect(try store.activeMemoryFacts(at: now) == [fact])
    #expect(try store.session(id: session.id) == session)
}

@Test
func voiceUsageAndCodexJobsSurviveProcessRestart() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-voice-restart-\(UUID().uuidString).sqlite")
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let now = Date(timeIntervalSince1970: 1_720_000_000)
    let usage = VoiceUsageLedger(periodStart: now, consumedUSDMicros: 14_500_000)
    let job = CodexJob(
        id: "job-1",
        workspacePath: "/tmp/project",
        objective: "Inspect the failing test",
        sandbox: .readOnly,
        state: .queued,
        createdAt: now
    )
    do {
        let writer = try VoicePersistenceStore(databaseURL: databaseURL)
        try writer.save(usage, updatedAt: now)
        try writer.save(job)
    }

    let reader = try VoicePersistenceStore(databaseURL: databaseURL)

    #expect(try reader.latestUsageLedger() == usage)
    #expect(try reader.codexJob(id: job.id) == job)
}
