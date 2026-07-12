# Zoid 666 Implementation Orchestration Rules

These rules remain binding until all 666 end-user scenarios are implemented and proven usable end to end.

- The root chat is orchestration-only.
- The root agent delegates every implementation, verification, documentation, and operational task to a subagent.
- Two implementation subagents must work continuously on the 666-scenario goal.
- The orchestrator maintains a durable, prioritized backlog so an implementation lane always has a ready next task.
- After an agent completes a substantial batch, the orchestrator closes that agent and starts a fresh agent on the next backlog slice to avoid context rot.
- All subagents use GPT Luna at medium effort when the platform supports explicit model and effort selection.
- Review time is cut in half relative to the previous workflow.
- Any review that is required runs in a parallel verifier lane so review never blocks the implementation pipeline.
- The authoritative scenario tracker and registry are updated after every completed and proven task.
- Implementation continues until every one of the 666 scenarios is fully implemented and proven usable end to end.

## Operating Contract

The two implementation lanes pull the highest-priority unowned item from `docs/impl/666-BACKLOG.md`.

Each item must have one owner, explicit acceptance proof, and an evidence location before work begins.

An implementation agent must deliver a clean commit, focused automated tests, relevant integration tests, and end-user proof proportional to the scenario.

A parallel verifier checks the acceptance proof without pausing the other implementation lane.

The orchestrator integrates completed commits, updates the tracker and registry, and immediately assigns the next backlog item.

Code presence alone never qualifies a scenario as complete.

