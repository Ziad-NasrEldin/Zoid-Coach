# ZC-030-011 fixed-product signed QA result

## Verdict

Strict Full eligibility: **No**.
The bounded signed run proved packaging, installation, service registration, current-day UI submission, and durable storage exactly once.
The stale-state setup then failed before changing authoritative policy, so the required negative paths and final helper suppression were not completed on this verifier tip.

## Verified identity

- Product base: `f20b3ba6bf3e6280eaba492dd3b494a973eec248`.
- QA layers in this worktree: `fb3a61e` and `1a7cf2a`.
- Verifier tip: `2f8eb02e757af92f05bcf37ecc51bb0a33c9a04c`.
- Packaged build identity: `zoid-coach-2f8eb02e757af92f05bcf37ecc51bb0a33c9a04c-clean`.

## Gates that passed

- The QA package built and deep-sign verification passed.
- Installed-package verification passed for the application, bundled LaunchAgent, Mach service, and signing identities.
- The isolated signed QA runtime installed successfully.
- The QA XPC runtime was writable and its prompt timeline was available.
- The QA LaunchAgent registered, ran from the isolated installed application, and exposed its Mach service.
- The signed application launched through LaunchServices.
- The current-day manual-adjustment sheet opened through Accessibility.
- The Accessibility probe submitted the manual-adjustment form exactly once.
- After asynchronous persistence settled, the database contained exactly one positive 15-minute row with note `qa-zc030011-manual-grant` for local day `2026-07-14`.
- The verifier confirmed that the signed-app grant was durable and the ten verifier-owned raw observations were unchanged.

## Failed or incomplete gates

- Stale local-day rejection: setup failed before authoritative policy mutation with `sqlite3.OperationalError: no such column: val_json`.
- The isolated runtime database exposed `settings.value_json`, while verifier tip `2f8eb02` queried `settings.val_json`.
- Because setup failed before mutation, the visible stale local-day rejection, refresh behavior, and zero-ledger-delta assertion were not completed.
- Changed-time-zone rejection, refresh behavior, and zero-ledger-delta assertion were not run.
- The unavailable-ledger copy, disabled Save control, and zero-write assertion were not run.
- The real signed helper `gamingIsUnlocked` suppression and its zero prompt, delivery, and QA-notification assertions were not run on this verifier tip.

## Cleanup proof

- The verifier-owned observations, adjustment row, and temporary verifier state were removed before uninstall.
- The QA LaunchAgent is unregistered.
- No `ZoidCoachQA`, `ZoidCoachAgentQA`, or gaming verifier process remains.
- The isolated QA database root is absent.
- The isolated install root is absent.
- The compiled Accessibility probe and temporary screenshot are absent.
- The generated `.build/app-qa` package directory is absent.
- The verifier branch worktree is clean.
- No production runtime, production data, privacy permission, canonical tracker, or canonical worktree was modified.
