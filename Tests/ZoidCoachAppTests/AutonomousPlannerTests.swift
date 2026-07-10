import Foundation
import Testing
@testable import ZoidCoachCore

@Test
func plannerKeepsTheDailyCommitmentSetWithinCapacityAndMakesTheUrgentTaskMain() {
    let planner = AutonomousPlanner()
    let reference = Date(timeIntervalSince1970: 1_784_000_000)
    let input = PlanningInput(
        referenceDate: reference,
        availableFocusMinutes: 120,
        maximumCommitments: 3,
        candidates: [
            PlanningTaskCandidate(
                id: "client-review",
                title: "Send client review",
                estimateMinutes: 60,
                dueDate: reference.addingTimeInterval(2 * 60 * 60),
                reminderPriority: .high,
                carryoverDays: 0,
                deferralCount: 0,
                recentAlignedMinutes: 0,
                isBlocked: false
            ),
            PlanningTaskCandidate(
                id: "design-system",
                title: "Refine design system",
                estimateMinutes: 45,
                dueDate: nil,
                reminderPriority: .medium,
                carryoverDays: 2,
                deferralCount: 1,
                recentAlignedMinutes: 90,
                isBlocked: false
            ),
            PlanningTaskCandidate(
                id: "stretch-project",
                title: "Large exploratory project",
                estimateMinutes: 90,
                dueDate: nil,
                reminderPriority: .none,
                carryoverDays: 0,
                deferralCount: 0,
                recentAlignedMinutes: 0,
                isBlocked: false
            ),
            PlanningTaskCandidate(
                id: "waiting-on-client",
                title: "Waiting on client reply",
                estimateMinutes: 15,
                dueDate: nil,
                reminderPriority: .high,
                carryoverDays: 4,
                deferralCount: 4,
                recentAlignedMinutes: 0,
                isBlocked: true
            )
        ]
    )

    let proposal = planner.plan(input)

    #expect(proposal.items.map(\.taskID) == ["client-review", "design-system"])
    #expect(proposal.mainObjectiveTaskID == "client-review")
    #expect(proposal.plannedFocusMinutes == 105)
    #expect(proposal.items.allSatisfy { !$0.reason.isEmpty })
}

@Test
func screenwatchDecoderPreservesTheObservationNeededForLaterEvidenceAnalysis() throws {
    let decoder = ScreenwatchLogDecoder()
    let line = "{\"t\":\"10-20-30\",\"epoch\":1783639230,\"app\":\"WhatsApp\",\"window\":\"Sarah\",\"url\":\"\",\"img\":true}"

    let observation = try decoder.decode(Data(line.utf8))

    #expect(observation.timeLabel == "10-20-30")
    #expect(observation.epoch == 1_783_639_230)
    #expect(observation.appName == "WhatsApp")
    #expect(observation.windowTitle == "Sarah")
    #expect(observation.hasScreenshot)
}

@Test
func schedulerPlacesWorkOnlyInsideFreeIntervalsAndLeavesTransitionTime() {
    let start = Date(timeIntervalSince1970: 1_783_670_400)
    let scheduler = CalendarBlockScheduler()
    let result = scheduler.schedule(
        tasks: [
            SchedulableTask(id: "first", title: "First", durationMinutes: 45),
            SchedulableTask(id: "second", title: "Second", durationMinutes: 30)
        ],
        availableIntervals: [
            CalendarInterval(start: start, end: start.addingTimeInterval(60 * 60)),
            CalendarInterval(start: start.addingTimeInterval(2 * 60 * 60), end: start.addingTimeInterval(3 * 60 * 60))
        ],
        transitionMinutes: 10
    )

    #expect(result.blocks.count == 2)
    #expect(result.blocks[0].taskID == "first")
    #expect(result.blocks[0].start == start)
    #expect(result.blocks[0].end == start.addingTimeInterval(45 * 60))
    #expect(result.blocks[1].taskID == "second")
    #expect(result.blocks[1].start == start.addingTimeInterval(2 * 60 * 60))
    #expect(result.unscheduledTaskIDs.isEmpty)
}

@Test
func meetingExtractorResolvesAnExplicitWeekdayAndTimeAsAConfirmableCandidate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9, minute: 0))!

    let candidate = MeetingCandidateExtractor(calendar: calendar).extract(
        from: "Let's meet Tuesday at 3:30 PM for 45 minutes to review the proposal.",
        observedAt: reference
    )

    #expect(candidate?.start == calendar.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 15, minute: 30)))
    #expect(candidate?.durationMinutes == 45)
    #expect(candidate?.confidence == .high)
    #expect(candidate?.requiresClarification == false)
}

@Test
func meetingExtractorKeepsAMeridiemFreeTimeAsAnEditableDraft() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9, minute: 0))!

    let candidate = MeetingCandidateExtractor(calendar: calendar).extract(
        from: "Can we meet tomorrow at 3 to discuss the proposal?",
        observedAt: reference
    )

    #expect(candidate?.confidence == .medium)
    #expect(candidate?.requiresClarification == true)
}

@Test
func meetingExtractorRecognizesArabicTomorrowTimeAndDuration() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9, minute: 0))!

    let candidate = MeetingCandidateExtractor(calendar: calendar).extract(
        from: "خلينا نتقابل بكرة الساعة ٣:٣٠ م لمدة ٤٥ دقيقة",
        observedAt: reference
    )

    #expect(candidate?.start == calendar.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 15, minute: 30)))
    #expect(candidate?.durationMinutes == 45)
    #expect(candidate?.confidence == .high)
}

@Test
func plannerUsesBoundedLocalAIAdviceWithoutAllowingItToBypassCapacity() {
    let planner = AutonomousPlanner()
    let reference = Date(timeIntervalSince1970: 1_784_000_000)
    let proposal = planner.plan(
        PlanningInput(
            referenceDate: reference,
            availableFocusMinutes: 60,
            maximumCommitments: 3,
            candidates: [
                PlanningTaskCandidate(
                    id: "routine",
                    title: "Routine work",
                    estimateMinutes: 45,
                    dueDate: nil,
                    reminderPriority: .medium,
                    carryoverDays: 0,
                    deferralCount: 0,
                    recentAlignedMinutes: 0,
                    isBlocked: false
                ),
                PlanningTaskCandidate(
                    id: "ai-priority",
                    title: "Client commitment",
                    estimateMinutes: 45,
                    dueDate: nil,
                    reminderPriority: .none,
                    carryoverDays: 0,
                    deferralCount: 0,
                    recentAlignedMinutes: 0,
                    isBlocked: false,
                    aiPriorityAdjustment: 180,
                    aiReason: "A recent commitment needs a response"
                )
            ]
        )
    )

    #expect(proposal.items.map(\.taskID) == ["ai-priority"])
    #expect(proposal.items[0].reason == "A recent commitment needs a response")
}

@Test
func nightlyScheduleTargetsTomorrowOnlyAfterTheConfiguredEveningTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let schedule = NightlyPlanningSchedule(hour: 22, minute: 30, calendar: calendar)
    let before = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 22, minute: 29))!
    let due = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 22, minute: 30))!

    #expect(schedule.targetDay(for: before) == nil)
    #expect(schedule.targetDay(for: due) == calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
}

@Test
func wakePolicyRequiresAHighConsequencePlanAndRespectsTheDailyInterventionBudget() {
    let policy = WakeUpPolicy(
        windowStartHour: 7,
        windowEndHour: 9,
        maximumDailyInterventions: 1,
        minimumMainObjectiveScore: 700
    )
    let urgentPlan = WakePlanEvidence(mainObjectiveScore: 800, plannedFocusMinutes: 120, completedInterventionsToday: 0)
    let exhaustedPlan = WakePlanEvidence(mainObjectiveScore: 800, plannedFocusMinutes: 120, completedInterventionsToday: 1)
    let ordinaryPlan = WakePlanEvidence(mainObjectiveScore: 400, plannedFocusMinutes: 120, completedInterventionsToday: 0)

    #expect(policy.decision(for: urgentPlan) == .eligible(reason: "High-consequence daily commitment"))
    #expect(policy.decision(for: exhaustedPlan) == .ineligible(reason: "Daily intervention budget reached"))
    #expect(policy.decision(for: ordinaryPlan) == .ineligible(reason: "No high-consequence commitment"))
}
