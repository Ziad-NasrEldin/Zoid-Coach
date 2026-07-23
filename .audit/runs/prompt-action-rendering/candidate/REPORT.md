# Prompt Action Rendering Candidate Report

## Decision

The priority-0 `ZC-034-011` signed blocker is fixed at the persistence boundary and is ready for a fresh independent signed verifier.

## Root cause

The signed verifier stored `requiresConfirmation` through SQLite `json_object`, which represented Boolean values as numeric `0` and `1`.

`StoredPromptEnvelope` required canonical JSON Booleans, so decoding the otherwise valid six-action envelope failed.

`decodeEnvelope` then used its legacy plain-payload fallback, which intentionally returned `actions: []`.

Today therefore rendered the prompt title and summary plus an empty action collection, exactly matching the screenshot and accessibility evidence.

The adaptive `LazyVGrid`, button accessibility identifiers, `Mark blocked` routing, and blocker validation sheet were not the cause.

## Red-capable regression

`promptInboxPreservesActionsFromLegacyNumericConfirmationFlags` writes the exact six-action numeric-flag envelope into a real prompt SQLite database, reopens `PromptInboxStore`, and requires all six actions, `Mark blocked`, and its destructive confirmation flag.

Before the fix, the test failed with `restored.actions.count` equal to zero, no `Mark blocked`, and no confirmation value.

After the fix, the test passes.

## Implementation

`StoredPromptEnvelope` continues to encode canonical Boolean JSON.

On decode, it first accepts canonical `[PromptAction]` values unchanged.

Only when that strict action decode fails does it decode the persisted action records with compatibility for Boolean values or legacy integer `0/1` values.

Invalid integers and unrelated types remain decode errors instead of being silently treated as safe confirmation values.

An omitted legacy confirmation flag retains the historic false default.

## Verification

One focused post-fix invocation covering the numeric-envelope regression, `PromptTaskBlockStateTests`, and `GamingDriftPromptServiceTests` passed.

The release build passed.

No debug instrumentation remains, and no UI or Screenwatch file was changed.

## Independent signed acceptance

Seed or generate the six-action gaming-drift prompt and confirm every action is visible, keyboard reachable, and present in the accessibility tree, including `Mark blocked`.

Complete the too-short reason, Cancel, meaningful block, replacement-main, answered-history, relaunch, and unavailable-agent paths from `.audit/runs/prompt-task-block/verifier/REPORT.md`.
