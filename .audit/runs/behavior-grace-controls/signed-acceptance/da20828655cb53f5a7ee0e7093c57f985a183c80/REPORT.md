# Signed acceptance for configurable behavior grace controls

The clean signed Zoid 666 QA package at commit `da20828655cb53f5a7ee0e7093c57f985a183c80` fully qualifies `ZC-045-006`.

The installed Settings UI visibly exposed task-start and return-from-idle grace controls with stable accessibility descriptions.

The running agent saved 12-minute and four-minute values as policy V2.

Closing and reopening Settings restored both exact values.

Restarting the app and helper restored policy V2 with both exact values.

An isolated signed-runtime fixture inside the 12-minute task-start boundary retained zero prompts, zero quiet-drift records, one active task, one open activity interval, and all ten behavior observations.

The same installed UI shortened task-start grace to ten minutes and saved policy V3 without restarting the helper.

The helper PID remained unchanged and its runtime checkpoint advanced during the bounded recheck.

No prompt was enqueued after the shorter boundary, so this run does not qualify `ZC-027-002` or `ZC-027-003` and does not claim that installed runtime branch.

The focused User Policy, Settings Policy Draft, and Gaming Drift Prompt Service groups passed 67 of 67 tests.

The release build and clean signed QA package verification passed.

The isolated signed helper, app, and runtime root were removed after the cap.
