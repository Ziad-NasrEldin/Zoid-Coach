import Foundation

actor ScreenwatchReader {
    private let fileManager: FileManager
    private let baseDirectory: URL
    private var activePath: URL?
    private var offset: UInt64 = 0
    private var trailingData = Data()
    private var recordsSeen = 0
    private var imageRecordsSeen = 0
    private var lastRecord: ScreenwatchRecord?

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("screenwatch/days", isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func inspect(now: Date = Date()) -> SourceHealth {
        let path = logPath(for: now)

        guard fileManager.fileExists(atPath: path.path) else {
            resetIfNeeded(for: path)
            return SourceHealth(
                id: .screenwatch,
                title: "Screenwatch",
                eyebrow: "Behavior",
                state: .unavailable,
                detail: "Today’s telemetry stream is missing",
                evidence: path.path.replacingOccurrences(of: fileManager.homeDirectoryForCurrentUser.path, with: "~"),
                actionTitle: "Retry"
            )
        }

        do {
            resetIfNeeded(for: path)
            try ingestNewRecords(from: path)

            guard let lastRecord else {
                return SourceHealth(
                    id: .screenwatch,
                    title: "Screenwatch",
                    eyebrow: "Behavior",
                    state: .attention,
                    detail: "The telemetry file contains no valid records",
                    evidence: "JSONL source found but no schema-valid event was parsed",
                    actionTitle: "Inspect"
                )
            }

            let age = max(0, now.timeIntervalSince1970 - TimeInterval(lastRecord.epoch))
            let state: HealthState = age <= 90 ? .healthy : .attention
            let detail = age <= 90
                ? "Live stream updated " + age.formattedAge + " ago"
                : "Stream is stale by " + age.formattedAge
            let evidence = "\(recordsSeen.formatted()) records parsed · \(imageRecordsSeen.formatted()) image references"

            return SourceHealth(
                id: .screenwatch,
                title: "Screenwatch",
                eyebrow: "Behavior",
                state: state,
                detail: detail,
                evidence: evidence,
                actionTitle: "Refresh"
            )
        } catch {
            return SourceHealth(
                id: .screenwatch,
                title: "Screenwatch",
                eyebrow: "Behavior",
                state: .attention,
                detail: "Telemetry could not be read safely",
                evidence: "Read failed without exposing captured content",
                actionTitle: "Retry"
            )
        }
    }

    private func logPath(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return baseDirectory
            .appendingPathComponent(formatter.string(from: date), isDirectory: true)
            .appendingPathComponent("log.jsonl", isDirectory: false)
    }

    private func resetIfNeeded(for path: URL) {
        guard activePath != path else { return }
        activePath = path
        offset = 0
        trailingData = Data()
        recordsSeen = 0
        imageRecordsSeen = 0
        lastRecord = nil
    }

    private func ingestNewRecords(from path: URL) throws {
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)
        guard let newData = try handle.readToEnd(), !newData.isEmpty else { return }
        offset += UInt64(newData.count)

        var combined = trailingData
        combined.append(newData)
        let endsWithNewline = combined.last == 0x0A
        var lines = combined.split(separator: 0x0A, omittingEmptySubsequences: true)

        if !endsWithNewline, let partial = lines.popLast() {
            trailingData = Data(partial)
        } else {
            trailingData = Data()
        }

        let decoder = JSONDecoder()
        for line in lines {
            guard let record = try? decoder.decode(ScreenwatchRecord.self, from: Data(line)) else { continue }
            recordsSeen += 1
            if record.img { imageRecordsSeen += 1 }
            lastRecord = record
        }
    }
}

private struct ScreenwatchRecord: Decodable, Sendable {
    let t: String
    let epoch: Int
    let app: String
    let window: String
    let url: String
    let img: Bool
}

private extension TimeInterval {
    var formattedAge: String {
        if self < 60 {
            return "\(Int(self.rounded()))s"
        }
        if self < 3_600 {
            return "\(Int((self / 60).rounded()))m"
        }
        return "\(Int((self / 3_600).rounded()))h"
    }
}
