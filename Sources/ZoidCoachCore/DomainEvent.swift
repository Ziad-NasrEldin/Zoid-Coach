import Foundation

public struct DomainEvent: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let type: String
    public let entityID: String?
    public let localDay: String
    public let timezoneIdentifier: String
    public let occurredAt: Date
    public let schemaVersion: Int
    public let evidenceIDs: [String]
    public let payload: [String: String]

    public init(id: String, type: String, entityID: String?, localDay: String, timezoneIdentifier: String, occurredAt: Date, schemaVersion: Int = 1, evidenceIDs: [String] = [], payload: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.entityID = entityID
        self.localDay = localDay
        self.timezoneIdentifier = timezoneIdentifier
        self.occurredAt = occurredAt
        self.schemaVersion = schemaVersion
        self.evidenceIDs = evidenceIDs
        self.payload = payload
    }
}
