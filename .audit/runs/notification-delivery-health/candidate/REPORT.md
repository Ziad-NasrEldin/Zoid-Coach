# Notification Delivery Health Candidate

## Scope

This candidate makes notification authorization, scheduling acceptance, deterministic QA delivery, fallback, replacement, and failure visible without claiming that macOS displayed content it only accepted for delivery.
It targets `ZC-044-011`, `ZC-044-013`, `ZC-048-004`, `ZC-050-002`, `ZC-050-007`, `ZC-054-008`, and `ZC-054-009`.
It preserves Today as the fallback for every unresolved prompt.

## Implementation

- Migration 36 adds an ordered, non-destructive `notification_delivery_events` ledger after the daily-plan revision migration 35.
- The ledger records only opaque request and prompt identifiers, category, outcome, time, attempt number, replacement state, and a bounded redacted error.
- Notification titles, bodies, action text, and user content are never copied into the ledger.
- Delivery outcomes distinguish authorization unavailable, accepted by macOS, delivered by the isolated QA fixture, and scheduling failed.
- Repeated scheduling for the same stable request records a replacement attempt instead of describing it as a stacked notification.
- The prompt notification coordinator records real and deterministic-fixture outcomes while retaining its stable request identifier.
- Notification source health now reports the latest truthful local outcome.
- Settings Signals now exposes current authorization, direct System Settings repair, refresh, Today fallback guidance, recent local outcomes, replacement explanations, accessibility identifiers, and the 30-day retention boundary.
- Notification delivery history participates in privacy inventory, date-range deletion, delete-all behavior, and automatic 30-day retention.
- Migration 35 was hardened to skip its three additive columns when a legacy fixture legitimately lacks `daily_plan_entries`; its behavior is unchanged when that table exists.

## Focused proof

- `swift test --filter 'NotificationDelivery|OnboardingTestPromptService|AutonomousDatabaseMigrator|PrivacyDataService'` passed on 13 July 2026.
- Migration tests prove versions 35 and 36 apply in order and apply exactly once.
- Ledger tests prove all four outcomes, stable replacement attempts, restart recovery, identifier bounds, error redaction, retention, and privacy date-range deletion.
- Onboarding integration tests prove a granted deterministic notification records delivered truth and an authorization denial records Today fallback truth.
- Settings controller tests prove healthy history loading and denied-access fallback guidance.
- `git diff --check` passed.

## Remaining verifier work

This implementation candidate does not qualify the affected scenarios as fully implemented yet.
A fresh verifier must integrate it after the authoritative daily-plan revision, build the signed QA app, inspect Settings Signals with VoiceOver accessibility state, exercise denied and granted fixture authorization, prove the System Settings repair link, schedule the same prompt twice, and confirm restart-safe history without displaying private notification content.
The verifier should also confirm that a real macOS scheduling success is labeled `Accepted by macOS`, not `Delivered`.
