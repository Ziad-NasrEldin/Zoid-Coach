import Foundation

public struct ScreenwatchObservation: Equatable, Sendable {
    public let timeLabel: String
    public let epoch: Int
    public let appName: String
    public let windowTitle: String
    public let url: String
    public let hasScreenshot: Bool

    public init(
        timeLabel: String,
        epoch: Int,
        appName: String,
        windowTitle: String,
        url: String,
        hasScreenshot: Bool
    ) {
        self.timeLabel = timeLabel
        self.epoch = epoch
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.hasScreenshot = hasScreenshot
    }
}

public struct ScreenwatchLogDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> ScreenwatchObservation {
        let record = try JSONDecoder().decode(Record.self, from: data)
        return ScreenwatchObservation(
            timeLabel: record.t,
            epoch: record.epoch,
            appName: record.app,
            windowTitle: record.window,
            url: record.url,
            hasScreenshot: record.img
        )
    }

    private struct Record: Decodable {
        let t: String
        let epoch: Int
        let app: String
        let window: String
        let url: String
        let img: Bool
    }
}
