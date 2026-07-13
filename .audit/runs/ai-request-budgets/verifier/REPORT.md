# AI Request Budgets Verification

## Result

`ZC-046-006` advances from Frontend only left to Touches remaining.

The end user can configure, save, and recover separate daily and monthly limits, while focused deterministic proof establishes provider-independent enforcement, atomic reservations, truthful monthly behavior, fallback usability, and independent conflict merging.

## Automated proof

- One focused invocation passed all seven Settings, ledger, concurrency, provider-switch, daily-boundary, monthly-boundary, fallback, and conflict-merge tests.
- One QA release package passed app and helper builds, package coherence, signing, LaunchAgent, and Mach-service validation.

## Signed Settings journey

- The installed signed app exposed separate `DAILY REQUEST LIMIT` and `MONTHLY REQUEST LIMIT` controls with stable accessibility identifiers.
- The initial values were 100 requests per day and 3,000 requests per month.
- Accessible copy explained that the agent stops general AI requests when either limit is reached.
- Accessible copy explained that zero disables general AI requests without disabling local planning, tracking, coaching rules, or reviews.
- Native controls changed the limits independently to 110 and 3,100 requests.
- Saving produced policy version 2 and visible `All changes saved` confirmation.
- After killing and relaunching the installed app, both distinct values and the same explanatory copy remained visible and accessible.
- `settings-budgets.png` records the signed Intelligence surface with both edited limits.

## Deterministic enforcement proof

- Provider-independent ledger counting prevents a provider switch from resetting the allowance.
- Each accepted request is atomically reserved as pending before provider execution, so concurrent requests cannot overshoot the last slot.
- Daily and UTC calendar-month boundaries are enforced independently.
- The automatic planning wrapper keeps deterministic planning usable when AI advice is rejected at the limit.
- Settings conflict recovery preserves independent daily and monthly edits.

## Remaining acceptance boundary

The signed app has no dedicated deterministic provider-budget probe.

The capped runtime therefore stopped after Settings persistence instead of mutating the production ledger or invoking external providers through an unsafe ad hoc seam.

An installed deterministic provider invocation across a live provider switch remains the final acceptance touch.
