# Custom task estimate candidate

## Scope

- `ZC-011-006` - Enter a custom estimate.
- `ZC-011-007` - Receive a clear error for an empty, zero, negative, or malformed estimate.

## End-user result

Every plan task estimate selector now offers `CUSTOM` alongside the five presets.
The user can type whole minutes, press Return or Save, cancel without changing the plan, and immediately reuse the existing durable estimate-update path.
Empty, zero, negative, decimal, text, and estimates above eight hours remain in the editor and show a precise corrective message.
The upper bound explains that larger work should be split into smaller tasks.
The custom field, save control, trigger, and error have stable accessibility labels or identifiers.
Successful input closes the editor and returns to the confirmed estimate state.

## Evidence

- Candidate implementation: `edc4e5e`.
- `swift test --filter TaskEstimateInputTests` passed valid boundary, whitespace, invalid-format, invalid-range, and actionable-copy cases.
- `swift test --filter PlanningCapacityStateTests` passed estimate-dependent plan capacity, missing-estimate, buffer, overload, and plan-reduction behavior.
- `git diff --check` passed before the implementation commit.

## Verifier plan

A fresh verifier should rebase onto the authoritative root and run the two focused groups once.
In signed QA, open the first-plan review, enter empty, zero, negative, decimal, text, and excessive values, confirm each exact error, cancel once, then save 25 minutes with Return and confirm plan capacity updates and survives app/helper restart.
The root, runtime, tracker, registry, and Lavish artifact remain untouched by this implementation lane.
