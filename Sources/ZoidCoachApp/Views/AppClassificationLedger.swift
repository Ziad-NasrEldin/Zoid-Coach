import SwiftUI
import ZoidCoachCore

struct AppClassificationLedger: View {
    @Binding var draft: SettingsPolicyDraft
    @State private var items: [AppInventoryItem] = []
    @State private var query = ""
    @State private var filter = AppInventoryFilter.all
    @State private var isLoading = true
    @State private var warning: String?
    private let service: AppInventoryService

    init(draft: Binding<SettingsPolicyDraft>, service: AppInventoryService = AppInventoryService()) {
        _draft = draft
        self.service = service
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
                Text("AUTO USES ZOID 666 RULES")
                    .font(Sumi.label(8))
                    .sumiLabelTracking()
                    .foregroundStyle(Sumi.muted)
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
                                    get: { draft.classification(for: item.normalizedName) },
                                    set: { draft.setClassification($0, for: item.normalizedName) }
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
    }

    private var filteredItems: [AppInventoryItem] {
        let normalizedQuery = BehaviorPolicy.normalize(query)
        return items.filter { item in
            let matchesQuery = normalizedQuery.isEmpty || item.normalizedName.contains(normalizedQuery)
            let choice = draft.classification(for: item.normalizedName)
            return matchesQuery && filter.includes(choice)
        }
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
        let savedNames = draft.behaviorPolicy.workApplications + draft.behaviorPolicy.gamingApplications
        for name in savedNames where !loaded.contains(where: { $0.normalizedName == name }) {
            loaded.append(
                AppInventoryItem(
                    name: name,
                    normalizedName: name,
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
}

private enum AppInventoryFilter: String, CaseIterable {
    case all
    case automatic
    case work
    case gaming

    var label: String {
        switch self {
        case .all: "All"
        case .automatic: "Auto"
        case .work: "Work"
        case .gaming: "Gaming"
        }
    }

    func includes(_ choice: AppClassificationChoice) -> Bool {
        switch self {
        case .all: true
        case .automatic: choice == .automatic
        case .work: choice == .work
        case .gaming: choice == .gaming
        }
    }
}

private struct AppClassificationRow: View {
    let item: AppInventoryItem
    @Binding var selection: AppClassificationChoice

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceLabel: String {
        if item.isInstalled && item.isObserved { return "INSTALLED / OBSERVED" }
        if item.isInstalled { return "INSTALLED" }
        if item.isObserved { return "OBSERVED" }
        return "SAVED CLASSIFICATION"
    }
}

private struct AppClassificationChoiceControl: View {
    @Binding var selection: AppClassificationChoice
    let applicationName: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppClassificationChoice.allCases, id: \.self) { choice in
                Button {
                    selection = choice
                } label: {
                    Text(label(for: choice))
                        .font(.system(.caption2, design: .serif))
                        .sumiLabelTracking()
                        .foregroundStyle(selection == choice ? Sumi.paper : Sumi.ink)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(selection == choice ? Sumi.ink : Sumi.paper)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Classify \(applicationName) as \(label(for: choice))")
                .accessibilityValue(selection == choice ? "Selected" : "Not selected")

                if choice != AppClassificationChoice.allCases.last {
                    Rectangle().fill(Sumi.rule).frame(width: 1, height: 32)
                }
            }
        }
        .overlay { Rectangle().stroke(Sumi.rule, lineWidth: 1) }
    }

    private func label(for choice: AppClassificationChoice) -> String {
        switch choice {
        case .automatic: "Auto"
        case .work: "Work"
        case .gaming: "Gaming"
        }
    }
}
