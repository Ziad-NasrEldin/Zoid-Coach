# Onboarding persistence module migration

`OnboardingProgressStore` is now owned by `ZoidCoachInfrastructure` rather than `ZoidCoachCore`.

This is an intentional pre-release source migration.

Package clients should add the `ZoidCoachInfrastructure` library product to their target dependencies and import both modules where they use the store:

```swift
import ZoidCoachCore
import ZoidCoachInfrastructure

let store = OnboardingProgressStore()
```

The previous Core-only source form no longer compiles because `ZoidCoachCore.OnboardingProgressStore` has been removed.

The existing `ZoidCoachCore` package product also bundles the Infrastructure target for dependency compatibility, but Swift modules are not implicitly re-exported, so the explicit `import ZoidCoachInfrastructure` remains required.

No runtime data migration is required.

The persisted path remains `Zoid Coach/onboarding-progress.json`, and the document schema remains version 1.

A deprecated Core facade was rejected because Core cannot depend on Infrastructure without creating a dependency cycle.

Duplicating persistence in Core was also rejected because it would create two implementations and bypass the shared descriptor-relative locking, atomic-write, symlink-safety, and corruption-recovery guarantees.
