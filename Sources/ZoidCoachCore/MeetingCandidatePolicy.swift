import CryptoKit
import Foundation

public struct ExistingMeetingEvent: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let participants: [String]

    public init(id: String, title: String, start: Date, end: Date, participants: [String] = []) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.participants = participants
    }
}

public enum MeetingCandidateRoute: Equatable, Sendable {
    case readyForConfirmation
    case needsClarification
    case lowConfidence
    case duplicate(existingEventID: String)
    case conflict(existingEventID: String)
}

public struct MeetingCandidatePolicy: Sendable {
    public let readyThreshold: Double
    public let editableThreshold: Double
    public let duplicateTolerance: TimeInterval

    public init(readyThreshold: Double = 0.85, editableThreshold: Double = 0.60, duplicateTolerance: TimeInterval = 15 * 60) {
        self.readyThreshold = readyThreshold
        self.editableThreshold = editableThreshold
        self.duplicateTolerance = duplicateTolerance
    }

    public func route(_ candidate: MeetingCandidate, existingEvents: [ExistingMeetingEvent]) -> MeetingCandidateRoute {
        if let duplicate = existingEvents.first(where: { isDuplicate(candidate, event: $0) }) {
            return .duplicate(existingEventID: duplicate.id)
        }
        let candidateEnd = candidate.start.addingTimeInterval(TimeInterval(candidate.durationMinutes * 60))
        if let conflict = existingEvents.first(where: { $0.start < candidateEnd && $0.end > candidate.start }) {
            return .conflict(existingEventID: conflict.id)
        }
        if candidate.requiresClarification { return .needsClarification }
        if candidate.confidenceScore >= readyThreshold { return .readyForConfirmation }
        if candidate.confidenceScore >= editableThreshold { return .needsClarification }
        return .lowConfidence
    }

    public func fingerprint(_ candidate: MeetingCandidate) -> String {
        let normalizedParticipants = candidate.participants.map(normalize).sorted().joined(separator: ",")
        let roundedStart = Int(candidate.start.timeIntervalSince1970 / duplicateTolerance)
        let normalized = [
            normalize(candidate.title),
            normalizedParticipants,
            String(roundedStart),
            String(candidate.durationMinutes)
        ].joined(separator: "|")
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func isDuplicate(_ candidate: MeetingCandidate, event: ExistingMeetingEvent) -> Bool {
        guard abs(event.start.timeIntervalSince(candidate.start)) <= duplicateTolerance else { return false }
        let titleMatch = similarity(candidate.title, event.title) >= 0.5
        let candidateParticipants = Set(candidate.participants.map(normalize))
        let eventParticipants = Set(event.participants.map(normalize))
        let participantMatch = !candidateParticipants.isEmpty && !eventParticipants.isEmpty && !candidateParticipants.isDisjoint(with: eventParticipants)
        return titleMatch || participantMatch
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(normalize(lhs).split(separator: " ").map(String.init))
        let right = Set(normalize(rhs).split(separator: " ").map(String.init))
        guard !left.isEmpty || !right.isEmpty else { return 1 }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
