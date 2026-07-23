# QA ready-state verification

## Purpose

The ready-state preparer creates an isolated QA root that has completed all 12 onboarding steps and opens at Today.
It avoids spending signed-runtime acceptance caps repeating onboarding for scenarios that do not test onboarding.
It never changes production storage, permissions, Reminders, Calendar, notifications, Screenwatch, or launch services.

## Manifest

Copy `Scripts/fixtures/qa-ready-state.example.json` and change only the fixture facts required by the scenario.
The manifest explicitly separates completed onboarding decisions from deterministic operating-system fixture state.
Reminders, Calendar commitments, notifications, and permission states use the existing QA fixture schema.
Screenwatch supports `healthy`, `stale`, `missing`, and `deferred` states under the isolated QA root.

The preparer rejects unknown fields, invalid enum values, duplicate identifiers, notification IDs that differ from their prompt IDs, missing Reminder lists, inconsistent granted states, malformed Screenwatch records, relative roots, root-directory targets, and symbolic-link targets.
Validation completes before the target is changed.
Replacing an existing root requires `--replace` and uses a staged atomic replacement.

## Prepare and package

```sh
QA_ROOT=/private/tmp/zoid-666-ready-state
MANIFEST=Scripts/fixtures/qa-ready-state.example.json

Scripts/prepare-qa-ready-state.py "$MANIFEST" "$QA_ROOT"
CONFIGURATION=release \
ZOID_COACH_PACKAGE_MODE=qa \
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
Scripts/package-app.sh
```

The generated root contains validated 12 of 12 onboarding progress, an existing-schema QA control request, the normalized manifest, and optional Screenwatch day files.
The signed QA app processes the control request through `QAFixtureOSComposition` during startup.

## Launch and verify

Launch the signed package directly without installing or registering its helper:

```sh
APP="$PWD/.build/app-qa/Zoid 666 QA.app"
open -n "$APP"
PID="$(pgrep -f "$APP/Contents/MacOS/ZoidCoachQA" | head -1)"
/usr/bin/swift Scripts/qa-window-content-probe.swift \
  "$PID" \
  --expect-today \
  --screenshot /private/tmp/zoid-666-ready-state-today.png
```

`--expect-today` uses native Accessibility to require the current `TODAY / INBOX` heading, a non-minimized 1180 by 760 window, and at least five content nodes.
The optional screenshot provides pixel evidence.
Do not use System Events descendant counts as a SwiftUI visibility oracle.

Installed-helper acceptance remains serialized under the shared runtime lease.
A fresh verifier may prepare the root after the installer performs its clean-root step, then restart the isolated app and helper once before beginning the actual scenario.
