import Foundation
import ZoidCoachInfrastructure

actor ScreenwatchReader {
    private let source: Result<ScreenwatchDirectoryLease, Error>
    private var activeStreamID: String?
    private var offset: UInt64 = 0
    private var trailingData = Data()
    private var recordsSeen = 0
    private var imageRecordsSeen = 0
    private var lastRecord: ScreenwatchRecord?

    init(lease: ScreenwatchDirectoryLease) {
        source = .success(lease)
    }

    init(canonicalSource: Result<ScreenwatchDirectoryLease, Error>) {
        source = canonicalSource
    }

    init(
        fileManager _: FileManager = .default,
        baseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("screenwatch/days", isDirectory: true)
    ) {
        source = Result {
            try ScreenwatchDirectoryLease(rootURL: baseDirectory, source: .defaultLocation)
        }
    }

    func inspect(now: Date = Date()) -> SourceHealth {
        let lease: ScreenwatchDirectoryLease
        do {
            lease = try source.get()
        } catch ScreenwatchSourceResolutionError.missingDirectory {
            return SourceHealth(
                id: .screenwatch,
                title: "Screenwatch",
                eyebrow: "Behavior",
                state: .unavailable,
                detail: "Today’s telemetry stream is missing",
                evidence: "The canonical local source is not available yet",
                actionTitle: "Retry"
            )
        } catch {
            return SourceHealth(
                id: .screenwatch,
                title: "Screenwatch",
                eyebrow: "Behavior",
                state: .attention,
                detail: "The canonical telemetry source needs repair",
                evidence: error.localizedDescription,
                actionTitle: "Repair"
            )
        }
        let day = dayKey(for: now)
        let components = [day, "log.jsonl"]
        let streamID = "\(lease.sourceFingerprint):\(day)"
        guard lease.fileExists(components) else {
            resetIfNeeded(for: streamID)
            return SourceHealth(
                id: .screenwatch,
                title: "Screenwatch",
                eyebrow: "Behavior",
                state: .unavailable,
                detail: "Today’s telemetry stream is missing",
                evidence: "The canonical local source has no log for today",
                actionTitle: "Retry"
            )
        }

        do {
            try ingestNewRecords(from: lease, components: components, streamID: streamID)
            guard let lastRecord else {
                return SourceHealth(
                    id: .screenwatch,
                    title: "Screenwatch",
                    eyebrow: "Behavior",
                    state: .attention,
                    detail: "Telemetry exists but contains no readable records",
                    evidence: "No captured titles or URLs were displayed",
                    actionTitle: "Refresh"
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

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func resetIfNeeded(for streamID: String) {
        guard activeStreamID != streamID else { return }
        activeStreamID = streamID
        offset = 0
        trailingData = Data()
        recordsSeen = 0
        imageRecordsSeen = 0
        lastRecord = nil
    }

    private func ingestNewRecords(
        from lease: ScreenwatchDirectoryLease,
        components: [String],
        streamID: String
    ) throws {
        try lease.withOpenedFile(components) { opened in
            let identity = "\(streamID):\(opened.identity)"
            resetIfNeeded(for: identity)
            if opened.size < offset {
                offset = 0
                trailingData = Data()
                recordsSeen = 0
                imageRecordsSeen = 0
                lastRecord = nil
            }
            try opened.handle.seek(toOffset: offset)
            let newData = try opened.handle.readToEnd() ?? Data()
            offset += UInt64(newData.count)
            guard !newData.isEmpty else { return }

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
        if self < 60 { return "\(Int(self.rounded()))s" }
        if self < 3_600 { return "\(Int((self / 60).rounded()))m" }
        return "\(Int((self / 3_600).rounded()))h"
    }
}
