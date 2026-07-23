# ZC-052-005 Remaining Durable Mutation Candidate

## Candidate

The candidate was rebased onto authoritative commit `da1d82244fcc69f2230d0f4eedfbc79c18985290` before signed packaging.
The candidate code commit is `e096d92` before this evidence-only report commit.
The work remained isolated in `/private/tmp/zoid-666-zc052005-remaining`.

## Implemented Contract

Task mutation client state now enumerates pending requests and replays the same operation identifier after app or helper relaunch.
Relaunch reconciliation is bounded and retries while the freshly registered helper becomes reachable.
Successful or terminal reconciliation clears the exact pending request and does not clear unrelated requests.
Calendar plan writes now receive one persisted operation identifier before the XPC call.
The same Calendar operation survives a lost reply and client relaunch until a complete receipt is returned.
The canonical scheduler and ActionOutbox idempotency path remain the only write implementation.
The scheduler now declares the exact required command kinds and entity identifiers for the reviewed plan.
The router compares the committed commands loaded from the outbox against that exact set.
An incomplete set or a same-sized wrong set cannot return an accepted receipt.
Ambiguous Calendar replies now persist and render a distinct reconciling state instead of the `NOTHING WAS WRITTEN` refusal panel.
Only an authoritative zero-write refusal returns to review and atomically clears the pre-send reconciling receipt.

## Automated Evidence

The first red loop failed because Calendar operation persistence, exact required-set validation, reconciling state, and QA probe guards did not exist.
The focused combined green run passed thirteen selected tests.
Coverage includes Calendar identity across relaunch, exact-set acceptance, same-sized wrong-set rejection, incomplete-set rejection, reconciling receipt restoration, authoritative refusal clearing, canonical scheduler replay, temporary and persistent real SQLite locks, external Reminder raw cardinalities, task pending-ID restoration, and packaged-QA guard behavior.
The focused post-rebase run passed five selected tests on authoritative base `da1d822`.
The production release build completed with exit code zero before signed packaging.

## Signed QA Evidence

The candidate packaged, signed, installed, and registered the coherent QA helper successfully under `/private/tmp/zoid-666-zc052005-signed` and `/private/tmp/zoid-666-zc052005-install`.
The first signed temporary-lock attempt reproduced a separate background-write interaction.
While the real database lock was held, a background `PlanUndoRequestStore` write tripped the process-wide read-only circuit breaker before the user task mutation reached its bounded retry boundary.
The signed app truthfully refused the action as read-only, so this attempt does not qualify as temporary-lock success.
The first signed lost-reply run committed the external Reminder completion once and intentionally retained the client request across helper restart.
The immediate relaunch reconciliation occurred before the new helper was reachable and retained the pending identity instead of duplicating effects.
The raw preserved database contains completion operation `A1C2183C-43DE-4400-8EE4-CA8DD3625902` in completed state, one `completeReminder` command for `qa-reminder-0`, and one completed task-history row.
The same database also contains the separate completed start operation and one selected history row, as expected.
That signed failure produced the bounded helper-readiness retry fix included in `e096d92`.
The post-fix focused tests pass, but the runtime cap ended before the corrected package could repeat the signed lost-reply journey.
The preserved raw database is `runtime/lost-reply.sqlite`.

## Remaining Acceptance Gates

The signed external Reminder temporary-lock journey must be repeated without the unrelated background writer tripping the circuit breaker first.
The signed persistent-lock journey must still show a bounded truthful user-visible failure and prove zero completion operation, outbox, completed history, reward, and learning rows.
The corrected signed lost-reply journey must prove the same pending operation identifier resolves after both helper and app relaunch without duplicate effects.
The signed Calendar lost-reply journey must prove the complete required command set is reconciled and the reconciling panel never renders `NOTHING WAS WRITTEN`.
Native accessibility and pixel captures were not completed before the runtime cap.

## Status Recommendation

Keep `ZC-052-005` at `Partially implemented`.
The candidate materially closes the code defects and adds safe signed-QA controls, but the four required installed usability gates are not all accepted end to end.
