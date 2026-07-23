# Zoid Voice

## Purpose

Zoid Voice is the always-available conversational surface for the existing autonomous coach.
Gemini Live supplies low-latency conversation and function selection.
The local Zoid agent retains authority over policy, memory, actions, approval, auditing, and recovery.
Codex runs longer scoped work without blocking the live conversation.

## Activation and audio

The signed app remains available as a menu-bar host after the main window closes.
Control-Option-Space toggles the live session by default, with Command-Shift-Space available from settings.
The phrase "Hey Zoid" is recognized locally through the macOS on-device Speech framework.
This is the current signed-build fallback while the sherpa-onnx Apple Silicon runtime and acoustic model are packaged.
The wake listener stops before Gemini audio capture begins so only one process owns the microphone stream.

Live microphone audio is converted to mono 16 kHz PCM.
Gemini audio is decoded as mono 24 kHz PCM.
Speaking while Zoid is playing audio stops playback and returns the session to listening.
Raw audio is never written to disk.

## Gemini transport

The production client uses the Gemini Live WebSocket protocol directly from Swift.
The API key is attached only to the authenticated WebSocket request and is stored in macOS Keychain.
Session setup enables native audio, input and output transcription, context-window compression, function declarations, and session resumption.
The app checkpoints long conversations after approximately ten minutes and can reconnect from a resumption handle after a server `GoAway` event.

## Tools and authority

The model receives only the allowlisted chief-of-staff tools.
Unknown tools and arbitrary shell requests are denied before execution.

Automatically allowed tools cover daily briefing, active-task state, application launch, web search, Spotlight file lookup, file opening, Reminders, Zoid-owned focus blocks, automation pause or resume, scoped Codex jobs, conversation memory, and selected Screenwatch context.
Every reversible tool that changes local state requires explicit user intent from the active conversation.

Externally meaningful Calendar commitments create a two-minute approval request.
The local executor does not run the tool until the user approves it from the voice panel.
Denied, expired, and replayed approvals cannot execute the action.
The approval panel names the exact tool and arguments, and concurrent approval claims are serialized.

Codex jobs receive an existing workspace, an objective, a read-only or workspace-write sandbox, and a thirty-minute timeout.
Their instruction forbids commit, push, deploy, publishing, messaging, purchases, credential exposure, and writes outside the workspace.
Workspace-write jobs also run under a macOS sandbox rule that denies writes to the workspace Git metadata, so a job cannot create a commit by ignoring the prompt.
Jobs and final outcomes survive app restarts, while interrupted jobs are marked failed with a recovery explanation.

## Context and memory

Each session begins with the current Today snapshot, active task, recommendation, behavior summary, source health, upcoming Calendar commitments, active Codex jobs, current policy, and relevant conversation memories.
This context is marked as untrusted evidence in the system instruction.

Final transcript turns remain in the local database for thirty days.
Confirmed goals, preferences, commitments, corrections, and summaries remain until deleted.
Unconfirmed or expired facts cannot authorize an action.
Voice tools support correcting or deleting a memory, explaining its source and confirmation state, exporting active memories as JSON, and deleting retained transcripts after confirmation.

Screenwatch remains the complete local visual archive.
When Gemini needs visual context, Zoid selects at most four recent screenshots, removes repeated perceptual fingerprints, verifies the files still exist, and transmits only the selected frames.
Every transmitted selection is recorded in the local audit table.
The audit is committed before image bytes are sent, and local paths and artifact identifiers are removed from the tool response returned to Gemini.
The tool remains unavailable unless the active privacy policy allows explicit private content.

## Cost control and fallback

The monthly Gemini limit is fixed at $20 and resets on the first day of the configured local month.
The ledger uses provider token counts when available and a conservative audio-duration estimate when usage metadata is missing.
The higher estimate wins.
Each cloud session atomically reserves all remaining monthly budget before connecting and settles that reservation to actual usage when it closes.
If the app or Mac crashes, the conservative reservation remains charged, so a restart cannot bypass the cap.

Zoid warns at $14 and $18.
When projected usage reaches $20, microphone streaming stops and the current response is allowed to finish before the cloud session closes.
Subsequent activations use local command mode until the next period.

Local command mode supports the daily brief, app launch, web search, Spotlight file search, and automation pause or resume.
It uses on-device speech recognition and macOS system speech.
If on-device recognition is unavailable, the typed command field and normal app controls remain available.

## Proactive behavior

The app checks the agent snapshot once per minute without opening a Gemini session.
Initial triggers cover commitments within fifteen minutes, overdue high-urgency work, completed or stopped Codex jobs, and at least five new minutes of drift while a task is active.
Configured quiet hours are always respected.

When headphones are active, proactive copy uses local system speech.
Otherwise Zoid posts a silent macOS notification.
Proactive behavior never opens the cloud microphone.

## Verification

Run `swift test` for domain, migration, persistence, transport-codec, policy, approval, Screenwatch selection, local parser, and Codex lifecycle coverage.
Run `./Scripts/install-app.sh` to package, sign, install, register the background agent, and verify the Screenwatch-to-Zoid background chain.
The Gemini network path additionally requires a user-supplied API key and microphone permission on the target Mac.
