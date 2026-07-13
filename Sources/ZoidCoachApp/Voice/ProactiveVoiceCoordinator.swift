import AVFoundation
import CoreAudio
import Foundation
import UserNotifications
import ZoidCoachCore

@MainActor
final class ProactiveVoiceCoordinator {
    private let speaker = AVSpeechSynthesizer()
    private let notificationIdentity: RuntimeNotificationIdentity
    private var monitorTask: Task<Void, Never>?
    private var priorActiveJobIDs = Set<String>()
    private var announcedCommitments = Set<String>()
    private var announcedOverdueTasks = Set<String>()
    private var previousDistractionMinutes = 0
    private var lastDriftIntervention: Date?

    init(runtimeEnvironment: RuntimeEnvironment = .production()) {
        notificationIdentity = runtimeEnvironment.identity.notification
    }

    func start(context: @escaping @Sendable () async throws -> ChiefOfStaffContextPacket) {
        stop()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let packet = try await context()
                    await self?.evaluate(packet)
                } catch {
                    // The background agent may be restarting. The next cycle retries.
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func evaluate(_ context: ChiefOfStaffContextPacket) async {
        let now = Date()
        let activeJobIDs = Set(context.activeCodexJobs.map(\.id))
        let distraction = context.snapshot.behavior.meaningfulGamingMinutes + context.snapshot.behavior.distractingMinutes
        guard !isQuietTime(now, schedule: context.schedule) else {
            priorActiveJobIDs = activeJobIDs
            previousDistractionMinutes = distraction
            return
        }
        if let commitment = context.upcomingCommitments.first(where: {
            $0.start > now && $0.start.timeIntervalSince(now) <= 15 * 60 && !announcedCommitments.contains($0.id)
        }) {
            announcedCommitments.insert(commitment.id)
            await deliver("\(commitment.title) starts in \(max(1, Int(commitment.start.timeIntervalSince(now) / 60))) minutes.")
        }
        if let overdue = context.snapshot.taskRows.first(where: {
            $0.urgency == .high && ($0.dueDate ?? .distantFuture) < now && !announcedOverdueTasks.contains($0.taskID)
        }) {
            announcedOverdueTasks.insert(overdue.taskID)
            await deliver("\(overdue.title) is overdue. Your next responsible action is ready in Zoid 666.")
        }
        if !priorActiveJobIDs.isEmpty, !priorActiveJobIDs.subtracting(activeJobIDs).isEmpty {
            await deliver("A Codex job finished or stopped. Open Zoid Voice for the verified result.")
        }
        priorActiveJobIDs = activeJobIDs
        if context.snapshot.activeTask != nil,
           distraction - previousDistractionMinutes >= 5,
           lastDriftIntervention.map({ now.timeIntervalSince($0) >= 60 * 60 }) ?? true {
            lastDriftIntervention = now
            await deliver("You have drifted from the active task for about five minutes. Say Hey Zoid to recover or intentionally override the plan.")
        }
        previousDistractionMinutes = distraction
    }

    private func deliver(_ text: String) async {
        if Self.headphonesAreActive() {
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.48
            speaker.speak(utterance)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Zoid 666"
        content.body = text
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: notificationIdentity.proactiveRequestPrefix + UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func isQuietTime(_ date: Date, schedule: SchedulePolicy) -> Bool {
        guard let timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let start = schedule.quietHours.start.minuteOfDay
        let end = schedule.quietHours.end.minuteOfDay
        return schedule.quietHours.crossesMidnight
            ? minute >= start || minute < end
            : minute >= start && minute < end
    }

    private static func headphonesAreActive() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            return false
        }
        address.mSelector = kAudioObjectPropertyName
        var unmanagedName: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &unmanagedName) == noErr,
              let name = unmanagedName?.takeUnretainedValue() else { return false }
        let lowered = (name as String).lowercased()
        return ["airpods", "headphone", "headset", "earbuds", "buds"].contains(where: lowered.contains)
    }
}
