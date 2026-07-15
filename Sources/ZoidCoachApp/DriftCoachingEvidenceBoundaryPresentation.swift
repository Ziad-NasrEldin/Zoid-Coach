struct DriftCoachingEvidenceBoundaryPresentation: Equatable {
    let hasSourceIssue: Bool
    let unknownMinutes: Int

    let policyDetail = "Strong gaming coaching also requires fresh, sustained, confident gaming and unfinished priority work."

    var title: String {
        if hasSourceIssue { return "COACHING HOLDS WHEN EVIDENCE IS LIMITED" }
        if unknownMinutes > 0 { return "UNKNOWN TIME DOES NOT TRIGGER STRONG COACHING" }
        return "CLASSIFICATION IS NOT INTENT"
    }

    var detail: String {
        if hasSourceIssue {
            return "Zoid 666 does not use stale or missing activity as strong drift evidence. Restore Source Health before trusting today's behavior picture."
        }
        if unknownMinutes > 0 {
            return "Unknown time stays out of work, gaming, and distraction. Review it if you know what happened; Zoid 666 does not guess."
        }
        return "Fresh classifications can support coaching, but an app name alone does not prove why you used it or whether it supported the active task."
    }

    var accessibilityValue: String {
        if hasSourceIssue { return "Limited evidence" }
        if unknownMinutes > 0 { return "Unknown evidence excluded" }
        return "Current evidence boundary"
    }
}
