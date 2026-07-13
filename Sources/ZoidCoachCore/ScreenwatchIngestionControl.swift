public struct ScreenwatchIngestionControl: Equatable, Sendable {
    public let permitsNewRecords: Bool

    public init(policy: CapturePolicy) {
        permitsNewRecords = policy.ingestionEnabled
    }

    public func run<Value>(
        disabledValue: @autoclosure () -> Value,
        operation: () throws -> Value
    ) rethrows -> (performed: Bool, value: Value) {
        guard permitsNewRecords else { return (false, disabledValue()) }
        return (true, try operation())
    }
}
