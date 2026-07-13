# ZC-025-003 Independent Verification

## Verdict

Advance `ZC-025-003` from `Not implemented` to `Touches remaining`.

The contextual classifier is implemented, persists its result, and is usable through the signed installed app for the automatic path.

The remaining touch is one visible user-applied rule followed by contradictory later context and an app/helper relaunch.

The focused integration test proves rule precedence, but that last native action was not completed within the ten-minute serialized runtime lease.

## Verified Build

The independent branch started from authoritative commit `36992399667bc3a7db0979ffa86761e373b78f09`.

Candidate `0207975` was transplanted without its conflicting backlog note as isolated commit `52e2179`.

The backlog conflict was documentation-only and the authoritative backlog was left untouched.

The verifier added a reopen assertion in `ScreenwatchArchiveTests.swift` and committed it as `60b6bea` before packaging.

## Focused Code Review

The decision order is durable correction rule, explicit application policy, local contextual classification, then the legacy deterministic classifier.

This preserves user authority over automatic evidence.

Safari and other browsers, Discord, Slack, Notion, YouTube, and Preview are context-sensitive.

Clear local signals produce Work, Gaming, or Distracting, while insufficient context produces Unknown.

The implementation only reads the title and URL fields already present in the local Screenwatch archive.

It adds no prompt, diagnostic, export, remote-request, or new persistence path for those private fields.

No product-code defect was found in the focused review.

## Automated Evidence

`swift test --filter ScreenwatchArchiveTests` exited successfully.

`swift test --filter contextSensitiveApplicationsUseLocalWindowAndURLMeaningInsteadOfPermanentLabels` passed.

That test covers Safari work, YouTube work and distraction, Discord work and gaming, Notion work, Preview work, and Slack Unknown.

The verifier reopened the SQLite archive and confirmed that the same eight classifications remained persisted.

`swift test --filter explicitApplicationPolicyOverridesContextualEvidence` passed.

That test proves that an explicit Slack-to-Gaming policy outranks contradictory work context.

`swift build -c release` exited successfully.

`git diff --check` passed before handoff.

The build emitted pre-existing deprecation warnings for `PolicyStore.save` in nearby tests, with no failure.

## Signed Native Journey

The canonical ready-state preparer built an isolated QA root at `/private/tmp/zoid-666-contextual-qa`.

One signed QA package was installed under `/private/tmp/zoid-666-contextual-install` from verifier commit `60b6bea`.

The fixture ingested the following local records:

- Safari with Swift documentation became Work.

- YouTube with a Swift tutorial became Work.

- YouTube Shorts became Distracting.

- Discord with the Zoid 666 project became Work.

- Discord with a Minecraft server became Gaming.

- Notion with a product roadmap became Work.

- Preview with a client proposal became Work.

- Slack with a generic General window remained Unknown.

The durable database contained the exact app/category pairs before UI inspection.

Native AX and window pixels showed Today with separate Work, Gaming, and Distraction totals.

After app and helper relaunch, native AX showed `Work, 5 minutes`, `Gaming, 1 minutes`, `Distraction, 1 minutes`, and `Unknown, 1 minutes`.

The same relaunch exposed `REVIEW AND CORRECT ACTIVITY`.

The Review surface showed one unknown session and explained that leaving it Unknown is a valid choice.

The Review surface also stated that only local activity summaries are shown and that window titles, URLs, and screenshots are never displayed there.

The signed runtime was removed and both QA processes were absent before the lease was released.

## Pixel Evidence

- `signed-today.png` shows the installed Today surface after fixture consumption.

- `signed-activity.png` shows separate Work, Gaming, Distraction, Idle, and Unknown totals with uncertainty copy.

- `signed-activity-relaunch.png` preserves the visible totals after app and helper relaunch.

- `signed-review.png` shows the privacy-safe Review surface reached from the activity sheet.

## Remaining Acceptance

Open the installed Settings or Review classification control.

Apply one explicit rule to a context-sensitive application.

Ingest a later record whose contextual signal contradicts that rule.

Restart the helper and app.

Confirm visibly that the explicit rule still wins without exposing the title or URL.

After that single touch, `ZC-025-003` can advance to `Fully implemented` without further classifier work.
