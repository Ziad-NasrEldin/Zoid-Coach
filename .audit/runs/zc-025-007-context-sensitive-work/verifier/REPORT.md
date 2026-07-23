# ZC-025-007 Independent Signed Verification

## Verdict

Candidate `30fd8d2bd93a16952c22811fd60dac1e9caeaeef` is eligible for `Fully implemented` for ZC-025-007.

The installed signed app visibly recognizes a technical YouTube documentation tutorial as Work while explicitly leaving Research at zero and explaining that application evidence did not prove support for the active task.

An insufficient-context YouTube observation remained Unknown and did not add Research time.

The same result survived an app and helper relaunch.

## Candidate Review

The exact candidate changes four files only.

The state model derives uncertain work only from application summaries already classified as Work when the application name is not itself a recognized work-category tool.

The UI exposes privacy-safe stable identifiers, labels, and hints through a dedicated accessibility bridge.

The implementation does not expose window titles or URLs and does not create a new persistence path.

No product-code correction was required.

## Automated Gates

The 11 `Today behavior evidence` state tests passed.

The two `Behavior evidence accessibility` tests passed.

The contextual YouTube classification integration test passed.

These are the requested 14 focused tests.

The broader `BehaviorEvidence` filter also selected three existing migration and baseline tests, and all 17 executed tests passed.

## Signed Package Gates

The release QA package completed from the exact candidate commit.

Deep strict code-sign verification passed for the app and embedded helper.

The installed app used bundle identifier `qa.ziadnasreldin.ZoidCoach` and team `377QC32T9T`.

The isolated LaunchAgent registered as `qa.ziadnasreldin.ZoidCoach.agent` from the installed signed app.

The canonical QA heartbeat, writable XPC runtime, prompt timeline, Mach service, and LaunchServices visibility gates passed.

## Signed Native Journey

The fixture created one incomplete task named for a Swift concurrency pipeline and the actual installed UI started it as the active open-ended commitment.

The real signed helper ingested ten one-minute YouTube observations containing a private technical documentation title and URL sentinel.

The helper classified all ten technical observations as Work through the production contextual classifier.

The helper also ingested two insufficient-context YouTube observations and classified them Unknown.

The installed Today surface visibly showed ten minutes of Working time while the related task remained active.

The actual Behavior Evidence sheet visibly showed Work at 10 minutes, Research at 0 minutes, Uncategorized work at 10 minutes, and Unknown at 1 minute.

The sheet visibly stated that the YouTube work was observed as Work but could not be proven to support the active task or safely labeled Research.

The uncertain application row exposed stable identifier `today.behavior-evidence.work-uncertainty.596f7554756265`, label `YouTube, 10 complete minutes, work category uncertain`, and the matching privacy-safe hint.

The Research category exposed stable identifier `today.behavior-evidence.work-category.research` and remained at zero minutes.

No private title, URL, negative-observation sentinel, or task sentinel appeared anywhere in the Behavior Evidence sheet accessibility tree.

After terminating and relaunching both the signed helper and app, the same Work, Research, Uncategorized, Unknown, identifier, label, hint, and privacy result remained visible.

## Fixture Correction

The first fixture wording used `tutorial`, which is not an explicit contextual work rule and correctly produced Unknown.

The verifier changed only the isolated source fixture wording to `documentation tutorial`, removed the two fixture-owned imported groups, and let the actual signed helper ingest them again.

No success row was inserted or modified directly.

## Isolation And Cleanup

All package, app, helper, database, Screenwatch, and OS-fixture paths were under `/private/tmp/zoid-666-zc025007-*`.

No production app, LaunchAgent, database, tracker, registry, Lavish artifact, or canonical source file was targeted.

The verifier worktree remained clean at the exact candidate commit.

The signed QA LaunchAgent was unregistered and removed.

The QA app and helper processes were absent after cleanup.

The isolated QA database, Screenwatch fixture, control files, and install root were removed.
