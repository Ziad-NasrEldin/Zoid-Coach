# Arabic Welcome Signed Runtime Verification

## Candidate

The corrected signed runtime was packaged from clean verifier tip `a0f45d3a6c69db99d23550b1691781898ebb112d` on canonical base `100c5055fbf9d45072d5483182ed04f50d307fd7`.
The source repair commit is `b58427f` and the bundle-localization repair is `f1a1aa6`.
The release package passed app, LaunchAgent, Mach-service, signing-identity, and strict on-disk signature validation.
The isolated installer passed writable XPC, prompt-timeline, LaunchAgent, installed-executable, and canonical-heartbeat gates.
The installed bundle advertised `CFBundleLocalizations` values `en` and `ar`.

## Signed Arabic Welcome

The signed app launched at onboarding step 1 with its app-specific language set to Arabic.
The 1180 by 760 window visibly rendered the complete Arabic Welcome card without clipping.
The progress rail appeared on the logical right and the Welcome card, header, status, and action used right-to-left layout.
Accessibility exposed Arabic setup progress, Exit title and help, Ready status, Continue title, and localized native roles.
The visible card contained the Arabic eyebrow, title, positioning body, and safety note.

## Step boundary and relaunch

Activating the signed Continue control persisted onboarding step 1 and opened step 2.
Step 2 restored the exact existing English content and left-to-right layout while the application language remained Arabic.
The app and installed QA helper were then terminated.
The LaunchAgent restarted from the installed signed helper, and relaunch restored step 2 with the same English content and left-to-right layout.

## Incomplete gates

Computer Use could not resize this native window because its window transport returned `noWindowsAvailable`.
The 519-point installed layout therefore remains unverified, although the focused hosted-width contract is covered by the passing eight-test gate.
Two native Return-event attempts did not advance the focused app, so this run credits the Continue activation but not keyboard Return acceptance.
A generic Arabic setup error was not safely induced in the remaining runtime cap.
The unsupported French fallback was not repeated in the signed app.

## Verdict

The first-screen Arabic localization is materially usable in the standard signed journey and persists the expected language boundary across app and helper restart.
Scenario `ZC-056-003` is not fully implemented because localization remains limited to this first-screen slice and the narrow-width, keyboard, error, and unsupported-locale installed gates remain open.
The correct tracker classification is `Touches remaining`.
