# Zoid 666 Audit Evidence

The authoritative current usability status is `docs/zoid-coach-product-scenario-tracker.md`.

The authoritative final consistency result is `.audit/consistency-report.md`.

The `scenarios-01-17.md`, `scenarios-18-34.md`, `scenarios-35-50.md`, and `scenarios-51-65.md` files are intermediate parallel audit reports.

They preserve the evidence observed by each auditor at the time of its pass, including transient runtime states that may have changed before final consolidation.

Do not use an intermediate slice report as current status without checking the final tracker and consistency report.

Future implementation evidence belongs under `.audit/runs/<slice>/<commit-sha>/` and must never overwrite an earlier run.
