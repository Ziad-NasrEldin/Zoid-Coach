# Candidate claim

Scenario: `ZC-021-005`.

An active task whose Apple Reminder is deleted externally must stop tracking immediately after the next source refresh.
The task must remain visible in Today with a specific deletion explanation so the user understands why work stopped.
Repeated refreshes and app restart must not add tracked time or duplicate the pause transition.
The user must still be able to complete the orphaned row and continue with the remaining plan.

This candidate does not claim signed external Apple Reminders deletion or visible Today UI acceptance.
