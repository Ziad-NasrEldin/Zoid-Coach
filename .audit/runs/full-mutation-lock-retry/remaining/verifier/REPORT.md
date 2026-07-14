# ZC-052-005 Independent Remaining-Gates Verification

## Status

`ZC-052-005` remains `Partially implemented`.

The signed temporary-lock, task lost-reply, and Calendar complete-receipt replay gates passed.

The persistent-lock zero-partial-effects journey, native Accessibility and pixel proof, signed incomplete-set refusal, and signed authoritative-refusal UI recovery remain unproved.

This report does not authorize tracker promotion.

## Verified Candidate

The independently verified commit was `75a2eacddfa51b779f5c7fe7920bd0abbdd28642` on branch `codex/verify-zc052005-remaining`.

The signed package reported build identity `zoid-coach-75a2eacddfa51b779f5c7fe7920bd0abbdd28642-clean`.

The package mode was `qa`.

The signed bundle identifier was `qa.ziadnasreldin.ZoidCoach`.

The package used team identifier `377QC32T9T` and the configured Apple Development identity.

The installed runtime path was `/private/tmp/zc052005-install/Zoid 666 QA E2E.app`.

The isolated runtime root was `/private/tmp/zc052005-verifier-75a2eac`.

The installed runtime and isolated runtime root were removed when the serialized runtime lease ended.

The clean packaged artifact remains at `.build/app-qa/Zoid 666 QA.app` in the verifier worktree.

## Privacy-Safe Artifact Hashes

- `ZoidCoachQA`: `928f3510a4d00b52cd09523af7f4c4bbcb8c779307edee85cfdca40c8889b986`
- `ZoidCoachAgentQA`: `bf3c48b802d1edf9fff977ff45d6fc3db99be14b2f2ac26e5d51f54bf6bb9269`
- `Info.plist`: `ff4d39b21914609e041d2a65c6dfe33ef1ebf4a59f4b72b121a0641cb64f672d`

The hashes identify the exact signed QA evidence package without retaining user data.

## Temporary External Reminder Lock

The installed signed QA probe completed successfully with `--qa-zc052005-acceptance temporary-lock`.

The probe created an external Reminder-backed task inside the isolated deterministic QA fixture.

The probe held a real exclusive SQLite lock while submitting the user completion mutation.

The lock was released inside the bounded retry window.

The mutation then completed successfully.

The signed probe queried the raw isolated database and proved these exact cardinalities for the prepared task:

- One `task_mutation_operations` row with command `complete`.
- One `action_commands` row with action type `completeReminder`.
- One `task_history` row with state `completed`.

The signed probe exited with `PASS: temporary real database lock produced one external completion operation, outbox command, and history row`.

The temporary-lock probe did not independently query reward and learning cardinalities.

## Task Lost Reply And Helper Relaunch

The installed signed QA probe completed successfully with `--qa-zc052005-acceptance lost-task-reply` after a clean fixture reinstall.

The client retained the same pending task operation identifier after the first authoritative application completed but before the client acknowledged the reply.

The LaunchAgent helper was restarted.

The relaunched client reconciled the pending request with the same operation identifier.

The pending client identity cleared only after the authoritative replay returned.

The signed probe reused the raw-cardinality assertions and proved one completion operation, one `completeReminder` outbox command, and one completed history row for the task.

The signed probe exited with `PASS: lost task reply reused one pending operation across helper relaunch without duplicate effects`.

## Calendar Complete-Set Ledger Replay

The installed signed QA probe completed successfully with `--qa-zc052005-acceptance calendar-lost-reply` against migration 44 and the durable Calendar operation ledger.

The first authoritative call returned an accepted receipt with a non-empty command identifier set.

The client deliberately retained the same pending Calendar operation to model a lost reply.

The LaunchAgent helper was restarted.

The relaunched client reconciled the pending operation.

The replayed receipt contained exactly the same command identifier set as the first committed receipt.

The pending client operation cleared after the replay.

Every distinct receipt command identifier resolved to a persisted outbox command.

The signed probe exited with `PASS: Calendar lost reply reconciled the same complete command set across helper relaunch`.

The isolated database was intentionally deleted during signed-runtime cleanup, so privacy-sensitive command identifiers and a raw database copy were not retained.

## Fixture Reinstall Condition

Running the task lost-reply probe immediately after the temporary-lock probe in the same deterministic fixture root failed before the target journey.

The failure was `The persisted fixture state is invalid: invalid persisted identifier`.

The probes use a deterministic fixture identifier, so the previous journey's retained fixture state conflicted with preparing another task under the same identifier.

Uninstalling and reinstalling the same clean signed commit with the fixture root reset removed that test-harness condition.

The task lost-reply journey then passed.

This reinstall was test isolation, not a production recovery claim.

Future automation should allocate a fresh isolated QA root per signed journey or explicitly reset the deterministic fixture between modes.

## Focused And Broader Test Evidence

The migration 44 operation-store, frozen-scheduler, durable-router replay, and authoritative-refusal focused tests passed.

The broader 86-test selection covering mutation operations, outbox locking, Calendar routing and scheduling, approval receipt state, XPC client identity, the acceptance probe, and database migrations passed.

The release build completed with exit code 0 before signed packaging.

The tests prove exact required-set equality, same-sized wrong-set rejection, incomplete-set rejection, frozen command-list replay, same-operation receipt replay, migration persistence, and authoritative refusal clearing at code and integration level.

These tests do not substitute for the missing signed native UI gates below.

## Unproved Gates

### Persistent Lock

The signed persistent-lock journey was not completed before the hard runtime cap.

There is no accepted signed proof that a lock persisting beyond the retry bound leaves zero completion operation, outbox, completed history, reward, and learning rows.

There is no accepted signed proof that the installed UI renders the final read-only or unchanged-state message for that journey.

### Native Calendar Receipt UI

Native Accessibility traversal and pixel captures were not completed for the Calendar reconciling panel.

The signed probe proved the authoritative complete command-set replay, but it did not render and inspect the restored app panel.

There is no accepted native proof that the panel never displays `NOTHING WAS WRITTEN` while the receipt remains ambiguous or reconciling.

### Signed Incomplete-Set Refusal

Wrong and incomplete command sets are rejected by focused tests.

The installed signed app was not driven through an injected incomplete authoritative receipt.

The corresponding zero-success UI was not captured with native Accessibility or pixels.

### Signed Authoritative Refusal Recovery

Focused tests prove that an authoritative `accepted = false` receipt clears the durable reconciling receipt and returns the approval state to review.

The installed signed app was not driven through that refusal after a lost reply.

The recovered review state and truthful zero-write message were not captured with native Accessibility or pixels.

## Acceptance Decision

The candidate materially closes the durable Calendar operation identity and replay defect.

The three completed signed backend journeys are accepted as real evidence for their exact scopes.

`ZC-052-005` must remain `Partially implemented` until the persistent-lock and signed native UI gates are completed end to end.
