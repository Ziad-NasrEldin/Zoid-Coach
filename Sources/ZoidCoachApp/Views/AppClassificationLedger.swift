import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZoidCoachCore

struct AppClassificationLedger: View {
    @Binding var draft: SettingsPolicyDraft
    @State private var items: [AppInventoryItem] = []
    @State private var query = ""
    @State private var filter = AppInventoryFilter.all
    @State private var isLoading = true
    @State private var warning: String?
    @State private var notice: String?
    @State private var pendingAction: PendingAppRuleAction?
    @State private var showsDomainRules = false
    private let service: AppInventoryService
    private let rulesService: AppClassificationRulesDocumentService
    private let domainRuleReview = DomainRuleReviewState()

    init(
        draft: Binding<SettingsPolicyDraft>,
        service: AppInventoryService = AppInventoryService(),
        rulesService: AppClassificationRulesDocumentService = AppClassificationRulesDocumentService()
    ) {
        _draft = draft
        self.service = service
        self.rulesService = rulesService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 14) {
                    searchField
                    filterRail.frame(width: 360)
                }
                VStack(alignment: .leading, spacing: 14) {
                    searchField
                    filterRail
                }
            }

            HStack {
                Text("\(filteredItems.count) APP\(filteredItems.count == 1 ? "" : "S")")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
                Spacer()
                Text("COMMUNICATION COUNTS AS WORK BUT STAYS A DISTINCT RULE")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
            }

            ruleActions
            domainRuleReviewSection

            if let notice {
                Text(notice)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Sumi.softPaper)
                    .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
                    .accessibilityIdentifier("settings.app-rules.notice")
            }

            if let warning {
                Text(warning)
                    .font(Sumi.body(12))
                    .foregroundStyle(Sumi.seal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Sumi.sealWash)
                    .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            }

            if isLoading {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(Sumi.ink)
                    Text("Reading installed apps and local behavior history.")
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .background(Sumi.mist)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            } else if filteredItems.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(query.isEmpty ? "NO APPS IN THIS VIEW" : "NO MATCHING APPS")
                        .font(Sumi.label(9))
                        .sumiLabelTracking()
                    Text(query.isEmpty ? "Choose another classification filter." : "Try another app name or clear the search field.")
                        .font(Sumi.body(12))
                        .foregroundStyle(Sumi.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .background(Sumi.mist)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            AppClassificationRow(
                                item: item,
                                selection: Binding(
                                    get: { draft.settingsClassification(for: item.normalizedName) },
                                    set: { draft.setClassifications($0, for: [item.normalizedName]) }
                                )
                            )
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: 520)
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            }
        }
        .task { await loadInventory() }
        .confirmationDialog(
            pendingAction?.title ?? "Confirm classification rule change",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { clearPendingAction() } }
            )
        ) {
            if let pendingAction {
                Button(pendingAction.confirmationLabel, role: pendingAction.isDestructive ? .destructive : nil) {
                    apply(pendingAction)
                }
                Button("CANCEL", role: .cancel) { clearPendingAction() }
            }
        } message: {
            if let pendingAction { Text(pendingAction.message) }
        }
    }

    private var filteredItems: [AppInventoryItem] {
        let normalizedQuery = BehaviorPolicy.normalize(query)
        return items.filter { item in
            let matchesQuery = normalizedQuery.isEmpty || item.normalizedName.contains(normalizedQuery)
            let choice = draft.settingsClassification(for: item.normalizedName)
            return matchesQuery && filter.includes(choice)
        }
    }

    private var ruleActions: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { bulkButtons }
                VStack(alignment: .leading, spacing: 8) { bulkButtons }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { documentButtons }
                VStack(alignment: .leading, spacing: 8) { documentButtons }
            }
        }
    }

    private var domainRuleReviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showsDomainRules.toggle()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DOMAIN RULES")
                            .font(Sumi.label(9))
                            .sumiLabelTracking()
                            .foregroundStyle(Sumi.ink)
                        Text(domainRuleReview.summary)
                            .font(Sumi.body(11))
                            .foregroundStyle(Sumi.muted)
                    }
                    Spacer()
                    Text(showsDomainRules ? "HIDE" : "REVIEW")
                        .font(Sumi.label(8))
                        .sumiLabelTracking()
                    Image(systemName: showsDomainRules ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Review domain rules")
            .accessibilityValue(showsDomainRules ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the built-in URL and domain signals used by local contextual classification.")
            .accessibilityIdentifier("settings.domain-rules.toggle")

            if showsDomainRules {
                Text(domainRuleReview.privacyDetail)
                    .font(Sumi.body(11))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.domain-rules.privacy")

                LazyVStack(spacing: 0) {
                    ForEach(domainRuleReview.rows) { row in
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                domainRuleIdentity(row)
                                Text(row.outcome.uppercased())
                                    .font(Sumi.label(8))
                                    .sumiLabelTracking()
                                    .foregroundStyle(Sumi.ink)
                                    .frame(width: 100, alignment: .trailing)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                domainRuleIdentity(row)
                                Text(row.outcome.uppercased())
                                    .font(Sumi.label(8))
                                    .sumiLabelTracking()
                                    .foregroundStyle(Sumi.ink)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .background(Sumi.paper)
                        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.accessibilityLabel)
                        .accessibilityHint(row.explanation)
                        .accessibilityIdentifier(row.accessibilityIdentifier)
                    }
                }
                .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
            }
        }
        .padding(12)
        .background(Sumi.softPaper)
        .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.domain-rules")
    }

    private func domainRuleIdentity(_ row: DomainRuleReviewRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.pattern)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Sumi.ink)
                .textSelection(.enabled)
            Text(row.explanation)
                .font(Sumi.body(10))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var bulkButtons: some View {
        Text("SET \(filteredItems.count) VISIBLE")
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .foregroundStyle(Sumi.muted)
        ForEach(ApplicationRuleCategory.allCases, id: \.self) { category in
            Button(category.label.uppercased()) {
                pendingAction = .bulk(category, filteredItems.map(\.normalizedName))
            }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            .disabled(filteredItems.isEmpty)
            .accessibilityIdentifier("settings.app-rules.bulk.\(category.rawValue)")
        }
    }

    @ViewBuilder
    private var documentButtons: some View {
        Button("IMPORT RULES") { chooseImport() }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            .accessibilityIdentifier("settings.app-rules.import")
        Button("EXPORT RULES") { chooseExport() }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            .accessibilityIdentifier("settings.app-rules.export")
        Button("RESET APP RULES") { pendingAction = .reset }
            .buttonStyle(SumiActionButtonStyle(role: .quiet, size: .compact))
            .disabled(draft.behaviorPolicy == BehaviorPolicy())
            .accessibilityIdentifier("settings.app-rules.reset")
        Text("Imported and bulk-edited rules take effect only after SAVE SETTINGS.")
            .font(Sumi.body(11))
            .foregroundStyle(Sumi.muted)
    }

    private var searchField: some View {
        SumiTextField("FIND AN APP", placeholder: "Search installed and observed apps", text: $query)
            .frame(maxWidth: .infinity)
    }

    private var filterRail: some View {
        SumiChoiceRail(
            "SHOW",
            options: AppInventoryFilter.allCases,
            selection: $filter,
            title: { $0.label }
        )
    }

    @MainActor
    private func loadInventory() async {
        let result = await Task.detached { service.load() }.value
        var loaded = result.items
        let savedNames = draft.behaviorPolicy.workApplications
            + draft.behaviorPolicy.communicationApplications
            + draft.behaviorPolicy.gamingApplications
        let reviewableNames = savedNames + ContextualGamingAppRulePresentation.builtInApplications
        for name in reviewableNames where !loaded.contains(where: {
            $0.normalizedName == BehaviorPolicy.normalize(name)
        }) {
            loaded.append(
                AppInventoryItem(
                    name: name,
                    normalizedName: BehaviorPolicy.normalize(name),
                    bundleIdentifier: nil,
                    isInstalled: false,
                    lastObservedAt: nil,
                    observationCount: 0
                )
            )
        }
        items = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        warning = result.warning
        isLoading = false
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Review Rules"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try rulesService.importRules(from: url)
            pendingAction = .importRules(imported)
        } catch {
            notice = error.localizedDescription
        }
    }

    private func chooseExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "zoid-666-app-classification-rules.json"
        panel.prompt = "Export Rules"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let receipt = try rulesService.export(draft.behaviorPolicy, to: url)
            notice = "Exported \(receipt.workCount) work, \(receipt.communicationCount) communication, and \(receipt.gamingCount) gaming rules."
        } catch {
            notice = error.localizedDescription
        }
    }

    private func apply(_ action: PendingAppRuleAction) {
        switch action {
        case let .bulk(category, names):
            draft.setClassifications(category, for: names)
            notice = "Updated \(names.count) visible app rules to \(category.label). Choose SAVE SETTINGS to persist them."
        case .reset:
            draft.resetApplicationRules()
            notice = "All explicit app rules were reset to Automatic. Choose SAVE SETTINGS to persist the reset."
        case let .importRules(imported):
            draft.behaviorPolicy = imported
            appendSavedItems(from: imported)
            notice = "Imported app rules are ready. Review them, then choose SAVE SETTINGS to persist."
        }
        clearPendingAction()
    }

    private func appendSavedItems(from policy: BehaviorPolicy) {
        let names = policy.workApplications + policy.communicationApplications + policy.gamingApplications
        for name in names where !items.contains(where: { $0.normalizedName == name }) {
            items.append(AppInventoryItem(
                name: name,
                normalizedName: name,
                bundleIdentifier: nil,
                isInstalled: false,
                lastObservedAt: nil,
                observationCount: 0
            ))
        }
        items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func clearPendingAction() {
        pendingAction = nil
    }
}

private enum AppInventoryFilter: String, CaseIterable {
    case all
    case automatic
    case work
    case communication
    case gaming

    var label: String {
        switch self {
        case .all: "All"
        case .automatic: "Auto"
        case .work: "Work"
        case .communication: "Comms"
        case .gaming: "Gaming"
        }
    }

    func includes(_ choice: ApplicationRuleCategory) -> Bool {
        switch self {
        case .all: true
        case .automatic: choice == .automatic
        case .work: choice == .work
        case .communication: choice == .communication
        case .gaming: choice == .gaming
        }
    }
}

private struct AppClassificationRow: View {
    let item: AppInventoryItem
    @Binding var selection: ApplicationRuleCategory

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                identity
                AppClassificationChoiceControl(selection: $selection, applicationName: item.name)
                    .frame(width: 270)
            }
            VStack(alignment: .leading, spacing: 10) {
                identity
                AppClassificationChoiceControl(selection: $selection, applicationName: item.name)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 54, alignment: .leading)
        .background(selection == .automatic ? Sumi.paper : Sumi.softPaper)
        .overlay(alignment: .bottom) { Rectangle().fill(Sumi.rule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.app-rules.row.\(identifierSuffix)")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Sumi.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(sourceLabel)
                .font(.system(.caption2, design: .serif))
                .sumiLabelTracking()
                .foregroundStyle(Sumi.muted)
            if ContextualGamingAppRulePresentation.isSupported(item.normalizedName) {
                let presentation = ContextualGamingAppRulePresentation(
                    application: item.name,
                    selection: selection
                )
                Text(presentation.title)
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.sealDeep)
                Text(presentation.detail)
                    .font(Sumi.body(10))
                    .foregroundStyle(Sumi.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.app-rules.context.\(identifierSuffix)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceLabel: String {
        if item.isInstalled && item.isObserved { return "INSTALLED / OBSERVED" }
        if item.isInstalled { return "INSTALLED" }
        if item.isObserved { return "OBSERVED" }
        if ContextualGamingAppRulePresentation.isSupported(item.normalizedName) {
            return "CONTEXT-SENSITIVE OPTION"
        }
        return "SAVED CLASSIFICATION"
    }

    private var identifierSuffix: String {
        ContextualGamingAppRulePresentation.identifierSuffix(for: item.normalizedName)
    }
}

private struct AppClassificationChoiceControl: View {
    @Binding var selection: ApplicationRuleCategory
    let applicationName: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ApplicationRuleCategory.allCases, id: \.self) { choice in
                Button {
                    selection = choice
                } label: {
                    Text(displayLabel(for: choice))
                        .font(.system(.caption2, design: .serif))
                        .sumiLabelTracking()
                        .foregroundStyle(selection == choice ? Sumi.paper : Sumi.ink)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(selection == choice ? Sumi.ink : Sumi.paper)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Classify \(applicationName) as \(choice.label)")
                .accessibilityValue(selection == choice ? "Selected" : "Not selected")
                .accessibilityHint(accessibilityHint(for: choice))
                .accessibilityIdentifier(
                    "settings.app-rules.\(identifierSuffix).\(choice.rawValue)"
                )

                if choice != ApplicationRuleCategory.allCases.last {
                    Rectangle().fill(Sumi.rule).frame(width: 1, height: 32)
                }
            }
        }
        .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
    }

    private func displayLabel(for choice: ApplicationRuleCategory) -> String {
        choice == .communication ? "Comms" : choice.label
    }

    private func accessibilityHint(for choice: ApplicationRuleCategory) -> String {
        guard ContextualGamingAppRulePresentation.isSupported(applicationName) else {
            return "Applies this classification to future observed activity after Save Settings."
        }
        return ContextualGamingAppRulePresentation(
            application: applicationName,
            selection: choice
        ).detail
    }

    private var identifierSuffix: String {
        ContextualGamingAppRulePresentation.identifierSuffix(for: applicationName)
    }
}

private enum PendingAppRuleAction: Equatable {
    case bulk(ApplicationRuleCategory, [String])
    case reset
    case importRules(BehaviorPolicy)

    var title: String {
        switch self {
        case .bulk: "Apply a bulk app classification?"
        case .reset: "Reset every explicit app classification?"
        case .importRules: "Replace the current app classifications?"
        }
    }

    var confirmationLabel: String {
        switch self {
        case let .bulk(category, _): "SET TO \(category.label.uppercased())"
        case .reset: "RESET APP RULES"
        case .importRules: "USE IMPORTED RULES"
        }
    }

    var message: String {
        switch self {
        case let .bulk(category, names):
            "This changes \(names.count) currently visible apps to \(category.label). The change remains a draft until Save Settings."
        case .reset:
            "Every explicit Work, Communication, and Gaming app rule returns to Automatic. The change remains a draft until Save Settings."
        case let .importRules(policy):
            "The reviewed file contains \(policy.workApplications.count) Work, \(policy.communicationApplications.count) Communication, and \(policy.gamingApplications.count) Gaming rules. Existing app rules will be replaced only in the current draft."
        }
    }

    var isDestructive: Bool {
        switch self {
        case .reset, .importRules: true
        case .bulk: false
        }
    }
}

private extension ApplicationRuleCategory {
    var label: String {
        switch self {
        case .automatic: "Auto"
        case .work: "Work"
        case .communication: "Communication"
        case .gaming: "Gaming"
        }
    }
}
