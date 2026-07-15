import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Today coaching runtime state")
struct CoachingStatePresentationTests {
    private let now = Date(timeIntervalSince1970: 1_783_742_400)

    @Test("an active pause wins over baseline and coaching level")
    func pauseWins() {
        let resumesAt = now.addingTimeInterval(3_600)
        let timed = CoachingRuntimeState.resolve(
            automationPause: AutomationPause(isPaused: true, resumesAtUTC: resumesAt),
            baselineStatus: baseline(completeDays: 0),
            coachingLevel: .accountability,
            now: now
        )
        let indefinite = CoachingRuntimeState.resolve(
            automationPause: .pausedIndefinitely,
            baselineStatus: baseline(completeDays: 7),
            coachingLevel: .gentle,
            now: now
        )

        #expect(timed == CoachingRuntimeState(state: .paused, pauseEvidence: .until(resumesAt)))
        #expect(indefinite == CoachingRuntimeState(state: .paused, pauseEvidence: .indefinite))
    }

    @Test("incomplete baseline limits both configured active levels to observation")
    func baselineSuppressionWins() {
        for level in CoachingLevel.allCases {
            #expect(CoachingRuntimeState.resolve(
                automationPause: .running,
                baselineStatus: baseline(completeDays: 6),
                coachingLevel: level,
                now: now
            ).state == .observation)
        }
    }

    @Test("complete baseline exposes the persisted gentle or accountability level")
    func activeLevels() {
        #expect(resolve(level: .gentle).state == .gentle)
        #expect(resolve(level: .accountability).state == .accountability)
    }

    @Test("load failure is explicit and stale refreshes cannot overwrite newer state")
    func unavailableAndRefreshRace() {
        #expect(CoachingRuntimeState.unavailable.state == .unavailable)
        var gate = CoachingStateRefreshGate()
        let older = gate.begin()
        let newer = gate.begin()

        #expect(!gate.shouldInstall(older))
        #expect(gate.shouldInstall(newer))
    }

    @Test("presentations remain accessible, privacy safe, and noncontradictory")
    func accessibleCopy() {
        let states: [CoachingRuntimeState] = [
            .init(state: .gentle),
            .init(state: .accountability),
            .init(state: .observation),
            .init(state: .paused, pauseEvidence: .indefinite),
            .init(state: .paused, pauseEvidence: .until(now.addingTimeInterval(3_600))),
            .unavailable
        ]

        for runtimeState in states {
            let presentation = CoachingStatePresentation(runtimeState: runtimeState)
            #expect(!presentation.statusLabel.isEmpty)
            #expect(presentation.accessibilityLabel.contains(presentation.statusLabel))
            #expect(presentation.explanation.contains("activity observation"))
            #expect(!presentation.accessibilityLabel.contains(".."))
            #expect(!presentation.accessibilityLabel.localizedCaseInsensitiveContains("private-window-title"))
            #expect(!presentation.accessibilityLabel.localizedCaseInsensitiveContains("screenshot"))
            if runtimeState.state == .paused {
                #expect(presentation.recoveryHint != nil)
                #expect(!presentation.accessibilityLabel.contains("COACHING ACTIVE"))
            } else {
                #expect(presentation.recoveryHint == nil)
                #expect(presentation.pauseReason == nil)
            }
        }
    }

    private func resolve(level: CoachingLevel) -> CoachingRuntimeState {
        CoachingRuntimeState.resolve(
            automationPause: .running,
            baselineStatus: baseline(completeDays: 7),
            coachingLevel: level,
            now: now
        )
    }

    private func baseline(completeDays: Int) -> BaselineObservationStatus {
        BaselineObservationStatus(
            days: (0..<completeDays).map { index in
                BaselineObservationDay(
                    localDay: "2026-07-\(String(format: "%02d", index + 1))",
                    observedMinutes: 60,
                    workMinutes: 45,
                    gamingMinutes: 0,
                    distractingMinutes: 0,
                    unknownMinutes: 15,
                    eligibleDriftCount: 0,
                    coverage: .complete,
                    recordedAt: now
                )
            },
            report: BaselineObservationReport(
                averageObservedWorkMinutes: 45,
                gamingDayCount: 0,
                totalGamingMinutes: 0,
                eligibleDriftCount: 0,
                unknownSharePercent: 25
            )
        )
    }
}
