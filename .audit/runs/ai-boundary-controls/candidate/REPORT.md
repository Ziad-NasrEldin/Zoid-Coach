# Optional AI boundary controls candidate

## Outcome

The Intelligence settings surface now makes the local-versus-remote evidence boundary inspectable before the user saves a remote choice.
It also exposes the existing authenticated AI metadata deletion path directly beside the provider controls.

## End-to-end behavior

- Local-only preview states that no remote payload is sent.
- Redacted preview uses anonymous task and application labels and shows representative scheduling metadata.
- Private-content preview makes the additional title and application fields visible before opt-in.
- Every preview explicitly excludes screenshots, extracted conversation text, URLs, internal task identifiers, and credentials.
- The preview is a fixed sample and clearly says it is not the user's current data.
- The Clear AI Cache and Request History action uses the existing confirmation and background-agent deletion command.
- The destructive confirmation explains that model-run cache records, Codex jobs, and transmission receipts are removed while Keychain credentials remain.
- Completion or failure is shown on the same Intelligence surface.

## Verification

- `swift test --filter RemoteEvidencePreviewTests` passed.
- Both individual preview tests passed when filtered by exact test name.
- The tests prove local-only sends nothing, redacted samples omit real titles, private samples disclose their extra fields, and all modes retain the required exclusions.
- `git diff --check` passed.

## Acceptance boundary

The candidate does not claim installed-app interaction or background-agent deletion proof.
A fresh verifier should inspect all three previews, confirm the redacted/private differences and accessibility content, seed a model-run cache record, clear it through the signed Settings UI, and prove the record is removed while credentials and non-AI local data remain.
