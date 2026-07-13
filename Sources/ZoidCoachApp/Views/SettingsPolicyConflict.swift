import SwiftUI

struct SettingsPolicySaveConflict: Equatable {
    let winningVersion: Int
    let concurrentChanges: [String]
    let overlappingChanges: [String]
    let safeDraft: SettingsPolicyDraft
    let retryDraft: SettingsPolicyDraft

    var hasOverlaps: Bool { overlappingChanges.isEmpty == false }
}

struct SettingsPolicyMergeResult: Equatable {
    let safeDraft: SettingsPolicyDraft
    let retryDraft: SettingsPolicyDraft
    let concurrentChanges: [String]
    let overlappingChanges: [String]
}

enum SettingsPolicyConflictResolver {
    static func resolve(
        base: SettingsPolicyDraft,
        mine: SettingsPolicyDraft,
        current: SettingsPolicyDraft
    ) -> SettingsPolicyMergeResult {
        var safe = current
        var retry = current
        var concurrent = Set<String>()
        var overlaps = Set<String>()

        func merged<Value: Equatable>(
            _ keyPath: WritableKeyPath<SettingsPolicyDraft, Value>,
            label: String
        ) -> (safe: Value, retry: Value) {
            let baseValue = base[keyPath: keyPath]
            let mineValue = mine[keyPath: keyPath]
            let currentValue = current[keyPath: keyPath]
            let mineChanged = mineValue != baseValue
            let currentChanged = currentValue != baseValue
            if currentChanged { concurrent.insert(label) }
            if mineChanged, currentChanged, mineValue != currentValue {
                overlaps.insert(label)
                return (currentValue, mineValue)
            }
            if mineChanged { return (mineValue, mineValue) }
            return (currentValue, currentValue)
        }

        func apply<Value: Equatable>(
            _ keyPath: WritableKeyPath<SettingsPolicyDraft, Value>,
            label: String
        ) {
            let values = merged(keyPath, label: label)
            safe[keyPath: keyPath] = values.safe
            retry[keyPath: keyPath] = values.retry
        }

        apply(\.operatingMode, label: "Operating mode")
        apply(\.coachingLevel, label: "Coaching level")
        apply(\.gamingDailyBudgetMinutes, label: "Gaming daily budget")
        apply(\.gamingPriorityTaskRewardMinutes, label: "Gaming priority reward")
        apply(\.gamingIntentionalOverrideMinutes, label: "Intentional gaming override")
        apply(\.isPaused, label: "Automation pause")
        apply(\.workStart, label: "Workday window")
        apply(\.workEnd, label: "Workday window")
        apply(\.quietStart, label: "Quiet hours")
        apply(\.quietEnd, label: "Quiet hours")
        apply(\.nightlyPlanningTime, label: "Planning times")
        apply(\.morningConfirmationTime, label: "Planning times")
        apply(\.capacityPercent, label: "Planning capacity")
        apply(\.visibleCalendarIdentifiers, label: "Visible calendars")
        apply(\.schedulingCalendarIdentifier, label: "Scheduling calendar")
        apply(\.screenshotAnalysisEnabled, label: "Screenshot analysis")
        apply(\.aiProvider, label: "AI provider")
        apply(\.remoteEvidencePolicy, label: "Remote evidence")
        apply(\.rawScreenshotRetentionDays, label: "Data retention")
        apply(\.extractedTextRetentionDays, label: "Data retention")
        apply(\.diagnosticRetentionDays, label: "Data retention")
        apply(\.behaviorRecordRetentionDays, label: "Data retention")
        apply(\.taskSessionRetentionDays, label: "Data retention")
        apply(\.promptRetentionDays, label: "Data retention")
        apply(\.reviewRetentionDays, label: "Data retention")
        apply(\.codexCLIModel, label: "Codex model")
        apply(\.codexCLICustomModelID, label: "Codex model")
        apply(\.codexCLIReasoningEffort, label: "Codex reasoning")
        apply(\.wakeEligible, label: "Wake coaching")
        apply(\.wakeStart, label: "Wake window")
        apply(\.wakeEnd, label: "Wake window")
        apply(\.maximumDailyWakeInterventions, label: "Wake intervention limit")
        apply(\.wakeQuietWeekdays, label: "Wake quiet days")
        apply(\.behaviorPolicy, label: "Application classifications")
        apply(\.captureMode, label: "Capture mode")
        apply(\.captureDisplayIDs, label: "Capture displays")
        apply(\.reminderListPolicy, label: "Reminder lists")

        return SettingsPolicyMergeResult(
            safeDraft: safe,
            retryDraft: retry,
            concurrentChanges: concurrent.sorted(),
            overlappingChanges: overlaps.sorted()
        )
    }
}

struct SettingsPolicyConflictBanner: View {
    let conflict: SettingsPolicySaveConflict
    let keepCurrent: () -> Void
    let reapply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Sumi.seal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SETTINGS CHANGED SOMEWHERE ELSE")
                        .font(Sumi.label(10))
                        .sumiLabelTracking()
                    Text("Policy v\(conflict.winningVersion) is now the saved truth. Zoid 666 kept its winning values and preserved only your non-conflicting edits.")
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if conflict.concurrentChanges.isEmpty == false {
                Text("Changed elsewhere: \(conflict.concurrentChanges.joined(separator: ", ")).")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.ink)
            }
            if conflict.hasOverlaps {
                Text("Needs your decision: \(conflict.overlappingChanges.joined(separator: ", ")).")
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.seal)
            }

            HStack(spacing: 10) {
                Button("KEEP CURRENT VALUES", action: keepCurrent)
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .accessibilityIdentifier("settings.policyConflict.keepCurrent")
                Button("REAPPLY MY CHANGES", action: reapply)
                    .buttonStyle(SumiActionButtonStyle(role: .accent, size: .standard))
                    .accessibilityIdentifier("settings.policyConflict.reapply")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sumi.sealWash)
        .overlay { Rectangle().stroke(Sumi.seal, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.policyConflict")
    }
}
