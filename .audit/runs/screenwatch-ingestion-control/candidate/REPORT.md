# Screenwatch Ingestion Control Candidate Report

Scenario: `ZC-039-009`.

Candidate status: implementation complete and ready for independent signed runtime verification.

## End-User Journey Implemented

- Settings now exposes an explicit Ingest new Screenwatch activity toggle with a stable accessibility identifier.
- Turning the toggle off explains that no new Screenwatch records will be imported.
- The paused copy explicitly confirms that existing Zoid 666 history and all Screenwatch source files are kept.
- The choice persists through the versioned policy path and survives restart.
- Legacy policies without the new field continue with ingestion enabled, so an upgrade never silently stops behavior evidence.
- A concurrent unrelated Settings edit merges safely without losing the ingestion choice.
- The running agent reads the latest policy every watch-loop pass, skips live ingestion while paused, and resumes without restart.
- One-shot agent runs also honor the paused choice.
- Historical backfill and Screenwatch maintenance ingestion do not import records while paused.
- The central ingestion gate never opens or reads the source when paused, so source-owned data is untouched.

## Focused Proof

- `swift test --filter ScreenwatchIngestionControlTests` passed on 13 July 2026.
- `swift test --filter capturePolicyDefaultsLegacyDocumentsToEnabledIngestionAndRoundTripsAPause` passed on 13 July 2026.
- `swift test --filter settingsScreenwatchIngestionPauseRoundTripsAndMergesIndependently` passed on 13 July 2026.
- The debug test build compiled the changed Core, app, agent, and test targets.
- `swift build -c release` passed on 13 July 2026.

## Independent Verifier Plan

1. Install and launch the signed QA app with a healthy Screenwatch fixture containing known historical observations.
2. Record the current behavior total and source-file count.
3. Turn Ingest new Screenwatch activity off in Settings and save.
4. Add a new Screenwatch source observation and wait through at least two agent watch-loop passes.
5. Verify the behavior total does not include the new observation while historical totals and source files remain unchanged.
6. Relaunch and verify the toggle remains paused and the new source observation remains unimported.
7. Turn ingestion on without restarting the agent.
8. Verify the waiting observation imports once, behavior evidence updates, and source files remain untouched.
9. Save an unrelated Settings edit concurrently and verify the ingestion choice is not overwritten.

The tracker and registry should not promote this scenario until the signed pause, relaunch, resume, and source-preservation journey passes.
