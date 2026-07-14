# Arabic Welcome Signed Runtime Verification

## Candidate

The signed runtime was packaged from clean verifier tip `0a2f274682485fe9025858c61a69e78c7c6a06ec` on canonical base `100c5055fbf9d45072d5483182ed04f50d307fd7`.
The release package passed app, LaunchAgent, Mach-service, signing-identity, and strict on-disk signature validation.
The isolated installer passed writable XPC, prompt-timeline, LaunchAgent, installed-executable, and canonical-heartbeat gates.

## Core gate verdict

The Arabic Welcome journey is blocked before its first visible acceptance gate.
The installed app rendered the exact English Welcome shell after launch with `-AppleLanguages (ar) -AppleLocale ar_EG`.
The installed app still rendered the exact English Welcome shell after setting app-domain `AppleLanguages` to `ar` and `AppleLocale` to `ar_EG`, terminating the process, and relaunching the installed signed app.
Accessibility reported `SETUP · 1 OF 12`, `EXIT FOR NOW`, `READY TO CONTINUE`, and `CONTINUE` in both attempts.

## Root cause boundary

The packaged `Info.plist` declares `CFBundleDevelopmentRegion` but does not declare `CFBundleLocalizations`.
The signed bundle therefore does not advertise Arabic as a supported application localization, so macOS keeps SwiftUI's locale environment on the English path.
The localized Arabic model and its focused tests are not reachable through the installed end-user product as packaged.

## Remaining acceptance

No Arabic RTL, narrow-width, Arabic error, step-two reset, or Arabic relaunch gate can be credited from this run.
No tracker, registry, or Lavish promotion is justified.
A follow-up must add Arabic to the packaged bundle localization metadata, repackage and sign, then repeat the bounded core journey.
