#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly EXPECTED_PATHS=(
    Sources/ZoidCoachCore/AgentMutationCommand.swift
    Sources/ZoidCoachCore/TodayDashboard.swift
    Sources/ZoidCoachApp/LocalTaskCreationController.swift
    Sources/ZoidCoachApp/Views/LocalTaskCreationView.swift
    Sources/ZoidCoachApp/TodayPlanPresentation.swift
    Sources/ZoidCoachApp/ActiveCommitmentPresentation.swift
    Sources/ZoidCoachInfrastructure/AgentMutationRouter.swift
    Sources/ZoidCoachInfrastructure/ReminderSnapshotStore.swift
    Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift
    Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift
    Tests/ZoidCoachAppTests/LocalTaskCreationControllerTests.swift
    Tests/ZoidCoachAppTests/AutonomousDatabaseMigratorTests.swift
    Scripts/qa-zc061001-technical-task-fixture.sh
    Scripts/qa-zc061001-technical-task-ax-probe.swift
    Scripts/qa-zc061001-signed-preflight.sh
    Scripts/verify-zc-061-001-technical-task-static.sh
    docs/ZC-061-001-SIGNED-QA-RUNBOOK.md
)

require() {
    rg -Fq "$2" "$ROOT/$1" || {
        print -u2 -- "FAIL: missing '$2' in $1"
        exit 1
    }
}

for owned_path in "${EXPECTED_PATHS[@]}"; do
    [[ -f "$ROOT/$owned_path" ]] || { print -u2 -- "FAIL: missing $owned_path"; exit 1; }
done
require Sources/ZoidCoachCore/AgentMutationCommand.swift "case technical"
require Sources/ZoidCoachCore/AgentMutationCommand.swift "declaredContext: DeclaredTaskContext? = nil"
require Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift 'column: "declared_context"'
require Sources/ZoidCoachInfrastructure/ReminderSnapshotStore.swift "declared_context"
require Sources/ZoidCoachInfrastructure/AgentMutationRouter.swift "declaredContext: task.declaredContext"
require Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift "declaredContext: reminder.declaredContext"
require Sources/ZoidCoachApp/TodayPlanPresentation.swift "declaredContext: snapshot.declaredContext"
require Sources/ZoidCoachApp/Views/LocalTaskCreationView.swift '"local-task-technical-context"'
require Sources/ZoidCoachApp/ActiveCommitmentPresentation.swift '"Technical task. "'
require Tests/ZoidCoachAppTests/LocalTaskCreationControllerTests.swift "legacyLocalTaskCommandDecodesWithoutDeclaredContext"
require Tests/ZoidCoachAppTests/AutonomousDatabaseMigratorTests.swift "migration50AddsNullableDeclaredTaskContextWithoutChangingLegacyRows"
"$ROOT/Scripts/qa-zc061001-technical-task-fixture.sh" --self-test
swift "$ROOT/Scripts/qa-zc061001-technical-task-ax-probe.swift" --self-test
"$ROOT/Scripts/qa-zc061001-signed-preflight.sh" --self-test
print -- "PASS: ZC-061-001 static scope and QA self-tests"
