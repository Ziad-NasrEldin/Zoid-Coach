#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"

zsh -n "$SCRIPT_DIR/qa-zc017007-open-ended-elapsed-fixture.sh"
zsh -n "$SCRIPT_DIR/qa-zc017007-signed-preflight.sh"
"$SCRIPT_DIR/qa-zc017007-open-ended-elapsed-fixture.sh" self-test
swift "$SCRIPT_DIR/qa-zc017007-open-ended-elapsed-ax-probe.swift" --self-test
"$SCRIPT_DIR/qa-zc017007-signed-preflight.sh" --self-test

print -- "PASS: ZC-017-007 signed runbook tooling self-test"
