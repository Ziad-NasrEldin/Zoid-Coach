import Foundation
import ZoidCoachInfrastructure

actor ScreenwatchReader {
    private let source: Result<ScreenwatchDirectoryLease, Error>
    private var activeStreamID: String?
    private var fileIdentity: String?
    private var offset: UInt64 = 0
    private var trailingData = Data()
    private var recordsSeen = 0
    private var imageRecordsSeen = 0
    private var schemaMismatchRecords = 0
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
        let exists: Bool
        do {
            exists = try lease.fileExists(components)
        } catch {
            return SourceHealth(
                id: .screenwatch,
                title: "Screenwatch",
                eyebrow: "Behavior",
                state: .attention,
                detail: "Telemetry could not be read safely",
                evidence: "The canonical source rejected an unsafe or inaccessible child path",
                actionTitle: "Repair"
            )
        }
        guard exists else {
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
                if schemaMismatchRecords > 0 {
                    return SourceHealth(
                        id: .screenwatch,
                        title: "Screenwatch",
                        eyebrow: "Behavior",
                        state: .attention,
                        detail: "Screenwatch source format is unsupported",
                        evidence: "\(schemaMismatchRecords.formatted()) complete record\(schemaMismatchRecords == 1 ? "" : "s") did not match the expected schema · captured titles and URLs were not displayed",
                        actionTitle: "Repair"
                    )
                }
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
            let hasSchemaMismatch = schemaMismatchRecords > 0
            let state: HealthState = hasSchemaMismatch || age > 90 ? .attention : .healthy
            let detail = hasSchemaMismatch
                ? "Some Screenwatch records use an unsupported format"
                : (age <= 90
                    ? "Live stream updated " + age.formattedAge + " ago"
                    : "Stream is stale by " + age.formattedAge)
            let mismatchEvidence = hasSchemaMismatch
                ? " · \(schemaMismatchRecords.formatted()) unsupported schema record\(schemaMismatchRecords == 1 ? "" : "s")"
                : ""
            let evidence = "\(recordsSeen.formatted()) record\(recordsSeen == 1 ? "" : "s") parsed · \(imageRecordsSeen.formatted()) image reference\(imageRecordsSeen == 1 ? "" : "s")\(mismatchEvidence)"
            return SourceHealth(
                id: .screenwatch,
                title: "Screenwatch",
                eyebrow: "Behavior",
                state: state,
                detail: detail,
                evidence: evidence,
                actionTitle: hasSchemaMismatch ? "Repair" : "Refresh"
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
        fileIdentity = nil
        trailingData = Data()
        recordsSeen = 0
        imageRecordsSeen = 0
        schemaMismatchRecords = 0
        lastRecord = nil
    }

    private func ingestNewRecords(
        from lease: ScreenwatchDirectoryLease,
        components: [String],
        streamID: String
    ) throws {
        let previousOffset = offset
        let read = try lease.read(
            at: components,
            offset: offset,
            expectedIdentity: fileIdentity,
            maximumBytes: 16 * 1_024 * 1_024
        )
        let identity = "\(streamID):\(read.identity)"
        if activeStreamID != identity || read.offset < previousOffset {
            resetIfNeeded(for: identity)
        }
        fileIdentity = read.identity
        offset = read.offset + UInt64(read.data.count)
        let newData = read.data
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
            let data = Data(line)
            do {
                let record = try decoder.decode(ScreenwatchRecord.self, from: data)
                recordsSeen += 1
                if record.img { imageRecordsSeen += 1 }
                lastRecord = record
            } catch {
                if (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
                    schemaMismatchRecords += 1
                }
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
