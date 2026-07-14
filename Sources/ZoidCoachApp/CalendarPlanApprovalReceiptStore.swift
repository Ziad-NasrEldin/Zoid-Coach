import Foundation

final class CalendarPlanApprovalReceiptStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults, key: String = "calendar-plan-approval-receipt-v1") {
        self.defaults = defaults
        self.key = key
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> CalendarPlanApprovalReceipt? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(CalendarPlanApprovalReceipt.self, from: data)
    }

    func save(_ receipt: CalendarPlanApprovalReceipt) throws {
        defaults.set(try encoder.encode(receipt), forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
