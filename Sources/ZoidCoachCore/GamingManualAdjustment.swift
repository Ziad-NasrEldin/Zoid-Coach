import Foundation

public struct GamingManualAdjustmentRequest: Equatable, Codable, Sendable {
    public let requestID: String
    public let day: Date
    public let timeZoneIdentifier: String
    public let minutes: Int
    public let note: String?

    public init(
        requestID: String,
        day: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        minutes: Int,
        note: String?
    ) {
        self.requestID = requestID
        self.day = day
        self.timeZoneIdentifier = timeZoneIdentifier
        self.minutes = minutes
        self.note = note
    }
}

public struct GamingManualAdjustment: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let localDay: String
    public let minutes: Int
    public let note: String?
    public let recordedAt: Date

    public init(
        id: String,
        localDay: String,
        minutes: Int,
        note: String?,
        recordedAt: Date
    ) {
        self.id = id
        self.localDay = localDay
        self.minutes = minutes
        self.note = note
        self.recordedAt = recordedAt
    }
}

public struct GamingManualAdjustmentReceipt: Equatable, Codable, Sendable {
    public let adjustment: GamingManualAdjustment
    public let replayed: Bool

    public init(adjustment: GamingManualAdjustment, replayed: Bool) {
        self.adjustment = adjustment
        self.replayed = replayed
    }
}
