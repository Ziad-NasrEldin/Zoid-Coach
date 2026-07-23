# ZC-025-003 Candidate Report

## Outcome

Screenwatch ingestion now treats browsers, Discord, Slack, Notion, YouTube, and Preview as context-sensitive applications rather than assigning a permanent judgment from the app name.
Clear local title or URL evidence can identify work, research, communication, gaming, or distracting use, while insufficient evidence remains unknown for later review.

## Decision Order

1. A durable review-correction rule remains authoritative.
2. An explicit user application policy remains authoritative.
3. Local context signals are evaluated for context-sensitive applications.
4. Ambiguous context remains unknown.
5. Applications outside the context-sensitive set retain the existing deterministic classifier.

## Covered Contexts

- A Safari developer-documentation page is work.
- A YouTube technical tutorial is work while YouTube Shorts is distracting.
- A Discord project context is work while a Minecraft server context is gaming.
- A Notion product roadmap and Preview client proposal are work.
- A generic Slack window remains unknown instead of being permanently labeled work.
- An explicit user rule overrides contradictory contextual evidence.

## Privacy Boundary

Classification runs locally during Screenwatch ingestion.
No title or URL content is added to prompts, diagnostics, exports, or remote requests by this change.

## Verification

- `swift test --filter ScreenwatchArchiveTests` passed.
- Focused mixed-context ingestion and explicit-policy precedence tests passed.
- `swift build -c release` passed.
- `git diff --check` passed before handoff.

## Remaining Acceptance

An independent verifier must ingest a controlled signed-QA mixed-context fixture, confirm the persisted categories in visible totals or review, confirm the generic ambiguous state stays reviewable, apply one explicit rule, and verify the override after app and helper relaunch.
Only the root integrator may update the authoritative tracker and registry after that verification.
