import SwiftUI

struct LocalSystemDiagnosticsView: View {
    private let service: LocalSystemDiagnosticsService
    @State private var snapshot: LocalSystemDiagnosticsSnapshot?
    @State private var isRefreshing = false

    init(service: LocalSystemDiagnosticsService = LocalSystemDiagnosticsService()) {
        self.service = service
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOCAL SYSTEM")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    Text("Storage and AI diagnostics")
                        .font(Sumi.display(22))
                        .foregroundStyle(Sumi.ink)
                }
                Spacer()
                if let snapshot {
                    Text("INSPECTED \(snapshot.inspectedAt.formatted(date: .omitted, time: .shortened).uppercased())")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.muted)
                }
                Button(isRefreshing ? "CHECKING" : "REFRESH") { refresh() }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .disabled(isRefreshing)
                    .accessibilityIdentifier("source-health.local-system.refresh")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Sumi.softPaper)

            if let snapshot {
                databaseRow(snapshot.database)
                aiRow(snapshot.ai)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Inspecting read-only local diagnostics...")
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.muted)
                }
                .padding(.horizontal, 28)
                .frame(minHeight: 72)
                .accessibilityIdentifier("source-health.local-system.loading")
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        .task { refresh() }
    }

    private func databaseRow(_ diagnostic: LocalDatabaseDiagnostic) -> some View {
        let availability = LocalDatabaseAvailabilityPresentation(diagnostic: diagnostic)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                diagnosticTitle(eyebrow: "FOUNDATION", title: "Local database")
                VStack(alignment: .leading, spacing: 5) {
                    Text(diagnostic.detail)
                        .font(Sumi.body(13))
                        .foregroundStyle(Sumi.ink)
                    Text(databaseFacts(diagnostic))
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                        .textSelection(.enabled)
                }
                Spacer()
                diagnosticBadge(databaseStateLabel(diagnostic.state), attention: diagnostic.state != .healthy)
            }
            databaseAvailabilityCard(availability)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("source-health.local-database")
    }

    private func databaseAvailabilityCard(_ availability: LocalDatabaseAvailabilityPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(availability.statusLabel)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(availability.availability == .available ? Sumi.okay : Sumi.seal)
                Text(availability.title)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(availability.detail)
                .font(Sumi.body(11))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !availability.unavailableActions.isEmpty {
                Text("TEMPORARILY UNAVAILABLE")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.seal)
                ForEach(availability.unavailableActions, id: \.self) { action in
                    Text("• \(action)")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let recoveryGuidance = availability.recoveryGuidance {
                Text(recoveryGuidance)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if availability.showsRecoveryAction, let label = availability.recoveryActionLabel {
                Button(label) { refresh() }
                    .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
                    .disabled(isRefreshing)
                    .accessibilityIdentifier("source-health.local-database.retry")
                    .accessibilityHint("Runs the same read-only storage check again. It does not repair, migrate, or delete the database.")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(availability.availability == .available ? Sumi.softPaper : Sumi.paper)
        .overlay(Rectangle().stroke(availability.availability == .available ? Sumi.paleRule : Sumi.seal, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("source-health.local-database.availability")
    }

    private func aiRow(_ diagnostic: LocalAIDiagnostic) -> some View {
        HStack(alignment: .top, spacing: 18) {
            diagnosticTitle(eyebrow: "REASONING", title: "AI mode")
            VStack(alignment: .leading, spacing: 7) {
                Text(diagnostic.processingLabel)
                    .font(Sumi.body(13))
                    .foregroundStyle(Sumi.ink)
                if diagnostic.recentFailures.isEmpty {
                    Text("No recent provider failures are recorded.")
                        .font(Sumi.body(11))
                        .foregroundStyle(Sumi.muted)
                } else {
                    Text("RECENT PROVIDER FAILURES")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                        .foregroundStyle(Sumi.seal)
                    ForEach(diagnostic.recentFailures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(failure.provider) · \(failure.state) · \(failure.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(Sumi.body(11))
                                .foregroundStyle(Sumi.ink)
                            Text(failure.diagnostic)
                                .font(Sumi.body(11))
                                .foregroundStyle(Sumi.muted)
                        }
                    }
                    Text("Only provider, state, time, and the stored redacted diagnostic are shown.")
                        .font(Sumi.body(10))
                        .foregroundStyle(Sumi.muted)
                }
            }
            Spacer()
            diagnosticBadge(diagnostic.modeLabel.uppercased(), attention: diagnostic.provider == nil)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.paleRule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("source-health.ai-mode")
    }

    private func diagnosticTitle(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(Sumi.label(8))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.seal)
            Text(title)
                .font(Sumi.display(18))
                .foregroundStyle(Sumi.ink)
        }
        .frame(width: 185, alignment: .leading)
    }

    private func diagnosticBadge(_ label: String, attention: Bool) -> some View {
        Text(label)
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .foregroundStyle(attention ? Sumi.paper : Sumi.ink)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(attention ? Sumi.seal : Sumi.softPaper)
            .overlay { Rectangle().stroke(attention ? Sumi.seal : Sumi.rule, lineWidth: 1) }
    }

    private func databaseStateLabel(_ state: LocalDatabaseDiagnosticState) -> String {
        switch state {
        case .healthy: "HEALTHY"
        case .attention: "ATTENTION"
        case .unavailable: "NOT READY"
        }
    }

    private func databaseFacts(_ diagnostic: LocalDatabaseDiagnostic) -> String {
        let size = ByteCountFormatter.string(fromByteCount: diagnostic.sizeBytes, countStyle: .file)
        let schema = diagnostic.schemaVersion.map(String.init) ?? "unavailable"
        let migration = diagnostic.lastMigrationAt?.formatted(date: .abbreviated, time: .shortened) ?? "unavailable"
        return "\(diagnostic.fileName) · \(size) · schema \(schema) of \(diagnostic.expectedSchemaVersion) · last migration \(migration)"
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let service = service
        Task {
            let refreshed = await Task.detached { service.inspect() }.value
            snapshot = refreshed
            isRefreshing = false
        }
    }
}
