# ZC-030-011 signed QA remaining-gates rerun

## Verdict at the time of this run

The stale local-day, changed-time-zone, and unavailable-ledger gates passed completely.

The hard ten-minute cap arrived after the helper prerequisite was prepared but before the later real-helper suppression probe ran.

## Verified identity

- Signed verifier tip: `91e33ff277a5985d0f8d33de96dc6493441cbd36`.
- The package was rebuilt cleanly and installed through the isolated signed-QA lifecycle.
- Earlier current-day Save evidence from verifier tip `2f8eb02e757af92f05bcf37ecc51bb0a33c9a04c` was reused as authorized.

## Gates that passed in this rerun

- Stale local day: the signed sheet opened, authoritative policy moved from `Africa/Cairo` to `Pacific/Kiritimati`, Save visibly rejected the stale presentation, the ledger delta remained zero, and the refreshed Today snapshot reported `Pacific/Kiritimati`.
- Changed time zone: from a fresh isolated QA root, the signed sheet opened, authoritative policy moved from `Africa/Cairo` to `America/Adak` while retaining the same local day, Save visibly rejected the stale presentation, the ledger delta remained zero, and the refreshed Today snapshot reported `America/Adak`.
- Ledger unavailable: from a fresh isolated QA root with the helper stopped, the signed UI displayed the unavailable-ledger disclosure, disabled the adjustment control, and produced zero ledger writes after restoration.

## Incomplete gate later closed separately

- Real-helper `gamingIsUnlocked` suppression was not run before this run's hard cap.
- Its prerequisite state was prepared with seven complete baseline days, ten current gaming observations, and one isolated 15-minute grant.

## Cleanup proof

- Verifier-owned rows and temporary state were removed.
- The QA LaunchAgent is unregistered.
- No QA application, helper, or gaming verifier process remains.
- The isolated QA root, install root, compiled Accessibility probe, and `.build/app-qa` package are absent.
- Production runtime, production data, privacy permissions, canonical files, and tracker files were untouched.
