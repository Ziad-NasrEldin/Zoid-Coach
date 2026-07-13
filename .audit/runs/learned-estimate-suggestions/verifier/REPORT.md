# Learned Estimate Suggestions Verification

## Result

- Verified candidate commit: `4a34cd7d425e3f08b48d9e0f45ea293d117d907b`.
- `LearnedEstimateSuggestionTests` passed once.
- The release QA package, signing identities, LaunchAgent, and Mach service validation passed once.

## Signed Evidence

- A signed Today plan showed `Write proposal` with its original 30-minute estimate and no suggestion when only three eligible matching samples existed.
- After a fourth eligible matching sample and aggregate were available, the app and helper were relaunched once.
- Today then showed an accessible `LEARNED ESTIMATE` card recommending 50 minutes from four similar completed tasks.
- The card showed the exact historical aligned-work range of 40 to 55 minutes and labeled the evidence `EARLY PATTERN`.
- The card explicitly stated that the suggestion was advisory and that no estimate changes until Use is selected.
- The task remained visibly selected at 30 minutes, proving the advice did not silently overwrite the plan.
- The capped run stopped after the requested supported refresh and relaunch, so Use, Keep, custom-entry, and low-coverage UI branches remain unverified.

## Runtime

- Installed app: `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app`.
- QA root: `/private/tmp/zoid-666-learned-estimate-suggestions-qa`.
