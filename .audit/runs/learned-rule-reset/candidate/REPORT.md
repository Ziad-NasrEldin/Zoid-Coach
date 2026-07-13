# Learned rule reset candidate

## Scope

- `ZC-045-015` - Reset learned rules.

## End-user result

Daily Review now shows the exact number of active learned app-classification rules.
When at least one exists, the user can choose `RESET LEARNED RULES` and review a destructive confirmation before anything changes.
The confirmation explains that future observations return to the normal Settings policy while historical corrections and review totals remain unchanged.
Reset appends one removal record per active rule instead of deleting audit history.
The active-rule ledger refreshes immediately and reports the exact number removed.
Repeating reset with no active rules is safe and changes nothing.
The reset control has a stable accessibility identifier.

## Evidence

- Candidate implementation: `c62aa88`.
- `swift test --filter DailyReviewTests` passed the full focused review group.
- The new journey creates two learned rules from corrected sessions, resets both, proves four append-only rule records, repeats reset idempotently, reopens the database, and proves both historical corrections and task attachments remain.
- `git diff --check` passed before the implementation commit.

## Verifier plan

A fresh verifier should rebase the candidate onto authoritative root `4b1960b` or later and run `DailyReviewTests` once.
In signed QA, create two distinct learned rules, relaunch, confirm the active count, cancel the reset once, confirm and reset, verify the ledger disappears and success copy reports two, then relaunch and confirm historical corrected sessions and totals remain while future rules stay absent.
The root, runtime, tracker, registry, and Lavish artifact remain untouched by this implementation lane.
