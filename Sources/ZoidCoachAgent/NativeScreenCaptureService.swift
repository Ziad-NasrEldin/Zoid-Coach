import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import ZoidCoachInfrastructure

actor NativeScreenCaptureService {
    struct Configuration: Sendable {
        let daysDirectory: URL
        let configurationStore: NativeCaptureConfigurationStore
        let metadataCadence: Duration
        let idleSkipSeconds: TimeInterval

        init(
            daysDirectory: URL,
            configurationStore: NativeCaptureConfigurationStore,
            metadataCadence: Duration = .seconds(NativeCapturePolicy.metadataCadenceSeconds),
            idleSkipSeconds: TimeInterval = NativeCapturePolicy.idleSkipSeconds
        ) {
            self.daysDirectory = daysDirectory
            self.configurationStore = configurationStore
            self.metadataCadence = metadataCadence
            self.idleSkipSeconds = idleSkipSeconds
        }
    }

    private let configuration: Configuration
    private let healthStore: AgentCaptureHealthStore

    init(configuration: Configuration, healthStore: AgentCaptureHealthStore) {
        self.configuration = configuration
        self.healthStore = healthStore
    }

    func run() async {
        updateHealth(isRunning: true, lastCaptureAt: nil, detail: "Native capture is running")
        while !Task.isCancelled {
            let startedAt = ContinuousClock.now
            do {
                let persisted = try configuration.configurationStore.load()
                if persisted.mode == .legacy {
                    updateHealth(
                        isEnabled: false,
                        isRunning: false,
                        displayIDs: persisted.configuredDisplayIDs,
                        lastCaptureAt: healthStore.snapshot.lastCaptureAt,
                        detail: "Legacy Screenwatch capture is active"
                    )
                } else {
                    try await captureObservation(at: Date(), displayIDs: Set(persisted.configuredDisplayIDs))
                }
            } catch {
                updateHealth(
                    isEnabled: true,
                    isRunning: false,
                    displayIDs: (try? configuration.configurationStore.load().configuredDisplayIDs) ?? [],
                    lastCaptureAt: healthStore.snapshot.lastCaptureAt,
                    detail: String(error.localizedDescription.prefix(240))
                )
            }
            let elapsed = ContinuousClock.now - startedAt
            if elapsed < configuration.metadataCadence {
                try? await Task.sleep(for: configuration.metadataCadence - elapsed)
            }
        }
        updateHealth(isEnabled: healthStore.snapshot.isEnabled, isRunning: false, displayIDs: healthStore.snapshot.configuredDisplayIDs, lastCaptureAt: healthStore.snapshot.lastCaptureAt, detail: "Native capture stopped")
    }

    private func captureObservation(at now: Date, displayIDs: Set<UInt32>) async throws {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        let shouldCaptureImage = NativeCapturePolicy.shouldCaptureImage(idleSeconds: idleSeconds, idleSkipSeconds: configuration.idleSkipSeconds)
        let dayDirectory = try createDayDirectory(for: now)
        let timestamp = Self.timeFormatter.string(from: now)
        let activeApplication = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        }
        var hasImage = false
        if shouldCaptureImage {
            let image = try await captureConfiguredDisplays(displayIDs: displayIDs)
            let destination = dayDirectory.appendingPathComponent("\(timestamp).jpg")
            try Self.writeJPEG(image, to: destination)
            hasImage = true
        }
        try appendMetadata(
            to: dayDirectory.appendingPathComponent("log.jsonl"),
            timestamp: timestamp,
            epoch: Int(now.timeIntervalSince1970),
            application: activeApplication,
            hasImage: hasImage
        )
        updateHealth(
            isEnabled: true,
            isRunning: true,
            displayIDs: displayIDs.sorted(),
            lastCaptureAt: now,
            detail: shouldCaptureImage
                ? "Captured metadata and configured displays"
                : "Captured metadata; screenshot skipped after 90 seconds idle"
        )
    }

    private func captureConfiguredDisplays(displayIDs: Set<UInt32>) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw NativeCaptureError.screenRecordingDenied }
        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let selected = shareable.displays
            .filter { displayIDs.isEmpty || displayIDs.contains($0.displayID) }
            .sorted { lhs, rhs in
                if displayIDs.isEmpty {
                    return lhs.displayID == CGMainDisplayID() && rhs.displayID != CGMainDisplayID()
                }
                return lhs.displayID < rhs.displayID
            }
        guard !selected.isEmpty else { throw NativeCaptureError.noConfiguredDisplay }
        var images: [CGImage] = []
        for display in selected {
            let streamConfiguration = SCStreamConfiguration()
            streamConfiguration.width = display.width
            streamConfiguration.height = display.height
            streamConfiguration.showsCursor = true
            let filter = SCContentFilter(display: display, excludingWindows: [])
            images.append(try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: streamConfiguration
            ))
        }
        return try Self.compose(images)
    }

    private func createDayDirectory(for date: Date) throws -> URL {
        let directory = configuration.daysDirectory.appendingPathComponent(Self.dayFormatter.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func appendMetadata(
        to logURL: URL,
        timestamp: String,
        epoch: Int,
        application: String,
        hasImage: Bool
    ) throws {
        let record: [String: Any] = [
            "t": timestamp,
            "epoch": epoch,
            "app": application,
            "window": "",
            "url": "",
            "img": hasImage,
        ]
        var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        data.append(0x0A)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
                throw NativeCaptureError.cannotWriteMetadata
            }
        }
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private func updateHealth(isEnabled: Bool = true, isRunning: Bool, displayIDs: [UInt32] = [], lastCaptureAt: Date?, detail: String) {
        healthStore.update(AgentCaptureHealthSnapshot(
            isEnabled: isEnabled,
            isRunning: isRunning,
            screenRecording: CGPreflightScreenCaptureAccess() ? .granted : .denied,
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            automation: .notRequired,
            configuredDisplayIDs: displayIDs,
            lastCaptureAt: lastCaptureAt,
            detail: detail
        ))
    }

    private static func compose(_ images: [CGImage]) throws -> CGImage {
        guard let first = images.first else { throw NativeCaptureError.noConfiguredDisplay }
        if images.count == 1 { return first }
        let maximumHeight = 1_440.0
        let sizes = images.map { image -> (width: Int, height: Int) in
            let scale = min(1, maximumHeight / Double(image.height))
            return (max(1, Int(Double(image.width) * scale)), max(1, Int(Double(image.height) * scale)))
        }
        let width = sizes.reduce(0) { $0 + $1.width }
        let height = sizes.map(\.height).max() ?? first.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NativeCaptureError.cannotComposeDisplays }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var x = 0
        for (image, size) in zip(images, sizes) {
            context.draw(image, in: CGRect(x: x, y: height - size.height, width: size.width, height: size.height))
            x += size.width
        }
        guard let result = context.makeImage() else { throw NativeCaptureError.cannotComposeDisplays }
        return result
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NativeCaptureError.cannotWriteScreenshot
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NativeCaptureError.cannotWriteScreenshot }
    }

    private static let dayFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()

    private static let timeFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "HH-mm-ss"
        return value
    }()
}

private enum NativeCaptureError: LocalizedError {
    case screenRecordingDenied
    case noConfiguredDisplay
    case cannotComposeDisplays
    case cannotWriteScreenshot
    case cannotWriteMetadata

    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied: "Screen Recording permission is required for native capture."
        case .noConfiguredDisplay: "No configured display is currently available."
        case .cannotComposeDisplays: "Configured display screenshots could not be composed."
        case .cannotWriteScreenshot: "The native screenshot could not be written."
        case .cannotWriteMetadata: "The native Screenwatch metadata log could not be written."
        }
    }
}
