import AppKit
import SwiftUI

@MainActor
final class ScreenwatchConnectionController: ObservableObject {
    @Published private(set) var status: ScreenwatchSetupStatus?
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    private let service: any ScreenwatchSetupServicing
    private let now: () -> Date

    init(
        service: (any ScreenwatchSetupServicing)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service ?? ScreenwatchSetupService()
        self.now = now
    }

    func inspect() async {
        await perform { service, now in await service.inspect(now: now) }
    }

    func recheck() async {
        await perform { service, now in await service.recheck(now: now) }
    }

    func selectDirectory(_ url: URL) async {
        await perform { service, now in
            try await service.selectAlternateDaysDirectory(url, now: now)
        }
    }

    func useExpectedDirectory() async {
        await perform { service, now in await service.useDefaultLocation(now: now) }
    }

    func applicationDidBecomeActive() async {
        guard status != nil else { return }
        await recheck()
    }

    private func perform(
        _ operation: (any ScreenwatchSetupServicing, Date) async throws -> ScreenwatchSetupStatus
    ) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            status = try await operation(service, now())
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ScreenwatchConnectionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller: ScreenwatchConnectionController

    init(controller: ScreenwatchConnectionController = ScreenwatchConnectionController()) {
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let status = controller.status {
                statusContent(status)
            } else if controller.isWorking {
                ProgressView("Checking the local Screenwatch source")
                    .accessibilityIdentifier("settings.screenwatch.loading")
            }

            if let error = controller.errorMessage {
                Text(error)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.screenwatch.error")
            }

            HStack(spacing: 8) {
                Button("RECHECK") { Task { await controller.recheck() } }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .standard))
                    .disabled(controller.isWorking)
                    .accessibilityIdentifier("settings.screenwatch.recheck")
                Button(repairPresentation.primaryTitle) { chooseFolder() }
                    .buttonStyle(SumiActionButtonStyle(role: .primary, size: .standard))
                    .disabled(controller.isWorking)
                    .accessibilityIdentifier("settings.screenwatch.choose-folder")
                    .accessibilityHint(repairPresentation.accessibilityHint)
                if controller.status?.source == .alternateFolder {
                    Button("USE EXPECTED FOLDER") {
                        Task { await controller.useExpectedDirectory() }
                    }
                    .buttonStyle(SumiActionButtonStyle(role: .text, size: .standard))
                    .disabled(controller.isWorking)
                    .accessibilityIdentifier("settings.screenwatch.use-default")
                }
            }
        }
        .task {
            if controller.status == nil { await controller.inspect() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await controller.applicationDidBecomeActive() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.screenwatch.connection")
    }

    private func statusContent(_ status: ScreenwatchSetupStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(status.source == .alternateFolder ? "CHOSEN FOLDER" : "EXPECTED FOLDER")
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                Spacer()
                Text(healthLabel(status.health))
                    .font(Sumi.label(9))
                    .sumiLabelTracking()
                    .foregroundStyle(status.health == .healthy ? Sumi.okay : Sumi.sealDeep)
            }
            Text(status.summary)
                .font(Sumi.body(13))
                .foregroundStyle(Sumi.ink)
            Text(status.evidence)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
            if let recordEvidence = ScreenwatchRecordEvidence(status: status) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SOURCE FOLDER")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                    Text(recordEvidence.sourcePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Sumi.ink)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("settings.screenwatch.source-path")
                    Text("LAST VALID RECORD")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                    Text(recordEvidence.lastValidRecordText ?? "No valid record available yet")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.ink)
                        .accessibilityIdentifier("settings.screenwatch.last-valid-record")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(recordEvidence.accessibilitySummary)
                .accessibilityIdentifier("settings.screenwatch.record-evidence")
            }
            Text(ScreenwatchRepairActionPresentation(status: status).explanation)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.screenwatch.status")
    }

    private var repairPresentation: ScreenwatchRepairActionPresentation {
        ScreenwatchRepairActionPresentation(status: controller.status)
    }

    private func healthLabel(_ health: ScreenwatchSetupHealth) -> String {
        switch health {
        case .healthy: "HEALTHY"
        case .stale: "STALE"
        case .missing: "WAITING FOR TODAY'S LOG"
        case .malformed: "INCOMPATIBLE FORMAT"
        case .bookmarkUnavailable: "FOLDER ACCESS EXPIRED"
        case .accessUnavailable: "FOLDER UNAVAILABLE"
        case .unsafePath: "UNSAFE FOLDER"
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Screenwatch Days Folder"
        panel.message = "Select the folder containing YYYY-MM-DD/log.jsonl directories. Zoid 666 validates the schema without showing captured content."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await controller.selectDirectory(url) }
    }
}
