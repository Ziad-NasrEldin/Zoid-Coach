# Drift grace and neutral activity verification

Candidate chain `bfd7ca2` plus verifier fix `17ac1e5` was independently rebased onto authoritative root `7e61bef`.

## Result

ZC-027-001, ZC-027-004, and ZC-027-007 are fully implemented.

The exact focused rules, installed signed agent, isolated QA database, prompt store, and active-task state were used together.

## Blocker fixed

The candidate described neutral application matching as bounded, but it used unrestricted substring matching.

It also treated every window title beginning with `Open ` or `Save ` as a file dialog.

The verifier changed application matching to exact names or bounded name prefixes and changed file-dialog matching to an explicit title set.

Negative coverage proves that OpenTTD, Steam with an `Open World` title, and Gmail Notifier remain non-neutral.

## Focused proof

- The combined exact run passed the new task-start, idle-return, sustained-gaming bypass, and neutral read-only journeys.
- The same run passed the affected ten-minute eligibility and corrected-session deduplication seams.
- After the accepted-break integration, both new journeys passed again on the rebased chain.
- The release build passed.
- One clean release-configured signed QA package and install passed.

## Installed proof

- The isolated active policy used accountability coaching, a zero-minute gaming allowance, a full-week work window, and seven complete baseline days.
- A durable active priority task started 150 seconds before a new two-minute gaming session.
- After the signed helper evaluated the state, no prompt existed, the task remained active, and its activity interval remained open.
- A separate idle-to-gaming return within one minute also produced no prompt or task mutation.
- A sustained ten-minute pre-task gaming seed reached a truthful zero-minute allowance and ten used minutes in the signed Today snapshot.
- The expected bypass prompt was not observed before the ten-minute signed timebox ended, so ZC-027-003 is not promoted to Full.
- A signed System Settings observation after sustained gaming produced no prompt, kept one active task, and kept one open activity interval.

## Conservative boundaries

ZC-027-002 remains Touches remaining because idle-return and telemetry-gap grace are implemented, while explicit wake and unlock signals are not modeled.

ZC-027-003 remains Touches remaining because its deterministic integration passes but the signed prompt did not appear within the capped run.

ZC-027-005 and ZC-027-006 remain Touches remaining because deterministic coverage spans password managers, Finder/downloads, file dialogs, local files, and communication tools, while the capped signed run completed only the System Settings representative.
