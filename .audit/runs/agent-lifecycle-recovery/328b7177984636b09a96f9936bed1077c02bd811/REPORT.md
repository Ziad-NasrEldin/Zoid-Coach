# Background Agent Lifecycle Signed Verification

The installed signed QA app completed the decisive background-agent lifecycle journey against commit `328b717`.

The Background Agent window distinguished a current helper heartbeat from missing and stale runtime evidence.
Repair replaced the stopped helper with a new launchd process and returned the UI to Healthy.
Disable required explicit confirmation, explained that local plans, reviews, and history remain, and changed the UI to Not Connected.
Enable restored a healthy helper.
Terminating the helper caused launchd to replace PID `35687` with PID `36438`, after which Check Again returned the UI to Healthy.

Visible states covered current, missing, five-minute stale, repaired, disabled, re-enabled, and restart recovered.

A bounded three-second post-restart sample observed CPU values of `0.0%`, `1.2%`, and `2.5%` during startup.
Resident memory rose from `128 KB` during process creation to `23,616 KB` after initialization.
Open handles rose from `0` to `19` during initialization.
The SQLite file remained exactly `647,168` bytes in all three samples.

The full SQLite checksum changed from `1de8d1e88e8e536cb65c05310feea3c4034d7f120c3e3556d8a37d38cff339f7` to `ec2c603664476e4b9b448f8a5b7fdada851f098928748e2fff2441242f3c9aeb` because the acceptance fixture deliberately changed and then refreshed `processing_checkpoints.agent-runtime`.
No database-size growth occurred during repair, disable, re-enable, or restart.
The post-run logical dump excluding processing checkpoints hashed to `7e74ad24309e6c7d552ce96f932e65093f1fc2dbfdbe4ebde489488040b6301b`.

`ZC-048-007` is fully usable end to end.
The broader unhealthy-source impact and direct-repair scenarios remain conservative because non-agent gaps are outside this lifecycle slice.
`ZC-057-008` remains partial because a three-second startup sample is not a sustained energy measurement.
