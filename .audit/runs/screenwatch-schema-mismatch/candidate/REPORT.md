# Screenwatch Schema Mismatch Candidate Report

Scenario: `ZC-049-008`.

Candidate status: implementation complete and ready for independent signed source-health verification.

## End-User Behavior Implemented

- A complete JSON record that no longer matches the expected Screenwatch fields is identified as an unsupported source schema.
- A stream containing only changed-schema records shows `Screenwatch source format is unsupported` instead of claiming the stream is empty.
- A stream containing both valid and changed-schema records remains in Attention and explains that some records use an unsupported format.
- The evidence reports only aggregate parsed, image-reference, and schema-mismatch counts.
- Captured titles, URLs, application names, and malformed record content are never displayed in the health message.
- The action changes to Repair for schema mismatches while valid and merely stale streams retain Refresh.
- Truncated or invalid JSON is not mislabeled as a schema change.
- Singular and plural evidence counts now read naturally.

## Focused Proof

- `swift test --filter ScreenwatchReaderTests` passed on 13 July 2026.
- Focused tests cover healthy schema, missing stream, fully changed schema with private content, and mixed valid and changed schema.
- The private fixture title is explicitly asserted absent from the user-visible evidence.
- The debug test build compiled the changed app and test targets.
- `swift build -c release` passed on 13 July 2026.

## Independent Verifier Plan

1. Launch the signed QA app against an isolated Screenwatch source containing a current valid record and verify healthy source copy.
2. Replace the source record with a complete JSON object using changed field names and refresh Source Health.
3. Verify the visible state says `Screenwatch source format is unsupported`, offers Repair, and contains no captured content.
4. Provide one valid record and one changed-schema record and verify the mixed-schema Attention message and aggregate counts.
5. Restore the expected schema and verify the source returns to healthy without restart.
6. Relaunch and repeat the changed-schema check to prove the message is derived safely from the current source.

The tracker and registry should not promote this scenario until the signed healthy, changed, mixed, repaired, and relaunch sequence passes.
