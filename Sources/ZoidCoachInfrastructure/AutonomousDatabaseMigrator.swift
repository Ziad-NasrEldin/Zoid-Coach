import Foundation
import SQLite3
import ZoidCoachCore

public struct AutonomousMigrationResult: Equatable, Sendable {
    public let previousVersion: Int
    public let currentVersion: Int
    public let appliedVersions: [Int]
    public let backupURL: URL?

    public init(previousVersion: Int, currentVersion: Int, appliedVersions: [Int], backupURL: URL?) {
        self.previousVersion = previousVersion
        self.currentVersion = currentVersion
        self.appliedVersions = appliedVersions
        self.backupURL = backupURL
    }
}

public final class AutonomousDatabaseMigrator: @unchecked Sendable {
    public static let currentVersion = 19

    private let databaseURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.now = now
    }

    @discardableResult
    public func migrate() throws -> AutonomousMigrationResult {
        try fileManager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database
        else { throw AutonomousDatabaseMigrationError.openDatabase }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        guard sqlite3_exec(database, "PRAGMA journal_mode = WAL;", nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(database, "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);", nil, nil, nil) == SQLITE_OK
        else { throw AutonomousDatabaseMigrationError.prepareSchema(errorMessage(database)) }

        let previousVersion = try maximumAppliedVersion(database)
        let pending = Self.migrations.filter { $0.version > previousVersion }
        var backupURL: URL?
        if pending.contains(where: \.isDestructive), fileManager.fileExists(atPath: databaseURL.path) {
            backupURL = try createBackup()
        }

        var applied: [Int] = []
        for migration in pending {
            try apply(migration, database: database)
            applied.append(migration.version)
        }
        return AutonomousMigrationResult(
            previousVersion: previousVersion,
            currentVersion: try maximumAppliedVersion(database),
            appliedVersions: applied,
            backupURL: backupURL
        )
    }

    private func apply(_ migration: Migration, database: OpaquePointer) throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw AutonomousDatabaseMigrationError.begin(migration.version, errorMessage(database))
        }
        var committed = false
        defer { _ = sqlite3_exec(database, committed ? "COMMIT;" : "ROLLBACK;", nil, nil, nil) }
        do {
            for operation in migration.operations {
                try perform(operation, database: database)
            }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);", -1, &statement, nil) == SQLITE_OK,
                  let statement
            else { throw AutonomousDatabaseMigrationError.apply(migration.version, errorMessage(database)) }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(migration.version))
            bind(ISO8601DateFormatter().string(from: now()), statement, 2)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AutonomousDatabaseMigrationError.apply(migration.version, errorMessage(database))
            }
            committed = true
        } catch {
            throw error
        }
    }

    private func perform(_ operation: MigrationOperation, database: OpaquePointer) throws {
        switch operation {
        case let .sql(sql):
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw AutonomousDatabaseMigrationError.statement(errorMessage(database))
            }
        case let .addColumn(table, column, declaration):
            guard try columnExists(column, in: table, database: database) == false else { return }
            let sql = "ALTER TABLE \(table) ADD COLUMN \(column) \(declaration);"
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw AutonomousDatabaseMigrationError.statement(errorMessage(database))
            }
        }
    }

    private func maximumAppliedVersion(_ database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw AutonomousDatabaseMigrationError.readVersion }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw AutonomousDatabaseMigrationError.readVersion }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func columnExists(_ column: String, in table: String, database: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw AutonomousDatabaseMigrationError.inspectTable(table) }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column { return true }
        }
        return false
    }

    private func createBackup() throws -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = databaseURL.deletingPathExtension()
            .appendingPathExtension("backup-\(formatter.string(from: now())).sqlite")
        do {
            try fileManager.copyItem(at: databaseURL, to: backupURL)
            return backupURL
        } catch {
            throw AutonomousDatabaseMigrationError.backup(error.localizedDescription)
        }
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func errorMessage(_ database: OpaquePointer) -> String {
        sqlite3_errmsg(database).map(String.init(cString:)) ?? "Unknown SQLite error"
    }
}

private extension AutonomousDatabaseMigrator {
    struct Migration {
        let version: Int
        let isDestructive: Bool
        let operations: [MigrationOperation]
    }

    enum MigrationOperation {
        case sql(String)
        case addColumn(table: String, column: String, declaration: String)
    }

    static let migrations: [Migration] = [
        Migration(version: 1, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS source_checkpoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id TEXT NOT NULL,
            state TEXT NOT NULL,
            detail TEXT NOT NULL,
            evidence TEXT NOT NULL,
            checked_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS source_checkpoints_source_time ON source_checkpoints(source_id, checked_at);
        """)]),
        Migration(version: 2, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS daily_plan_entries (
            day_key TEXT NOT NULL,
            reminder_id TEXT NOT NULL,
            rank INTEGER NOT NULL,
            is_main_objective INTEGER NOT NULL,
            estimate_minutes INTEGER,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (day_key, reminder_id)
        );
        CREATE INDEX IF NOT EXISTS daily_plan_entries_day_rank ON daily_plan_entries(day_key, rank);
        CREATE TABLE IF NOT EXISTS reminder_list_order (
            list_id TEXT PRIMARY KEY,
            position INTEGER NOT NULL,
            updated_at TEXT NOT NULL
        );
        """)]),
        Migration(version: 3, isDestructive: false, operations: [
            .addColumn(table: "daily_plan_entries", column: "selection_reason", declaration: "TEXT"),
            .addColumn(table: "daily_plan_entries", column: "selection_score", declaration: "INTEGER")
        ]),
        Migration(version: 4, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS scheduled_blocks (
            day_key TEXT NOT NULL,
            plan_item_id TEXT NOT NULL,
            calendar_event_id TEXT NOT NULL,
            start_at TEXT NOT NULL,
            end_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (day_key, plan_item_id)
        );
        CREATE INDEX IF NOT EXISTS scheduled_blocks_day_start ON scheduled_blocks(day_key, start_at);
        """)]),
        Migration(version: 5, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS domain_events (
            id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            entity_id TEXT,
            local_day TEXT NOT NULL,
            timezone_identifier TEXT NOT NULL,
            occurred_at_utc TEXT NOT NULL,
            schema_version INTEGER NOT NULL,
            evidence_ids_json TEXT NOT NULL,
            payload_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS domain_events_entity_time ON domain_events(entity_id, occurred_at_utc);
        CREATE TABLE IF NOT EXISTS daily_plans (
            id TEXT PRIMARY KEY,
            local_day TEXT NOT NULL UNIQUE,
            timezone_identifier TEXT NOT NULL,
            state TEXT NOT NULL,
            capacity_minutes INTEGER NOT NULL,
            usable_capacity_minutes INTEGER NOT NULL,
            policy_version INTEGER NOT NULL,
            generated_at_utc TEXT NOT NULL,
            delayed_after_wake INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS daily_plan_items (
            id TEXT PRIMARY KEY,
            plan_id TEXT NOT NULL,
            source_task_id TEXT NOT NULL,
            rank INTEGER NOT NULL,
            estimate_minutes INTEGER NOT NULL,
            estimate_confidence TEXT NOT NULL,
            reason TEXT NOT NULL,
            evidence_ids_json TEXT NOT NULL,
            is_main_objective INTEGER NOT NULL,
            state TEXT NOT NULL,
            FOREIGN KEY(plan_id) REFERENCES daily_plans(id)
        );
        CREATE INDEX IF NOT EXISTS daily_plan_items_plan_rank ON daily_plan_items(plan_id, rank);
        CREATE TABLE IF NOT EXISTS action_commands (
            id TEXT PRIMARY KEY,
            idempotency_key TEXT NOT NULL UNIQUE,
            action_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            desired_state_json TEXT NOT NULL,
            state TEXT NOT NULL,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            next_attempt_at_utc TEXT,
            created_at_utc TEXT NOT NULL,
            updated_at_utc TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS action_commands_ready ON action_commands(state, next_attempt_at_utc);
        CREATE TABLE IF NOT EXISTS action_attempts (
            id TEXT PRIMARY KEY,
            command_id TEXT NOT NULL,
            attempt_number INTEGER NOT NULL,
            state TEXT NOT NULL,
            platform_identifier TEXT,
            redacted_error TEXT,
            started_at_utc TEXT NOT NULL,
            finished_at_utc TEXT,
            FOREIGN KEY(command_id) REFERENCES action_commands(id),
            UNIQUE(command_id, attempt_number)
        );
        CREATE TABLE IF NOT EXISTS prompt_episodes (
            id TEXT PRIMARY KEY,
            decision_key TEXT NOT NULL UNIQUE,
            prompt_type TEXT NOT NULL,
            state TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            action_token TEXT NOT NULL UNIQUE,
            payload_json TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            expires_at_utc TEXT
        );
        CREATE TABLE IF NOT EXISTS prompt_responses (
            id TEXT PRIMARY KEY,
            prompt_id TEXT NOT NULL,
            action_token TEXT NOT NULL UNIQUE,
            response TEXT NOT NULL,
            surface TEXT NOT NULL,
            responded_at_utc TEXT NOT NULL,
            FOREIGN KEY(prompt_id) REFERENCES prompt_episodes(id)
        );
        """)]),
        Migration(version: 6, isDestructive: false, operations: [
            .sql("""
            CREATE TABLE IF NOT EXISTS source_tasks (
                source_id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                due_at TEXT,
                priority INTEGER NOT NULL DEFAULT 0,
                is_completed INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL
            );
            """),
            .addColumn(table: "source_tasks", column: "notes", declaration: "TEXT"),
            .addColumn(table: "source_tasks", column: "list_id", declaration: "TEXT"),
            .addColumn(table: "source_tasks", column: "list_name", declaration: "TEXT"),
            .addColumn(table: "source_tasks", column: "modified_at", declaration: "TEXT"),
            .addColumn(table: "source_tasks", column: "source_hash", declaration: "TEXT"),
            .addColumn(table: "scheduled_blocks", column: "ownership_token", declaration: "TEXT"),
            .addColumn(table: "scheduled_blocks", column: "state", declaration: "TEXT NOT NULL DEFAULT 'scheduled'"),
            .addColumn(table: "scheduled_blocks", column: "last_reconciled_at_utc", declaration: "TEXT")
        ]),
        Migration(version: 7, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS screenshot_artifacts (
            id TEXT PRIMARY KEY,
            behavior_day TEXT NOT NULL,
            behavior_epoch INTEGER NOT NULL,
            path TEXT NOT NULL,
            content_hash TEXT NOT NULL UNIQUE,
            perceptual_fingerprint TEXT NOT NULL,
            ocr_state TEXT NOT NULL,
            extractor_version INTEGER NOT NULL,
            retention_until_utc TEXT NOT NULL,
            created_at_utc TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS extracted_facts (
            id TEXT PRIMARY KEY,
            artifact_id TEXT NOT NULL,
            fact_type TEXT NOT NULL,
            schema_version INTEGER NOT NULL,
            confidence REAL NOT NULL,
            encrypted_payload BLOB,
            evidence_hash TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            FOREIGN KEY(artifact_id) REFERENCES screenshot_artifacts(id)
        );
        CREATE TABLE IF NOT EXISTS meeting_evidence (
            candidate_id TEXT NOT NULL,
            artifact_id TEXT NOT NULL,
            evidence_hash TEXT NOT NULL,
            PRIMARY KEY(candidate_id, artifact_id)
        );
        CREATE TABLE IF NOT EXISTS model_runs (
            id TEXT PRIMARY KEY,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            schema_version INTEGER NOT NULL,
            prompt_version INTEGER NOT NULL,
            normalized_input_hash TEXT NOT NULL,
            validation_state TEXT NOT NULL,
            redacted_diagnostic TEXT,
            started_at_utc TEXT NOT NULL,
            finished_at_utc TEXT,
            duration_milliseconds INTEGER
        );
        CREATE UNIQUE INDEX IF NOT EXISTS model_runs_cache ON model_runs(provider, model, schema_version, normalized_input_hash);
        """)]),
        Migration(version: 8, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL,
            policy_version INTEGER NOT NULL,
            updated_at_utc TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS processing_checkpoints (
            source_id TEXT PRIMARY KEY,
            file_identity TEXT,
            byte_offset INTEGER NOT NULL DEFAULT 0,
            last_record_epoch INTEGER,
            last_success_at_utc TEXT,
            last_scheduled_local_day TEXT,
            last_scheduled_timezone TEXT,
            missed_trigger_at_utc TEXT,
            diagnostic TEXT
        );
        CREATE TABLE IF NOT EXISTS policy_versions (
            policy_type TEXT NOT NULL,
            version INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            is_active INTEGER NOT NULL,
            PRIMARY KEY(policy_type, version)
        );
        CREATE TABLE IF NOT EXISTS learning_aggregates (
            aggregate_type TEXT NOT NULL,
            aggregate_key TEXT NOT NULL,
            sample_count INTEGER NOT NULL,
            median_value REAL NOT NULL,
            confidence REAL NOT NULL,
            policy_version INTEGER NOT NULL,
            updated_at_utc TEXT NOT NULL,
            PRIMARY KEY(aggregate_type, aggregate_key)
        );
        """)]),
        Migration(version: 9, isDestructive: false, operations: [
            .sql("""
            CREATE TABLE IF NOT EXISTS behavior_records (
                source_day TEXT NOT NULL,
                epoch INTEGER NOT NULL,
                time_label TEXT NOT NULL,
                app_name TEXT NOT NULL,
                window_title TEXT NOT NULL,
                url TEXT NOT NULL,
                has_screenshot INTEGER NOT NULL,
                screenshot_path TEXT,
                ingested_at TEXT NOT NULL,
                PRIMARY KEY (source_day, epoch)
            );
            CREATE INDEX IF NOT EXISTS behavior_records_epoch ON behavior_records(epoch);
            CREATE TABLE IF NOT EXISTS screenshot_analyses (
                source_day TEXT NOT NULL,
                epoch INTEGER NOT NULL,
                outcome TEXT NOT NULL,
                processed_at TEXT NOT NULL,
                PRIMARY KEY (source_day, epoch)
            );
            CREATE TABLE IF NOT EXISTS meeting_candidates (
                source_day TEXT NOT NULL,
                epoch INTEGER NOT NULL,
                title TEXT NOT NULL,
                start_at TEXT NOT NULL,
                duration_minutes INTEGER NOT NULL,
                confidence TEXT NOT NULL,
                requires_clarification INTEGER NOT NULL,
                state TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY (source_day, epoch)
            );
            CREATE INDEX IF NOT EXISTS meeting_candidates_start_at ON meeting_candidates(start_at);
            """),
            .addColumn(table: "meeting_candidates", column: "candidate_fingerprint", declaration: "TEXT"),
            .addColumn(table: "meeting_candidates", column: "confidence_score", declaration: "REAL"),
            .addColumn(table: "meeting_candidates", column: "participants_json", declaration: "TEXT"),
            .addColumn(table: "meeting_candidates", column: "start_expression", declaration: "TEXT"),
            .addColumn(table: "meeting_candidates", column: "location", declaration: "TEXT"),
            .addColumn(table: "meeting_candidates", column: "call_link", declaration: "TEXT"),
            .addColumn(table: "meeting_candidates", column: "timezone_identifier", declaration: "TEXT"),
            .addColumn(table: "meeting_candidates", column: "conflict_event_id", declaration: "TEXT"),
            .addColumn(table: "meeting_candidates", column: "duplicate_event_id", declaration: "TEXT"),
            .addColumn(table: "meeting_candidates", column: "expires_at_utc", declaration: "TEXT"),
            .sql("""
            CREATE UNIQUE INDEX IF NOT EXISTS meeting_candidates_fingerprint_unique
            ON meeting_candidates(candidate_fingerprint)
            WHERE candidate_fingerprint IS NOT NULL;
            CREATE INDEX IF NOT EXISTS screenshot_artifacts_fingerprint
            ON screenshot_artifacts(perceptual_fingerprint);
            """)
        ]),
        Migration(version: 10, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS learning_samples (
            id TEXT PRIMARY KEY,
            sample_type TEXT NOT NULL,
            context_key TEXT NOT NULL,
            estimated_value REAL,
            actual_value REAL NOT NULL,
            local_minute_of_day INTEGER,
            timezone_identifier TEXT NOT NULL,
            evidence_id TEXT NOT NULL,
            occurred_at_utc TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS learning_samples_type_context_time
        ON learning_samples(sample_type, context_key, occurred_at_utc);
        """)]),
        Migration(version: 11, isDestructive: false, operations: [
            .addColumn(table: "learning_samples", column: "payload_json", declaration: "TEXT"),
            .addColumn(table: "learning_aggregates", column: "proposal_json", declaration: "TEXT"),
            .addColumn(table: "learning_aggregates", column: "rollback_json", declaration: "TEXT")
        ]),
        Migration(version: 12, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS planner_trust_cycles (
            local_day TEXT PRIMARY KEY,
            plan_version INTEGER NOT NULL,
            item_count INTEGER NOT NULL,
            stayed_within_capacity INTEGER NOT NULL,
            external_writes_suppressed INTEGER NOT NULL,
            observed_at_utc TEXT NOT NULL
        );
        """)]),
        Migration(version: 13, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS daily_plan_revisions (
            id TEXT PRIMARY KEY,
            day_key TEXT NOT NULL,
            revision INTEGER NOT NULL,
            entries_json TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            restored_at_utc TEXT,
            UNIQUE(day_key, revision)
        );
        CREATE TABLE IF NOT EXISTS plan_undo_requests (
            id TEXT PRIMARY KEY,
            prompt_id TEXT NOT NULL UNIQUE,
            day_key TEXT NOT NULL,
            state TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            updated_at_utc TEXT NOT NULL
        );
        """)]),
        Migration(version: 14, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS task_execution_states (
            task_id TEXT PRIMARY KEY,
            state TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS task_activity_intervals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT
        );
        CREATE UNIQUE INDEX IF NOT EXISTS task_activity_one_open ON task_activity_intervals((ended_at IS NULL)) WHERE ended_at IS NULL;
        CREATE INDEX IF NOT EXISTS task_activity_task_time ON task_activity_intervals(task_id, started_at);
        CREATE TABLE IF NOT EXISTS task_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT NOT NULL,
            state TEXT NOT NULL,
            occurred_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS task_history_task_state ON task_history(task_id, state);
        CREATE TABLE IF NOT EXISTS today_snapshots (
            day_key TEXT PRIMARY KEY,
            payload BLOB NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS gaming_reward_ledger (
            day_key TEXT NOT NULL,
            task_id TEXT NOT NULL,
            policy_version INTEGER NOT NULL,
            applied_at TEXT NOT NULL,
            PRIMARY KEY(day_key, task_id, policy_version)
        );
        CREATE UNIQUE INDEX IF NOT EXISTS gaming_reward_one_per_day_policy ON gaming_reward_ledger(day_key, policy_version);
        """)]),
        Migration(version: 15, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS prompt_response_effects (
            response_id TEXT PRIMARY KEY,
            prompt_id TEXT NOT NULL,
            effect_type TEXT NOT NULL,
            state TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            updated_at_utc TEXT NOT NULL,
            FOREIGN KEY(response_id) REFERENCES prompt_responses(id),
            FOREIGN KEY(prompt_id) REFERENCES prompt_episodes(id)
        );
        CREATE INDEX IF NOT EXISTS prompt_response_effects_pending
        ON prompt_response_effects(state, created_at_utc);
        """)]),
        Migration(version: 16, isDestructive: false, operations: [.sql("""
        CREATE TABLE IF NOT EXISTS plan_schedule_requests (
            id TEXT PRIMARY KEY,
            prompt_id TEXT NOT NULL UNIQUE,
            day_key TEXT NOT NULL,
            state TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            updated_at_utc TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS plan_schedule_requests_pending
        ON plan_schedule_requests(state, created_at_utc);
        """)]),
        Migration(version: 17, isDestructive: false, operations: [
            .addColumn(table: "action_commands", column: "action_origin", declaration: "TEXT NOT NULL DEFAULT 'explicit_user'"),
            .sql("""
            UPDATE action_commands
            SET action_origin = 'automatic_plan'
            WHERE state IN ('pending', 'retryable_failure')
              AND action_type IN ('createCalendarBlock', 'updateCalendarBlock', 'reconcileCalendarBlock', 'deleteCalendarBlock', 'setReminderPriority', 'setReminderDueDate', 'setReminderMetadata');
            """)
        ]),
        Migration(version: 18, isDestructive: false, operations: [
            .addColumn(table: "meeting_candidates", column: "source_evidence", declaration: "TEXT")
        ]),
        Migration(version: 19, isDestructive: false, operations: [.sql("""
        UPDATE meeting_candidates SET source_evidence = '' WHERE COALESCE(source_evidence, '') <> '';
        UPDATE prompt_episodes
        SET summary = 'Meeting details are available in Zoid Coach.',
            payload_json = json_remove(payload_json, '$.sourceEvidence')
        WHERE prompt_type = 'MEETING_CANDIDATE';
        """)])
    ]
}

public enum AutonomousDatabaseMigrationError: LocalizedError {
    case openDatabase
    case prepareSchema(String)
    case readVersion
    case begin(Int, String)
    case apply(Int, String)
    case statement(String)
    case inspectTable(String)
    case backup(String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open the Zoid Coach database for migration."
        case let .prepareSchema(message): "Could not prepare migration metadata: \(message)"
        case .readVersion: "Could not read the current database version."
        case let .begin(version, message): "Could not begin migration \(version): \(message)"
        case let .apply(version, message): "Migration \(version) failed: \(message)"
        case let .statement(message): "A migration statement failed: \(message)"
        case let .inspectTable(table): "Could not inspect table \(table) before migration."
        case let .backup(message): "Could not create a database backup: \(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
