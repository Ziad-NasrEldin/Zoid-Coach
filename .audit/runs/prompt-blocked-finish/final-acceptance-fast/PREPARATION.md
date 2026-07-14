# ZC-034-011 Fast Acceptance Preparation Evidence

## Exact package

The verifier detached to exact canonical commit `f28ad1087623bd308fc410f78ab6215cf1b69131` with a clean worktree before packaging.
The package command used release configuration, QA mode, and fixed isolated root `/private/tmp/zoid-666-zc034011-fast-root`.
The package reported coherent app, LaunchAgent, Mach-service, and signing identities.
The packaged app is isolated at `.build/app-qa/Zoid 666 QA.app` in the verifier worktree.
Its embedded build identity is `zoid-coach-f28ad1087623bd308fc410f78ab6215cf1b69131-clean`.
Its bundle identifier is `qa.ziadnasreldin.ZoidCoach` and its display name is `Zoid 666 QA`.
Its embedded QA root exactly matches the root guarded by the runtime harness.

## Signing

Deep strict code-sign verification passed for the app and packaged helper.
The app CDHash is `94e7a2b09afc96a13c2bc349fc3cfeeee543083e`.
The signing authority is `Apple Development: Ziad Ahmed (4VJ4SRGADX)` under team `377QC32T9T`.
The app executable SHA-256 is `2012d1dea61ea8c8cb1e5e2ad995d879f752da0b62460fcb499abac55f6aa748`.
The helper executable SHA-256 is `bfcc3343ab964e9b56cfa876d819308ce1204df9f4da63d1ddfc1a5f978ac9c8`.

## Verifier tools

The native accessibility driver compiled successfully into ignored verifier output `.build/zc034011-fast/ax-driver`.
The signed-window and pixel probe compiled successfully into ignored verifier output `.build/zc034011-fast/qa-window-content-probe`.
Invoking each tool without arguments returned its expected usage contract without touching a running process.

## Guarded dry run

The non-runtime dry run passed.
It revalidated the exact clean package identity, deep strict signature, compiled tools, source-product parity, and fixture manifest.
It explicitly reported that no install, app launch, helper registration, or runtime mutation was performed.

## Runtime readiness

The next command is `ZOID_ACCEPT_RUNTIME_LEASE=granted .audit/runs/prompt-blocked-finish/final-acceptance-fast/run-acceptance.sh` from this verifier worktree.
The command must not run until the serialized signed-runtime lease is granted.
At preparation completion, the package used 36 MB, verifier tools used 204 KB, and `df` reported approximately 11 GiB available.

