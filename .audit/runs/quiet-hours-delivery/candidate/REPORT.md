# Quiet-hours notification delivery candidate report

## Scope

- `ZC-005-008` - Configure quiet hours.
- `ZC-045-004` - Change quiet hours.

## End-user behavior

- Every prompt scheduled by the background agent now reads the latest persisted quiet-hours policy at delivery time.
- A prompt created during quiet hours remains durable and immediately available in Today, while its macOS notification is scheduled for the next quiet-hours end.
- The same boundary applies to plan-ready, plan-changed, meeting, gaming-drift, onboarding-test, and future supported prompt categories because it sits at the shared notification coordinator.
- Same-day and overnight quiet windows are supported.
- The exact quiet-hours end is allowed immediately rather than deferred by another day.
- Editing quiet hours changes the next scheduling decision without recreating or restarting the agent.
- Existing explicitly future-dated notification delivery is preserved and is moved only when the proposed time itself falls inside quiet hours.
- Invalid timezone data fails open to the proposed delivery time instead of silently losing a notification.

## Focused proof

- `swift test --filter "(QuietHoursDeliveryBoundaryTests|PromptNotificationCoordinatorTests)"` passed.
- Boundary tests prove both sides of an overnight interval converge on the same next end, same-day deferral, daytime and exact-end immediate delivery, and changed-policy behavior through one retained closure.
- Existing prompt-category and bounded-action notification tests pass with the shared delivery-boundary injection.
- The focused build compiles both production and QA fixture AgentMain composition with the latest-policy closure.
- `git diff --check` passed.

## Verifier plan

1. Rebase onto the current authoritative root and rerun the two focused groups once.
2. Under the serialized runtime lease, install signed QA with deterministic notification authorization.
3. Configure an overnight quiet window that contains the fixture clock, create one agent prompt, and verify it appears unresolved in Today immediately.
4. Inspect the fixture or Notification Center request and prove its one replacement-safe notification is scheduled exactly for quiet end rather than delivered immediately.
5. Restart the app and helper before quiet end and confirm the same prompt and scheduled request remain singular.
6. Change quiet hours so the fixture clock is outside the window, create another prompt without restarting the helper, and verify immediate notification eligibility.
7. Exercise a same-day window and the exact-end boundary.
8. Only after installed proof, update tracker, registry, backlog, and Lavish conservatively.
