# Scenario Evidence Runs

`Scripts/scenario_evidence.py` creates an immutable evidence manifest for one or more scenario IDs.
The run directory must end with the exact commit being verified.
An existing run directory is never overwritten.

First create and verify a clean packaged QA app.
Then create the evidence run before launching that exact package:

```bash
python3 Scripts/scenario_evidence.py create \
  --run-dir .audit/runs/onboarding/0123456789abcdef0123456789abcdef01234567 \
  --scenario ZC-001-001 \
  --scenario ZC-001-002 \
  --build-identity zoid-coach-0123456789abcdef0123456789abcdef01234567-clean \
  --fixture first-run \
  --qa-root /tmp/zoid-coach-qa/onboarding-001 \
  --commit 0123456789abcdef0123456789abcdef01234567
```

The verifier records relative artifact paths and SHA-256 values in `evidence.json`.
The verifier also records assertions, commands, completion time, and final status.
Only a passed run with at least one assertion and one checksummed artifact is accepted.

Validate the completed manifest against the current 666-scenario registry:

```bash
python3 Scripts/scenario_evidence.py validate \
  .audit/runs/onboarding/0123456789abcdef0123456789abcdef01234567/evidence.json
```

Registry drift, missing scenarios, malformed run identity, escaping artifact paths, missing artifacts, and checksum mismatches fail validation.
A build identity is accepted only when it contains the full existing verified commit and the `clean` state.
